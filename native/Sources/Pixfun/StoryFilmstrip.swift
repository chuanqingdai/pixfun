import SwiftUI
import AVFoundation

/// Decode only visible video ranges; photos repeat their cover without video decoding.
struct StoryFilmstrip: View {
    @EnvironmentObject var store: WorkspaceStore
    let shot: AgentShot
    let cover: String?
    let isPhoto: Bool
    let width: Double
    let visible: Bool
    @State private var frames: [NSImage] = []
    @State private var loadedKey: String?
    @State private var coverImage: NSImage?
    @State private var loadedCover: String?
    var tileCount: Int { StoryTimeline.filmstripTileCount(width: width) }
    var frameCount: Int { min(6, tileCount) }
    var requestKey: String { "\(shot.mediaId):\(shot.start):\(shot.end):\(frameCount)" }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tileCount, id: \.self) { index in
                Group {
                    if loadedKey == requestKey, !frames.isEmpty {
                        Image(nsImage: frames[min(frames.count-1, index*frames.count/tileCount)])
                            .resizable().scaledToFill()
                    } else if loadedCover == cover, let coverImage {
                        Image(nsImage: coverImage).resizable().scaledToFill()
                    } else { Color.pixfunRaised.overlay { Image(systemName: "photo").foregroundStyle(Color.pixfunMuted) } }
                }.frame(width: max(0, width) / Double(tileCount), height: 44).clipped()
            }
        }.frame(width: max(0, width), height: 44).clipped().accessibilityHidden(true)
            .task(id: visible ? cover : nil) {
                guard visible, let cover, !cover.isEmpty else { return }
                let image = await store.service.image(cover)
                guard !Task.isCancelled else { return }
                coverImage = image; loadedCover = cover
            }
            .task(id: visible && !isPhoto ? requestKey : nil) {
                guard visible, !isPhoto else { return }
                await loadFrames()
            }
    }

    @MainActor private func loadFrames() async {
        let key = requestKey
        let cacheKey = "\(ObjectIdentifier(store.service)):\(key)" as NSString
        if let cached = StoryFrameCache.images.object(forKey: cacheKey) as? [NSImage] {
            frames = cached; loadedKey = key; return
        }
        do {
            let url = try await store.service.original(shot.mediaId)
            try Task.checkCancellation()
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 192, height: 108)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let times = StoryTimeline.thumbnailTimes(start: shot.start, end: shot.end, count: frameCount)
            let decoded: [NSImage] = try await withTaskCancellationHandler(operation: {
                var result: [NSImage] = []
                for time in times {
                    try Task.checkCancellation()
                    let frame = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
                    try Task.checkCancellation()
                    result.append(NSImage(cgImage: frame.image, size: .zero))
                }
                return result
            }, onCancel: { generator.cancelAllCGImageGeneration() })
            try Task.checkCancellation()
            StoryFrameCache.images.setObject(decoded as NSArray, forKey: cacheKey, cost: decoded.count*192*108*4)
            frames = decoded; loadedKey = key
        } catch {
            // The cached media cover stays visible if the source is unavailable.
        }
    }
}

@MainActor private enum StoryFrameCache {
    static let images: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>()
        cache.countLimit = 160
        cache.totalCostLimit = 32*1024*1024
        return cache
    }()
}
