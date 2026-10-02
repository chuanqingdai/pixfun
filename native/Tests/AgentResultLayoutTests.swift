import AppKit
import SwiftUI

/// Offscreen rendering of the production result components. Does not start the service.
@main
struct AgentResultLayoutTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let store = WorkspaceStore()
        store.items = try JSONDecoder().decode([MediaItem].self, from: Data(#"[{"id":"rest","file":{"name":"rest.mp4"},"kind":"video","status":"ready"},{"id":"snow","file":{"name":"snow.mp4"},"kind":"video","status":"ready"}]"#.utf8))
        let fixtures: [AgentArtifact] = [
            .init(id: "rest", type: "analysis", title: "rest.mp4", text: "Two travelers share a quiet moment inside a tent, surrounded by forest and mountain views.\nAction · Reaction · Recommended · 3s\nKeep the shared pause to introduce a calm, personal moment before the landscape sequence.", mediaId: "rest", start: 0, end: 8),
            .init(id: "rest2", type: "analysis", title: "rest.mp4", text: "The camera moves towards the opening of the tent.", mediaId: "rest", start: 8, end: 12),
            .init(id: "json1", type: "file", title: "Shot breakdown · rest.mp4", text: "Editorial JSON", path: "/fixture/rest.json"),
            .init(id: "snow", type: "analysis", title: "snow.mp4", text: "A wide view of a snow-covered mountain beneath shifting clouds. The mountain remains still as patches of blue sky appear.\nAction · Transition · Recommended · 3s\nUse as an establishing shot or a scenic transition after the tent scene.", mediaId: "snow", start: 0, end: 9),
            .init(id: "json2", type: "file", title: "Shot breakdown · snow.mp4", text: "Editorial JSON", path: "/fixture/snow.json"),
            .init(id: "sound", type: "finishing", title: "Sound & transitions", text: "Transitions: fade through black")
        ]
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for width in [760.0, 380.0] {
            let content = VStack(alignment: .leading, spacing: 8) {
                Text("Layout fixture · no model inference").font(.system(size: 12)).foregroundStyle(Color.pixfunMuted)
                AgentSourceResults(artifacts: fixtures)
            }.padding(24).frame(width: width).background(Color.pixfunBackground)
                .foregroundStyle(Color.pixfunInk).environmentObject(store).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("Could not render result layout")
            }
            let path = folder.appendingPathComponent("results-\(Int(width)).png")
            try png.write(to: path)
            print(path.path)
        }
        let mediaFixtures = try JSONDecoder().decode([MediaItem].self, from: Data(#"[{"id":"queued","file":{"name":"New import.mp4"},"kind":"video","status":"queued"},{"id":"active","file":{"name":"Mountain walk.mp4"},"kind":"video","status":"ready","metadata":{"duration":18},"shotAnalysis":{"status":"running"}},{"id":"finished","file":{"name":"Ready clip.mp4"},"kind":"video","status":"ready","metadata":{"duration":12}}]"#.utf8))
        let mediaContent = VStack(alignment: .leading, spacing: 16) {
            Text("Cover states · layout fixtures, not live analysis").font(.system(size: 12))
            HStack(alignment: .top, spacing: 16) {
                ForEach(mediaFixtures) { MediaCard(item: $0).frame(width: 240) }
            }
        }.padding(24).background(Color.pixfunBackground).foregroundStyle(Color.pixfunInk)
            .environmentObject(store).environment(\.colorScheme, .dark)
        let mediaRenderer = ImageRenderer(content: mediaContent)
        mediaRenderer.scale = 2
        guard let tiff = mediaRenderer.nsImage?.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            fatalError("Could not render media cover states")
        }
        let mediaPath = folder.appendingPathComponent("media-cover-states.png")
        try png.write(to: mediaPath)
        print(mediaPath.path)
        let failedRun = AgentRun(id: "fixture", projectId: "fixture", prompt: "Analyze my footage", mode: "local",
            status: "failed", stage: "understand", message: "'VideoDescriptions' object has no attribute 'library'",
            summary: "", intent: "analyze", question: "", resultText: "", events: [], artifacts: [], timeline: [],
            version: 1, completed: 0, total: 2, duration: 30, aspect: "16:9", updatedAt: 0)
        for width in [760.0, 380.0] {
            let content = VStack(alignment: .leading, spacing: 18) {
                Label("Pixfun", systemImage: "sparkles").foregroundStyle(Color.pixfunGold)
                AgentFailureCard(run: failedRun, canRetry: true)
                Text("Saved results").font(.pixfun(14, semibold: true))
                AgentSourceResults(artifacts: Array(fixtures.prefix(1)))
            }.padding(24).frame(width: width).background(Color.pixfunBackground)
                .foregroundStyle(Color.pixfunInk).environmentObject(store).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let tiff = renderer.nsImage?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                fatalError("Could not render failure card")
            }
            let path = folder.appendingPathComponent("failure-\(Int(width)).png")
            try png.write(to: path)
            print(path.path)
        }
    }
}
