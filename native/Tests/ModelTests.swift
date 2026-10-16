import Foundation

@main struct NativeModelTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            guard value() else { fatalError("FAIL: \(label)") }; checks += 1
        }
        // Explicit, opt-in integration probe. Normal tests never call Apple services.
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--live-boundary",
           let lat = Double(CommandLine.arguments[2]), let lon = Double(CommandLine.arguments[3]),
           let query = PlaceQuery(CaptureLocation(latitude: lat, longitude: lon), language: "zh-Hans") {
            do {
                let match = try await PlaceBoundaryLookup().lookup(query)
                print("OSM boundary: \(String(describing: match))")
            } catch { print("OSM boundary unavailable: \(error)") }
            return
        }
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--live-place",
           let lat = Double(CommandLine.arguments[2]), let lon = Double(CommandLine.arguments[3]),
           let query = PlaceQuery(CaptureLocation(latitude: lat, longitude: lon), language: "zh-Hans") {
            if let address = try await PlaceNameResolver.appleLookup(query) { print("Apple Maps result: \(address.label ?? "") | area: \(address.area ?? "")") }
            else { print("Apple Maps returned no address; coordinate fallback remains available.") }
            return
        }
        let savedSettings = AppSettingsDraft()
        check(CameraMotionLabel.display("Pushing in + Horizontal pan right", chinese: true) == "向前推进 · 向右摇镜", "compound movement is readable Chinese")
        check(CameraMotionLabel.display("PUSHING IN+Horizontal Pan Right", chinese: true) == "向前推进 · 向右摇镜", "motion aliases ignore case and separator spacing")
        check(CameraMotionLabel.display("Push in then pan right", chinese: true) == "向前推进 → 向右摇镜", "explicit sequence is preserved")
        check(CameraMotionLabel.display("Zoom in", chinese: true) == "变焦放大", "zoom is not physical camera movement")
        check(CameraMotionLabel.display("Following", chinese: true) == "跟随拍摄", "existing simple motion still localizes")
        check(CameraMotionLabel.display("向右摇镜", chinese: true) == "向右摇镜", "Chinese evidence stays unchanged")
        check(CameraMotionLabel.display("Unknown movement", chinese: true) == "Unknown movement", "unknown motion is never guessed")
        check(CameraMotionLabel.display("Pushing in + Horizontal pan right", chinese: false) == "Pushing in + Horizontal pan right", "English mode preserves original evidence")
        check(!savedSettings.onlinePlaceNames, "online place lookup defaults off")
        var privacyDraft = savedSettings
        privacyDraft.onlinePlaceNames = true
        check(privacyDraft != savedSettings && !savedSettings.onlinePlaceNames, "place consent remains a draft until confirmation")
        let suite = "com.pixfun.place-tests.\(UUID().uuidString)"
        let placeDefaults = UserDefaults(suiteName: suite)!
        defer { placeDefaults.removePersistentDomain(forName: suite) }
        let coordinate = CaptureLocation(latitude: 40.0248, longitude: 116.2882, source: "file-metadata")
        let placeQuery = PlaceQuery(coordinate, language: "zh-Hans")!
        check(PlaceQuery(CaptureLocation(latitude: 91, longitude: 0), language: "en") == nil, "invalid coordinates never reach a service")
        check(PlaceQuery(CaptureLocation(latitude: .nan, longitude: 0), language: "en") == nil, "non-finite coordinates never reach a service")
        check(placeQuery.key != PlaceQuery(coordinate, language: "en")!.key, "cached places are language-specific")
        check(placeQuery.key != PlaceQuery(CaptureLocation(latitude: 40.02481, longitude: 116.2882), language: "zh-Hans")!.key, "nearby coordinates are not merged into one guessed address")
        check(PlaceAddress(region: "北京市", city: "北京市", district: "海淀区", street: "颐和园路").label == "北京市 · 海淀区 · 颐和园路", "address components are deduplicated")
        check(PlaceAddress().label == nil, "missing placemark does not invent a place")
        let campus = PlaceAddress(city: "北京市", district: "海淀区", street: "至善路", area: "清华大学", nearbyName: "清华大学药学院")
        check(campus.label == "北京市 · 海淀区 · 清华大学 · 至善路", "coordinate area and internal road form a hierarchy")
        check(campus.label?.contains("药学院") == false, "nearby reference is not a verified photographed building")
        typealias Boundary = PlaceBoundaryPolicy
        func boundary(_ type: String = "area", _ id: Int64 = 1234, _ name: String = "测试大学", _ tags: [String: String] = ["amenity": "university"]) -> Boundary.Element {
            .init(type: type == "area" ? "contained" : type, id: id, tags: tags.merging(["name": name, "_osm_type": type]) { _, new in new })
        }
        func match(_ elements: [Boundary.Element], language: String = "zh-Hans", remark: String? = nil) -> Boundary.Match? {
            Boundary.match(.init(elements: elements, remark: remark), language: language)
        }
        let campusBoundary = match([boundary()])!
        check(campusBoundary.name == "测试大学" && campusBoundary.relation == "inside", "arbitrary mapped campus is selected by containment, not a hardcoded name")
        check(match([boundary("node")]) == nil, "a nearby campus POI is not a campus boundary")
        check(match([boundary("way")]) == nil, "nearby campus perimeter does not prove containment")
        check(match([.init(type: "contained", id: 2345, tags: ["_osm_type": "way", "name": "闭合校园", "amenity": "university"])])?.relation == "inside", "is_in closed ways support campuses without relation areas")
        check(match([boundary(), boundary("area", 2222, "另一大学")]) == nil, "conflicting same-rank boundaries abstain")
        check(match([boundary(), boundary()], remark: "runtime error: timeout") == nil, "partial Overpass output never produces a place")
        check(match([]) == nil, "missing coverage does not invent a place")
        check(match([boundary("area", 1234, "", ["amenity": "university"])]) == nil, "unnamed boundaries stay unnamed")
        check(match([boundary("area", 1234, "测试省", ["boundary": "administrative"])]) == nil, "province containment never invents a scenic destination")
        check(match([boundary("area", 1234, "湖景酒店", ["tourism": "hotel"])]) == nil, "hotel names do not establish a lake")
        let waterTags = ["natural": "water", "water": "lake"]
        let lake = match([boundary("relation", 4321, "测试湖", waterTags)])!
        check(lake.relation == "nearby" && lake.kind == "lake", "100m lake perimeter query is explicitly proximity")
        check(match([boundary("area", 4321, "测试湖", waterTags)])?.relation == "inside", "only is_in water area proves containment")
        check(match([boundary("relation", 4321, "测试湖", waterTags), boundary("relation", 4322, "另一湖", waterTags)]) == nil, "ambiguous neighboring lakes abstain")
        check(match([boundary(), boundary("relation", 4321, "测试湖", waterTags)])?.kind == "campus", "contained campus wins over a nearby lake")
        check(match([boundary("area", 4321, "小公园", ["leisure": "park"]), boundary()])?.kind == "campus", "campus groups its smaller parks")
        check(match([boundary("area", 1234, "大学", ["amenity": "university", "name:en": "Example University"])], language: "en")?.name == "Example University", "boundary names follow requested language")
        let corrected = Boundary.applying(campusBoundary, to: PlaceAddress(city: "北京市", street: "至善路", area: "错误的公园"), language: "zh-Hans")
        check(corrected.displayName == "北京 测试大学", "city and campus form a concise tag")
        check(corrected.area == "测试大学" && corrected.label?.contains("错误的公园") == false, "boundary evidence can correct an unrelated reverse-geocoder area")
        check(corrected.street == "至善路", "street detail remains available")
        let lakeside = Boundary.applying(lake, to: PlaceAddress(region: "青海省", city: "海南藏族自治州"), language: "zh-Hans")
        check(lakeside.displayName == "青海 测试湖附近", "lake context uses province and preserves proximity")
        check(lakeside.label?.contains("附近") == true, "full address also preserves proximity")
        check(Boundary.applying(lake, to: nil, language: "en").displayName == "测试湖 vicinity", "boundary result survives Apple outage without inventing a city")
        check(Boundary.query(placeQuery).contains("is_in(40.0248,116.2882)") && !Boundary.query(placeQuery).contains("清华"), "request uses coordinates and generic categories only")
        check(!savedSettings.onlinePlaceBoundaries, "new provider never inherits Apple consent automatically")
        var placeCalls = 0
        let resolver = PlaceNameResolver(defaults: placeDefaults, interval: 0.001, lookup: { query in
            placeCalls += 1
            try await Task.sleep(nanoseconds: 10_000_000)
            return PlaceAddress(street: "北京市 · 海淀区 · 颐和园路")
        })
        resolver.schedule([placeQuery], enabled: false, foreground: true)
        try await Task.sleep(nanoseconds: 20_000_000)
        check(placeCalls == 0, "no consent means no network call")
        resolver.schedule([placeQuery], enabled: true, foreground: false)
        try await Task.sleep(nanoseconds: 20_000_000)
        check(placeCalls == 0, "background app does not initiate lookups")
        resolver.schedule([placeQuery, placeQuery], enabled: true, foreground: true)
        try await Task.sleep(nanoseconds: 2_000_000)
        resolver.schedule([placeQuery], enabled: true, foreground: true)
        for _ in 0..<100 where resolver.cached(placeQuery) == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        check(resolver.cached(placeQuery) == "北京市 · 海淀区 · 颐和园路" && placeCalls == 1, "duplicate and in-flight queries are coalesced")
        let reopened = PlaceNameResolver(defaults: placeDefaults, lookup: { _ in fatalError("cache hit must not use network") })
        check(reopened.cached(placeQuery) == resolver.cached(placeQuery), "names survive client restarts in a local cache")
        var boundaryCalls = 0
        let enrichedResolver = PlaceNameResolver(defaults: placeDefaults, interval: 0.001,
            useBoundaries: { true }, lookup: { _ in PlaceAddress(city: "北京市", street: "至善路") },
            boundaryLookup: { _ in boundaryCalls += 1; return campusBoundary })
        check(enrichedResolver.cached(placeQuery) == nil, "Apple-only cache does not prevent new boundary enrichment")
        enrichedResolver.schedule([placeQuery], enabled: true, foreground: true)
        for _ in 0..<100 where enrichedResolver.cached(placeQuery) == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        check(boundaryCalls == 1 && enrichedResolver.resolved(placeQuery)?.displayName == "北京 测试大学", "boundary enrichment flows through scheduled cache and result contract")
        let boundaryCache = PlaceNameResolver(defaults: placeDefaults, useBoundaries: { true },
            lookup: { _ in fatalError("cache must not query") }, boundaryLookup: { _ in fatalError("cache must not query boundaries") })
        check(boundaryCache.resolved(placeQuery)?.boundaryID == "area/1234", "boundary identity survives client restarts")
        let offlineSuite = suite + ".boundary-offline"
        let offlineDefaults = UserDefaults(suiteName: offlineSuite)!
        defer { offlineDefaults.removePersistentDomain(forName: offlineSuite) }
        let boundaryOffline = PlaceNameResolver(defaults: offlineDefaults, interval: 0.001, useBoundaries: { true },
            lookup: { _ in PlaceAddress(city: "北京市", street: "原街道") },
            boundaryLookup: { _ in throw URLError(.notConnectedToInternet) })
        boundaryOffline.schedule([placeQuery], enabled: true, foreground: true)
        for _ in 0..<100 where boundaryOffline.cached(placeQuery) == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        check(boundaryOffline.resolved(placeQuery)?.version == 2 && boundaryOffline.cached(placeQuery)?.contains("原街道") == true, "boundary outage preserves Apple's address without claiming containment")
        let retryBoundary = PlaceNameResolver(defaults: offlineDefaults, now: { Date().addingTimeInterval(901) }, useBoundaries: { true })
        check(retryBoundary.cached(placeQuery) == nil, "failed enrichment retries after cooldown, not after 30 days")
        let noBoundarySuite = suite + ".boundary-disabled"
        let noBoundaryDefaults = UserDefaults(suiteName: noBoundarySuite)!
        defer { noBoundaryDefaults.removePersistentDomain(forName: noBoundarySuite) }
        let boundaryDisabled = PlaceNameResolver(defaults: noBoundaryDefaults, useBoundaries: { false },
            lookup: { _ in PlaceAddress(city: "北京") }, boundaryLookup: { _ in fatalError("new provider needs separate consent") })
        boundaryDisabled.schedule([placeQuery], enabled: true, foreground: true)
        for _ in 0..<100 where boundaryDisabled.cached(placeQuery) == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        check(boundaryDisabled.resolved(placeQuery)?.version == 2, "Apple consent alone never queries the new provider")
        let expired = PlaceNameResolver(defaults: placeDefaults, now: { Date().addingTimeInterval(31 * 86400) }, lookup: { _ in nil })
        check(expired.cached(placeQuery) == nil, "expired cache entries can be refreshed")
        var noResultCalls = 0
        let noResult = PlaceNameResolver(defaults: UserDefaults(suiteName: suite + ".empty")!, lookup: { _ in noResultCalls += 1; return nil })
        defer { UserDefaults.standard.removePersistentDomain(forName: suite + ".empty") }
        noResult.schedule([placeQuery], enabled: true, foreground: true)
        try await Task.sleep(nanoseconds: 20_000_000)
        noResult.schedule([placeQuery], enabled: true, foreground: true)
        try await Task.sleep(nanoseconds: 20_000_000)
        check(noResultCalls == 1 && noResult.cached(placeQuery) == nil, "no-result responses fall back and do not retry on each refresh")
        var failedCalls = 0
        let failedResolver = PlaceNameResolver(defaults: UserDefaults(suiteName: suite + ".failed")!, lookup: { _ in
            failedCalls += 1; throw NSError(domain: "offline-fixture", code: 1)
        })
        defer { UserDefaults.standard.removePersistentDomain(forName: suite + ".failed") }
        failedResolver.schedule([placeQuery], enabled: true, foreground: true)
        try await Task.sleep(nanoseconds: 20_000_000)
        failedResolver.schedule([placeQuery], enabled: true, foreground: true)
        try await Task.sleep(nanoseconds: 20_000_000)
        check(failedCalls == 1 && failedResolver.cached(placeQuery) == nil, "network failures keep coordinates and back off without a request loop")
        failedResolver.cancel()
        let cancelled = PlaceNameResolver(defaults: UserDefaults(suiteName: suite + ".cancel")!, lookup: { _ in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return PlaceAddress(street: "must not publish after consent withdrawal")
        })
        defer { UserDefaults.standard.removePersistentDomain(forName: suite + ".cancel") }
        cancelled.schedule([placeQuery], enabled: true, foreground: true)
        try await Task.sleep(nanoseconds: 5_000_000)
        cancelled.schedule([], enabled: false, foreground: true)
        try await Task.sleep(nanoseconds: 20_000_000)
        check(cancelled.cached(placeQuery) == nil, "revoking consent discards in-flight responses")
        var pendingSettings = savedSettings
        pendingSettings.language = .english
        check(savedSettings.language == .chinese, "language selection edits an isolated draft")
        check(!pendingSettings.requiresCloudSave(comparedTo: savedSettings), "language-only confirmation never touches provider or Keychain")
        check(pendingSettings.validationIssue == nil, "local mode does not require cloud credentials")
        pendingSettings = savedSettings
        check(pendingSettings == savedSettings, "cancel discards pending settings")
        pendingSettings.mode = "cloud"
        check(pendingSettings.requiresCloudSave(comparedTo: savedSettings), "processing mode change requires explicit save")
        check(pendingSettings.validationIssue == "Enter a text model ID.", "validate cloud model before committing anything")
        pendingSettings.cloud.model = "test-model"
        check(pendingSettings.validationIssue == "Enter an API key.", "validate credentials before committing anything")
        pendingSettings.cloud.apiKey = "test-only"
        check(pendingSettings.validationIssue == "Enter a vision model ID.", "cloud analysis requires a vision model")
        pendingSettings.mode = "hybrid"
        check(pendingSettings.validationIssue == nil, "hybrid processing does not require cloud vision")
        let captureMetadata = try JSONDecoder().decode(Metadata.self, from: Data(#"{"capturedAt":"2026-10-05T13:30:45+0800","camera":"iPhone 14 Pro Max","mediaCreatedAt":"2026-10-07T13:40:14Z"}"#.utf8))
        check(captureMetadata.captureDate == ISO8601DateFormatter().date(from: "2026-10-05T05:30:45Z"), "card capture time uses actual recording metadata and honors timezone")
        check(captureMetadata.camera == "iPhone 14 Pro Max", "card device label decodes recorded camera model")
        let originalMetadata = try JSONDecoder().decode(Metadata.self, from: Data(#"{"fps":59.94,"videoCodec":"hevc","audioCodec":"aac","mediaCreatedAt":"2026-10-11T06:23:20Z","dateSource":"QuickTime creationdate"}"#.utf8))
        check(originalMetadata.frameRateLabel == "59.94 fps", "original frame rate retains fractional precision")
        check(Metadata(fps: 60).frameRateLabel == "60 fps", "integer frame rates have no redundant decimals")
        check(Metadata(fps: 0).frameRateLabel == nil && Metadata(fps: .infinity).frameRateLabel == nil, "unread or invalid frame rates are not fabricated")
        check(Metadata.codecLabel(originalMetadata.videoCodec) == "HEVC (H.265)", "video codec is decoded from file metadata")
        check(Metadata.codecLabel(originalMetadata.audioCodec) == "AAC", "audio codec is decoded separately")
        check(Metadata.codecLabel("unknown") == nil && Metadata.codecLabel(nil) == nil, "unknown codecs stay absent")
        check(originalMetadata.mediaCreatedAt == "2026-10-11T06:23:20Z" && originalMetadata.dateSource == "QuickTime creationdate", "container date and capture-date provenance remain separate")
        check(originalMetadata.captureDate == nil, "container creation date must not become a capture date")
        let exportOnly = try JSONDecoder().decode(Metadata.self, from: Data(#"{"mediaCreatedAt":"2026-10-07T13:40:14Z"}"#.utf8))
        let locationFixture = #"{"id":"capture","file":{"name":"Original.MOV"},"kind":"video","status":"ready","metadata":{"duration":10,"location":{"latitude":39.9,"longitude":116.4,"source":"file-metadata"}},"result":{"analysis":{"subtitleState":"transcribed","subtitleSource":"local-asr","subtitleCues":[{"start":1,"end":3,"text":"前面就是入口"}]}},"analysisEvidence":{"version":1,"tags":[],"onScreenText":[{"text":"游客中心","start":2,"end":8,"confidence":0.95}]}}"#
        var capturedItem = try JSONDecoder().decode(MediaItem.self, from: Data(locationFixture.utf8))
        let localCaptureSource = MediaSourceIdentity(item: capturedItem)
        let phoneBadge = MediaCaptureIdentity(camera: "iPhone 14 Pro Max", source: localCaptureSource)
        check(phoneBadge.name == "iPhone 14 Pro Max" && phoneBadge.symbol == "iphone", "iPhone imported locally uses phone badge, not computer")
        check(localCaptureSource.symbol == "desktopcomputer", "camera badge never changes import source semantics")
        check(MediaCaptureIdentity(camera: " IPHONE 15 PRO ", source: localCaptureSource).symbol == "iphone", "camera icon handles case and whitespace")
        check(MediaCaptureIdentity(camera: "iPad Pro", source: localCaptureSource).symbol == "ipad", "tablet does not use a phone or computer icon")
        check(MediaCaptureIdentity(camera: "Google Pixel 9", source: localCaptureSource).symbol == "smartphone", "known Android phone uses smartphone icon")
        check(MediaCaptureIdentity(camera: "Sony ILCE-7M4", source: localCaptureSource).symbol == "camera", "named cameras use camera icon")
        check(MediaCaptureIdentity(camera: "DJI Osmo Pocket 3", source: localCaptureSource).symbol == "camera", "manufacturer alone does not imply a drone")
        check(MediaCaptureIdentity(camera: nil, source: localCaptureSource).symbol == localCaptureSource.symbol, "missing capture device uses actual import source")
        check(MediaCaptureIdentity(camera: "  ", source: localCaptureSource).name == localCaptureSource.name, "blank camera uses matching source label and icon")
        var mappedItem = capturedItem
        mappedItem.metadata?.location = coordinate
        let originalCoordinate = mappedItem.metadata?.location?.coordinates
        mappedItem = resolver.applyingCache(to: [mappedItem], language: "zh-Hans")[0]
        check(mappedItem.recordedLocation == "北京市 · 海淀区 · 颐和园路", "cached names replace coordinate-only labels")
        check(mappedItem.metadata?.location?.coordinates == originalCoordinate, "name lookup never changes source coordinates")
        check(mappedItem.matches("海淀区") && mappedItem.matches("40.02480"), "both resolved names and original coordinates remain searchable")
        check(MediaQuickTags.tags(mappedItem).first?.text == mappedItem.recordedLocation, "location tags share the resolved name")
        check(mappedItem.locationAttribution.contains("Approximate area"), "geocoded areas are never claimed as verified visits")
        check(resolver.applyingCache(to: [mappedItem], language: "en")[0].recordedLocation == originalCoordinate, "language change does not reuse stale-language labels")
        mappedItem.context = ["location":"用户指定地点"]
        check(resolver.applyingCache(to: [mappedItem], language: "zh-Hans")[0].recordedLocation == "用户指定地点", "user place names are never overwritten")
        mappedItem.context = nil; mappedItem.metadata?.location?.name = "文件内地点"
        check(resolver.applyingCache(to: [mappedItem], language: "zh-Hans")[0].recordedLocation == "文件内地点", "source place names take priority without a network request")
        check(capturedItem.recordedLocation == "39.90000, 116.40000", "GPS-only capture stays coordinates; no guessed city")
        check(MediaQuickTags.tags(capturedItem).first?.facet == .location, "metadata locations appear in the location filter")
        check(capturedItem.subtitleSourceLabel == "Speech transcription", "speech and authored captions have distinct provenance")
        check(capturedItem.transcriptCues.first?.text == "前面就是入口", "saved ASR is available to the detail page")
        let capturedSearch = MediaSearchDocument(capturedItem)
        check(capturedSearch.fields.contains { $0.text == "游客中心" && $0.start == 2 }, "OCR text is searchable at its observation window")
        capturedItem.context = ["location":"用户确认地点"]
        check(capturedItem.recordedLocation == "用户确认地点", "confirmed location wins without overwriting source GPS")
        check(capturedItem.name == "Original.MOV", "capture extraction preserves the original filename")
        capturedItem.result?.analysis?.subtitleMessage = "No embedded subtitles. Speech recognition is not bundled in this build."
        check(capturedItem.subtitleDisplayMessage == "No saved transcript yet. Analyze this file to extract subtitles and speech.", "legacy cache does not claim current build lacks speech recognition")
        capturedItem.result?.analysis?.subtitleMessage = "Speech recognition failed."
        check(capturedItem.subtitleDisplayMessage == "Speech recognition failed.", "actual speech failures remain visible")
        check(exportOnly.captureDate == nil, "container/export date is never mislabeled as capture date")
        check(Metadata(capturedAt: "invalid").captureDate == nil, "malformed capture dates remain unknown")
        check(Metadata(capturedAt: "2026-10-05T05:30:45.123Z").captureDate != nil, "fractional-second capture timestamps are supported")
        check(WorkspacePage.mediaPages == [.media, .mediaSync], "Media groups the library and sync")
        check(WorkspacePage.creationPages == [.home, .project, .skills] && WorkspacePage.project.isCreation, "Create groups new video, projects and skills")
        check(WorkspacePage.primaryPages == [.media, .mediaSync, .home, .project, .skills], "all destinations have one sidebar entry and keyboard shortcut")
        check(Set(WorkspacePage.primaryPages) == Set(WorkspacePage.allCases), "sidebar covers every destination exactly once")
        check(WorkspacePage.home.navigationTitle == "New video" && WorkspacePage.skills.navigationTitle == "Skills", "child labels remain distinct from the Create group")
        let syncJSON = #"{"devices":[{"id":"card","name":"Card","kind":"camera","status":"Paused","message":"Completed files are kept.","automatic":true,"photos":true,"videos":true,"connected":true,"busy":false,"lastSync":null,"completed":2,"total":10,"failed":1,"skipped":3,"bytes":500,"totalBytes":1000}],"storage":[{"id":"working","name":"Not configured","path":null,"availableBytes":null,"connected":false,"enabled":false}],"available":[],"archivePending":0,"archiving":false,"phoneAvailable":false}"#
        let sync = try JSONDecoder().decode(MediaSyncSnapshot.self, from: Data(syncJSON.utf8))
        check(sync.devices[0].processed == 5 && sync.devices[0].pending == 4, "sync counts separate ready, pending and failed files")
        check(sync.devices[0].fraction == 0.5, "sync progress uses real transferred bytes")
        check(sync.devices[0].action == "Resume", "paused imports have a direct resume action")
        check(!sync.storageBusy && sync.working?.path == nil, "empty storage remains unconfigured without fabricated capacity")
        check(!sync.phoneAvailable, "unconnected phone capability stays unavailable")
        check(sync.wifi == nil, "older service snapshots do not fabricate Wi-Fi readiness")
        let wifi = try JSONDecoder().decode(SyncWiFi.self, from: Data(#"{"enabled":true,"error":null,"pairing":{"payload":"test-code","expiresAt":2000000000}}"#.utf8))
        check(wifi.enabled && wifi.pairing?.payload == "test-code", "Wi-Fi pairing preserves the QR payload and expiry")
        var phoneDevice = sync.devices[0]; phoneDevice.kind = "phone"; phoneDevice.status = "Offline"
        check(phoneDevice.method == "Wi-Fi sync" && phoneDevice.phaseTitle == "Waiting for phone", "phone sources use their existing card with correct connection state")
        check(phoneDevice.phaseMessage.contains("same Wi-Fi") && phoneDevice.phaseMessage.contains("Background"), "offline phone instructions explain connection and background limitations")
        let detectedCard = try JSONDecoder().decode(SyncDiscoveredSource.self, from: Data(#"{"id":"volume-id","name":"EOS_CARD","path":"/Volumes/EOS_CARD","kind":"camera"}"#.utf8))
        check(detectedCard.name == "EOS_CARD" && detectedCard.kind == "camera", "discovery preserves system volume name and supported source kind")
        let legacySource = try JSONDecoder().decode(SyncDiscoveredSource.self, from: Data(#"{"id":"volume-id","name":"Travel SSD","path":"/Volumes/Travel SSD"}"#.utf8))
        check(legacySource.kind == nil, "existing discovery snapshots remain compatible")
        var syncDevice = sync.devices[0]
        syncDevice.status = "Waiting for storage"
        check(!syncDevice.checking && !syncDevice.showsProgress, "waiting for a drive is not active transfer progress")
        check(syncDevice.phaseMessage.contains("automatically"), "storage reconnection explains automatic recovery")
        syncDevice.status = "Offline"
        check(syncDevice.phaseTitle == "Waiting for your device" && !syncDevice.needsAttention, "automatic offline source is a normal waiting state")
        syncDevice.automatic = false
        check(syncDevice.phaseTitle == "Disconnected" && syncDevice.needsAttention, "manual offline source retains explicit recovery")
        syncDevice.automatic = true
        syncDevice.bytes = 2000
        check(syncDevice.fraction == 1, "sync progress is clamped")
        syncDevice.totalBytes = 0
        check(syncDevice.fraction == 0, "scan without known total does not fabricate a percentage")
        syncDevice.status = "Needs Attention"
        check(syncDevice.action == "Retry", "failed imports have a direct retry action")
        syncDevice.status = "Scanning"
        check(syncDevice.checking, "resume checking does not present a reset determinate progress bar")
        syncDevice.status = "Waiting"
        check(syncDevice.checking, "queued work is distinguished from copying")
        syncDevice.completed = 0; syncDevice.failed = 0; syncDevice.skipped = 10
        check(syncDevice.summary == "10 already imported", "completed duplicate-only runs do not add redundant zero counts")
        syncDevice.status = "Completed"
        check(syncDevice.phaseTitle == "Up to date" && syncDevice.actionLabel == "Check for new", "duplicate-only imports offer a simple recheck")
        syncDevice.status = "Verifying"; syncDevice.bytes = 1000; syncDevice.totalBytes = 1000
        check(!syncDevice.showsProgress && syncDevice.phaseTitle == "Verifying copies", "100 percent copied is not import completion")
        syncDevice.status = "Paused"; syncDevice.busy = true
        check(syncDevice.phaseTitle == "Pausing…" && !syncDevice.showsProgress, "pause waits for the current safe step")
        syncDevice.busy = false
        check(syncDevice.showsProgress && syncDevice.actionLabel == "Continue import", "paused job keeps progress and one recovery action")
        syncDevice.status = "Offline"
        check(!syncDevice.needsAttention && syncDevice.phaseMessage.contains("Plug it in"), "completed disconnected source stays quiet but keeps recovery guidance")
        check(AgentExample.starters.count == 3, "three supported starter workflows")
        check(Set(AgentExample.starters.map(\.symbol)).count == 3, "starter actions have distinct icons")
        check(AgentExample.starters.map(\.id) == ["analyze", "create", "highlights"], "starters offer analysis, a travel video, then a short highlight reel")
        check(AgentExample.starters.allSatisfy { $0.outcome.count < 30 }, "three starter requests remain concise")
        check(AgentExample.starters.allSatisfy { $0.prompt.count <= 90 && $0.prompt.filter { $0 == "." }.count == 1 && !$0.prompt.contains("\n") }, "inserted starter requests are one short sentence")
        check(AgentExample.starters[1].prompt.hasPrefix("Create a travel video") && AgentExample.starters[2].prompt.hasPrefix("Make a short travel highlight reel"), "video starters request distinct finished outputs, not plans")
        let example = AgentExample.starters[0]
        check(example.applying(to: " \n") == example.prompt, "example fills an empty draft")
        check(example.applying(to: "Keep my instruction") == "Keep my instruction", "custom draft stays intact until replacement is confirmed")
        check(example.requiresReplacementConfirmation(for: "Keep my instruction"), "custom draft requires confirmation")
        check(example.applying(to: AgentExample.starters[2].prompt) == example.prompt, "switching starters replaces conflicting instructions")
        check(AgentExample.starters[0].prompt == "Summarize my media and suggest what to use.", "analysis starter covers photos and videos")
        check(AgentExample.starters.allSatisfy { example in
            let text = "\(example.title) \(example.outcome) \(example.prompt)".lowercased()
            return !["original sound", "original audio", "each video", "no music", "no narration", "16:9", "9:16"].contains { text.contains($0) }
        }, "starter copy does not impose source audio, video-only inputs or skill-specific finishing choices")
        let raw = #"{"id":"a","file":{"name":"trip.mov","size":123},"kind":"video","status":"ready","metadata":{"width":1080,"height":1920,"duration":690,"hasAudio":true},"favorite":true,"context":{"location":"Glacier","device":"iPhone"},"description":"A mountain walk","result":{"analysis":{"segments":[{"id":"seg-1","label":"Chapter 1","start":0,"end":86.25,"boundary":{"type":"time_split"}}],"subtitleCues":[{"start":0.2,"end":3,"text":"Complete spoken sentence"}]}}}"#
        let item = try JSONDecoder().decode(MediaItem.self, from: Data(raw.utf8))
        var syncedItem = item; syncedItem.id = "synced"; syncedItem.syncSourceId = "camera"; syncedItem.syncSourceName = "My camera"
        check(MediaFilter(syncSourceID: "camera").apply([item, syncedItem], locations: [:]).map(\.id) == ["synced"], "View Media locates imported assets independent of Working Storage paths")
        let restoredSync = try JSONDecoder().decode(MediaItem.self, from: JSONEncoder().encode(syncedItem))
        check(restoredSync.syncSourceId == "camera", "device identity survives library decoding")
        let syncStore = WorkspaceStore()
        syncStore.items = [item, syncedItem]; syncStore.syncSourceName = "My camera"; syncStore.syncSourceID = "camera"
        check(syncStore.visibleItems.map(\.id) == ["synced"] && syncStore.hasMediaFilters, "device filter uses the existing media browser")
        check(syncStore.mediaResultSummary.contains("My camera"), "device context stays visible while browsing")
        check(syncStore.importedSources.count == 1, "many imported assets share one source menu entry")
        syncStore.resetMediaFilters()
        check(syncStore.visibleItems.count == 2 && syncStore.syncSourceID == nil, "Clear returns to the full library")
        check(item.aspect == 1080.0 / 1920.0, "portrait aspect retained")
        check(item.matches("GLACIER") && item.matches("iphone"), "search location and device")
        check(item.matches("spoken sentence"), "search subtitles, not substitute for description")
        check(item.transcriptCues.count == 1, "real subtitles keep transcript module available")
        var silent = item
        silent.result?.analysis?.subtitleCues = nil
        check(silent.transcriptCues.isEmpty, "missing subtitles hide transcript module")
        silent.result?.analysis?.subtitleCues = [Cue(start: 0, text: " \n\t ")]
        check(silent.transcriptCues.isEmpty, "blank subtitle entries do not create an empty module")
        silent.result?.analysis?.subtitleCues?.append(Cue(start: 2, text: "A real line"))
        check(silent.transcriptCues.count == 1 && silent.cues.count == 2, "display filters blank entries without changing stored subtitles")
        check(!item.matches("unrelated"), "search mismatch")
        var described = item
        described.videoDescription = VideoDescription(status: "ready", title: "林间徒步抵达观景点", full_description: "同行者在观景点停留，适合作为故事转折。")
        check(described.name == "trip.mov" && described.file.name == "trip.mov", "analysis never replaces the displayed or original filename")
        check(MediaSearchDocument(described).match(MediaSearchQuery("林间徒步"), scope: .content, location: nil) != nil, "suggested titles remain searchable as content metadata")
        var evidenced = described
        let riverTag = EvidenceTag(id:"scene:water", category:"scene", key:"water", label:"Lakes & rivers", aliases:["河流"], source:"visual-observation", evidence:[.init(start:2, end:6, shotIds:["canonical"], text:"river")])
        evidenced.analysisEvidence = .init(version:1, tags:[riverTag])
        check(MediaQuickTags.tags(evidenced).contains { $0.key == "water" }, "structured tags use existing filter IDs")
        check(!MediaQuickTags.tags(evidenced).contains { $0.key == "mountain" }, "structured tags do not leak legacy prose-derived classifications")
        let evidenceHits = MediaSearchDocument(evidenced).match(MediaSearchQuery("河流"), scope: .content, location: nil)
        check(evidenceHits?.first?.start == 2 && evidenceHits?.first?.segmentID == "canonical", "tag synonyms retain observed time and shot identity")
        evidenced.tagCorrections = .init(hidden:["scene:water"], added:[])
        check(evidenced.evidenceTags.isEmpty && !MediaQuickTags.tags(evidenced).contains { $0.key == "water" }, "correction hides a category without modifying the source evidence")
        let roundtripEvidence = try JSONDecoder().decode(MediaItem.self, from: JSONEncoder().encode(evidenced))
        check(roundtripEvidence.generatedTags.count == 1 && roundtripEvidence.evidenceTags.isEmpty, "corrections and original evidence survive decoding separately")
        check(described.matches("故事转折") && described.matches("trip.mov"), "search full description and original filename")
        var sample = described
        sample.isExample = true
        sample.sampleCopy = VideoDescription(status: "ready", title: "Wild Alaska", full_description: "A journey through Lake Clark, from lakes and forest to snow-covered peaks.", coverage: "Prepared editorial sample", model: "Prepared editorial example")
        sample.videoDescription?.status = "running"
        check(sample.name == "Wild Alaska", "sample title stays English during reanalysis")
        check(sample.displayVideoDescription?.full_description == sample.sampleCopy?.full_description, "old Chinese sample description displays authored English copy")
        check(sample.videoDescription?.busy == true && sample.videoDescription?.title == described.videoDescription?.title, "sample presentation preserves running analysis and original results")
        check(sample.displayVideoDescription?.coverage == "Prepared editorial sample", "prepared sample is not mislabeled as model output")
        sample.videoDescription?.full_description = "An English model description."
        check(sample.displayVideoDescription?.full_description == "An English model description.", "new English analysis remains visible")
        let restoredDescription = try JSONDecoder().decode(MediaItem.self, from: JSONEncoder().encode(described))
        check(restoredDescription.videoDescription?.full_description == described.videoDescription?.full_description, "description survives round trip")
        let numberedDescription = VideoDescription(status: "ready", full_description: "A riverside view reveals a mountain.\n\n1. Opening view: A wide view of the river.\n2. Camera movement: The camera pans at 3.1s.\nThe same continuous take reveals two figures.\n\nEditing note: Use as an establishing moment.\nVerification note: Confirm the transcript before quoting it.")
        let reading = numberedDescription.readingBlocks
        check(reading.count == 5 && reading[0].kind == .overview, "overview is separate from numbered moments and notes")
        check(reading[1].number == "1" && reading[1].label == "Opening view", "numbered detail has a separate label")
        check(reading[2].text.contains("3.1s.") && reading[2].text.contains("continuous take"), "wrapped detail retains decimal timestamps and shot continuity")
        check(reading[3].kind == .note && reading[4].label == "Verification note", "editing and verification remain visible distinct notes")
        check(numberedDescription.contentBlocks.count == 4 && numberedDescription.contentBlocks.last?.label == "Verification note", "factual content keeps uncertainty but separates editing advice")
        check(numberedDescription.editingNotes.count == 1 && numberedDescription.editingNotes[0].text == "Use as an establishing moment.", "old editing advice is preserved for its own disclosure")
        check(numberedDescription.full_description?.contains("Editing note:") == true, "presentation never rewrites stored descriptions")
        let legacyText = "The sequence opens with a wide view of a river bordered by a stone retaining wall and branches in the foreground. The camera stays steady until 3.1s, then pans right to reveal a rocky mountain beneath a blue sky. Two people stand near the bank as the camera tilts slightly upward, retaining the river surface and distant vehicles in view."
        let legacy = VideoDescriptionBlock.parse(legacyText)
        check(legacy.count > 1 && legacy.allSatisfy { $0.number == nil }, "legacy paragraphs are not relabeled as detected shots")
        check(legacy.map(\.text).joined(separator: " ") == legacyText, "legacy layout preserves every word and decimal timestamp")
        check(VideoDescriptionBlock.parse(" \n ").isEmpty, "blank descriptions create no empty reading blocks")
        check(ShotReadingText.summary("A river beside a stone wall. Several cars are parked above it.") == "A river beside a stone wall.", "shot summary shows one original sentence")
        check(ShotReadingText.summary("The camera pans at 3.1s. Two people appear.") == "The camera pans at 3.1s.", "shot summary does not split decimal timestamps")
        check(ShotReadingText.summary("河流流经石墙。岸边停着几辆汽车。") == "河流流经石墙。", "Chinese shot summaries stop at sentence boundaries")
        check(ShotReadingText.summary(String(repeating: "riverbank ", count: 40)).count <= 180, "long shot summaries have a bounded reading length")
        check(ShotReadingText.summary(" \n ") == "No shot description yet.", "missing shot text does not invent a scene")
        check(item.segments[0].splitReason == "Time-based split", "do not invent scene detection")
        var analyzed = item
        analyzed.shotAnalysis = ShotAnalysis(status: "ready", summary: "A continuous walk", segments: [Segment(id: "shot_001", label: "Continuous mountain walk", start: 0, end: 690, boundary: Segment.Boundary(type: "semantic_change"))])
        check(analyzed.segments.count == 1 && analyzed.segments[0].id == "shot_001", "editorial shots replace coarse navigation without changing originals")
        check(analyzed.segments[0].splitReason.contains("review timing"), "semantic sample boundaries expose uncertainty")
        check(analyzed.matches("Continuous mountain"), "editorial descriptions are searchable")
        let restoredShots = try JSONDecoder().decode(MediaItem.self, from: JSONEncoder().encode(analyzed))
        check(restoredShots.shotAnalysis?.summary == "A continuous walk", "editorial analysis persists")
        var highlight = EditorialShot(shot_id: "shot_001", start_time: "00:00:00.000", end_time: "00:00:08.000", description: "营地互动", shot_size: "中景", capture_type: "", camera_motion: "", story_role: ["高光"], dialogue: "", reaction: "", audio: [], importance_score: 80, duplicate_candidate: false, unusable_candidate: false, edit_recommendation: .init(level: "推荐", recommended_duration_sec: 3, reason: "保留互动"))
        check(highlight.isHighlight, "highlight includes score 80 with recommended usable shot")
        var presentation = analyzed
        presentation.videoDescription = .init(status: "failed", message: "Return only title and full_description.")
        presentation.shotAnalysis?.segments?[0].editorial = highlight
        check(presentation.descriptionShots.isEmpty, "single shot has no repeated numbered shot section")
        check(presentation.descriptionParagraphs == [highlight.description], "failed overview uses full single-shot evidence, not an empty placeholder")
        presentation.videoDescription = numberedDescription
        check(presentation.descriptionParagraphs.count == 1 && presentation.descriptionMoments.count == 2, "overview and distinct changes have separate reading levels")
        check(!presentation.descriptionParagraphs.joined().contains("establishing moment"), "editing advice is not visible factual prose")
        presentation.shotAnalysis?.segments?.append(.init(id:"later", label:"Later scene", start:700, end:710, editorial:highlight))
        check(presentation.descriptionShots.isEmpty, "generated changes are never replaced with raw multi-shot prose")
        check(presentation.descriptionParagraphs == ["A riverside view reveals a mountain."], "multi-shot overview excludes duplicate model-authored numbered moments")
        var retrieval = presentation
        retrieval.shotAnalysis?.segments?[0].editorial?.description = "五位身着黑色长袍的人手持金边托盘，背景有石雕与树木。"
        retrieval.videoDescription = .init(status: "ready", full_description: "五人站在平台上。\n\n1. 人物转身：中间一人转身向前移动。\n2. 镜头推进：木质平台占据更多画面。")
        check(retrieval.descriptionMoments.first?.label == "人物转身", "Chinese labels are separated from body text")
        check(retrieval.descriptionMoments.first?.text == "中间一人转身向前移动。", "concise changes are preserved verbatim")
        check(retrieval.descriptionShots.isEmpty && retrieval.matches("金边托盘"), "hidden raw evidence remains searchable")
        retrieval.videoDescription?.full_description = "五人站在木质平台上，手持托盘。"
        check(retrieval.descriptionShots.isEmpty && retrieval.descriptionMoments.isEmpty, "overview-only scenes do not acquire invented changes")
        retrieval.videoDescription = nil
        check(retrieval.descriptionShots.map(\.id) == ["shot_001", "later"], "missing synthesis falls back to reviewed evidence in time order")
        presentation.shotAnalysis = nil
        check(presentation.descriptionShots.isEmpty, "unreviewed observation windows do not become numbered shots")
        check(presentation.videoDescription?.full_description == numberedDescription.full_description, "presentation does not rewrite stored description")
        var searchable = item
        searchable.id = "searchable"
        searchable.file.name = "Café ＴＲＩＰ.mov"
        searchable.title = "A quiet afternoon"
        searchable.videoDescription = VideoDescription(status: "ready", message: "internal-debug-only", title: "A quiet afternoon", full_description: "A traveler packs a blue backpack.")
        var searchShot = highlight
        searchShot.description = "A hiker crosses the market square."
        searchShot.shot_size = "Wide shot"; searchShot.capture_type = "Handheld"; searchShot.camera_motion = "Pan right"
        searchShot.story_role = ["Establishing"]
        searchShot.reaction = "Smiling"; searchShot.audio = ["Footsteps", "Wind"]
        searchShot.dialogue = "Model-only unverified words"
        searchShot.edit_recommendation = .init(level: "Recommended", recommended_duration_sec: 3, reason: "Connects arrival to the viewpoint")
        searchable.shotAnalysis = ShotAnalysis(status: "ready", summary: "Exploring a mountain town", segments: [Segment(id: "search-shot", label: "Shot 2", start: 12, end: 20, editorial: searchShot)])
        searchable.result?.analysis?.subtitleCues = [Cue(start: 14, end: 17, text: "We finally reached the lookout.")]
        let searchLocation = MediaLocation(id: searchable.id, path: "/Volumes/Travel/Autumn/Café ＴＲＩＰ.mov")
        let searchDocument = MediaSearchDocument(searchable)
        func searchHits(_ query: String, _ scope: MediaSearchScope = .all) -> [MediaSearchHit]? {
            searchDocument.match(MediaSearchQuery(query), scope: scope, location: searchLocation)
        }
        check(searchHits("cafe trip", .name) != nil, "case, diacritic and width insensitive filename search")
        check(searchHits("backpack", .content)?.first?.label == "Description", "full description indexed with evidence")
        check(searchHits("market", .content)?.first?.start == 12, "shot descriptions retain source timestamps")
        check(searchHits("market", .content)?.first?.segmentID == "search-shot", "shot match identifies exact segment")
        check(searchHits("Pan right", .content) != nil && searchHits("Wide", .content) != nil, "framing and camera movement searchable")
        check(searchHits("Footsteps", .content) != nil && searchHits("Smiling", .content) != nil, "described sound and reaction searchable")
        check(searchHits("town", .content) != nil, "video shot summary searchable")
        check(searchHits("viewpoint", .editing) != nil && searchHits("Establishing", .editing) != nil, "editing reasons and story roles searchable")
        check(searchHits("Highlight", .editing) != nil, "computed highlight pick searchable")
        check(searchHits("finally lookout", .transcript)?.first?.start == 14, "multiple transcript keywords match and seek")
        check(searchHits("Model-only", .transcript) == nil && searchHits("Model-only", .content)?.first?.label == "Model-reported dialogue", "model dialogue is not represented as a transcript")
        check(searchHits("Glacier iphone", .context) != nil, "location and device keywords compose")
        check(searchHits("Autumn", .folder)?.first?.text == "/Volumes/Travel/Autumn", "parent folder path searchable")
        check(searchHits("backpack", .name) == nil && searchHits("backpack", .folder) == nil, "scopes do not leak unrelated fields")
        check(searchHits("market iphone") != nil && searchHits("market never-present") == nil, "AND terms may span fields of one item")
        check(searchHits("internal-debug-only") == nil, "technical status messages excluded")
        var tagged = searchable
        tagged.analysisTags = ["Lakeside", " Walking ", "lakeside", "unknown", "", String(repeating: "x", count: 60)]
        check(tagged.searchTags.filter { $0.text.lowercased() == "lakeside" }.count == 1, "tags are normalized and deduplicated")
        check(!tagged.searchTags.contains { $0.text == "unknown" || $0.text.count > 48 }, "empty and invalid tags never become chips")
        check(tagged.searchTags.contains { $0.text == "Wide shot" } && tagged.searchTags.contains { $0.text == "Establishing" }, "structured framing and story roles become search tags")
        check(tagged.searchTags.allSatisfy { MediaSearchDocument(tagged).match(MediaSearchQuery($0.text), scope: $0.scope, location: nil) != nil }, "every displayed tag can find its own material in the indicated scope")
        let detailGroups = MediaTagPresentation.detailGroups(tagged)
        check(detailGroups.contains { $0.title == "Framing" && $0.tags.contains { $0.text == "Wide shot" } }, "detail tags expose framing as a separate retrieval intent")
        check(!detailGroups.contains { ["Capture", "Story use"].contains($0.title) }, "redundant capture and editing roles stay out of detail tag groups")
        check(detailGroups.flatMap(\.tags).allSatisfy { MediaSearchDocument(tagged).match(MediaSearchQuery($0.text), scope: $0.scope, location: nil) != nil }, "every grouped detail tag retrieves its own source")
        var denseTags = tagged
        denseTags.videoDescription = nil; denseTags.shotAnalysis = nil; denseTags.description = nil; denseTags.result = nil
        denseTags.analysisTags = ["river", "stone wall", "cars", "road", "vegetation", "rocky bank", "natural landscape", "two people standing by river", "rocky mountain background", "river flowing", "gravel shoreline", "parked vehicles", "trees along bank", "utility lines", "clear blue sky", "distant utility lines", "gravel shore", "utility lines stretch", "blue sky", "clear sky", "Key change"]
        let conciseDetails = MediaTagPresentation.visualDetails(denseTags)
        check(conciseDetails.count <= 6 && conciseDetails.count >= 4, "dense visual details become a small useful set")
        check(conciseDetails.filter { $0.text.contains("sky") }.count == 1, "sky synonyms collapse to one original label")
        check(conciseDetails.filter { $0.text.contains("shore") || $0.text.contains("bank") }.count == 1, "shore and bank descriptions do not flood the detail row")
        check(conciseDetails.filter { $0.text.contains("utility") }.map(\.text) == ["utility lines"], "utility line variants collapse to a concise original phrase")
        check(!conciseDetails.contains { ["Key change", "river", "cars", "vegetation", "natural landscape"].contains($0.text) || $0.text.split(separator: " ").count > 4 }, "structure labels, broad categories and sentences are not visual chips")
        check(conciseDetails.allSatisfy { denseTags.analysisTags!.contains($0.text) }, "display cleanup never invents observations")
        check(MediaSearchDocument(denseTags).match(MediaSearchQuery("two people standing by river"), scope: .content, location: nil) != nil, "hidden visual details remain fully searchable")
        let restoredTags = try JSONDecoder().decode(MediaItem.self, from: JSONEncoder().encode(tagged))
        check(restoredTags.analysisTags == tagged.analysisTags, "saved observation tags survive native decoding")
        check(Array(tagged.contentTags.prefix(2)).map(\.text) == ["Lakeside", "Walking"], "saved content tags take precedence over derived phrases")
        check(!tagged.contentTags.contains { ["Wide shot", "Establishing", "Highlight"].contains($0.text) }, "generic editing and camera labels do not occupy visible content chips")
        let boardwalkTags = MediaContentTags.extract("The camera tracks forward along a wooden boardwalk beside a calm lake, maintaining a consistent perspective with no visible movement or people.")
        let personTags = MediaContentTags.extract("A boy in a plaid shirt stands in a sunlit grassy field, holding a coffee cup and making a peace sign with his hand.")
        check(boardwalkTags.contains("wooden boardwalk") && boardwalkTags.contains("calm lake"), "old analyses yield grounded scene phrases without a model call")
        check(personTags.contains("coffee cup") && personTags.contains("peace sign"), "specific objects and gestures distinguish content chips")
        check(Array(boardwalkTags.prefix(3)) != Array(personTags.prefix(3)), "different materials no longer share generic visible tags")
        check(!boardwalkTags.contains(where: { $0.contains("people") || $0.contains("camera") || $0.contains("perspective") }), "negated subjects and camera boilerplate do not become content tags")
        check(MediaContentTags.extract("No boats or people. Possibly a temple.").isEmpty, "uncertain and negative observations do not become positive tags")
        check(MediaContentTags.extract("").isEmpty, "missing analysis does not fabricate content tags")
        check(!MediaContentTags.extract("A wooden boardwalk beside a calm body of water.").contains("calm body"), "incomplete noun phrases are not presented as tags")
        let visualOnly = MediaContentTags.extract("A large sign reading 'North Mountain Trail' (Ye Ya Hu). A single word spoken by an unseen speaker.")
        check(!visualOnly.contains { $0.contains("Mountain") || $0.contains("Ya Hu") || $0.contains("word") || $0.contains("speaker") }, "quoted speech, sign fragments and transcript boilerplate do not clutter visual tags")
        check(!MediaContentTags.extract("The camera tracks horizontally across the lake.").contains("tracks"), "camera verbs misclassified as nouns stay out of visible tags")
        var chineseTags = tagged
        chineseTags.analysisTags = ["湖边", "骑行", "跟拍", "湖边"]
        check(Array(chineseTags.contentTags.prefix(2)).map(\.text) == ["湖边", "骑行"], "Chinese content tags stay concise and generic camera terms stay hidden")
        var oldPhoto = tagged
        oldPhoto.analysisTags = nil; oldPhoto.shotAnalysis = nil; oldPhoto.result = nil; oldPhoto.description = nil; oldPhoto.kind = "image"
        oldPhoto.videoDescription = VideoDescription(status: "ready", full_description: "A coffee cup on a wooden table.")
        check(oldPhoto.contentTags.contains { $0.text == "coffee cup" }, "legacy photos gain content tags without editorial shots")
        let oldTags = oldPhoto.contentTags.map(\.text)
        oldPhoto.videoDescription = VideoDescription(status: "ready", full_description: "A wooden boardwalk beside a calm lake.")
        check(oldPhoto.contentTags.map(\.text) != oldTags, "tag cache updates when analysis changes")
        check(oldPhoto.contentTags.allSatisfy { MediaSearchDocument(oldPhoto).match(MediaSearchQuery($0.text), scope: $0.scope, location: nil) != nil }, "derived content chips remain clickable search terms")
        check(tagged.cardSummary != nil, "analyzed cards show a useful summary beneath the filename")
        check(searchHits(" \n\t ")?.isEmpty == true, "blank query is normal library state")
        check(searchHits("徒步") == nil, "keyword search does not pretend to translate English analysis")
        check(searchable.matches("blue backpack"), "legacy matcher delegates to full document")
        var noAnalysis = searchable
        noAnalysis.videoDescription = nil; noAnalysis.shotAnalysis = nil; noAnalysis.result = nil; noAnalysis.description = nil
        check(MediaSearchDocument(noAnalysis).match(MediaSearchQuery("cafe"), scope: .all, location: nil) != nil, "unanalyzed files remain searchable by name")
        check(MediaSearchDocument(noAnalysis).match(MediaSearchQuery("backpack"), scope: .all, location: nil) == nil, "unanalyzed footage does not invent content matches")
        var brokenTime = searchable
        brokenTime.result?.analysis?.subtitleCues = [Cue(start: -1, text: "invalid-time"), Cue(start: 800, text: "outside-duration")]
        let brokenHits = MediaSearchDocument(brokenTime).match(MediaSearchQuery("invalid-time"), scope: .transcript, location: nil)
        check(brokenHits?.first?.start == nil, "invalid transcript timestamps never become seek links")
        check(MediaSearchDocument(brokenTime).match(MediaSearchQuery("outside-duration"), scope: .transcript, location: nil)?.first?.start == nil, "out-of-range timestamps never become seek links")
        let longHit = MediaSearchHit(id: 1, label: "Shot", text: String(repeating: "prefix ", count: 80) + "backpack in the frame", priority: 1)
        check(longHit.excerpt(query: "backpack").contains("backpack") && longHit.excerpt(query: "backpack").hasPrefix("…"), "evidence excerpt centers match in long text")
        var nameWinner = noAnalysis; nameWinner.id = "name-winner"; nameWinner.file.name = "backpack.mov"; nameWinner.title = nil
        var sampleMatch = searchable; sampleMatch.isExample = true
        check(MediaFilter(query: "backpack").apply([sampleMatch, nameWinner], locations: [:]).first?.id == "name-winner", "search relevance outranks pinned sample")
        check(MediaFilter().apply([sampleMatch, nameWinner], locations: [:]).first?.id == nameWinner.id, "new imports appear above the sample")
        var newImport = nameWinner; newImport.id = "new-import"; newImport.status = "queued"
        check(MediaFilter().apply([sampleMatch, nameWinner, newImport], locations: [:]).map(\.id) == [newImport.id, nameWinner.id, sampleMatch.id], "newest imports appear first before analysis finishes")
        newImport.status = "ready"
        check(MediaFilter().apply([sampleMatch, nameWinner, newImport], locations: [:]).map(\.id) == [newImport.id, nameWinner.id, sampleMatch.id], "analysis completion preserves newest-first order")
        let searchStore = WorkspaceStore()
        searchStore.items = [searchable]; searchStore.locations = [searchable.id: searchLocation]
        searchStore.query = "market"
        check(searchStore.visibleItems.count == 1 && searchStore.mediaSearchResults[0].hits.first?.start == 12, "store caches evidence and defaults to full search")
        searchStore.items = [noAnalysis]
        check(searchStore.visibleItems.isEmpty, "updated analysis invalidates search index")
        searchStore.searchScope = .folder; searchStore.query = "Autumn"
        check(searchStore.visibleItems.count == 1, "cached search includes resolved folder paths")
        searchStore.locations = [:]
        check(searchStore.visibleItems.isEmpty, "relinked location invalidates search results")
        searchStore.query = ""
        check(searchStore.searchScope == .folder && searchStore.visibleItems.count == 1, "clear search keeps chosen scope")
        searchStore.resetMediaFilters()
        check(searchStore.searchScope == .all && !searchStore.hasMediaFilters, "reset restores everything scope")
        searchStore.query = "river"
        check(searchStore.visibleItems.isEmpty, "typing an unmatched query never silently scans media")
        check(searchStore.visualMatchTime(noAnalysis.id) == nil, "unsearched media never has a fabricated visual match time")
        searchStore.query = ""
        check(searchStore.visibleItems.count == 1, "empty query retains normal browsing")
        searchStore.query = noAnalysis.file.name
        check(searchStore.visibleItems.count == 1, "filename matches are available without a search mode or index")
        searchStore.searchVisualMedia()
        check(!searchStore.catalogBusy && searchStore.visibleItems.count == 1, "Return without an index preserves text matches and does not start work")
        searchStore.query = ""
        var visualOnlyItem = noAnalysis; visualOnlyItem.id = "visual-only"
        let textResult = MediaSearchResult(item:noAnalysis, hits:[])
        let visualResult = MediaSearchResult(item:visualOnlyItem, hits:[])
        let visualHit = CatalogHit(mediaId:visualOnlyItem.id, shotId:"shot", start:2, end:4, similarity:0.6, label:"Visual match")
        let sameFileHit = CatalogHit(mediaId:noAnalysis.id, shotId:"shot", start:1, end:3, similarity:0.8, label:"Visual match")
        let merged = MediaSearchMerge.combine(text:[textResult], visual:[sameFileHit,visualHit,visualHit], allowed:[textResult,visualResult])
        check(merged.map(\.id) == [noAnalysis.id,visualOnlyItem.id], "unified search preserves text matches, appends visual matches and deduplicates files")
        check(merged.last?.hits.first?.start == 2, "visual-only results keep their matched time")
        check(MediaSearchMerge.combine(text:[textResult], visual:[visualHit], allowed:[textResult]).count == 1, "visual matches cannot bypass folder or device filters")
        let catalog = try JSONDecoder().decode(CatalogStatus.self, from: Data(#"{"indexed":2,"total":5,"stale":1,"job":null}"#.utf8))
        check(catalog.indexed == 2 && catalog.stale == 1, "visual index coverage is independent of total media count")
        var lakeClip = noAnalysis
        lakeClip.id = "facet-lake"; lakeClip.context = ["location": "Hangzhou"]; lakeClip.kind = "video"
        lakeClip.analysisTags = ["Lakeside", "Walking", "walking", "boy"]
        lakeClip.description = "A boy walks, with a lake in the background."
        let lakeTags = MediaQuickTags.tags(lakeClip)
        let displayedTags = MediaTagPresentation.core(lakeClip, frequencies: [:])
        check(displayedTags.map(\.facet) == [.location, .activity, .subject], "card shows at most three different toolbar categories")
        check(displayedTags.allSatisfy { tag in lakeTags.contains { $0.id == tag.id && $0.text == tag.text } }, "card labels and IDs exactly match category filters")
        var untaggedClip = noAnalysis
        untaggedClip.context = nil; untaggedClip.analysisTags = nil
        check(MediaTagPresentation.core(untaggedClip, frequencies: [:]).isEmpty, "no fabricated tags on unanalysed cards")
        var diverseClip = lakeClip
        diverseClip.id = "facet-diverse"
        diverseClip.context = nil
        diverseClip.analysisTags = ["mountains", "river", "walking", "boy", "no visible boats"]
        let diverseTags = MediaTagPresentation.core(diverseClip, frequencies: ["Scene:mountain": 20, "Scene:water": 2])
        check(diverseTags.first?.key == "water", "card prioritizes a more distinctive recognized scene in this library")
        check(Set(diverseTags.map(\.facet)).count == diverseTags.count, "core tags do not repeat a category")
        check(!MediaTagPresentation.content(diverseClip).contains { $0.text == "no visible boats" }, "negative observations are not positive keyword chips")
        var multiSubject = diverseClip
        multiSubject.analysisTags = ["boy", "dog", "car", "mountains"]
        multiSubject.description = "A boy walks with a dog; cars are in the background."
        let subjects = MediaQuickTags.tags(multiSubject).filter { $0.facet == .subject }
        check(subjects.isEmpty, "ambiguous legacy main clause abstains rather than choosing the first keyword")
        var explicitSubjects = multiSubject
        explicitSubjects.analysisEvidence = MediaEvidence(version: 2, tags: ["people", "animals", "vehicles"].map { key in
            EvidenceTag(id: "subject:"+key, category: "subject", key: key, label: key, aliases: [], source: "visual-primary-subject", evidence: [])
        })
        check(MediaQuickTags.tags(explicitSubjects).filter { $0.facet == .subject }.map(\.key) == ["people", "animals"], "at most two explicitly supported primary subjects")
        var followedPerson = noAnalysis
        followedPerson.description = "镜头跟随穿格子衬衫的人行走，左侧自行车道有骑车人和汽车。"
        followedPerson.analysisTags = ["骑车人", "汽车", "树木", "穿格子衬衫的人"]
        check(MediaQuickTags.tags(followedPerson).filter { $0.facet == .subject }.map(\.key) == ["people"], "legacy clothing-based person phrase is recognized without promoting vehicles")
        check(MediaQuickTags.tags(followedPerson).filter { $0.facet == .activity }.map(\.key) == ["walking"], "background cycling is not the followed person's activity")
        followedPerson.analysisEvidence = MediaEvidence(version: 1, tags: [], focusVersion: 2)
        check(MediaQuickTags.tags(followedPerson).filter { [.subject, .activity].contains($0.facet) }.isEmpty, "modern abstention never falls back to summary keywords")
        let focusTagsJSON = #"{"version":1,"focusVersion":2,"tags":[{"id":"subject:people","category":"subject","key":"people","label":"People","aliases":[],"source":"visual-primary-subject","evidence":[]},{"id":"activity:walking","category":"activity","key":"walking","label":"Walking & hiking","aliases":[],"source":"visual-primary-activity","evidence":[{"start":0,"end":6,"shotIds":[],"text":"The followed person walks","subject":"people","subjectDescription":"person in checkered clothing"}]},{"id":"activity:cycling","category":"activity","key":"cycling","label":"Cycling","aliases":[],"source":"visual-observation","evidence":[]}]}"#
        followedPerson.analysisEvidence = try JSONDecoder().decode(MediaEvidence.self, from: Data(focusTagsJSON.utf8))
        check(MediaQuickTags.tags(followedPerson).filter { $0.facet == .activity }.map(\.key) == ["walking"], "only subject-bound activity is shown for modern focus")
        followedPerson.tagCorrections = TagCorrections(hidden: [], added: [EvidenceTag(id: "subject:buildings", category: "subject", key: "buildings", label: "Buildings", aliases: [], source: "user", evidence: [])])
        check(MediaQuickTags.tags(followedPerson).filter { $0.facet == .subject }.map(\.key) == ["buildings"], "user subject correction replaces generated focus rather than adding a co-star")
        check(MediaQuickTags.tags(followedPerson).filter { $0.facet == .activity }.isEmpty, "changing subject does not inherit the previous subject action")
        followedPerson.tagCorrections = TagCorrections(hidden: ["activity:walking"], added: [])
        check(MediaQuickTags.tags(followedPerson).filter { $0.facet == .activity }.isEmpty, "hidden action is never recreated by legacy inference")
        followedPerson.tagCorrections = nil
        followedPerson.shotAnalysis = ShotAnalysis(status: "ready", message: nil, summary: "A person walks", segments: nil, limitations: nil, tags: [], focusVersion: 2)
        check(MediaQuickTags.tags(followedPerson).filter { [.subject,.activity].contains($0.facet) }.isEmpty, "empty newer shot focus supersedes older observation tags")
        var campusClip = lakeClip
        campusClip.context = nil
        campusClip.metadata?.location = coordinate
        campusClip.resolvedPlace = ResolvedPlace(version: 2, label: campus.label!, area: campus.area, nearbyName: campus.nearbyName,
            latitude: coordinate.latitude!, longitude: coordinate.longitude!, language: "zh-Hans", provider: "apple-geocoder", resolvedAt: Date().timeIntervalSince1970)
        check(campusClip.recordedLocation == campus.label && campusClip.locationGroup == "清华大学", "precise address is preserved while campus is grouped")
        check(MediaQuickTags.tags(campusClip).first?.text == "清华大学", "place filter groups different roads in the same campus")
        campusClip.resolvedPlace = ResolvedPlace(version: 3, label: corrected.label!, area: corrected.area, nearbyName: nil,
            latitude: coordinate.latitude!, longitude: coordinate.longitude!, language: "zh-Hans", provider: "apple-osm", resolvedAt: Date().timeIntervalSince1970,
            displayName: corrected.displayName, boundaryID: corrected.boundaryID, areaRelation: corrected.areaRelation, placeKind: corrected.placeKind)
        check(campusClip.locationGroup == "北京 测试大学", "boundary display reaches media tags")
        check(campusClip.locationGroupKey == "osm:area/1234:inside", "different campus roads share stable boundary identity")
        check(campusClip.locationAttribution.contains("OpenStreetMap"), "OSM attribution follows boundary results")
        campusClip.metadata?.location?.latitude = 20
        check(campusClip.validResolvedPlace == nil, "changed GPS invalidates a saved place")
        check(MediaQuickTags.tags(explicitSubjects).filter { $0.facet == .subject }.allSatisfy { tag in
            var selection = MediaFacetSelection(); selection.values[.subject] = tag
            return selection.matches(MediaQuickTags.tags(explicitSubjects))
        }, "a multi-subject clip is retrievable under each of its subject filters")
        searchStore.items = [lakeClip, diverseClip]
        searchStore.query = "unrelated query"
        searchStore.filterMediaTag(displayedTags[0])
        check(searchStore.query.isEmpty && searchStore.mediaFacets.values[.location]?.id == displayedTags[0].id, "detail tag navigates into the shared category filter")
        check(searchStore.visibleItems.map(\.id) == [lakeClip.id], "detail tag filter finds the matching media")
        searchStore.resetMediaFilters()
        check(MediaQuickTags.cardTags(lakeTags).map(\.facet) == [.location, .activity], "card prioritizes the concrete location without a separate scene row")
        check(lakeTags.contains { $0.facet == .scene && $0.key == "water" }, "compact cards retain scene data for dropdown filtering")
        check(MediaQuickTags.cardTags(lakeTags.filter { $0.facet != .location }).map(\.facet) == [.scene, .activity], "cards without a location retain the recognized scene")
        check(MediaQuickTags.cardTags([]).isEmpty, "cards do not fabricate labels when analysis is absent")
        let repeatedPlace = MediaFacetTag(facet: .location, key: "people", text: "People")
        check(MediaQuickTags.cardTags([repeatedPlace, .init(facet: .subject, key: "people", text: "People")]).count == 1, "visible tags never repeat identical text across facets")
        var mountainPhoto = noAnalysis
        mountainPhoto.id = "facet-mountain"; mountainPhoto.kind = "image"; mountainPhoto.context = ["location": " hangzhou "]
        mountainPhoto.analysisTags = ["山景", "骑行", "人物"]
        var diningClip = noAnalysis
        diningClip.id = "facet-dining"; diningClip.context = ["location": "Shanghai"]
        diningClip.analysisTags = ["café", "coffee", "drinking", "woman"]
        var unknownClip = noAnalysis
        unknownClip.id = "facet-unknown"; unknownClip.context = nil; unknownClip.analysisTags = nil
        unknownClip.file.name = "Beijing-mountain-hiking.mov"
        check(MediaQuickTags.tags(unknownClip).isEmpty, "filenames never invent place, scene or activity tags")
        unknownClip.description = "No people or boats. Possibly a temple. A sign reading 'Mountain Park'. Voiceover says beach."
        check(MediaQuickTags.tags(unknownClip).isEmpty, "negative, uncertain, quoted and spoken content does not create facet tags")
        unknownClip.description = "A boy walking beside a lake."
        check(Set(MediaQuickTags.tags(unknownClip).map(\.key)) == ["water"], "legacy mixed-object clause retains scene, but abstains on focus and its action")
        unknownClip.description = "A boy walking, with a lake in the background."
        check(Set(MediaQuickTags.tags(unknownClip).map(\.key)) == ["people", "walking", "water"], "legacy visual descriptions produce common grounded tags, not guessed locations")
        unknownClip.description = "湖边的男孩正在骑行。"
        check(Set(MediaQuickTags.tags(unknownClip).map(\.key)) == ["people", "cycling", "water"], "Chinese visual observations share common filter keys")
        unknownClip.description = nil
        let facetStore = WorkspaceStore()
        facetStore.items = [lakeClip, mountainPhoto, diningClip, unknownClip]
        facetStore.locations = [lakeClip.id: .init(id: lakeClip.id, path: "/Clips/Trip/lake.mov"), mountainPhoto.id: .init(id: mountainPhoto.id, path: "/Clips/Trip/Day2/mountain.jpg")]
        let place = facetStore.mediaFacetOptions[.location]!.first { $0.tag.key == "hangzhou" }!
        check(place.count == 2, "location dropdown normalizes whitespace and case and counts unique files")
        check(facetStore.mediaFacetOptions[.activity]!.first { $0.tag.key == "walking" }?.count == 1, "repeated observation tags do not inflate file counts")
        check(facetStore.mediaFacetOptions[.scene]!.count == 3, "only available recognized scene categories appear")
        facetStore.toggleMediaTag(place.tag)
        check(facetStore.visibleItems.count == 2 && facetStore.hasMediaFilters, "clicking a location filters files and enables clear")
        check(facetStore.query.isEmpty && facetStore.searchScope == .all, "tag selection never overwrites search text or scope")
        let water = facetStore.mediaFacetOptions[.scene]!.first { $0.tag.key == "water" }!.tag
        let mountain = facetStore.mediaFacetOptions[.scene]!.first { $0.tag.key == "mountain" }!.tag
        facetStore.toggleMediaTag(water)
        check(facetStore.visibleItems.map(\.id) == [lakeClip.id], "different dropdowns combine with AND")
        check(facetStore.mediaFacetOptions[.scene]!.contains { $0.tag.id == mountain.id && $0.count == 1 }, "own dropdown retains alternatives when selected")
        check(!facetStore.mediaFacetOptions[.activity]!.contains { $0.tag.key == "cycling" }, "other dropdowns only offer tags with matching files")
        facetStore.toggleMediaTag(mountain)
        check(facetStore.visibleItems.map(\.id) == [mountainPhoto.id], "choosing another same-facet tag replaces rather than stacks")
        facetStore.category = .video
        check(facetStore.visibleItems.isEmpty, "category and tag selections intersect")
        check(facetStore.mediaFacetOptions[.scene]!.contains { $0.id == mountain.id && $0.count == 0 }, "zero-result selection remains visible and clearable")
        facetStore.toggleMediaTag(mountain)
        check(facetStore.visibleItems.map(\.id) == [lakeClip.id], "clicking selected card tag clears its filter")
        facetStore.resetMediaFilters(); facetStore.folder = "/Clips/Trip"
        check(facetStore.mediaFacetOptions[.location]!.count == 1 && facetStore.mediaFacetOptions[.location]![0].count == 2, "folder filter includes descendants in tag counts")
        facetStore.query = "Lakeside"
        check(facetStore.mediaFacetOptions[.location]![0].count == 1, "search and dropdown counts use the same file set")
        facetStore.resetMediaFilters()
        facetStore.toggleMediaTag(water)
        lakeClip.analysisTags = ["Forest", "walking"]
        lakeClip.description = "A boy walks in the forest."
        facetStore.items = [lakeClip, mountainPhoto, diningClip, unknownClip]
        check(facetStore.visibleItems.isEmpty && facetStore.mediaFacetOptions[.scene]!.contains { $0.tag.key == "forest" }, "analysis changes refresh tags and preserve the selected filter")
        facetStore.resetMediaFilters()
        check(facetStore.mediaFacets.isEmpty && !facetStore.hasMediaFilters && facetStore.visibleItems.count == 4, "clear restores all files without affecting media selection")
        var facetFilter = MediaFilter()
        facetFilter.facets.values[.scene] = mountain
        check(facetFilter.apply(facetStore.items, locations: [:]).map(\.id) == [mountainPhoto.id], "standalone MediaFilter uses the same exact tag semantics")
        facetStore.items = []
        check(facetStore.mediaFacetOptions.values.allSatisfy(\.isEmpty), "empty libraries do not show fabricated tag options")
        var hoverShot = Segment(id: "hover", label: "Shot 1", start: 0, end: 8, note: "Detected visual cut", editorial: highlight)
        check(hoverShot.hoverHelp(analysisStatus: "ready") == "Shot 1 · 0:00–0:08\n\n营地互动", "hover shows timing and the actual shot description")
        check(hoverShot.hoverDescription(analysisStatus: "running") == "营地互动", "existing description remains readable during reanalysis")
        hoverShot.editorial?.description = " \n "
        check(hoverShot.hoverDescription(analysisStatus: "running").contains("Analyzing"), "blank descriptions show an honest running state")
        check(hoverShot.hoverDescription(analysisStatus: "failed").contains("Retry"), "failed analysis offers retry guidance")
        hoverShot.editorial = nil
        check(hoverShot.hoverDescription(analysisStatus: nil).contains("Analyze shots"), "unanalysed shots do not use notes or subtitles as descriptions")
        highlight.importance_score = 79
        check(!highlight.isHighlight, "lower scores do not receive highlight")
        highlight.importance_score = 95; highlight.duplicate_candidate = true
        check(!highlight.isHighlight, "suspected duplicates are not highlighted")
        highlight.duplicate_candidate = false; highlight.unusable_candidate = true
        check(!highlight.isHighlight, "unusable candidates are not highlighted")
        highlight.unusable_candidate = false; highlight.edit_recommendation.level = "可压缩"
        check(!highlight.isHighlight, "compressible shots do not receive quality badge solely from score")
        highlight.edit_recommendation.level = "必留"
        check(highlight.isHighlight, "must-keep high-value shots are highlighted")
        highlight.edit_recommendation.level = "Keep"
        check(highlight.isHighlight, "English keep recommendations retain highlights")
        highlight.edit_recommendation.level = "Recommended"
        check(highlight.isHighlight, "English recommendations retain highlights")
        highlight.edit_recommendation.level = "Shorten"
        check(!highlight.isHighlight, "English shorten recommendations are not highlights")
        highlight.edit_recommendation.level = "Keep"
        highlight.edit_recommendation.recommended_duration_sec = 0
        check(!highlight.isHighlight, "zero-duration recommendations are not highlighted")
        check(item.segments[0].editorial?.isHighlight != true, "legacy unanalysed segments have no badge")
        check(!item.processing && item.favorite == true, "legacy favorite and status")
        check(item.processingLabel == nil, "ready media has no loading badge")
        var contentItem = item
        contentItem.mediaAnalysis = MediaAnalysisState(status: "queued", message: "Waiting")
        check(contentItem.processingLabel == "Queued…" && contentItem.processing, "content queue remains visible after basic import")
        contentItem.mediaAnalysis = MediaAnalysisState(status: "running", message: "Reading frames")
        check(contentItem.processingLabel == "Analyzing…", "automatic understanding shows progress")
        contentItem.mediaAnalysis = MediaAnalysisState(status: "failed", message: "Model unavailable")
        check(contentItem.analysisNeedsAttention && MediaWorkFilter.attention.includes(contentItem), "content failure is actionable")
        check(contentItem.processingLabel == nil, "failed content analysis never spins indefinitely")
        contentItem.mediaAnalysis = MediaAnalysisState(status: "retrying", message: "temporary timeout", attempt: 1, maxAttempts: 3)
        contentItem.shotAnalysis = ShotAnalysis(status: "failed")
        check(contentItem.processingLabel == "Waiting to retry…", "backoff is distinguished from active inference")
        check(!contentItem.analysisNeedsAttention && MediaWorkFilter.analyzing.includes(contentItem), "pending retry is not presented as a terminal failure")
        let retryDecoded = try JSONDecoder().decode(MediaAnalysisState.self, from: JSONEncoder().encode(contentItem.mediaAnalysis!))
        check(retryDecoded.attempt == 1 && retryDecoded.maxAttempts == 3, "retry budget survives decoding")
        var partialAnalysis = item
        partialAnalysis.mediaAnalysis = MediaAnalysisState(status: "failed", message: "Shot output failed validation")
        partialAnalysis.shotAnalysis = ShotAnalysis(status: "failed")
        partialAnalysis.videoDescription = VideoDescription(status: "ready", title: "Saved description", full_description: "A saved view.")
        check(partialAnalysis.attentionReason == .shotsIncomplete, "saved description does not disguise failed shot analysis as pending work")
        check(partialAnalysis.processingLabel == nil, "terminal shot failure is not a waiting or running task")
        check(MediaAttentionReason.shotsIncomplete.summary(count: 1, chinese: true) == "1 个素材分镜分析未完成", "summary identifies the unfinished stage in Chinese")
        check(MediaAttentionReason.shotsIncomplete.summary(count: 2, chinese: false) == "2 files: shot analysis incomplete", "English summary identifies the same stage")
        partialAnalysis.shotAnalysis = ShotAnalysis(status: "running")
        check(partialAnalysis.attentionReason == nil && partialAnalysis.processing, "manual stage retry suppresses the previous terminal issue")
        partialAnalysis.shotAnalysis = ShotAnalysis(status: "ready")
        partialAnalysis.videoDescription = VideoDescription(status: "failed")
        check(partialAnalysis.attentionReason == .descriptionIncomplete, "description failure has its own explanation")
        partialAnalysis.shotAnalysis = ShotAnalysis(status: "failed")
        check(partialAnalysis.attentionReason == .videoAnalysisIncomplete, "both unfinished video stages are reported together")
        partialAnalysis.missing = true
        check(partialAnalysis.attentionReason == .originalMissing, "missing original takes priority over analysis recovery")
        partialAnalysis.missing = false
        partialAnalysis.status = "error"
        check(partialAnalysis.attentionReason == .importIncomplete, "failed import is not confused with a failed model stage")
        partialAnalysis.status = "ready"
        partialAnalysis.shotAnalysis = ShotAnalysis(status: "ready")
        partialAnalysis.videoDescription = VideoDescription(status: "ready")
        check(partialAnalysis.attentionReason == .analysisIncomplete, "coordinator failure such as speech still remains actionable")
        partialAnalysis.mediaAnalysis = MediaAnalysisState(status: "ready")
        check(partialAnalysis.attentionReason == nil && !MediaWorkFilter.attention.includes(partialAnalysis), "complete results remove the warning instead of leaving pending work")
        let completedBatch = Array(repeating: partialAnalysis, count: 14)
        check(completedBatch.allSatisfy { $0.attentionReason == nil && !$0.processing }, "fully completed batch has no activity banner")
        partialAnalysis.mediaAnalysis = MediaAnalysisState(status: "failed")
        partialAnalysis.shotAnalysis = ShotAnalysis(status: "failed")
        let mixedBatch = Array(completedBatch.prefix(13)) + [partialAnalysis]
        check(mixedBatch.filter { $0.attentionReason == .shotsIncomplete }.count == 1 && mixedBatch.allSatisfy { !$0.processing }, "13 complete and one partial failure show exactly one specific issue, not one queued item")
        var loadingItem = item
        loadingItem.status = "queued"
        check(loadingItem.processingLabel == "Queued…", "queued import shows on its cover")
        loadingItem.status = "analyzing"
        check(loadingItem.processingLabel == "Analyzing…", "active import shows on its cover")
        loadingItem.status = "ready"
        loadingItem.shotAnalysis = ShotAnalysis(status: "running")
        check(loadingItem.processingLabel == "Analyzing…", "semantic analysis remains visible on covers")
        loadingItem.shotAnalysis = nil
        loadingItem.videoDescription = VideoDescription(status: "running")
        check(loadingItem.processingLabel == "Analyzing…", "description analysis is also shown")
        loadingItem.videoDescription = VideoDescription(status: "queued")
        check(loadingItem.processingLabel == "Queued…", "waiting semantic analysis is distinguished from active analysis")
        loadingItem.shotAnalysis = ShotAnalysis(status: "running")
        check(loadingItem.processingLabel == "Analyzing…", "running analysis takes priority over another queued stage")
        loadingItem.shotAnalysis = ShotAnalysis(status: "completed")
        loadingItem.videoDescription = VideoDescription(status: "completed")
        check(loadingItem.processingLabel == nil, "loading disappears once all stages finish")
        loadingItem.videoDescription = nil; loadingItem.status = "error"
        check(loadingItem.processingLabel == nil, "failed imports do not spin forever")
        check(item.isExample == nil, "existing user media is not marked as an example")
        var exampleItem = item
        exampleItem.isExample = true
        exampleItem.coverUrl = "/assets/examples/wild-alaska/cover.jpg"
        let exampleDecoded = try JSONDecoder().decode(MediaItem.self, from: JSONEncoder().encode(exampleItem))
        check(exampleDecoded.isExample == true && exampleDecoded.cover == exampleItem.coverUrl, "example marker and dedicated cover survive decoding")
        check(timestamp(690) == "11:30" && timestamp(3661) == "1:01:01", "duration formatting")
        check(timestamp(-3) == "0:00" && timestamp(.infinity) == "0:00", "invalid duration")
        var draft = Draft()
        draft.attach([item, item]); check(draft.attachments.count == 1, "deduplicate selection")
        draft.prompt = "Create a travel guide"
        draft.skill = ChosenSkill(id: "guide", title: "Travel guide", strategy: "Preserve complete explanations")
        let encoded = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(Draft.self, from: encoded)
        check(decoded == draft, "draft round trip")
        let legacyDraft = try JSONDecoder().decode(Draft.self, from: Data(#"{"prompt":"Keep me","attachments":[]}"#.utf8))
        check(legacyDraft.prompt == "Keep me" && legacyDraft.projectId == nil, "read Electron draft")
        let pending = try JSONDecoder().decode(MediaItem.self, from: Data(#"{"id":"pending","file":{"name":"a.mp4"},"kind":"video","status":"queued","metadata":null,"result":null}"#.utf8))
        check(pending.processing && pending.segments.isEmpty, "queued nullable data")
        var clip2 = item; clip2.id = "clip2"; clip2.file.name = "Trip 2.MOV"; clip2.metadata?.duration = 10
        var clip10 = item; clip10.id = "clip10"; clip10.file.name = "Trip 10.MOV"; clip10.metadata?.duration = 20; clip10.favorite = false
        var photoItem = item; photoItem.id = "photo"; photoItem.kind = "image"; photoItem.file.name = "山景.jpg"
        var audioItem = item; audioItem.id = "audio"; audioItem.kind = "audio"
        let fixtures = [clip10, photoItem, clip2, audioItem]
        let locations = [
            "clip2": MediaLocation(id: "clip2", path: "/Volumes/Travel/Day 1/Trip 2.MOV"),
            "clip10": MediaLocation(id: "clip10", path: "/Volumes/Travel/Day 1/Phone/Trip 10.MOV"),
            "photo": MediaLocation(id: "photo", path: "/Volumes/Travel/Day 10/山景.jpg")
        ]
        var filter = MediaFilter(scope: .name)
        filter.folder = "/Volumes/Travel/Day 1"
        check(filter.apply(fixtures, locations: locations).map(\.id) == ["clip2", "clip10"], "folder includes descendants in newest-first order, not similarly named siblings")
        filter.query = " trip 2 "
        check(filter.apply(fixtures, locations: locations).map(\.id) == ["clip2"], "combine folder with case-insensitive trimmed filename search")
        filter.query = "Glacier"
        check(filter.apply(fixtures, locations: locations).isEmpty, "name search does not match unrelated location text")
        filter.scope = .all
        check(filter.apply(fixtures, locations: locations).count == 2, "explicit all-information search includes location")
        filter.category = .favorites
        check(filter.apply(fixtures, locations: locations).map(\.id) == ["clip2"], "favorites composes with folder and query")
        filter = MediaFilter(category: .video, sort: .nameAscending)
        check(filter.apply(fixtures, locations: locations).map(\.id) == ["clip2", "clip10"], "natural filename sort")
        filter.sort = .nameDescending
        check(filter.apply(fixtures, locations: locations).map(\.id) == ["clip10", "clip2"], "descending filename sort")
        filter.sort = .longest
        check(filter.apply(fixtures, locations: locations).map(\.id) == ["clip10", "clip2"], "duration sort")
        filter = MediaFilter(query: "山景")
        check(filter.apply(fixtures, locations: locations).map(\.id) == ["photo"], "Unicode filename search")
        check(MediaFilter().apply(fixtures, locations: locations).count == 3, "audio remains outside Media")
        let workspace = WorkspaceStore()
        check(workspace.page == .media, "the app opens in Library without a creation prompt")
        workspace.items = fixtures; workspace.locations = locations
        workspace.beginSelection(); workspace.cancelSelection()
        check(workspace.page == .media && !workspace.selecting, "canceling a Library selection does not navigate into creation")
        workspace.beginSelection(); workspace.selection = [clip2.id]; workspace.finishSelection()
        check(workspace.page == .home && workspace.draft.attachments.contains { $0.id == clip2.id }, "explicit rough-cut action carries selected Library media into Create")
        workspace.draft = Draft(); workspace.navigate(.media)
        var newlyImported = clip2; newlyImported.importedAt = Date().timeIntervalSince1970 * 1000
        check(MediaAddedRange.today.includes(newlyImported), "today filter uses recorded import date")
        check(!MediaAddedRange.today.includes(clip10) && MediaAddedRange.all.includes(clip10), "legacy files with unknown import dates remain accessible without invented dates")
        newlyImported.importedAt = Date().addingTimeInterval(-86400 * 40).timeIntervalSince1970 * 1000
        check(!MediaAddedRange.month.includes(newlyImported), "date filter excludes genuinely older imports")
        newlyImported.status = "analyzing"
        check(MediaWorkFilter.analyzing.includes(newlyImported), "live analysis status can be opened as a Library filter")
        newlyImported.status = "error"
        check(MediaWorkFilter.attention.includes(newlyImported), "failed media has an actionable attention filter")
        workspace.mediaAddedRange = .today; workspace.mediaWorkFilter = .attention
        workspace.resetMediaFilters()
        check(workspace.mediaAddedRange == .all && workspace.mediaWorkFilter == .all, "reset clears date and work filters too")
        workspace.folder = "/Volumes/Travel/Day 1"; workspace.query = "Trip"; workspace.sort = .nameAscending
        workspace.openMedia(clip2)
        check(workspace.page == .media && workspace.detail?.id == "clip2", "detail is a Media child route")
        workspace.backToMedia()
        check(workspace.detail == nil && workspace.folder == "/Volumes/Travel/Day 1" && workspace.query == "Trip" && workspace.sort == .nameAscending, "back preserves folder, query and sort")
        workspace.openMedia(clip2); workspace.page = .skills
        check(workspace.detail == nil, "sidebar navigation leaves the detail route")
        workspace.resetMediaFilters()
        check(!workspace.hasMediaFilters && workspace.visibleItems.count == 3, "reset restores all local visual references")
        let projectA = Project(id: "project-a", title: "Mountain story", updatedAt: 1000, attachments: [Attachment(id: clip2.id, name: clip2.name, kind: "video")], messages: [])
        let projectB = Project(id: "project-b", title: "City story", updatedAt: 2000, attachments: [], messages: [])
        workspace.projects = [projectA, projectB]
        workspace.open(projectA); workspace.composerDraft.prompt = "Keep my draft"
        workspace.openMedia(clip2)
        check(workspace.detail?.id == clip2.id && workspace.mediaBackTitle == "Conversation", "analysis card opens the correct material with a conversation return path")
        workspace.backToMedia()
        check(workspace.page == .project && workspace.selectedProjectID == projectA.id && workspace.composerDraft.prompt == "Keep my draft", "return from material details restores the conversation without clearing its draft")
        workspace.openMedia(clip2); workspace.navigate(.media)
        check(workspace.mediaReturnProjectID == nil, "explicit sidebar navigation clears the conversation return path")
        workspace.draft = Draft(prompt: "Unsent Home idea")
        workspace.open(projectA)
        check(workspace.page == .project && workspace.currentProject?.id == projectA.id, "project opens independent child route")
        check(workspace.draft.prompt == "Unsent Home idea" && workspace.composerDraft.projectId == projectA.id, "opening project preserves Home draft")
        workspace.composerDraft.prompt = "Hold the view longer"
        workspace.beginSelection(); workspace.selection = [clip10.id]; workspace.finishSelection()
        check(workspace.page == .project && workspace.composerDraft.attachments.contains { $0.id == clip10.id }, "Media selection returns to project composer")
        check(workspace.draft.attachments.isEmpty && workspace.draft.prompt == "Unsent Home idea", "project attachments never leak into Home")
        workspace.beginSelection(); workspace.cancelSelection()
        check(workspace.page == .project && workspace.composerDraft.prompt == "Hold the view longer", "cancel selection preserves project draft and route")
        workspace.open(projectB); workspace.composerDraft.prompt = "A different edit"
        workspace.open(projectA)
        check(workspace.composerDraft.prompt == "Hold the view longer", "each project keeps its own unsent request")
        workspace.navigate(.project)
        check(workspace.selectedProjectID == nil && workspace.page == .project, "back and sidebar Project show list")
        workspace.navigate(.home)
        check(workspace.composerDraft.prompt == "Unsent Home idea" && workspace.composerDraft.projectId == nil, "Home always composes a new project")
        let submittedHome = workspace.draft
        workspace.completeSubmission(submittedHome, sourceID: nil, sourcePage: .home, projectID: projectA.id)
        check(workspace.page == .project && workspace.selectedProjectID == projectA.id && !workspace.draft.hasContent, "submitted Home brief transitions to project and clears only submitted draft")
        workspace.navigate(.home); workspace.draft.prompt = "New input while request finishes"
        workspace.completeSubmission(submittedHome, sourceID: nil, sourcePage: .home, projectID: projectB.id)
        check(workspace.page == .home && workspace.draft.prompt == "New input while request finishes", "late response cannot erase newer Home input")
        let inFlight = workspace.draft
        workspace.navigate(.media)
        workspace.completeSubmission(inFlight, sourceID: nil, sourcePage: .home, projectID: projectB.id)
        check(workspace.page == .media, "late response does not steal navigation")
        workspace.open(projectA)
        workspace.composerDraft.prompt = "Keep this unsent thought"
        let optionDraft = workspace.composerDraft
        workspace.completeSubmission(optionDraft, sourceID: projectA.id, sourcePage: .project, projectID: projectA.id, preservePrompt: true)
        check(workspace.composerDraft.prompt == "Keep this unsent thought", "direct option does not overwrite or clear the composer")
        workspace.draft = Draft(prompt: "Legacy follow-up", projectId: "legacy-project")
        workspace.migrateLegacyDraft()
        check(!workspace.draft.hasContent && workspace.projectDrafts["legacy-project"]?.prompt == "Legacy follow-up", "legacy project drafts migrate out of Home without loss")
        let savedProjectDrafts = try JSONDecoder().decode([String: Draft].self, from: JSONEncoder().encode(workspace.projectDrafts))
        check(savedProjectDrafts == workspace.projectDrafts, "separate project drafts survive persistence round trip")
        check(workspace.sortedProjects.map(\.id) == [projectB.id, projectA.id], "projects sort by recent edit")
        check(workspace.projectCover(projectB) == nil, "no video uses empty cover instead of invented artwork")
        var coveredClip = clip2
        coveredClip.result?.analysis?.segments?[0].thumbnailUrl = "/api/thumbnail/clip2.jpg"
        workspace.items = [coveredClip]
        check(workspace.projectCover(projectA) == "/api/thumbnail/clip2.jpg", "project uses an actual attached video thumbnail")
        let legacyRunJSON = #"{"id":"run-a","projectId":"project-a","prompt":"Edit","mode":"local","status":"completed","stage":"done","message":"Done","summary":"","intent":"create","question":"","resultText":"","events":[],"artifacts":[],"timeline":[],"version":1,"completed":1,"total":1,"duration":30,"aspect":"16:9","updatedAt":9999}"#
        var legacyRun = try JSONDecoder().decode(AgentRun.self, from: Data(legacyRunJSON.utf8))
        var materialRun = legacyRun
        materialRun.timeline = [
            AgentShot(id: "use-1", mediaId: "shared", start: 0, end: 3, label: "First use", reason: "Opening", locked: false),
            AgentShot(id: "use-2", mediaId: "shared", start: 5, end: 8, label: "Second use", reason: "Closing", locked: false)]
        materialRun.mediaIds = ["shared", "unused", "shared"]
        materialRun.artifacts = [
            AgentArtifact(id: "evidence-1", type: "analysis", title: "Shared.mov", text: "A lakeside walk", mediaId: "shared"),
            AgentArtifact(id: "evidence-2", type: "observation", title: "Shared.mov", text: "A lakeside walk", mediaId: "shared"),
            AgentArtifact(id: "evidence-3", type: "analysis", title: "Other.jpg", text: "Mountains", mediaId: "other")]
        let materialRows = AgentConversationMaterial.collect(materialRun)
        check(materialRows.map(\.id) == ["shared", "unused", "other"], "one row per material across shots, attachments and evidence")
        check(materialRows[0].summary == "A lakeside walk", "duplicate source descriptions are merged")
        check(materialRows[0].mediaID == "shared", "merged material retains its source link")
        check(materialRun.timeline.count == 2, "merging presentation never changes the edit")
        materialRun.status = "failed"
        check(AgentConversationMaterial.collect(materialRun).count == 3, "failed runs retain their materials behind the same disclosure")
        check(AgentConversationMaterial.collect(legacyRun).isEmpty, "empty results have no material disclosure")
        let section = workspace.conversationSection("run-a:materials")
        check(!section.wrappedValue, "materials start collapsed")
        section.wrappedValue = true
        check(workspace.conversationSection("run-a:materials").wrappedValue, "a reconstructed layout preserves expansion")
        check(!workspace.conversationSection("run-b:materials").wrappedValue, "other turns remain collapsed")
        section.wrappedValue = false
        check(!workspace.conversationSection("run-a:materials").wrappedValue, "one click collapses the full material list")
        var mixedRun = legacyRun
        mixedRun.status = "clarify"; mixedRun.clarificationKind = "video_only"
        mixedRun.skillNotice = "Using Travel Vlog to select highlights and shape your story."
        check(mixedRun.canUseVideosOnly, "mixed media has a direct continue action")
        check(mixedRun.hasConversationActions, "material confirmation is displayed with the message")
        mixedRun.clarificationKind = nil
        mixedRun.question = "This rough-cut workflow currently uses video and its original sound only. Remove separate audio/photos to continue; music mixing and photo slideshows are not connected."
        check(mixedRun.canUseVideosOnly && !mixedRun.displayQuestion.contains("not connected"), "old blocked tasks get a clear recoverable choice")
        mixedRun.status = "completed"
        check(!mixedRun.canUseVideosOnly, "completed runs do not offer attachment confirmation")
        check(!mixedRun.hasConversationActions, "completed creation does not retain old confirmation buttons")
        var oldPhotoRun = legacyRun; oldPhotoRun.status = "clarify"
        oldPhotoRun.question = "Add a video; photo slideshows are not supported yet."
        oldPhotoRun.attachments = [Attachment(id: "photo", name: "photo.jpg", kind: "image")]
        check(oldPhotoRun.canResumePhotoEdit && oldPhotoRun.hasConversationActions, "previously blocked photo edits can resume")
        check(!oldPhotoRun.displayQuestion.contains("not supported"), "old photo limits are no longer presented as current capabilities")
        for state in ["consent", "review", "failed", "cancelled", "interrupted"] {
            var decisionRun = legacyRun; decisionRun.status = state
            check(decisionRun.hasConversationActions, "\(state) decision stays in the conversation")
        }
        var activeRun = legacyRun; activeRun.status = "running"
        check(!activeRun.hasConversationActions, "running task has no stale response options")
        var directionRun = legacyRun; directionRun.status = "clarify"
        directionRun.choices = [.init(id: "selected", label: "Use selected moments", prompt: "Use only selected moments.")]
        let restoredDirection = try JSONDecoder().decode(AgentRun.self, from: JSONEncoder().encode(directionRun))
        check(restoredDirection.hasConversationActions && restoredDirection.choices?.first?.prompt == "Use only selected moments.", "direction options retain executable requests after reload")
        let restoredMixedRun = try JSONDecoder().decode(AgentRun.self, from: JSONEncoder().encode(mixedRun))
        check(restoredMixedRun.skillNotice == mixedRun.skillNotice, "skill notice survives persistence")
        var attachmentRun = legacyRun
        attachmentRun.attachments = projectA.attachments
        attachmentRun.messageAttachments = []
        check(attachmentRun.sentAttachments(in: fixtures).isEmpty, "follow-up without uploads does not repeat old message attachments")
        attachmentRun.messageAttachments = projectA.attachments
        let restoredAttachmentRun = try JSONDecoder().decode(AgentRun.self, from: JSONEncoder().encode(attachmentRun))
        check(restoredAttachmentRun.sentAttachments(in: []).map(\.name) == projectA.attachments.map(\.name), "sent filenames survive missing sources and reload")
        workspace.open(projectA); workspace.agentRuns = [attachmentRun]
        workspace.composerDraft = Draft(attachments: projectA.attachments, projectId: projectA.id)
        check(workspace.composerPendingAttachments.isEmpty, "sent project sources are hidden from composer")
        let newUpload = Attachment(id: "new-photo", name: "new.jpg", kind: "image")
        workspace.composerDraft.attachments.append(newUpload)
        check(workspace.composerPendingAttachments == [newUpload], "new uploads remain visible before sending")
        check(attachmentRun.sentAttachments(in: []).count == projectA.attachments.count, "editing the draft never mutates sent attachments")
        var analysisRun = legacyRun
        analysisRun.intent = "analyze"
        analysisRun.resultText = "Results are linked to original files and sampled time ranges. Visual descriptions are not transcripts."
        analysisRun.artifacts = [
            AgentArtifact(id: "a", type: "analysis", title: "camp.mp4", text: "Packing a bag.\nAction · 3s\nUse as preparation.", mediaId: "camp"),
            AgentArtifact(id: "b", type: "analysis", title: "camp.mp4", text: "Closing the bag.\nAction · 2s\nUse as preparation.", mediaId: "camp"),
            AgentArtifact(id: "c", type: "analysis", title: "coffee.jpg", text: "Two people at camp.", mediaId: "coffee")]
        let legacyReport = analysisRun.displayAnalysisReport!
        check(analysisRun.resultHeading == "Footage summary", "completed analysis identifies its actual deliverable")
        var outcomeRun = legacyRun
        outcomeRun.intent = "create"
        check(outcomeRun.resultHeading == nil, "completed flag alone cannot claim a video exists")
        outcomeRun.artifacts = [AgentArtifact(id: "preview-result", type: "preview", title: "Cut", text: "Video", path: "/fixture/preview.mp4")]
        check(outcomeRun.resultHeading == "Video preview", "rendered artifact is presented as a video deliverable")
        outcomeRun.status = "running"
        check(outcomeRun.resultHeading == nil, "running tasks never show a final output heading")
        outcomeRun.status = "completed"; outcomeRun.intent = "plan"; outcomeRun.artifacts = []
        outcomeRun.timeline = [AgentShot(id: "plan-shot", mediaId: "camp", start: 2, end: 5, label: "Opening", reason: "Establish the scene", locked: false)]
        check(outcomeRun.resultHeading == "Story plan" && outcomeRun.resultDetail?.contains("3.0s") == true, "custom plan requests show actual shot count and duration")
        let reportFile = AgentArtifact(id: "report", type: "file", title: "Shot breakdown · camp.mp4", text: "Editorial JSON", path: "/fixture/report.json")
        let sourceGroups = AgentSourceGroup.groups(analysisRun.artifacts + [reportFile])
        check(sourceGroups.count == 2 && sourceGroups[0].findings.count == 2, "source results group related shots without interleaving downloads")
        check(sourceGroups.map(\.title) == ["camp.mp4", "coffee.jpg"], "source groups preserve original order")
        let formatted = AgentArtifact(id: "formatted", type: "analysis", title: "snow.mp4", text: "A mountain under moving clouds.\nAction · Transition · Recommended · 3s\nUse as a scenic transition.")
        check(formatted.findingParts.content == "A mountain under moving clouds.", "analysis description is separate from technical metadata")
        check(formatted.findingParts.metadata == "Action · Transition · Recommended · 3s" && formatted.findingParts.suggestion == "Use as a scenic transition.", "editing advice has its own visual section")
        let transcript = AgentArtifact(id: "speech", type: "subtitle", title: "speech.mp4", text: formatted.text)
        check(transcript.findingParts.content == formatted.text && transcript.findingParts.suggestion == nil, "transcript text is never parsed as editing advice")
        let unstructured = AgentArtifact(id: "old", type: "analysis", title: "old.mp4", text: "First paragraph.\nSecond paragraph.")
        check(unstructured.findingParts.content == unstructured.text, "unstructured legacy analysis is preserved in full")
        check(legacyReport.materials.count == 2, "legacy findings group by file, not shot")
        check(legacyReport.materials[0].content == "Packing a bag.\nClosing the bag.", "legacy content covers all findings, not only the first shot")
        check(legacyReport.materials[0].suggestion == "Use as preparation.", "legacy advice is deduplicated")
        check(legacyReport.materials[1].suggestion.isEmpty, "no invented advice for legacy photo")
        analysisRun.analysisReport = AgentAnalysisReport(overview: "Camp activities and scenery.", materials: legacyReport.materials, synthesized: true)
        let decodedReport = try JSONDecoder().decode(AgentRun.self, from: JSONEncoder().encode(analysisRun))
        check(decodedReport.displayAnalysisReport?.overview == "Camp activities and scenery.", "structured report round-trips")
        analysisRun.status = "running"
        check(analysisRun.displayAnalysisReport == nil, "running task does not expose premature results")
        check(legacyRun.displayAnalysisReport == nil, "non-analysis results stay unchanged")
        var activityRun = legacyRun
        var scrolling = AgentScrollState()
        check(scrolling.observe(bottom: 400, height: 400, viewport: 500), "initial content follows latest")
        check(scrolling.observe(bottom: 900, height: 900, viewport: 500), "new material growth does not disable following")
        _ = scrolling.observe(bottom: 800, height: 900, viewport: 500)
        check(!scrolling.followingLatest, "scrolling up releases automatic following")
        check(!scrolling.observe(bottom: 1100, height: 1200, viewport: 500), "new findings do not pull a reader from history")
        _ = scrolling.observe(bottom: 510, height: 1200, viewport: 500)
        check(scrolling.followingLatest, "scrolling back to the bottom restores following")
        activityRun.status = "running"; activityRun.stage = "plan"
        activityRun.progressUpdates = [
            AgentProgressUpdate(id: "request", kind: "stage", stage: "intent"),
            AgentProgressUpdate(id: "review", kind: "stage", stage: "understand"),
            AgentProgressUpdate(id: "source", kind: "media", mediaId: "fire"),
            AgentProgressUpdate(id: "planning", kind: "stage", stage: "plan")]
        check(activityRun.visibleProgress.map(\.id) == ["request", "review", "source"], "live stage appears only in the final loading indicator")
        activityRun.status = "completed"
        check(activityRun.visibleProgress.last?.id == "planning", "finished stage history remains available")
        activityRun.progressUpdates = nil
        var evidenceRun = legacyRun
        evidenceRun.intent = "search"
        evidenceRun.artifacts = [AgentArtifact(id: "match", type: "match", title: "fire.mp4", text: "A campfire", mediaId: "fire", start: 1, end: 3)]
        check(evidenceRun.showsDirectEvidence && evidenceRun.directEvidence.count == 1, "search results are available directly")
        evidenceRun.intent = "subtitles"
        check(evidenceRun.directEvidence.isEmpty, "transcripts never substitute visual descriptions")
        evidenceRun.status = "running"
        check(!evidenceRun.showsDirectEvidence, "running results stay out of final answer")
        activityRun.status = "running"; activityRun.stage = "understand"
        activityRun.message = "Understanding camp.mp4 · window 1/2"
        activityRun.events = ["Preparing local tools", activityRun.message]
        check(activityRun.stageLabel == "Reviewing your clips" && activityRun.activityNotice == nil, "running UI has only one plain-language step")
        activityRun.total = 3; activityRun.completed = 1
        check(activityRun.stageLabel == "Reviewing your clips · 2/3", "multi-file progress is understandable without technical logs")
        activityRun.completed = 3
        check(activityRun.stageLabel.hasSuffix("3/3"), "progress never exceeds its total")
        activityRun.total = 1; activityRun.completed = 1
        for (stage, text) in [("intent", "Reading your request"), ("transcribe", "Listening to your audio"), ("plan", "Putting your story together"), ("render", "Making your preview")] {
            activityRun.stage = stage
            check(activityRun.stageLabel == text, "plain language for \(stage)")
        }
        activityRun.status = "queued"
        check(activityRun.stageLabel == "Getting started", "queued state is not shown as already processing")
        activityRun.status = "completed"
        check(activityRun.activityNotice == nil, "completed turns show results without stale progress")
        activityRun.status = "failed"; activityRun.message = "The original file is missing."
        check(activityRun.activityNotice == activityRun.message, "actionable failures remain visible")
        activityRun.message = "Invalid source range for fixture: start=0, end=12"
        check(activityRun.activityNotice == "I couldn't make a valid edit from these clips. Retry, or try fewer videos.", "invalid model edits offer a plain-language recovery action")
        activityRun.message = "'VideoDescriptions' object has no attribute 'library'"
        activityRun.stage = "understand"
        check(activityRun.activityNotice == "A local processing error stopped this task. Try again to continue.", "internal errors have a readable recovery message")
        check(activityRun.failureTitle == "Couldn't finish analyzing your footage", "failure heading identifies the affected step")
        check(activityRun.message.contains("has no attribute"), "original diagnostics remain available in technical details")
        activityRun.message = "Shot output failed validation: Return video_summary and exactly one shot."
        check(activityRun.activityNotice == "The model couldn't produce a valid shot description. Retry to continue from saved results.", "model schema failures show a recovery action, not raw JSON field requirements")
        check(activityRun.activityNotice != activityRun.message, "technical model error remains available in collapsed details")
        activityRun.status = "consent"; activityRun.question = "Allow this task to send selected frames to the cloud?"
        check(activityRun.activityNotice == nil && !activityRun.question.isEmpty, "consent question is preserved without duplicate notices")
        workspace.agentRuns = [legacyRun]
        check(workspace.projectEditedAt(projectA) == 1000, "background run timestamps do not masquerade as edits")
        legacyRun.editedAt = 3000; workspace.agentRuns = [legacyRun]
        check(workspace.projectEditedAt(projectA) == 3000 && workspace.sortedProjects.first?.id == projectA.id, "timeline edits update project timestamp and sorting")
        workspace.navigate(.home); workspace.draft = Draft(prompt: String(repeating: "字", count: 5001))
        check(!workspace.canSubmitAgent && workspace.composerIssue != nil, "oversized input is blocked before service request")
        workspace.draft.prompt = "Analyze"
        workspace.agentRuns = []
        check(workspace.needsComposerMaterials && !workspace.canSubmitAgent, "missing files show guidance and prevent an empty task")
        workspace.draft.attachments = projectA.attachments
        check(!workspace.needsComposerMaterials && workspace.canSubmitAgent && workspace.draft.prompt == "Analyze", "adding files enables send without changing or submitting the request")
        for starter in AgentExample.starters {
            workspace.draft = Draft(prompt: starter.prompt)
            let runCount = workspace.agentRuns.count
            check(workspace.needsComposerMaterials && !workspace.canSubmitAgent, "\(starter.id) guides missing material before submission")
            workspace.beginSelection(); workspace.cancelSelection()
            check(workspace.page == .home && workspace.draft.prompt == starter.prompt && workspace.draft.attachments.isEmpty, "\(starter.id) survives cancelling Media selection")
            workspace.beginSelection(); workspace.selection = [clip2.id]; workspace.finishSelection()
            check(workspace.page == .home && workspace.draft.prompt == starter.prompt && workspace.canSubmitAgent, "\(starter.id) is ready after selecting Media")
            check(workspace.agentRuns.count == runCount, "\(starter.id) waits for explicit send")
        }
        legacyRun.status = "running"; workspace.agentRuns = [legacyRun]
        check(workspace.blockingAgentRun?.id == legacyRun.id && !workspace.canSubmitAgent, "a different running project cannot be silently stopped")
        workspace.open(projectA)
        workspace.composerDraft.prompt = "Update this project"
        workspace.composerDraft.attachments = projectA.attachments
        check(workspace.canSubmitAgent, "explicit same-project stop and update remains available")
        check(!workspace.canApplyAgentOption, "option clicks cannot interrupt an active task")
        workspace.importing = true
        check(!workspace.canSubmitAgent, "wait for imported attachments before submitting")
        workspace.importing = false
        legacyRun.status = "clarify"; legacyRun.clarificationKind = "materials"; workspace.agentRuns = [legacyRun]
        workspace.composerDraft = Draft(attachments: projectA.attachments, projectId: projectA.id)
        check(workspace.canResumeWithMaterials && workspace.canSubmitAgent, "materials-only reply can continue the previous request")
        legacyRun.clarificationKind = nil; workspace.agentRuns = [legacyRun]
        check(workspace.canApplyAgentOption, "options execute with an empty composer")
        workspace.saving = true
        check(!workspace.canApplyAgentOption, "duplicate option clicks are blocked during submission")
        workspace.saving = false
        check(!workspace.canSubmitAgent, "other clarification requires a real answer")
        workspace.composerDraft.prompt = "Analyze"
        workspace.agentMode = "cloud"
        workspace.agentCapabilities = AgentCapabilities(localText: true, localVision: true, localSpeech: true, cloudText: false, cloudVision: false, baseURL: "", model: "", visionModel: "", localModel: "", note: "")
        check(!workspace.canSubmitAgent && workspace.composerIssue!.contains("cloud text"), "unconfigured cloud request is blocked with actionable feedback")
        workspace.agentMode = "local"; workspace.agentCapabilities = nil
        workspace.items = fixtures
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("photo.jpg")
        workspace.resetMediaFilters()
        check(workspace.visibleItems.count == 3, "no hidden location restriction remains")
        workspace.query = "Glacier"; workspace.searchScope = .all
        check(workspace.visibleItems.count == 3, "location metadata remains searchable via explicit all-information search")
        workspace.resetMediaFilters()
        check(!workspace.hasMediaFilters && workspace.searchScope == .all, "clear filters restores full-text library search")
        try Data([1]).write(to: photo)
        try Data([2]).write(to: directory.appendingPathComponent("skip.txt"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("alias.jpg"), withDestinationURL: photo)
        let paths = try WorkspaceStore.collect([directory, photo])
        check(paths == [photo.path], "deduplicate folders; skip unsupported files and symlinks")
        for index in 0..<100 { try Data([1]).write(to: directory.appendingPathComponent("\(index).mp4")) }
        do { _ = try WorkspaceStore.collect([directory]); fatalError("FAIL: import limit") }
        catch { check(error.localizedDescription.contains("100"), "reject oversized imports without truncation") }
        var editRun = legacyRun
        editRun.timeline = [AgentShot(id: "s1", mediaId: "clip2", start: 0, end: 3, label: "Trail", reason: "Action", locked: false)]
        var edit = EditorDraft(run: editRun)
        check(!edit.dirty && edit.validation(durations: ["clip2": 10]) == nil, "valid editor baseline")
        var photoEdit = edit
        photoEdit.shots = [AgentShot(id: "photo-shot", mediaId: "photo", start: 0, end: 4, label: "Photo", reason: "", locked: false)]
        check(photoEdit.validation(durations: ["photo": 60], photoIDs: ["photo"]) == nil, "photos have display durations instead of a zero source duration")
        photoEdit.shots[0].start = 1
        check(photoEdit.validation(durations: ["photo": 60], photoIDs: ["photo"]) != nil, "photo display starts at zero")
        photoEdit.shots[0].start = 0; photoEdit.shots[0].end = 61
        check(photoEdit.validation(durations: ["photo": 60], photoIDs: ["photo"]) != nil, "photo display limit matches backend")
        edit.split("s1", at: 1.5)
        check(edit.shots.count == 2 && edit.duration == 3 && edit.dirty, "split preserves source coverage and duration")
        edit.undo(); check(edit.shots == editRun.timeline && !edit.dirty, "undo restores exact baseline")
        edit.redo(); check(edit.shots.count == 2, "redo restores split")
        let restored = try JSONDecoder().decode(EditorDraft.self, from: JSONEncoder().encode(edit))
        check(restored == edit, "draft and undo/redo survive persistence")
        var layered = EditorDraft(run: editRun)
        var finishing = AgentFinishing.empty
        finishing.clipAudio = [.init(shotId: "s1", volume: 0.4, muted: true)]
        finishing.captions = [.init(id: "caption", start: 0.5, end: 1.5, text: "旅行的时光")]
        layered.setFinishing(finishing)
        check(layered.dirty && layered.finishing?.gain(for: "s1") == 0, "layer-only edit is dirty and mute retains remembered gain")
        check(layered.validation(durations: ["clip2": 10]) == nil, "valid subtitle range")
        layered.undo(); check(!layered.dirty, "undo restores layers together with shots")
        layered.redo(); check(layered.finishing == finishing, "redo restores exact caption and audio")
        let layerRoundTrip = try JSONDecoder().decode(EditorDraft.self, from: JSONEncoder().encode(layered))
        check(layerRoundTrip == layered, "layers and their history survive restart")
        var shortened = layered.shots; shortened[0].end = 1
        layered.replace(shortened)
        check(layered.validation(durations: ["clip2": 10]) != nil, "trim cannot silently truncate an existing caption")
        layered.undo(); check(layered.duration == 3 && layered.finishing == finishing, "undo keeps original caption timing")
        var legacyDraftJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(layered)) as! [String: Any]
        for key in ["finishing", "baseFinishing", "undoLayers", "redoLayers"] { legacyDraftJSON.removeValue(forKey: key) }
        var migrated = try JSONDecoder().decode(EditorDraft.self, from: JSONSerialization.data(withJSONObject: legacyDraftJSON))
        migrated.hydrateLayers(from: editRun)
        check(migrated.finishing == (editRun.finishing ?? .empty), "old draft migrates without discarding existing shots")
        edit.undo(); edit.shots[0].locked = true; edit.split("s1", at: 1)
        check(edit.shots.count == 1, "locked shot cannot split")
        edit.shots[0].end = 11
        check(edit.validation(durations: ["clip2": 10]) != nil, "reject source overflow")
        edit.shots[0].end = .nan
        check(edit.validation(durations: [:]) != nil, "reject nonfinite edits")
        edit.shots = []; check(edit.validation(durations: [:]) != nil, "reject empty timeline")
        edit = EditorDraft(run: editRun); edit.shots[0].end = 0.1
        check(edit.validation(durations: [:]) != nil, "reject sub-frame-like short interval")
        edit = EditorDraft(run: editRun); edit.shots.append(edit.shots[0])
        check(edit.validation(durations: [:]) != nil, "reject duplicate shot identifiers")
        edit = EditorDraft(run: editRun)
        let trim = edit.trimming("s1", leading: false, delta: 2, durations: ["clip2": 10], photoIDs: [])!
        check(trim[0].end == 5 && edit.shots[0].end == 3 && edit.undoStack.isEmpty, "handle preview leaves committed draft and undo untouched")
        edit.replace(trim)
        check(edit.undoStack.count == 1 && edit.duration == 5, "one drag commits one undo transaction")
        edit.undo(); check(edit.duration == 3, "undo restores pre-drag duration")
        edit.redo(); check(edit.duration == 5, "redo restores drag")
        check(edit.trimming("s1", leading: false, delta: 100, durations: ["clip2": 10], photoIDs: [])![0].end == 10, "right handle clamps to source duration")
        check(edit.trimming("s1", leading: true, delta: 100, durations: ["clip2": 10], photoIDs: [])![0].start == 4.75, "left handle retains minimum clip length")
        check(edit.trimming("s1", leading: true, delta: -100, durations: ["clip2": 10], photoIDs: [])![0].start == 0, "left handle cannot move before source")
        check(edit.trimming("s1", leading: false, delta: .nan, durations: [:], photoIDs: []) == nil, "nonfinite drag rejected")
        edit.shots[0].locked = true
        check(edit.trimming("s1", leading: false, delta: 1, durations: [:], photoIDs: []) == nil, "locked clip has no trim")
        edit.shots[0].locked = false; edit.base[0].locked = true
        check(edit.trimming("s1", leading: false, delta: 1, durations: [:], photoIDs: []) == nil, "unlock must be saved before trim")
        photoEdit.shots[0].end = 4
        let photoTrim = photoEdit.trimming("photo-shot", leading: true, delta: 1, durations: ["photo": 60], photoIDs: ["photo"])!
        check(photoTrim[0].start == 0 && photoTrim[0].end == 3, "photo left handle changes display time, never source in point")
        check(photoEdit.trimming("photo-shot", leading: false, delta: 100, durations: ["photo": 60], photoIDs: ["photo"])![0].end == 60, "photo handle clamps to 60 seconds")
        check(EditorDraft.time(at: 120, zoom: 40, duration: 9) == 3, "ruler uses exact pixels per second")
        check(EditorDraft.time(at: -10, zoom: 40, duration: 9) == 0 && EditorDraft.time(at: 999, zoom: 40, duration: 9) == 9, "scrubbing clamps at both timeline edges")
        check(EditorDraft.time(at: 10, zoom: 0, duration: 9) == 0, "invalid timeline scale is safe")
        check(EditorDraft.fitZoom(duration: 40, width: 1200) == 30, "fit timeline includes the whole cut")
        check(EditorDraft.fitZoom(duration: 600, width: 600) == 1, "long cuts can fit without a 20px minimum")
        check(EditorDraft.fitZoom(duration: 0, width: 600) == 36 && EditorDraft.fitZoom(duration: .nan, width: 600) == 36, "fit handles absent duration")
        check(EditorDraft.fitZoom(duration: 1, width: 900) == 160, "fit respects maximum scale")
        photoEdit.shots[0].end = 4
        let beforePhotoSplit = photoEdit.shots
        photoEdit.split("photo-shot", at: 1.5, photoIDs: ["photo"])
        check(photoEdit.shots.count == 2 && photoEdit.shots.allSatisfy { $0.start == 0 }, "split photos preserve zero source origin")
        check(photoEdit.duration == 4 && photoEdit.shots[1].end == 2.5, "photo split preserves total display duration")
        check(photoEdit.validation(durations: ["photo": 60], photoIDs: ["photo"]) == nil, "split photo timeline remains renderable")
        photoEdit.undo(); check(photoEdit.shots == beforePhotoSplit, "photo split is one reversible edit")
        edit = EditorDraft(run: editRun); edit.base[0].locked = true
        edit.split("s1", at: 1)
        check(edit.shots.count == 1, "unsaved unlock cannot bypass split lock")
        let editorStore = WorkspaceStore()
        let story = [
            AgentShot(id: "a", mediaId: "p", start: 0, end: 3, label: "Lake", reason: "", locked: false),
            AgentShot(id: "b", mediaId: "v", start: 2, end: 6, label: "Trail", reason: "", locked: false),
            AgentShot(id: "c", mediaId: "p2", start: 0, end: 2, label: "Sunset", reason: "", locked: false)
        ]
        check(StoryTimeline.index(at: 3, in: story) == 1 && StoryTimeline.offset("c", in: story) == 7, "story boundaries use source durations rather than source in points")
        var arrangementRun = legacyRun
        arrangementRun.timeline = story
        arrangementRun.resultText = "Open on the lake, then follow the walk to the lookout.\nNo recorded speech."
        check(arrangementRun.arrangementSummary == "Open on the lake, then follow the walk to the lookout.", "legacy story introduction excludes limitations")
        check(arrangementRun.arrangementDetails == "No recorded speech.", "story introduction is not duplicated in details")
        arrangementRun.storySummary = "Begin with the lookout, then return to the lakeside."
        arrangementRun.status = "running"; arrangementRun.stage = "render"
        check(arrangementRun.arrangementSummary == arrangementRun.storySummary, "validated arrangement is visible before rendering completes")
        arrangementRun.intent = "analyze"
        check(arrangementRun.arrangementSummary == nil, "analysis does not pretend to have an arrangement")
        arrangementRun.intent = "create"; arrangementRun.timeline = []
        check(arrangementRun.arrangementSummary == nil, "routing without a timeline does not invent an arrangement")
        check(StoryTimeline.index(at: 99, in: story) == 2 && StoryTimeline.index(at: .nan, in: story) == nil, "story seek handles the end and invalid input")
        check(StoryTimeline.move(["c"], before: "a", in: story, locked: [])?.map(\.id) == ["c", "a", "b"], "story card reorders before an explicit target")
        check(StoryTimeline.move(["a", "b"], before: nil, in: story, locked: [])?.map(\.id) == ["c", "a", "b"], "multi-card move preserves relative order")
        check(StoryTimeline.move(["c"], before: "a", in: story, locked: ["b"]) == nil, "reorder cannot move a locked card indirectly")
        check(StoryTimeline.move(["a"], before: "a", in: story, locked: []) == nil, "drop on self makes no undo step")
        check(StoryTimeline.move(["missing"], before: nil, in: story, locked: []) == nil, "unknown drag identifiers rejected")
        let voice = [AgentFinishing.Narration(start: 1, end: 6, text: "Across the lake", voice: "")]
        check(StoryTimeline.parseTime("1:02.50") == 62.5 && StoryTimeline.parseTime("3.25") == 3.25, "precision fields accept seconds and timecodes")
        check(["-1", "nan", "1:60", "1::2", "x", "1.2:03"].allSatisfy { StoryTimeline.parseTime($0) == nil }, "precision fields reject malformed or nonfinite timecodes")
        check(StoryTimeline.timecode(59.999) == "1:00.00", "timecode rounds across minute boundaries")
        check(StoryTimeline.timelineScale(viewport: 600, duration: 120, zoom: 1) == 5, "fit includes the whole timeline")
        check(StoryTimeline.timelineScale(viewport: 600, duration: 120, zoom: 4) == 20, "all lanes share zoom scale")
        check(StoryTimeline.timelineScale(viewport: 600, duration: 0, zoom: 1).isFinite, "empty timeline scale is finite")
        check(StoryTimeline.timelineScale(viewport: 600, duration: 120, zoom: 99) == 160, "zoom is bounded")
        check(StoryTimeline.rulerStep(scale: 5) == 10 && StoryTimeline.rulerStep(scale: 100) == 0.5, "ticks adapt to zoom without label overlap")
        check(StoryTimeline.thumbnailTimes(start: 10, end: 16, count: 3) == [11, 13, 15], "filmstrip samples within the selected source range")
        check(StoryTimeline.thumbnailTimes(start: 0, end: 0.25, count: 1) == [0.125], "short clips still have a frame")
        check(StoryTimeline.thumbnailTimes(start: 0, end: 6, count: 100).count == 6, "video frame decoding is bounded")
        check(StoryTimeline.thumbnailTimes(start: 2, end: 1, count: 1).isEmpty, "invalid ranges do not decode")
        check(StoryTimeline.thumbnailTimes(start: .nan, end: 1, count: 1).isEmpty, "nonfinite sample ranges are rejected")
        check(StoryTimeline.filmstripTileCount(width: 8) == 1, "short clip covers are never hidden")
        check(StoryTimeline.filmstripTileCount(width: 300) == 4, "long clips fill with multiple thumbnails")
        check(StoryTimeline.filmstripTileCount(width: 100000) == 128, "extreme zoom has bounded image tiles")
        check(abs(StoryTimeline.steppedTime(3, direction: 1, duration: 9)-3-1.0/30) < 0.00001, "right arrow steps one output frame")
        check(StoryTimeline.steppedTime(0, direction: -1, duration: 9) == 0, "left arrow clamps at start")
        check(StoryTimeline.steppedTime(8.99, direction: 1, duration: 9) == 9, "right arrow clamps at end")
        check(StoryTimeline.steppedTime(3, direction: -1, duration: 9, seconds: true) == 2, "shift arrow steps a second")
        check(StoryTimeline.steppedTime(.nan, direction: 1, duration: 9) == 0, "invalid playback time is safe")
        check(StoryTimeline.range(start: 2, end: 6, sourceDuration: 10, delta: 100, edge: 0) == 6...10, "slip keeps duration and clamps at source end")
        check(StoryTimeline.range(start: 2, end: 6, sourceDuration: 10, delta: -100, edge: 0) == 0...4, "slip cannot go before source start")
        check(StoryTimeline.range(start: 2, end: 6, sourceDuration: 10, delta: 100, edge: -1) == 5.75...6, "in handle cannot cross out handle")
        check(StoryTimeline.range(start: 2, end: 6, sourceDuration: 10, delta: -100, edge: 1) == 2...2.25, "out handle maintains minimum duration")
        var replacementPhoto = item; replacementPhoto.id = "replacement"; replacementPhoto.kind = "image"; replacementPhoto.status = "ready"
        let replacedPhoto = StoryTimeline.replacing(story[1], with: replacementPhoto)!
        let insertedPhoto = StoryTimeline.inserting(replacementPhoto, before: story[1].id, in: story)!
        check(insertedPhoto.count == story.count+1 && insertedPhoto[1].mediaId == replacementPhoto.id && insertedPhoto[1].end == 3, "insert photo at exact list position with default duration")
        check(!Set(story.map(\.id)).contains(insertedPhoto[1].id), "inserted use has a unique clip identity")
        check(StoryTimeline.inserting(replacementPhoto, before: "gone", in: story) == nil, "stale insertion target cannot append silently")
        var insertionLocked = story; insertionLocked[1].locked = true
        check(StoryTimeline.inserting(replacementPhoto, before: story[1].id, in: insertionLocked) == nil, "insertion does not shift a locked clip")
        check(StoryTimeline.inserting(replacementPhoto, before: nil, in: insertionLocked)?.count == story.count+1, "append after locked clip remains available")
        check(replacedPhoto.id == story[1].id && replacedPhoto.start == 0 && replacedPhoto.end == story[1].end - story[1].start, "replacement keeps clip identity and duration; photo starts at zero")
        var replacementVideo = replacementPhoto; replacementVideo.kind = "video"; replacementVideo.metadata?.duration = 1.5
        check(StoryTimeline.replacing(story[1], with: replacementVideo)?.end == 1.5, "short replacement clamps to available source")
        replacementVideo.missing = true
        check(StoryTimeline.replacing(story[1], with: replacementVideo) == nil, "missing media cannot replace a clip")
        var lockedStory = story[1]; lockedStory.locked = true
        check(StoryTimeline.replacing(lockedStory, with: replacementPhoto) == nil, "locked clip cannot be replaced")
        var duplicateRun = editRun; duplicateRun.timeline = [story[0], story[0]]; duplicateRun.timeline[1].id = "other-use"
        editorStore.selectedProjectID = duplicateRun.projectId; editorStore.agentRuns = [duplicateRun]
        check(editorStore.usedShots("p")?.shots.filter { $0.mediaId == "p" }.count == 2, "usage retains multiple ranges of the same source")
        var duplicateDraft = EditorDraft(run: duplicateRun); var adjusted = duplicateDraft.shots; adjusted[0].end = 5; duplicateDraft.replace(adjusted)
        editorStore.editorDrafts[duplicateRun.id] = duplicateDraft; editorStore.openEditor(duplicateRun.projectId)
        check(editorStore.usedShots("p")?.draft == true && editorStore.usedShots("p")?.shots[1].end == 3, "draft usage is marked and editing one instance leaves the other unchanged")
        check(editorStore.composerIssue == nil, "dirty timeline is saved by send instead of blocking input")
        editorStore.editorSelection = EditorSelection(runId: duplicateRun.id, version: duplicateRun.version, shotIds: [story[0].id])
        editorStore.freezeComposerTarget()
        let pauseRequest = editorStore.editorPauseRequest
        editorStore.editorSelection = EditorSelection(runId: duplicateRun.id, version: duplicateRun.version, shotIds: ["other-use"])
        check(editorStore.composerEditTarget?.shotIds == [story[0].id], "typing locks target even when another card is selected")
        editorStore.freezeComposerTarget()
        check(editorStore.editorPauseRequest == pauseRequest, "focus does not repeatedly pause or retarget an existing request")
        editorStore.chooseComposerTarget(wholeFilm: true)
        check(editorStore.composerEditTarget?.shotIds.isEmpty == true && editorStore.editorSelectionLabel == "Whole film", "scope chip explicitly switches to whole film")
        editorStore.chooseComposerTarget(wholeFilm: false)
        check(editorStore.composerEditTarget?.shotIds == ["other-use"], "explicit selected scope uses current selection")
        editorStore.agentRuns[0].version += 1
        check(editorStore.composerIssue?.contains("Choose") == true && editorStore.composerVisibleIssue != nil, "stale frozen target is visible and never silently retargeted")
        editorStore.agentRuns = [duplicateRun]
        var receiptRun = duplicateRun
        receiptRun.status = "completed"
        receiptRun.editReceipt = AgentEditReceipt(changedShotIds: ["other-use"], removedCount: 0, soundOrCaptions: false, aspectChanged: false, version: duplicateRun.version, undone: false)
        editorStore.agentRuns = [receiptRun]
        check(!editorStore.canUndoAgentEdit(receiptRun), "AI undo cannot overwrite a dirty local draft")
        editorStore.editorDrafts[duplicateRun.id] = EditorDraft(run: receiptRun)
        check(editorStore.canUndoAgentEdit(receiptRun), "latest unchanged AI result can be undone")
        var newer = receiptRun; newer.id = "newer-turn"; newer.updatedAt += 100
        editorStore.agentRuns = [newer, receiptRun]
        check(!editorStore.canUndoAgentEdit(receiptRun), "earlier conversation results cannot overwrite later work")
        editorStore.agentRuns = [receiptRun]
        var staleReceipt = receiptRun; staleReceipt.version += 1
        check(!editorStore.canUndoAgentEdit(staleReceipt), "saved manual version invalidates AI undo")
        check(receiptRun.editReceipt?.summary == "1 clip updated", "receipt summarizes actual changes compactly")
        editorStore.editorDrafts[duplicateRun.id] = duplicateDraft
        editorStore.closeEditor()
        check(editorStore.composerEditTarget?.shotIds == ["other-use"], "collapsing editor preserves the request scope in the same conversation")
        let failedSend = WorkspaceStore()
        var sendRun = editRun; sendRun.status = "completed"
        failedSend.agentRuns = [sendRun]; failedSend.items = [clip2]
        failedSend.openEditor(sendRun.projectId)
        failedSend.composerDraft = Draft(prompt: "Shorten this clip", attachments: [Attachment(id: clip2.id, name: clip2.name, kind: "video")], projectId: sendRun.projectId)
        var invalidDraft = EditorDraft(run: sendRun); invalidDraft.shots[0].end = -1
        failedSend.editorDrafts[sendRun.id] = invalidDraft
        failedSend.submitAgent()
        for _ in 0..<100 where failedSend.saving { try await Task.sleep(nanoseconds: 1_000_000) }
        check(failedSend.error != nil && failedSend.composerDraft.prompt == "Shorten this clip", "invalid autosave leaves request text intact and reports failure")
        check(failedSend.agentRuns.count == 1 && failedSend.editorDrafts[sendRun.id] == invalidDraft, "failed validation neither starts AI nor discards the draft")
        invalidDraft.shots[0].end = 2; failedSend.editorDrafts[sendRun.id] = invalidDraft; failedSend.error = nil
        failedSend.submitAgent()
        for _ in 0..<100 where failedSend.saving { try await Task.sleep(nanoseconds: 1_000_000) }
        check(!failedSend.saving && failedSend.error != nil && failedSend.composerDraft.prompt == "Shorten this clip", "unavailable service does not erase input or leave send spinning")
        check(failedSend.agentRuns.count == 1 && failedSend.editorDrafts[sendRun.id]?.dirty == true, "save failure prevents starting a new AI request")
        check(editorStore.editorProjectID == nil && editorStore.editorDrafts[duplicateRun.id]?.shots == adjusted, "video-card collapse retains unsaved timeline edits")
        editorStore.openEditor(duplicateRun.projectId)
        check(editorStore.editorProjectID == duplicateRun.projectId && editorStore.editorDrafts[duplicateRun.id]?.shots == adjusted, "reopening from the video card restores the same draft")
        duplicateDraft.undo(); check(duplicateDraft.shots == duplicateRun.timeline, "undo restores exact repeated-source ranges")
        editorStore.editorDrafts = [:]; editorStore.page = .home; editorStore.editorProjectID = nil
        check(StoryTimeline.narration(at: 0, shots: story, cues: voice).first?.continued == false, "narration starts on its first card")
        check(StoryTimeline.narration(at: 1, shots: story, cues: voice).first?.continued == true, "cross-clip narration uses continuation instead of duplicate text")
        check(StoryTimeline.narration(at: 2, shots: story, cues: voice).isEmpty, "finished narration is not shown on later cards")
        var generated = editRun
        generated.status = "completed"
        generated.artifacts = [AgentArtifact(id: "render1", type: "preview", title: "Preview", text: "", path: "/fixture/video.mp4")]
        editorStore.agentRuns = [generated]
        check(editorStore.editorProjectID == nil, "background generation never navigates away from home")
        editorStore.selectedProjectID = generated.projectId; editorStore.page = .project
        check(editorStore.editorProjectID == generated.projectId, "finished video opens editor by default")
        editorStore.closeEditor(); editorStore.agentRuns = [generated]
        check(editorStore.editorProjectID == nil, "polling respects manual collapse")
        generated.version += 1; generated.status = "running"
        editorStore.agentRuns = [generated]
        check(editorStore.editorProjectID == nil, "running work does not open old preview")
        generated.status = "completed"; generated.artifacts[0].id = "render2"
        editorStore.agentRuns = [generated]
        check(editorStore.editorProjectID == generated.projectId, "a newly completed render opens editor again")
        editorStore.closeEditor(); editorStore.page = .media
        generated.version += 1; editorStore.agentRuns = [generated]
        check(editorStore.editorProjectID == nil && editorStore.page == .media, "background completion does not interrupt media browsing")
        var chapterShots = [AgentShot(id: "chapter-a", mediaId: "p", start: 0, end: 3, label: "A", reason: "", locked: false),
                            AgentShot(id: "chapter-b", mediaId: "p", start: 0, end: 4, label: "B", reason: "", locked: false)]
        check(StoryTimeline.chapters(chapterShots).isEmpty, "unstructured films have no chapter controls")
        chapterShots[0].section = "intro"; chapterShots[1].section = "intro"
        check(StoryTimeline.chapters(chapterShots).isEmpty, "one chapter does not add navigation")
        chapterShots[1].section = "outro"
        check(StoryTimeline.chapters(chapterShots).map(\.start) == [0, 3], "chapter navigation uses current edited durations")
        let crossingVoice = [AgentFinishing.Narration(start: 2, end: 5, text: "Across the cut", voice: "Samantha")]
        check(StoryTimeline.narrationIndices(for: "chapter-a", shots: chapterShots, cues: crossingVoice) == [0] && StoryTimeline.narrationIndices(for: "chapter-b", shots: chapterShots, cues: crossingVoice) == [0], "one narration segment links to both overlapping shots")
        check(StoryTimeline.narrationIndices(for: "missing", shots: chapterShots, cues: crossingVoice).isEmpty, "removed clips have no narration link")
        var historyRun = editRun; historyRun.status = "completed"; historyRun.version = 2; historyRun.timeline = chapterShots
        historyRun.timelineHistory = [.init(version: 1, shots: [chapterShots[0]])]
        historyRun.artifacts = [.init(id: "old-render", type: "previous_preview", title: "Travel film · v1", text: "", path: "/fixture/v1.mp4")]
        let versions = StoryVersion.collect([historyRun])
        check(versions.count == 2 && versions[0].preview == nil && versions[0].shots.count == 2, "unsaved render state is a draft, not an old video mislabeled as current")
        check(versions[1].preview?.id == "old-render" && versions[1].shots.count == 1, "historical preview stays associated with its saved timeline")
        check(historyRun.version == 2 && historyRun.timeline == chapterShots, "reading versions does not change editable state")
        historyRun.artifacts[0].timelineVersion = 2
        check(StoryVersion.collect([historyRun])[0].preview?.id == "old-render", "explicit render version takes priority over an inherited old title after undo")
        var voiceDraft = EditorDraft(run: historyRun)
        var mixed = AgentFinishing.empty; mixed.narration = crossingVoice; mixed.narrationVolume = 0.4; mixed.narrationMuted = true; mixed.musicMuted = true
        voiceDraft.setFinishing(mixed)
        check(voiceDraft.validation(durations: ["p": 10]) == nil, "muted narration retains valid timing and volume")
        let mixRoundtrip = try JSONDecoder().decode(EditorDraft.self, from: JSONEncoder().encode(voiceDraft))
        check(mixRoundtrip.finishing?.narrationVolume == 0.4 && mixRoundtrip.finishing?.narrationMuted == true, "audio mix state survives draft persistence")
        voiceDraft.undo(); check(voiceDraft.finishing?.narrationMuted != true, "audio mixer uses existing undo stack")
        mixed.narration[0].end = 12; voiceDraft.setFinishing(mixed)
        check(voiceDraft.validation(durations: ["p": 10]) != nil, "narration cannot outlive the edited film")
        print("Passed \(checks) native model/import checks.")
    }
}
