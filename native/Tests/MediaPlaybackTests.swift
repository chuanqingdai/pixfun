import AppKit
import AVKit

@main
struct MediaPlaybackTests {
    @MainActor static func main() async throws {
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let controller = PlaybackController()
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
        }
        func waitFor(_ condition: () -> Bool) async throws {
            for _ in 0..<150 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            preconditionFailure("Timed out waiting for real AVFoundation playback state")
        }
        controller.open(source, withPoster: true)
        try await waitFor { controller.poster != nil && controller.player?.currentItem?.status == .readyToPlay }
        check(controller.showsPoster, "opening a source keeps the real poster visible")
        check(controller.player?.rate == 0, "loading a poster must not autoplay")
        check(abs(controller.player!.currentTime().seconds) < 0.01, "poster must not move the original clock")
        let image = controller.poster!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let bitmap = NSBitmapImageRep(cgImage: image)
        var brightness = 0.0
        for x in stride(from: 0, to: bitmap.pixelsWide, by: max(1,bitmap.pixelsWide/10)) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: max(1,bitmap.pixelsHigh/10)) {
                brightness += Double(bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!.redComponent)
            }
        }
        check(brightness > 5, "Wild Alaska initial poster must contain real nonblack pixels")
        controller.seek(15)
        check(!controller.showsPoster, "shot navigation immediately dismisses the cover")
        try await waitFor { abs(controller.player!.currentTime().seconds - 15) < 0.1 }
        controller.open(source, withPoster: true)
        try await waitFor { controller.poster != nil && controller.player?.currentItem?.status == .readyToPlay }
        controller.player!.play()
        try await waitFor { !controller.showsPoster }
        controller.stop()
        check(controller.player == nil && controller.poster == nil && !controller.showsPoster, "closing cancels and clears artwork")
        controller.open(source, at: 24, withPoster: true)
        check(!controller.showsPoster, "search result navigation never displays an unrelated beginning cover")
        try await waitFor { controller.player?.currentItem?.status == .readyToPlay && abs(controller.player!.currentTime().seconds - 24) < 0.1 }
        controller.open(source, withPoster: true)
        controller.stop()
        try await Task.sleep(nanoseconds: 200_000_000)
        check(controller.poster == nil && controller.player == nil, "cancelled image completion cannot revive a closed player")
        let view = PlaybackPosterImageView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        check(view.hitTest(NSPoint(x: 100,y: 100)) == nil, "cover never swallows playback or scrubber clicks")
        print("PASS real AVFoundation poster pixels, paused zero start, seek, play, search target, cancellation and click passthrough")
    }
}
