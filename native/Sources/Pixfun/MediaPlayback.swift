import SwiftUI
import AVKit

@MainActor
final class PlaybackController: ObservableObject {
    @Published var player: AVPlayer?
    @Published var error: String?
    @Published private(set) var poster: NSImage?
    @Published private(set) var showsPoster = false
    private var observation: NSKeyValueObservation?
    private var playbackObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var generator: AVAssetImageGenerator?
    private var timeout: Task<Void, Never>?
    private var source: URL?
    private var wantsPoster = false
    private var pendingTime = 0.0
    func open(_ url: URL, at seconds: Double = 0, withPoster: Bool = false) {
        stop(); source = url; error = nil; wantsPoster = withPoster
        pendingTime = seconds.isFinite ? max(0, seconds) : 0
        showsPoster = withPoster && pendingTime == 0
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        if withPoster {
            let generator = AVAssetImageGenerator(asset: item.asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280, height: 1280)
            // Decode the earliest available frame, including videos whose first
            // sample starts slightly after zero. Do not move the playback clock.
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .positiveInfinity
            self.generator = generator
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { [weak self] _, image, _, _, _ in
                guard let image else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.player?.currentItem === item else { return }
                    self.poster = NSImage(cgImage: image, size: .zero)
                }
            }
        }
        playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player === player else { return }
                if player.timeControlStatus != .paused { self.showsPoster = false }
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self, weak player] time in
            Task { @MainActor [weak self, weak player] in
                guard let self, let player, self.player === player else { return }
                // Also handles seeking with AVKit's own scrubber while paused.
                if time.seconds.isFinite && time.seconds > 0.001 { self.showsPoster = false }
            }
        }
        observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player?.currentItem === item else { return }
                if item.status == .readyToPlay {
                    self.timeout?.cancel(); self.error = nil
                    self.player?.seek(to: CMTime(seconds: self.pendingTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
                if item.status == .failed {
                    self.timeout?.cancel(); self.showsPoster = false
                    self.error = "Cannot play this file with the system codecs. Open the original in Finder or convert to H.264 / HEVC."
                }
            }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            guard let self, self.player?.currentItem === item, item.status == .unknown else { return }
            self.error = "Playback is taking too long. Check that the original is available on this Mac."
        }
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        pendingTime = max(0, seconds); showsPoster = false
        guard player?.currentItem?.status == .readyToPlay else { return }
        player?.seek(to: CMTime(seconds: pendingTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func retry() { if let source { open(source, at: pendingTime, withPoster: wantsPoster) } }
    func stop() {
        timeout?.cancel(); timeout = nil; observation = nil; playbackObservation = nil
        generator?.cancelAllCGImageGeneration(); generator = nil
        if let timeObserver { player?.removeTimeObserver(timeObserver) }; timeObserver = nil
        player?.pause(); player = nil; poster = nil; showsPoster = false
    }
}

/// Lives in AVKit's content overlay, below its native playback controls.
/// Never captures mouse events, including full-screen controls and the scrubber.
final class PlaybackPosterImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct NativeVideoPlayer: NSViewRepresentable {
    var player: AVPlayer
    var showsControls = true
    var poster: NSImage? = nil
    final class Coordinator {
        let posterView = PlaybackPosterImageView(frame: .zero)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = showsControls ? .inline : .none
        view.allowsVideoFrameAnalysis = false
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        let artwork = context.coordinator.posterView
        artwork.imageScaling = .scaleProportionallyUpOrDown
        artwork.autoresizingMask = [.width, .height]
        if let overlay = view.contentOverlayView {
            artwork.frame = overlay.bounds; overlay.addSubview(artwork)
        }
        artwork.image = poster; artwork.isHidden = poster == nil
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
        view.controlsStyle = showsControls ? .inline : .none
        context.coordinator.posterView.image = poster
        context.coordinator.posterView.isHidden = poster == nil
    }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.posterView.image = nil; coordinator.posterView.removeFromSuperview()
        view.player?.pause(); view.player = nil
    }
}
