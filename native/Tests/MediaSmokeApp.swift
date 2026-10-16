import SwiftUI

/// Real Media views with an isolated in-memory library. No service, source-file
/// changes, saved drafts, uploads or access to the user's production library.
@main struct MediaLayoutTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let raw = #"[{"id":"lake","file":{"name":"Lake walk.mov"},"kind":"video","status":"ready","favorite":true,"metadata":{"width":1920,"height":1080,"duration":12},"description":"A boy walking by a lake.","context":{"location":"Hangzhou"}},{"id":"mountain","file":{"name":"Mountain viewpoint.jpg"},"kind":"image","status":"ready","metadata":{"width":1920,"height":1080},"description":"A girl posing at a mountain viewpoint.","context":{"location":"Hangzhou"}},{"id":"cafe","file":{"name":"Café break.mov"},"kind":"video","status":"ready","metadata":{"width":1920,"height":1080,"duration":8},"description":"A woman drinking coffee in a café.","context":{"location":"Shanghai"}}]"#
        let store = WorkspaceStore()
        store.items = try JSONDecoder().decode([MediaItem].self, from: Data(raw.utf8))
        store.page = .media
        let baseline = store.items
        var evidenceItem = baseline[0]
        evidenceItem.file.name = "IMG_20261015.MOV"
        evidenceItem.file.size = 24268354
        evidenceItem.metadata = .init(width:1920, height:1080, duration:14.58, fps:59.94, hasAudio:true,
                                     capturedAt:"2026-10-11T14:23:20+0800", camera:"iPhone 14 Pro Max",
                                     location:.init(latitude:39.9, longitude:116.4, altitude:49.9, source:"file-metadata"),
                                     videoCodec:"hevc", audioCodec:"aac", mediaCreatedAt:"2026-10-11T06:23:20Z", dateSource:"QuickTime creationdate")
        evidenceItem.analysisEvidence = .init(version:1, tags:[
            .init(id:"scene:water", category:"scene", key:"water", label:"Lakes & rivers", aliases:["river"], source:"visual-observation", evidence:[.init(start:0, end:6, shotIds:["canonical-a"], text:"river")]),
            .init(id:"subject:people", category:"subject", key:"people", label:"People", aliases:["person"], source:"visual-observation", evidence:[.init(start:6, end:12, shotIds:["canonical-b"], text:"two people")])])
        evidenceItem.videoDescription = .init(status:"ready", title:"A walk along the river", full_description:"A riverside view reveals two walkers beside the water.\n\n1. Riverbank: Water flows past a stone wall, with cars visible on the road above.\n2. Walkers: The camera pans to two people standing by the river.", shotRevision:"fixture")
        let shot = EditorialShot(shot_id:"canonical-a", start_time:"00:00:00.000", end_time:"00:00:06.000", description:"Water flows past a stone wall, with cars visible on the road above.", shot_size:"Wide shot", capture_type:"Static", camera_motion:"Slow pan", story_role:["Establishing"], dialogue:"", reaction:"", audio:[], importance_score:78, duplicate_candidate:false, unusable_candidate:false, edit_recommendation:.init(level:"Recommended", recommended_duration_sec:3, reason:"Introduces the riverside setting before the walkers appear."))
        evidenceItem.shotAnalysis = .init(status:"ready", segments:[.init(id:"canonical-a", label:shot.description, start:0, end:6, boundary:.init(type:"video_start"), editorial:shot)], revision:"fixture")
        let assets = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("public/media/travel")
        for (state, width) in [("settings-places",620.0), ("wide", 1120.0), ("narrow", 760.0), ("filtered", 760.0), ("empty", 760.0), ("first-use",760.0), ("sample-only",760.0), ("waiting",760.0), ("analyzing",760.0), ("attention",760.0), ("selected",760.0), ("creation",960.0), ("navigation",1120.0), ("evidence-detail",1000.0), ("evidence-detail-multiple",1000.0), ("evidence-detail-failed",760.0), ("evidence-detail-capture",1000.0), ("evidence-tags",650.0)] {
            store.items = baseline; store.page = .media; store.selecting = false; store.selection = []
            store.syncSnapshot = nil
            for index in store.items.indices {
                store.items[index].coverUrl = assets.appendingPathComponent(["luxury.jpg", "city.jpg", "food.jpg"][index]).path
                store.items[index].importedAt = Date().addingTimeInterval(index == 2 ? -86400 : 0).timeIntervalSince1970 * 1000
                store.items[index].syncSourceId = index == 2 ? "camera" : "phone"
                store.items[index].syncSourceName = index == 2 ? "Travel camera" : "My iPhone"
                store.items[index].syncSourceKind = index == 2 ? "camera" : "phone"
                store.items[index].importBatchId = index == 2 ? "yesterday" : "today"
            }
            store.resetMediaFilters()
            if state == "first-use" { store.items = [] }
            if state == "sample-only" { for index in store.items.indices { store.items[index].isExample = true } }
            if state == "waiting" {
                store.items = []
                store.syncSnapshot = MediaSyncSnapshot(devices: [SyncDevice(id: "phone", name: "My iPhone", kind: "phone", status: "Scanning", message: "Checking new photos", automatic: true, photos: true, videos: true, connected: true, busy: true, lastSync: nil, completed: 0, total: 4, failed: 0, skipped: 0, bytes: 0, totalBytes: 400)], storage: [], available: [], archivePending: 0, archiving: false, phoneAvailable: true)
            }
            if state == "analyzing" { store.items[0].status = "analyzing"; store.items[1].status = "error" }
            if state == "attention" { store.items[1].status = "error" }
            if state == "selected" { store.beginSelection(); store.selection = ["lake"] }
            if state == "filtered" || state == "empty" {
                store.toggleMediaTag(store.mediaFacetOptions[.scene]!.first { $0.tag.key == "mountain" }!.tag)
                if state == "empty" { store.category = .video }
            }
            if state == "creation" { store.page = .home }
            if state.hasPrefix("evidence") { store.items = [evidenceItem] }
            if state == "evidence-detail-multiple" {
                var laterShot = shot
                laterShot.description = "Two people stand beside the river as the camera pans right, revealing a rocky mountain beneath a blue sky."
                store.items[0].shotAnalysis?.segments?.append(.init(id:"canonical-b", label:"Walkers", start:6, end:12, boundary:.init(type:"semantic_change"), editorial:laterShot))
            }
            if state == "evidence-detail-failed" {
                store.items[0].videoDescription = .init(status:"failed", message:"Return only title and full_description.")
            }
            if state == "evidence-detail-capture" {
                store.items[0].context = nil
                store.items[0].metadata?.hasAudio = true
                store.items[0].metadata?.location = CaptureLocation(latitude: 39.9, longitude: 116.4, source: "file-metadata")
                store.items[0].videoDescription = .init(status:"ready", title:"河边散步", full_description:"河水沿石墙流过，镜头向右移动，两位行人出现在岸边。")
                store.items[0].result = .init(analysis:.init(subtitleCues:[.init(start:1,end:3,text:"沿着河边往前走。"),.init(start:5,end:7,text:"这里就是入口。")],subtitleMessage:"Speech recognition may contain errors. Check against the original audio.",subtitleState:"transcribed",subtitleSource:"local-asr",subtitleLanguage:"zh"))
                store.items[0].analysisEvidence?.onScreenText = [.init(text:"游客中心",start:2,end:8,confidence:0.95)]
            }
            let content: AnyView = state == "settings-places" ? AnyView(AppSettingsView()) : state == "evidence-tags" ? AnyView(MediaTagReview(item:evidenceItem)) : state.hasPrefix("evidence-detail") ? AnyView(MediaDetailView(initialItem:store.items[0])) : state == "creation" ? AnyView(CreationWorkspaceView()) : state == "navigation" ? AnyView(HStack(spacing: 0) { PixfunSidebar().frame(width: 216); MediaView() }) : AnyView(MediaView())
            let view = content.environmentObject(store).font(.pixfun())
                .environment(\.locale, Locale(identifier: state == "evidence-detail-capture" ? "zh-Hans" : "en"))
                .foregroundStyle(Color.pixfunInk).tint(.pixfunGold)
                .environment(\.colorScheme, .dark).background(Color.pixfunBackground)
            let host = NSHostingView(rootView: view)
            let rect = NSRect(x: 0, y: 0, width: width, height: state == "evidence-detail-capture" ? 1400 : state.hasPrefix("evidence-detail") ? 1200 : 800)
            let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host; host.frame = rect
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(state + ".png"))
            print("Rendered Media \(state)")
        }
    }
}
