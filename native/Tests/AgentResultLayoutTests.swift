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
        if let movie = ProcessInfo.processInfo.environment["PIXFUN_PREVIEW_FIXTURE"] {
            let playback = AgentPlayback()
            playback.load(movie)
            for _ in 0..<50 {
                if playback.ready || playback.issue != nil { break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            guard playback.ready, playback.duration > 2 else { fatalError("Fixture playback failed: \(playback.issue ?? "timeout")") }
            playback.seek(-2)
            precondition(playback.currentTime == 0, "Seek clamps below zero")
            playback.seek(playback.duration + 10)
            precondition(playback.currentTime == playback.duration, "Seek clamps beyond the end")
            playback.seek(1)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            precondition(abs((playback.player?.currentTime().seconds ?? -1) - 1) < 0.1, "Native seek reaches the selected frame")
            playback.toggle()
            for _ in 0..<50 {
                if playback.playing { break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            // This offscreen harness verifies commands, not real-time presentation:
            // macOS can suspend the video clock without an active display. Test clock
            // progression and pointer scrubbing separately in the unlocked client.
            precondition(playback.playing && playback.player?.rate == 1, "Play command reaches the native player")
            playback.toggle()
            playback.load("/missing-preview-fixture.mp4")
            precondition(playback.issue != nil && !playback.ready, "Missing preview disables playback")
            print("Passed 5 native preview control checks; live playback progression requires the unlocked client.")
            store.editorProjectID = "fixture"
            for width in [760.0, 380.0, 320.0] {
                let card = AgentVideoMessage(artifact: AgentArtifact(id: "preview-layout", type: "preview", title: "Travel film · v1", text: "", path: movie), aspect: "16:9", editorProjectID: "fixture")
                    .padding(20).frame(width: width).background(Color.pixfunBackground)
                    .environmentObject(store).environment(\.colorScheme, .dark)
                let host = NSHostingView(rootView: card)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host; host.frame = NSRect(x: 0, y: 0, width: width, height: 500)
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(1))
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Preview bitmap failed") }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Preview snapshot failed") }
                let path = folder.appendingPathComponent("preview-card-\(Int(width)).png")
                try png.write(to: path); print(path.path)
            }
            store.editorProjectID = nil
        }
        let timelineItems = try JSONDecoder().decode([MediaItem].self, from: Data(#"[{"id":"photo1","kind":"image","file":{"name":"Lake.jpg"},"status":"ready"},{"id":"video1","kind":"video","file":{"name":"Trail.mp4"},"status":"ready","metadata":{"hasAudio":true}},{"id":"photo2","kind":"image","file":{"name":"Summit.jpg"},"status":"ready"}]"#.utf8))
        let timelineShots = [
            AgentShot(id: "a", mediaId: "photo1", start: 0, end: 3, label: "By the lake", reason: "", locked: false),
            AgentShot(id: "b", mediaId: "video1", start: 2, end: 6, label: "Along the trail", reason: "", locked: false),
            AgentShot(id: "c", mediaId: "photo2", start: 0, end: 3, label: "At the summit", reason: "", locked: false)
        ]
        let finish = AgentFinishing(music: .init(mediaId: "music", volume: 0.18, ducking: true), narration: [], transition: .init(kind: "fade", duration: 0.25), originalVolume: 1)
        for width in [760.0, 480.0] {
            let content = EditorTimelineView(shots: timelineShots, items: timelineItems, finishing: finish,
                selectedID: "b", zoom: 48, playhead: 4.5, showsPlayhead: true, canSeek: true,
                canTrim: { !$0.locked }, onSelect: { _ in }, onSeek: { _ in }, onTrim: { _, _, _ in },
                onTrimEnd: {}, onOriginal: { _ in }, onMove: { _, _ in })
                .padding(20).frame(width: width).background(Color.pixfunBackground).environment(\.colorScheme, .dark)
            // ImageRenderer omits macOS ScrollView content; render the native hierarchy.
            let host = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 236), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: width, height: 236)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Timeline bitmap failed") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Timeline render failed") }
            let path = folder.appendingPathComponent("editor-timeline-\(Int(width)).png")
            try png.write(to: path); print(path.path)
        }
        // Keep source matching independent of display order or duplicate filenames.
        let photos = try JSONDecoder().decode([MediaItem].self, from: Data(#"[{"id":"portrait","file":{"name":"IMG_0002.heic"},"kind":"image","status":"ready","coverUrl":"/fixture/portrait.jpg"},{"id":"landscape","file":{"name":"IMG_0002.heic"},"kind":"image","status":"ready","coverUrl":"/fixture/landscape.jpg"},{"id":"audio","file":{"name":"Mountain ambience.wav"},"kind":"audio","status":"ready"}]"#.utf8))
        store.items += photos.reversed()
        let mapped = AgentMaterialSummaryCard(title: "IMG_0002.heic", summary: "Portrait", mediaID: "portrait")
        // The source contract test checks ID matching; renders below check narrow layouts
        // and unavailable-cover placeholders without starting the service or model.
        for width in [760.0, 380.0] {
            let content = VStack(alignment: .leading, spacing: 16) {
                mapped
                AgentMaterialSummaryCard(title: "A long descriptive filename from the mountain trip.heic", summary: "A traveler stands at a scenic viewpoint, with green hills and distant water behind him. Open this material to see the complete analysis.", mediaID: "landscape")
                AgentMaterialSummaryCard(title: "Mountain ambience.wav", summary: "Birdsong and a gentle breeze recorded along the trail.", mediaID: "audio")
                AgentMaterialSummaryCard(title: "Unavailable.heic", summary: "A previously analyzed photo whose source is no longer in the library.", mediaID: "missing")
            }.padding(24).frame(width: width).background(Color.pixfunBackground)
                .foregroundStyle(Color.pixfunInk).environmentObject(store).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let tiff = renderer.nsImage?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                fatalError("Could not render material summaries")
            }
            let path = folder.appendingPathComponent("material-summaries-\(Int(width)).png")
            try png.write(to: path)
            print(path.path)
        }
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
        let mediaFixtures = try JSONDecoder().decode([MediaItem].self, from: Data(#"[{"id":"queued","file":{"name":"New import.mp4"},"kind":"video","status":"queued"},{"id":"active","file":{"name":"Mountain walk.mp4"},"kind":"video","status":"ready","metadata":{"duration":18},"shotAnalysis":{"status":"running"}},{"id":"finished","file":{"name":"IMG_0027.MOV"},"kind":"video","status":"ready","metadata":{"duration":12},"description":"A traveler walks along a tree-lined path beside the lake.","analysisTags":["Lakeside","Walking","Trees","Wide shot","Handheld","Establishing"]}]"#.utf8))
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
        var activeRun = failedRun
        var materialRun = failedRun
        materialRun.artifacts = fixtures
        materialRun.timeline = [
            AgentShot(id: "rest-1", mediaId: "rest", start: 0, end: 3, label: "Shared pause", reason: "Opening", locked: false),
            AgentShot(id: "rest-2", mediaId: "rest", start: 5, end: 8, label: "Return to the tent", reason: "Closing", locked: false)]
        for width in [380.0, 760.0] {
            for expanded in [false, true] {
                store.conversationSection("\(materialRun.id):materials").wrappedValue = expanded
                let content = AgentRunMaterials(run: materialRun).padding(20).frame(width: width)
                    .environmentObject(store).environment(\.colorScheme, .dark)
                    .background(Color.pixfunBackground).foregroundStyle(Color.pixfunInk)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                guard let tiff = renderer.nsImage?.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                    fatalError("Could not render unified material disclosure")
                }
                let path = folder.appendingPathComponent("conversation-materials-\(Int(width))-\(expanded ? "open" : "closed").png")
                try png.write(to: path); print(path.path)
            }
        }
        store.conversationSection("\(materialRun.id):materials").wrappedValue = false
        let keyboardRenderer = ImageRenderer(content: StoryKeyboardHelp()
            .foregroundStyle(Color.pixfunInk).background(Color.pixfunStoryRail).environment(\.colorScheme, .dark))
        keyboardRenderer.scale = 2
        guard let keyboardTIFF = keyboardRenderer.nsImage?.tiffRepresentation,
              let keyboardPNG = NSBitmapImageRep(data: keyboardTIFF)?.representation(using: .png, properties: [:]) else {
            fatalError("Keyboard help render failed")
        }
        try keyboardPNG.write(to: folder.appendingPathComponent("keyboard-help.png"))
        var audioFinish = AgentFinishing.empty
        audioFinish.music = .init(mediaId: "fixture-track", volume: 0.25, ducking: true, sourceStart: 0, loop: true)
        audioFinish.narration = [.init(start: 0, end: 4, text: "A quiet moment before the journey continues.", voice: "Samantha")]
        audioFinish.narrationVolume = 0.8
        let audioView = StoryAudioPopover(finish: audioFinish, duration: 8, musicSources: [],
            originalControls: AnyView(StoryMixGain(label: "Original sound", volume: 0.6, muted: false, setVolume: { _ in }, toggleMute: {})),
            selectedNarration: .constant(0), commit: { _, _ in }, locate: { _ in }, request: { _ in })
            .foregroundStyle(Color.pixfunInk).background(Color.pixfunStoryRail).environment(\.colorScheme, .dark)
        let audioHost = NSHostingView(rootView: audioView)
        let audioWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 510), styleMask: [.borderless], backing: .buffered, defer: false)
        audioWindow.contentView = audioHost; audioHost.frame = NSRect(x: 0, y: 0, width: 350, height: 510)
        audioHost.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        guard let audioBitmap = audioHost.bitmapImageRepForCachingDisplay(in: audioHost.bounds) else { fatalError("Audio popover bitmap failed") }
        audioHost.cacheDisplay(in: audioHost.bounds, to: audioBitmap)
        guard let audioPNG = audioBitmap.representation(using: .png, properties: [:]) else { fatalError("Audio popover PNG failed") }
        try audioPNG.write(to: folder.appendingPathComponent("audio-popover.png"))
        materialRun.status = "completed"; materialRun.intent = "modify"
        materialRun.artifacts = []; materialRun.storySummary = nil
        materialRun.editReceipt = AgentEditReceipt(changedShotIds: ["rest-2"], removedCount: 1,
            soundOrCaptions: true, aspectChanged: false, version: materialRun.version, undone: false)
        store.agentRuns = [materialRun]
        for width in [300.0, 380.0, 760.0] {
            let content = AgentRunResults(run: materialRun, isCurrent: true).padding(16).frame(width: width)
                .environmentObject(store).environment(\.colorScheme, .dark)
                .background(Color.pixfunBackground).foregroundStyle(Color.pixfunInk)
            let host = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host; host.frame = NSRect(x: 0, y: 0, width: width, height: 240)
            host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Edit receipt bitmap failed") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Edit receipt layout failed") }
            let path = folder.appendingPathComponent("edit-receipt-\(Int(width)).png")
            try png.write(to: path); print(path.path)
        }
        activeRun.status = "running"
        var queuedRun = activeRun
        queuedRun.status = "queued"
        var renderingRun = activeRun
        renderingRun.stage = "render"
        var progressingRun = activeRun
        progressingRun.stage = "plan"
        progressingRun.artifacts = fixtures
        progressingRun.progressUpdates = [
            AgentProgressUpdate(id: "intent", kind: "stage", stage: "intent"),
            AgentProgressUpdate(id: "understand", kind: "stage", stage: "understand"),
            AgentProgressUpdate(id: "rest", kind: "media", mediaId: "rest"),
            AgentProgressUpdate(id: "snow", kind: "media", mediaId: "snow"),
            AgentProgressUpdate(id: "plan", kind: "stage", stage: "plan")]
        for width in [760.0, 380.0] {
            let content = VStack(alignment: .leading, spacing: 20) {
                Text("Activity states · layout fixture").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                AgentProgressTimeline(run: progressingRun)
                AgentActivityView(run: progressingRun)
                AgentEditDetails(run: progressingRun)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24).frame(width: width)
                .background(Color.pixfunBackground).environment(\.colorScheme, .dark).environmentObject(store)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let tiff = renderer.nsImage?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                fatalError("Could not render activity states")
            }
            let path = folder.appendingPathComponent("activity-\(Int(width)).png")
            try png.write(to: path)
            print(path.path)
        }
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
