// Validate generated previews using the same macOS media framework as the client.
import AVFoundation
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Pass a generated preview path") }
let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
guard asset.isPlayable, asset.duration.seconds.isFinite, asset.duration.seconds > 0 else {
    fatalError("Preview is not playable in AVFoundation")
}
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
for fraction in [0.0, 0.5, 0.95] {
    let frame = try generator.copyCGImage(at: CMTime(seconds: asset.duration.seconds * fraction, preferredTimescale: 600), actualTime: nil)
    guard frame.width > 0 && frame.height > 0 else { fatalError("Empty native preview frame") }
}
print("Native preview playback eligibility and beginning/middle/end frame decoding: PASS (\(asset.duration.seconds)s)")
