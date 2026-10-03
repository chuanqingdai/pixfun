import SwiftUI
import AVKit

/// Source-only draft review. The rendered movie remains the authority for finishing effects.
@MainActor final class StorySequencePlayer: ObservableObject {
    @Published var player: AVPlayer?
    @Published var photo: NSImage?
    @Published var shotID: String?
    @Published var time = 0.0
    @Published var playing = false
    @Published var loading = false
    @Published var issue: String?
    private var shots: [AgentShot] = []
    private var photos = Set<String>()
    private var service: LocalService?
    private var job: Task<Void, Never>?
    private var clock: Task<Void, Never>?
    private var generation = 0
    private var index = 0
    private var photoClock = Date()
    private var photoStart = 0.0
    private var requestedPlay = false
    private var stopAtShot: String?
    private var originalVolume: Float = 1
    private var finishing: AgentFinishing?
    var duration: Double { shots.reduce(0) { $0 + $1.end - $1.start } }

    func configure(shots: [AgentShot], photos: Set<String>, service: LocalService, volume: Double) {
        stop(); self.shots = shots; self.photos = photos; self.service = service
        originalVolume = Float(min(1, max(0, volume)))
    }
    func updateFinishing(_ value: AgentFinishing?) {
        finishing = value
        if let id = shotID { player?.volume = Float(value?.gain(for: id) ?? Double(originalVolume)) }
    }
    func seek(_ value: Double, play: Bool = false, stoppingAt: String? = nil) {
        guard let service, value.isFinite, let i = StoryTimeline.index(at: value, in: shots) else { return }
        let wanted = shots[i]
        let target = min(duration, max(0, value))
        if shotID == wanted.id, !loading, issue == nil, photo != nil || player != nil {
            pause(); stopAtShot = stoppingAt; time = target
            if let player {
                player.seek(to: CMTime(seconds: wanted.start + max(0, target - StoryTimeline.offset(wanted.id, in: shots)), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            if play { resume() }
            return
        }
        stop(); generation += 1
        stopAtShot = stoppingAt
        let token = generation, shot = shots[i]
        index = i; shotID = shot.id; time = min(duration, max(0, value)); loading = true; issue = nil
        requestedPlay = play
        let offset = StoryTimeline.offset(shot.id, in: shots)
        let local = min(shot.end - shot.start, max(0, time - offset))
        job = Task { [weak self] in
            do {
                let url = try await service.original(shot.mediaId)
                guard let self, !Task.isCancelled, self.generation == token else { return }
                if self.photos.contains(shot.mediaId) {
                    guard let image = NSImage(contentsOf: url) else { throw ServiceError(message: "This photo could not be opened.") }
                    self.photo = image; self.loading = false
                } else {
                    let item = AVPlayerItem(url: url), player = AVPlayer()
                    self.player = player; player.volume = Float(self.finishing?.gain(for: shot.id) ?? Double(self.originalVolume)); player.replaceCurrentItem(with: item)
                    for _ in 0..<150 {
                        guard !Task.isCancelled, self.generation == token else { return }
                        if item.status == .failed { throw ServiceError(message: "This source video could not be played.") }
                        if item.status == .readyToPlay { break }
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                    guard item.status == .readyToPlay else { throw ServiceError(message: "Source loading timed out. Try again.") }
                    let ok = await player.seek(to: CMTime(seconds: shot.start + local, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    guard !Task.isCancelled, self.generation == token else { return }
                    guard ok else { throw ServiceError(message: "Could not seek this source. Try again.") }
                    self.loading = false
                }
                if self.requestedPlay { self.resume() }
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.issue = error.localizedDescription; self.loading = false; self.playing = false
            }
        }
    }
    func toggle() {
        if playing || (loading && requestedPlay) { pause() }
        else if loading { requestedPlay = true }
        else if shotID == nil || time >= duration - 0.01 { seek(0, play: true) }
        else { resume() }
    }
    func toggleAll() {
        if playing || (loading && requestedPlay) { pause() }
        else { seek(time >= duration - 0.01 ? 0 : time, play: true) }
    }
    func pause() {
        requestedPlay = false; playing = false; player?.pause(); clock?.cancel(); clock = nil
    }
    func stop() {
        generation += 1; job?.cancel(); job = nil; pause(); player = nil; photo = nil; shotID = nil; stopAtShot = nil; loading = false
    }
    private func resume() {
        guard !loading, issue == nil, shots.indices.contains(index) else { return }
        playing = true; requestedPlay = true; photoClock = Date(); photoStart = time
        player?.play(); clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled, let self, self.playing, self.shots.indices.contains(self.index) else { return }
                let shot = self.shots[self.index], offset = StoryTimeline.offset(shot.id, in: self.shots)
                if self.photo != nil { self.time = self.photoStart + Date().timeIntervalSince(self.photoClock) }
                else if let source = self.player?.currentTime().seconds, source.isFinite { self.time = offset + max(0, source - shot.start) }
                if self.player?.currentItem?.status == .failed {
                    self.pause(); self.issue = "Playback stopped. Retry this clip."; return
                }
                if self.time >= offset + shot.end - shot.start - 0.025 {
                    let next = offset + shot.end - shot.start
                    if self.stopAtShot == shot.id { self.time = max(offset, next - 0.03); self.pause() }
                    else if self.index + 1 < self.shots.count { self.seek(next, play: true) }
                    else { self.time = self.duration; self.pause() }
                    return
                }
            }
        }
    }
}
