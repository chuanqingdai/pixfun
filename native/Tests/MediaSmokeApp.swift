import SwiftUI
import MapKit

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
        if CommandLine.arguments.contains("--map-only") {
            // Synthetic points and existing local photos, never the user's database.
            var fixtures: [MediaItem] = []
            for index in 0..<8 {
                var item = baseline[0]
                item.id = "map-fixture-\(index)"; item.file.name = "Sample \(index + 1).mov"
                let lat = index < 6 ? 48.85 + Double(index / 2) * 0.003 : (index == 6 ? 51.50 : 41.90)
                let lon = index < 6 ? 2.32 + Double(index / 2) * 0.003 : (index == 6 ? -0.12 : 12.49)
                item.metadata = .init(capturedAt: "2026-09-16T14:\(String(format: "%02d", index * 5)):00+0200", camera: "Fixture camera", captureDeviceID: "camera-sha256:fixture",
                                      location: .init(latitude: lat, longitude: lon, source: "file-metadata", datum: "WGS84", horizontalAccuracy: 5))
                item.coverUrl = assets.appendingPathComponent(["luxury.jpg", "city.jpg", "food.jpg"][index % 3]).path
                fixtures.append(item)
            }
            // Compare selection states at the same width: footer wrapping may change
            // naturally between wide and narrow windows.
            var stableMapHeights: [CGFloat: CGFloat] = [:]
            for state in ["global", "region", "order", "numbers", "narrow-unselected", "narrow", "composer", "consent", "empty"] {
                store.items = state == "empty" ? [] : (state == "global" ? fixtures : Array(fixtures.prefix(6)))
                store.ready = true; store.page = .mediaMap
                if ["order", "numbers", "narrow-unselected", "narrow"].contains(state) {
                    for index in store.items.indices {
                        store.items[index].metadata?.location?.latitude = 48.85 + Double(index) * 0.0015
                        store.items[index].metadata?.location?.longitude = 2.32 + Double(index) * 0.0015
                        if state != "order" {
                            store.items[index].metadata?.location?.horizontalAccuracy = nil
                            store.items[index].metadata?.location?.datum = nil
                            store.items[index].metadata?.captureDeviceID = nil
                        }
                    }
                }
                store.resetMediaFilters()
                let ordered = ["order", "numbers", "narrow"].contains(state)
                if state == "composer" {
                    precondition(store.prepareMapCreation(Array(fixtures.prefix(3)).map(\.id), replaceDraft: true))
                    precondition(store.draft.attachments.count == 3 && store.agentRuns.isEmpty && !store.saving)
                }
                let content = state == "composer" ? AnyView(WorkspaceView()) : AnyView(HStack(spacing: 0) {
                    PixfunSidebar().frame(width: 216)
                    MediaMapView(initialDay: state == "order" ? "2026-09-16" : "", initialOrder: ordered,
                                 initialSelection: ordered ? Set(store.items.map(\.id)) : (state == "region" ? ["map-fixture-0", "map-fixture-1"] : []), mapEnabled: state != "consent")
                })
                let view = content
                    .environmentObject(store).environment(\.locale, Locale(identifier: "zh-Hans"))
                    .environment(\.colorScheme, .dark).tint(.pixfunGold)
                let host = NSHostingView(rootView: view)
                let rect = NSRect(x: 0, y: 0, width: state.hasPrefix("narrow") ? 960 : 1280, height: 740)
                let window = NSWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.title = "素材地图 · 独立测试预览"; window.contentView = host; host.frame = rect
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(4))
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("map-\(state).png"))
                func maps(_ view: NSView) -> [MKMapView] { (view as? MKMapView).map { [$0] } ?? view.subviews.flatMap(maps) }
                if let map = maps(host).first {
                    let points = map.annotations.filter { !($0 is MKClusterAnnotation) && !($0 is MKUserLocation) }.count
                    precondition(points == store.items.count, "Every fixture has a map annotation")
                    if let stableMapHeight = stableMapHeights[rect.width] {
                        precondition(abs(map.frame.height - stableMapHeight) < 1,
                                     "Selecting thumbnails must not resize and recenter the map")
                    } else { stableMapHeights[rect.width] = map.frame.height }
                    if state == "order" { precondition(map.overlays.contains { $0 is MKPolyline }, "Sequence overlay missing") }
                    if state == "numbers" || state == "narrow" { precondition(!map.overlays.contains { $0 is MKPolyline }, "Uncertain GPS must not create a route") }
                    print("Rendered map-\(state): \(points) source annotations, \(map.overlays.count) overlays")
                    print("Map frame \(map.frame), visible annotation views \(map.annotations.compactMap { map.view(for: $0) }.count)")
                } else { precondition(["consent", "empty", "composer"].contains(state), "Map missing") }
                if state == "composer" {
                    func editors(_ view: NSView) -> [NSTextView] { (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(editors) }
                    precondition(editors(host).contains { $0.string == store.draft.prompt && $0.isEditable }, "Default request must reach the existing editable composer")
                    print("Rendered existing Agent composer with three attachments and editable default request; no run created")
                }
                window.orderOut(nil)
            }
            return
        }
        if CommandLine.arguments.contains("--welcome-only") {
            precondition(LibraryWelcomeArtwork.image != nil, "The welcome illustration must be bundled")
            precondition(abs(LibraryWelcomeArtwork.image!.size.width / LibraryWelcomeArtwork.image!.size.height - 1487.0 / 450.0) < 0.02,
                         "Only the illustration crop should be rendered above native copy and controls")
            store.items = []; store.syncSnapshot = nil
            for (name, width, height, chinese) in [("welcome-reference", 1487.0, 1058.0, true), ("welcome-zh-wide", 1120.0, 760.0, true), ("welcome-zh-narrow", 420.0, 1100.0, true), ("welcome-en", 760.0, 760.0, false)] {
                let view = MediaLibraryWelcomeView().environmentObject(store)
                    .environment(\.locale, Locale(identifier: chinese ? "zh-Hans" : "en"))
                    .foregroundStyle(Color.pixfunInk).environment(\.colorScheme, .dark)
                    .frame(width: width, height: height, alignment: .top).background(Color.pixfunBackground)
                let host = NSHostingView(rootView: view)
                let rect = NSRect(x: 0, y: 0, width: width, height: height)
                let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host; host.frame = rect
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
                print("Rendered \(name)")
            }
            return
        }
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
