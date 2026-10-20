import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class WorkspaceStore: ObservableObject {
    let service = LocalService()
    @Published private(set) var language = AppLanguage.saved
    @Published var settingsPresented = false
    @Published private(set) var onlinePlaceNames = UserDefaults.standard.bool(forKey: PlaceNameResolver.consentKey)
    @Published private(set) var onlinePlaceBoundaries = UserDefaults.standard.bool(forKey: PlaceBoundaryLookup.consentKey)
    @Published private(set) var onlinePlaceFallback = UserDefaults.standard.bool(forKey: PlaceFallbackLookup.consentKey)
    private lazy var placeNames: PlaceNameResolver = {
        let resolver = PlaceNameResolver(canRequest: { NSApp?.isActive == true })
        resolver.onChange = { [weak self, weak resolver] in
            guard let self, let resolver else { return }
            self.items = resolver.applyingCache(to: self.items, language: self.language.rawValue)
            self.persistPlaceNames()
        }
        return resolver
    }()
    private var savedPlaces: [String: ResolvedPlace] = [:]
    private var placeWriteTask: Task<Void, Never>?
    private var placeWriteRetry = Date.distantPast
    private func persistPlaceNames() {
        guard ready, onlinePlaceNames, placeWriteTask == nil, Date() >= placeWriteRetry else { return }
        let changes = items.compactMap { item -> (String, ResolvedPlace)? in
            guard !item.hasSavedPlaceName, let place = item.validResolvedPlace,
                  place.language == language.rawValue, savedPlaces[item.id] != place else { return nil }
            return (item.id, place)
        }
        guard !changes.isEmpty else { return }
        placeWriteTask = Task { [weak self] in
            guard let self else { return }
            defer { placeWriteTask = nil }
            for (id, place) in changes {
                guard !Task.isCancelled, onlinePlaceNames, place.language == language.rawValue else { break }
                do {
                    struct Response: Decodable { var ok: Bool }
                    let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(place))
                    let response: Response = try await service.post("/api/desktop/analysis/place", ["id": id, "place": value], native: true)
                    if response.ok { savedPlaces[id] = place }
                } catch { placeWriteRetry = Date().addingTimeInterval(30); break }
            }
        }
    }
    func saveOnlinePlaceNames(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: PlaceNameResolver.consentKey)
        onlinePlaceNames = enabled
        updatePlaceNames()
    }
    func saveOnlinePlaceBoundaries(_ enabled: Bool) {
        placeNames.cancel()
        UserDefaults.standard.set(enabled, forKey: PlaceBoundaryLookup.consentKey)
        onlinePlaceBoundaries = enabled
        updatePlaceNames()
    }
    func savePlaceSettings(names: Bool, boundaries: Bool, fallback: Bool = false) {
        placeNames.cancel()
        UserDefaults.standard.set(names, forKey: PlaceNameResolver.consentKey)
        UserDefaults.standard.set(boundaries, forKey: PlaceBoundaryLookup.consentKey)
        onlinePlaceNames = names
        onlinePlaceBoundaries = boundaries
        UserDefaults.standard.set(fallback, forKey: PlaceFallbackLookup.consentKey)
        onlinePlaceFallback = fallback
        updatePlaceNames()
    }
    private func updatePlaceNames() {
        items = placeNames.applyingCache(to: items, language: language.rawValue)
        persistPlaceNames()
        placeNames.schedule(items.compactMap { $0.placeQuery(language: language.rawValue) },
                            enabled: onlinePlaceNames, foreground: NSApp?.isActive == true)
    }
    func saveLanguage(_ language: AppLanguage) async throws {
        struct Response: Decodable { var ok: Bool }
        let _: Response = try await service.post("/api/desktop/settings", ["key":"language", "value":language.rawValue], native: true)
        UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
        self.language = language
        updatePlaceNames()
    }
    @Published var page: WorkspacePage? = .media { didSet { if page != .media && page != .mediaMap { detail = nil; mediaReturnProjectID = nil }; expandCompletedEditor() } }
    @Published private(set) var mediaReturnProjectID: String?
    var mediaBackTitle: String { page == .mediaMap ? "Media map" : (mediaReturnProjectID == nil ? "Library" : "Conversation") }
    @Published var ready = false
    @Published var startupError: String?
    @Published var error: String?
    @Published var items: [MediaItem] = [] { didSet {
        searchDocuments = Dictionary(uniqueKeysWithValues: items.map { ($0.id, MediaSearchDocument($0)) })
        mediaTagFrequencies = MediaTagPresentation.frequencies(libraryItems)
        refreshMediaSearch()
        if page == .mediaMap && !hasMediaMap { navigate(.media) }
    } }
    @Published var projects: [Project] = []
    @Published var skills: [CreatorSkill] = []
    @Published var draft = Draft() { didSet { if restoredDraft { persistDraft() } } }
    @Published var projectDrafts: [String: Draft] = [:] { didSet { if restoredDraft { persistProjectDrafts() } } }
    @Published var selectedProjectID: String? { didSet { expandCompletedEditor() } }
    private var selectionProjectID: String?
    private var selectionReturnPage: WorkspacePage = .media
    @Published var mediaAddedRange = MediaAddedRange.all { didSet { refreshMediaSearch() } }
    @Published var mediaWorkFilter = MediaWorkFilter.all { didSet { refreshMediaSearch() } }
    @Published var syncSnapshot: MediaSyncSnapshot?
    @Published var syncStatusUnavailable = false
    @Published var query = "" { didSet { if query != oldValue { visualHits = []; visualQuery = "" }; refreshMediaSearch() } }
    @Published var catalogStatus: CatalogStatus?
    @Published var catalogBusy = false
    @Published var catalogError: String?
    private var visualHits: [CatalogHit] = []
    private var visualQuery = ""
    var catalogMessage: String {
        if let error = catalogError { return error }
        if catalogBusy { return catalogStatus?.job?.message ?? "Queued for local processing…" }
        let count = catalogStatus?.indexed ?? 0
        let total = catalogStatus?.total ?? libraryItems.filter { $0.kind == "video" }.count
        if let stale = catalogStatus?.stale, stale > 0 { return "\(count)/\(total) videos indexed · \(stale) need rebuilding after source or shot changes." }
        if count == 0 { return "No videos indexed. Build an index to search what appears on screen." }
        return "\(count)/\(total) videos indexed · Type a scene and press Return. Matches are suggestions."
    }
    func refreshCatalogStatus() async {
        guard ready else { return }
        do { catalogStatus = try await service.get("/api/desktop/agent/catalog", native: true) }
        catch { if let message = CatalogFailure.message(error) { catalogError = message } }
    }
    func startCatalogIndex() {
        let ids = libraryItems.filter { $0.kind == "video" && $0.missing != true }.map(\.id)
        guard !ids.isEmpty else { catalogError = "No online videos to index."; return }
        performCatalog(["action":"index", "ids":ids])
    }
    func searchVisualMedia() {
        guard (catalogStatus?.indexed ?? 0) > 0, [.all, .content].contains(searchScope),
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        performCatalog(["action":"search", "query":query], querySnapshot: query)
    }
    func stopCatalog() {
        Task {
            struct Result: Decodable { var ok: Bool }
            do { let _: Result = try await service.post("/api/desktop/agent/catalog", ["action":"stop"], native: true) }
            catch { if let message = CatalogFailure.message(error) { catalogError = message } }
        }
    }
    private func performCatalog(_ payload: [String: Any], querySnapshot: String? = nil) {
        guard !catalogBusy else { return }
        catalogBusy = true; catalogError = nil
        if querySnapshot != nil { visualHits = []; visualQuery = ""; refreshMediaSearch() }
        Task {
            defer { catalogBusy = false }
            struct Response: Decodable { var job: CatalogJob }
            do {
                let response: Response = try await service.post("/api/desktop/agent/catalog", payload, native: true)
                var job = response.job
                while job.status == "running" {
                    try await Task.sleep(nanoseconds: 700_000_000)
                    let status: CatalogStatus = try await service.get("/api/desktop/agent/catalog", native: true)
                    catalogStatus = status
                    guard let current = status.job, current.id == job.id else { throw ServiceError(message: "The local task changed. Refresh and retry.") }
                    job = current
                }
                if job.status == "failed" { throw ServiceError(message: job.message) }
                if job.status == "completed", let searched = querySnapshot, query == searched {
                    visualHits = job.hits; visualQuery = searched; refreshMediaSearch()
                }
                if !job.failures.isEmpty { catalogError = "\(job.failures.count) videos unavailable for visual search. HDR / rotation, missing files or model errors may need attention. Existing results were kept." }
                await refreshCatalogStatus()
            } catch { if let message = CatalogFailure.message(error) { catalogError = message } }
        }
    }
    func visualMatchTime(_ id: String) -> Double? {
        guard [.all, .content].contains(searchScope), visualQuery == query else { return nil }
        return visualHits.first { $0.mediaId == id }?.start
    }
    func visualMatch(_ id: String) -> CatalogHit? {
        guard [.all, .content].contains(searchScope), visualQuery == query else { return nil }
        return visualHits.first { $0.mediaId == id }
    }
    func saveMediaTags(_ item: MediaItem, hidden: Set<String>, added: [EvidenceTag]) async throws {
        struct Response: Decodable { var ok: Bool }
        let _: Response = try await service.post("/api/desktop/agent/media-tags", ["id":item.id,
            "hidden":Array(hidden), "added":added.map { ["category":$0.category, "label":$0.label] }], native: true)
        try await refresh()
    }
    @Published var category = MediaCategory.all { didSet { refreshMediaSearch() } }
    @Published var folder = "" { didSet { refreshMediaSearch() } }
    @Published var syncSourceID: String? { didSet { refreshMediaSearch() } }
    @Published var syncSourceName: String?
    @Published var searchScope = MediaSearchScope.all { didSet { refreshMediaSearch() } }
    @Published var sort = MediaSort.original { didSet { refreshMediaSearch() } }
    @Published private(set) var comparingBeauty = false
    private var beautyScores: [String: Double] = [:]
    var canCompareBeauty: Bool { agentCapabilities?.tools?.contains { $0.id == "beauty" && $0.installed && $0.lastExecution == "verified" } == true }
    func compareBeauty() {
        guard canCompareBeauty, !comparingBeauty else { return }
        let selected = visibleItems.filter { $0.status == "ready" && $0.missing != true }
        guard !selected.isEmpty, selected.count <= 100 else { error = "Filter to 1–100 ready materials before comparing."; return }
        let previousSort = sort
        comparingBeauty = true
        struct Job: Decodable { var id: String; var status: String; var scores: [String: Double]?; var message: String? }
        struct Response: Decodable { var job: Job }
        Task {
            defer { comparingBeauty = false }
            do {
                var result: Response = try await service.post("/api/desktop/agent/beauty-sort", ["mediaIds":selected.map(\.id)], native: true)
                for _ in 0..<360 where result.job.status == "running" {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    result = try await service.post("/api/desktop/agent/beauty-sort", ["jobId":result.job.id], native: true)
                }
                guard result.job.status == "completed", let scores = result.job.scores else {
                    throw ServiceError(message: result.job.message ?? "Comparison is taking longer than expected. Your order is unchanged.")
                }
                beautyScores = scores
                // Do not override a different order chosen while inference ran.
                if sort == previousSort { sort = .beauty } else { refreshMediaSearch() }
            } catch { self.error = error.localizedDescription }
        }
    }
    @Published var mediaFacets = MediaFacetSelection() { didSet { refreshMediaSearch() } }
    @Published private(set) var mediaFacetOptions: [MediaFacet: [MediaFacetOption]] = [:]
    @Published var locations: [String: MediaLocation] = [:] { didSet { refreshMediaSearch() } }
    private var searchDocuments: [String: MediaSearchDocument] = [:]
    private var mediaTagFrequencies: [String: Int] = [:]
    @Published private(set) var mediaSearchResults: [MediaSearchResult] = []
    var lastOpenedMediaID: String?
    var mediaSeekTime: Double = 0
    @Published var selecting = false
    @Published var selection: Set<String> = []
    @Published var detail: MediaItem?
    @Published var importing = false
    @Published var saving = false
    @Published var agentRuns: [AgentRun] = [] { didSet { expandCompletedEditor() } }
    @Published var agentCapabilities: AgentCapabilities?
    @Published var agentMode = "local"
    @Published var agentActionPending = false
    @Published var videoExport: VideoExportJob?
    @Published var exportedVideoURL: URL?
    @Published var videoExportSaving = false
    private var videoExportTask: Task<Void, Never>?
    private var cancelledVideoExportIDs = Set<String>()
    var videoExportBusy: Bool { videoExport?.busy == true || videoExportSaving }
    @Published var editorProjectID: String?
    private var presentedPreviews: [String: String] = [:]
    func expandCompletedEditor() {
        guard page == .project, let projectID = selectedProjectID,
              let run = latestRun(for: projectID), run.status == "completed", !run.timeline.isEmpty,
              let preview = run.preview else { return }
        let key = "\(run.id):\(run.version):\(preview.id)"
        guard presentedPreviews[projectID] != key else { return }
        presentedPreviews[projectID] = key
        editorProjectID = projectID; editorSelection = nil
    }
    @Published var editorSelection: EditorSelection?
    @Published var editorRequestedShotID: String?
    @Published var editorReviewShotID: String?
    @Published var editorComposerFocus = 0
    @Published var editorPauseRequest = 0
    @Published var editorAcceptedDraftRevision = 0
    // Empty shotIds explicitly means the whole film; nil means not frozen yet.
    @Published var composerEditTargets: [String: EditorSelection] = [:]
    var composerTimelineRun: AgentRun? {
        agentRuns.filter { $0.projectId == composerProjectID && !$0.timeline.isEmpty }.max { $0.updatedAt < $1.updatedAt }
    }
    var composerEditTarget: EditorSelection? {
        guard let id = composerProjectID, let run = composerTimelineRun else { return nil }
        if let fixed = composerEditTargets[id] { return fixed }
        if editorProjectID == id, let selected = editorSelection, selected.runId == run.id { return selected }
        return EditorSelection(runId: run.id, version: run.version, shotIds: [])
    }
    func freezeComposerTarget() {
        guard let id = composerProjectID, composerEditTargets[id] == nil, let target = composerEditTarget else { return }
        composerEditTargets[id] = target; editorPauseRequest += 1
    }
    func chooseComposerTarget(wholeFilm: Bool) {
        guard let id = composerProjectID, let run = composerTimelineRun else { return }
        composerEditTargets[id] = wholeFilm ? EditorSelection(runId: run.id, version: run.version, shotIds: []) : editorSelection
        freezeComposerTarget(); editorPauseRequest += 1
    }
    // Presentation state belongs to the conversation, not its wide/compact view.
    @Published var expandedConversationSections = Set<String>()
    var conversationBookmarks: [String: (following: Bool, messageID: String?)] = [:]
    @Published var materialSectionOverrides: [String: Bool] = [:]
    func materialSection(_ run: AgentRun) -> Binding<Bool> {
        Binding(get: { self.materialSectionOverrides[run.id] ?? (run.analyzingMaterials || ["failed", "interrupted", "cancelled"].contains(run.status) || run.intent == "analyze") },
                set: { self.materialSectionOverrides[run.id] = $0 })
    }
    func conversationSection(_ key: String) -> Binding<Bool> {
        Binding(get: { self.expandedConversationSections.contains(key) }, set: { expanded in
            if expanded { self.expandedConversationSections.insert(key) }
            else { self.expandedConversationSections.remove(key) }
        })
    }
    var composerVisibleIssue: String? {
        return composerIssue
    }
    func usedShots(_ mediaID: String) -> (run: AgentRun, shots: [AgentShot], draft: Bool)? {
        guard let projectID = selectedProjectID,
              let run = agentRuns.filter({ $0.projectId == projectID && !$0.timeline.isEmpty }).max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
        let draft = editorDrafts[run.id]
        let source = draft?.shots ?? run.timeline
        guard source.contains(where: { $0.mediaId == mediaID }) else { return nil }
        return (run, source, draft?.dirty == true || run.preview == nil)
    }
    func openUsedShot(_ shotID: String, projectID: String) {
        openEditor(projectID); editorRequestedShotID = shotID
    }
    var editorSelectionLabel: String {
        guard let scope = composerEditTarget, let run = composerTimelineRun, !scope.shotIds.isEmpty else { return language.text("Whole film") }
        let shots = editorDrafts[run.id]?.shots ?? run.timeline
        if scope.shotIds.count == 1, let index = shots.firstIndex(where: { scope.shotIds.contains($0.id) }) {
            return String(format: language.text("Clip %lld · %@"), index + 1, shots[index].label)
        }
        return String(format: language.text("%lld clips selected"), scope.shotIds.count)
    }
    @Published var editorDrafts: [String: EditorDraft] = [:] { didSet {
        guard restoredDraft else { return }
        do { try JSONEncoder().encode(editorDrafts).write(to: editorDraftsURL, options: .atomic) }
        catch { self.error = "Could not save the editor draft: \(error.localizedDescription)" }
    } }
    private var editorDraftsURL: URL { service.dataDirectory.appendingPathComponent("native-editor-drafts.json") }
    var editorTimelineRun: AgentRun? { agentRuns.filter { $0.projectId == editorProjectID && !$0.timeline.isEmpty }.max { $0.updatedAt < $1.updatedAt } }
    var editorHasPendingChanges: Bool {
        guard let run = editorTimelineRun, let draft = editorDrafts[run.id] else { return false }
        return draft.dirty || draft.version != run.version
    }
    func openEditor(_ projectID: String) { selectedProjectID = projectID; page = .project; editorProjectID = projectID; editorSelection = nil }
    func closeEditor() { editorProjectID = nil; editorSelection = nil }
    var activeAgentRun: AgentRun? { latestRun(for: selectedProjectID) }
    func latestRun(for id: String?) -> AgentRun? {
        guard let id else { return nil }
        return agentRuns.filter { $0.projectId == id }.max { $0.updatedAt < $1.updatedAt }
    }
    @Published var removed: MediaItem?
    @Published var mediaRemovalRequest: [MediaItem] = []
    @Published private(set) var removingMedia = false
    @Published private(set) var removedItems: [MediaItem] = []
    private var restoredDraft = false
    private var poller: Task<Void, Never>?
    private var draftURL: URL { service.dataDirectory.appendingPathComponent("native-draft.json") }
    private var projectDraftsURL: URL { service.dataDirectory.appendingPathComponent("native-project-drafts.json") }
    var currentProject: Project? { projects.first { $0.id == selectedProjectID } }
    var composerProjectID: String? { page == .project ? selectedProjectID : nil }
    var blockingAgentRun: AgentRun? { agentRuns.first { $0.busy && $0.projectId != composerProjectID } }
    var canResumeWithMaterials: Bool {
        guard composerProjectID != nil, let run = activeAgentRun else { return false }
        return run.status == "clarify" && run.clarificationKind == "materials" && !composerDraft.attachments.isEmpty
    }
    var composerIssue: String? {
        if let run = composerTimelineRun {
            if let target = composerEditTarget,
               target.runId != run.id || target.version != run.version {
                return "The edit changed. Choose the request scope again."
            }
            if let edit = editorDrafts[run.id], edit.version != run.version {
                return "Reload the updated timeline before sending."
            }
            let shots = editorDrafts[run.id]?.shots ?? run.timeline
            if let target = composerEditTarget, !Set(target.shotIds).isSubset(of: Set(shots.map(\.id))) {
                return "A referenced clip was removed. Choose the request scope again."
            }
        }
        if composerDraft.prompt.unicodeScalars.count > 5000 { return "Keep your request within 5,000 characters." }
        if blockingAgentRun != nil { return "Another project is running. You can keep writing here." }
        if let caps = agentCapabilities {
            if agentMode == "local" && !caps.localText { return "Local model unavailable. Open Models to check the runtime." }
            if agentMode != "local" && !caps.cloudText { return "Configure a cloud text model and API key in Models first." }
            if agentMode == "cloud" && !caps.cloudVision { return "Configure a cloud vision model in Models first." }
        }
        return nil
    }
    var needsComposerMaterials: Bool {
        composerDraft.attachments.isEmpty &&
            (!composerDraft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
             (composerProjectID != nil && activeAgentRun?.clarificationKind == "materials"))
    }
    var canSubmitAgent: Bool {
        !composerDraft.attachments.isEmpty && !saving && !importing && !agentActionPending && composerIssue == nil &&
            (!composerDraft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || canResumeWithMaterials)
    }
    var composerDraft: Draft {
        get { draft(for: composerProjectID) }
        set {
            if !newValue.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { freezeComposerTarget() }
            else if let id = composerProjectID { composerEditTargets[id] = nil }
            setDraft(newValue, for: composerProjectID)
        }
    }
    // The project keeps its source context; the composer shows only unsent additions.
    var composerPendingAttachments: [Attachment] {
        guard let projectID = composerProjectID else { return composerDraft.attachments }
        let sent = Set(agentRuns.filter { $0.projectId == projectID }.flatMap {
            ($0.attachments?.map(\.id)) ?? $0.originalMediaIds ?? $0.mediaIds ?? []
        })
        return composerDraft.attachments.filter { !sent.contains($0.id) }
    }
    func draft(for id: String?) -> Draft {
        guard let id else { return draft }
        if let saved = projectDrafts[id] { return saved }
        let project = projects.first { $0.id == id }
        return Draft(attachments: project?.attachments ?? [], projectId: id)
    }
    func setDraft(_ value: Draft, for id: String?) {
        if let id { var value = value; value.projectId = id; projectDrafts[id] = value }
        else { var value = value; value.projectId = nil; draft = value }
    }
    func migrateLegacyDraft() {
        if let id = draft.projectId {
            if projectDrafts[id] == nil { projectDrafts[id] = draft }
            draft = Draft()
        }
    }
    func navigate(_ destination: WorkspacePage) {
        guard destination != .mediaMap || hasMediaMap else { return }
        detail = nil
        mediaReturnProjectID = nil
        closeEditor()
        if destination == .project { selectedProjectID = nil }
        selecting = false; selection.removeAll(); selectionProjectID = nil
        page = destination
    }
    func projectEditedAt(_ project: Project) -> Double {
        max(project.updatedAt, agentRuns.filter { $0.projectId == project.id }.compactMap(\.editedAt).max() ?? 0)
    }
    var sortedProjects: [Project] { projects.sorted { projectEditedAt($0) > projectEditedAt($1) } }
    func projectCover(_ project: Project) -> String? {
        let ordered = (latestRun(for: project.id)?.timeline.map(\.mediaId) ?? []) + project.attachments.filter { $0.kind == "video" }.map(\.id)
        return ordered.compactMap { id in items.first { $0.id == id && $0.kind == "video" }?.cover }.first
    }
    var visibleItems: [MediaItem] {
        mediaSearchResults.map(\.item)
    }
    var libraryItems: [MediaItem] { items.filter { $0.kind != "audio" && $0.isExample != true } }
    // Independent map scope: never inherit hidden Library search/facet constraints.
    var mediaMapItems: [MediaItem] { items.filter { $0.isExample != true && ["video", "image"].contains($0.kind) } }
    var hasMediaMap: Bool { !mediaMapItems.isEmpty }
    var sidebarMediaPages: [WorkspacePage] { WorkspacePage.mediaPages.filter { $0 != .mediaMap || hasMediaMap } }
    func mediaSource(_ item: MediaItem) -> MediaSourceIdentity {
        let device = syncSnapshot?.devices.first { $0.id == item.syncSourceId }
        return MediaSourceIdentity(item: item, sourceName: device?.name, sourceKind: device?.kind)
    }
    private func refreshMediaSearch() {
        let eligible = libraryItems.filter { mediaAddedRange.includes($0) && mediaWorkFilter.includes($0) }
        var candidates = MediaFilter(category: category, query: query, scope: searchScope, folder: folder, sort: sort, syncSourceID: syncSourceID)
            .results(eligible, locations: locations, documents: searchDocuments)
        if [.all, .content].contains(searchScope) && isSearchingMedia && visualQuery == query {
            let allowed = MediaFilter(category: category, query: "", scope: searchScope, folder: folder, sort: sort, syncSourceID: syncSourceID)
                .results(eligible, locations: locations, documents: searchDocuments)
            candidates = MediaSearchMerge.combine(text: candidates, visual: visualHits, allowed: allowed)
        }
        let documents = candidates.compactMap { searchDocuments[$0.id] }
        mediaFacetOptions = Dictionary(uniqueKeysWithValues: MediaFacet.allCases.map {
            ($0, mediaFacets.options(for: $0, documents: documents))
        })
        mediaSearchResults = candidates.filter { mediaFacets.matches(searchDocuments[$0.id]?.quickTags ?? []) }
        if sort == .beauty {
            mediaSearchResults = mediaSearchResults.enumerated().sorted { a,b in
                let left = beautyScores[a.element.id] ?? -.infinity, right = beautyScores[b.element.id] ?? -.infinity
                return left == right ? a.offset < b.offset : left > right
            }.map(\.element)
        }
    }
    func mediaTags(for item: MediaItem) -> [MediaFacetTag] {
        searchDocuments[item.id]?.quickTags ?? MediaQuickTags.tags(item)
    }
    func coreMediaTags(for item: MediaItem) -> [MediaFacetTag] {
        MediaTagPresentation.core(item, frequencies: mediaTagFrequencies)
    }
    func filterMediaTag(_ tag: MediaFacetTag) {
        navigate(.media)
        detail = nil
        resetMediaFilters()
        mediaFacets.values[tag.facet] = tag
    }
    func searchMediaTag(_ tag: MediaSearchTag) {
        navigate(.media)
        detail = nil
        resetMediaFilters()
        searchScope = tag.scope
        query = tag.text
    }
    func toggleMediaTag(_ tag: MediaFacetTag) {
        mediaFacets.values[tag.facet] = mediaFacets.values[tag.facet]?.id == tag.id ? nil : tag
    }
    var isSearchingMedia: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var mediaResultSummary: String {
        let count = visibleItems.count
        if language == .chinese {
            if syncSourceID != nil { return "\(count) 个素材 · \(syncSourceName ?? "导入设备")" }
            return hasMediaFilters ? "找到 \(count) 个素材 · 共 \(libraryItems.count) 个" : "\(count) 个本地素材"
        }
        if syncSourceID != nil { return "\(count) \(count == 1 ? "file" : "files") · \(syncSourceName ?? "Imported device")" }
        return hasMediaFilters ? "\(count) \(count == 1 ? "result" : "results") · \(libraryItems.count) local files" : "\(count) local \(count == 1 ? "file" : "files")"
    }
    var folders: [MediaFolder] {
        let paths = libraryItems.filter { $0.syncSourceId == nil }.compactMap { locations[$0.id]?.folder }
        return Dictionary(grouping: paths, by: { $0 }).map { MediaFolder(path: $0.key, count: $0.value.count) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
    var importedSources: [(id: String, name: String, symbol: String)] {
        let grouped = Dictionary(grouping: libraryItems.filter { $0.syncSourceId != nil }, by: { $0.syncSourceId! })
        return grouped.map { let source = mediaSource($0.value[0]); return (id: $0.key, name: source.name, symbol: source.symbol) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var hasMediaFilters: Bool { mediaAddedRange != .all || mediaWorkFilter != .all || syncSourceID != nil || isSearchingMedia || !folder.isEmpty || category != .all || searchScope != .all || !mediaFacets.isEmpty }
    func resetMediaFilters() { query = ""; folder = ""; category = .all; searchScope = .all; mediaFacets = .init(); syncSourceID = nil; syncSourceName = nil; mediaAddedRange = .all; mediaWorkFilter = .all }
    func openSyncedMedia(_ id: String, name: String) {
        navigate(.media); detail = nil; resetMediaFilters(); sort = .original
        syncSourceName = name; syncSourceID = id
        perform { try await self.refresh() }
    }
    func openMedia(_ item: MediaItem, at seconds: Double = 0) {
        mediaReturnProjectID = page == .project ? selectedProjectID : nil
        mediaSeekTime = max(0, seconds); lastOpenedMediaID = item.id; detail = item
        if page != .mediaMap { page = .media }
    }
    func backToMedia() {
        let project = mediaReturnProjectID
        detail = nil; mediaReturnProjectID = nil
        if let project { selectedProjectID = project; page = .project }
        else if page != .mediaMap { page = .media }
    }
    func start() async {
        guard !ready else { return }
        startupError = nil
        do {
            try await service.start()
            try await saveLanguage(language)
            if let config = CloudSettings.read(), !config.model.isEmpty {
                struct Configured: Decodable { var ok: Bool }
                let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
                do { let _: Configured = try await service.post("/api/desktop/agent/configure", value, native: true) }
                catch { self.error = "Cloud configuration could not be restored. Local processing is still available." }
            }
            try await refresh()
            if let data = try? Data(contentsOf: editorDraftsURL) {
                editorDrafts = try JSONDecoder().decode([String: EditorDraft].self, from: data)
            }
            if let data = try? Data(contentsOf: projectDraftsURL) {
                do { projectDrafts = try JSONDecoder().decode([String: Draft].self, from: data) }
                catch { throw ServiceError(message: "Project drafts could not be read. The saved file was left unchanged.") }
            }
            if let data = try? Data(contentsOf: draftURL) {
                do { draft = try JSONDecoder().decode(Draft.self, from: data) }
                catch { throw ServiceError(message: "Your saved draft could not be read. It was left unchanged at \(draftURL.path).") }
            } else {
                struct Settings: Decodable { var settings: [String: String] }
                let settings: Settings = try await service.get("/api/desktop/settings")
                if let raw = settings.settings["projectDraft"], let data = raw.data(using: .utf8) {
                    draft = (try? JSONDecoder().decode(Draft.self, from: data)) ?? Draft()
                }
            }
            if let url = Bundle.main.url(forResource: "skills", withExtension: "json") {
                skills = try JSONDecoder().decode([CreatorSkill].self, from: Data(contentsOf: url))
            }
            migrateLegacyDraft()
            restoredDraft = true; ready = true
            // Save migrated project drafts before replacing the legacy Home draft.
            if persistProjectDrafts() { persistDraft() }
            poller = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled, let self else { return }
                    do { try await self.refresh() }
                    catch { self.error = "Lost connection to the local engine. Your files and saved projects are safe. Restart Pixfun to reconnect."; return }
                }
            }
        } catch { service.stop(); startupError = error.localizedDescription }
    }
    func stop() { poller?.cancel(); placeNames.cancel(); placeWriteTask?.cancel(); service.stop() }
    func refresh() async throws {
        struct Library: Decodable { var items: [MediaItem] }
        struct Projects: Decodable { var projects: [Project] }
        struct Locations: Decodable { var items: [MediaLocation] }
        let library: Library = try await service.get("/api/desktop/library")
        let history: Projects = try await service.get("/api/desktop/projects")
        let paths: Locations = try await service.get("/api/desktop/locations", native: true)
        locations = Dictionary(uniqueKeysWithValues: paths.items.map { ($0.id, $0) })
        savedPlaces = Dictionary(uniqueKeysWithValues: library.items.compactMap { item in item.validResolvedPlace.map { (item.id, $0) } })
        items = placeNames.applyingCache(to: library.items, language: language.rawValue); projects = history.projects
        persistPlaceNames()
        placeNames.schedule(items.compactMap { $0.placeQuery(language: language.rawValue) },
                            enabled: onlinePlaceNames, foreground: NSApp?.isActive == true)
        do { syncSnapshot = try await service.get("/api/desktop/sync", native: true); syncStatusUnavailable = false }
        catch { syncSnapshot = nil; syncStatusUnavailable = true }
        struct Runs: Decodable { var runs: [AgentRun] }
        let runs: Runs = try await service.get("/api/desktop/agent/runs", native: true)
        agentRuns = runs.runs
        agentCapabilities = try await service.get("/api/desktop/agent/capabilities", native: true)
        selection.formIntersection(Set(items.map(\.id)))
    }
    func perform(_ operation: @escaping () async throws -> Void) {
        Task { do { try await operation() } catch { self.error = error.localizedDescription } }
    }
    private func persistDraft() {
        do { try JSONEncoder().encode(draft).write(to: draftURL, options: .atomic) }
        catch { self.error = "Could not save your draft: \(error.localizedDescription)" }
    }
    @discardableResult private func persistProjectDrafts() -> Bool {
        do { try JSONEncoder().encode(projectDrafts).write(to: projectDraftsURL, options: .atomic); return true }
        catch { self.error = "Could not save project drafts: \(error.localizedDescription)"; return false }
    }
    func attach(_ ids: Set<String>) { draft.attach(items.filter { ids.contains($0.id) }); page = .home }
    /// Map handoff is draft preparation only. Reuse the normal Agent submission and editor.
    @discardableResult func prepareMapCreation(_ ids: [String], replaceDraft: Bool = false) -> Bool {
        guard !saving, !importing, !ids.isEmpty else { return false }
        let records = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let chosen = ids.filter { seen.insert($0).inserted }.compactMap { records[$0] }
        guard chosen.count == seen.count, chosen.allSatisfy(MediaMapCreation.eligible) else { return false }
        var value = replaceDraft ? Draft() : draft
        value.attach(chosen)
        if value.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value.prompt = MediaMapCreation.prompt(chinese: language == .chinese)
        }
        setDraft(value, for: nil)
        detail = nil; selecting = false; selection = []; selectionProjectID = nil
        navigate(.home)
        return true
    }
    func beginSelection() {
        selectionReturnPage = page ?? .media; selectionProjectID = composerProjectID; detail = nil
        selection = selectionReturnPage == .media ? [] : Set(composerDraft.attachments.map(\.id))
        selecting = true; page = .media
    }
    func finishSelection() {
        let destination = selectionProjectID
        var value = draft(for: selectionProjectID); value.attach(items.filter { selection.contains($0.id) })
        setDraft(value, for: selectionProjectID)
        cancelSelection()
        if let destination { selectedProjectID = destination; page = .project } else { page = .home }
    }
    func cancelSelection() {
        let destination = selectionProjectID
        selecting = false; selection.removeAll(); selectionProjectID = nil
        if let destination { selectedProjectID = destination; page = .project } else { page = selectionReturnPage }
    }
    func toggleSelection(_ id: String) { if selection.contains(id) { selection.remove(id) } else { selection.insert(id) } }
    func use(_ skill: CreatorSkill) { draft.skill = skill.chosen; page = .home }
    func confirmDiscard() -> Bool {
        guard draft.hasContent else { return true }
        let alert = NSAlert()
        alert.messageText = "Replace the current draft?"
        alert.informativeText = "Your saved projects and original files will not be removed."
        alert.addButton(withTitle: "Replace draft"); alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    func newProject() { guard confirmDiscard() else { return }; draft = Draft(); page = .home }
    func open(_ project: Project) {
        selectedProjectID = project.id
        agentMode = activeAgentRun?.mode ?? "local"
        page = .project
    }
    var canApplyAgentOption: Bool {
        !composerDraft.attachments.isEmpty && !saving && !importing && !agentActionPending &&
        composerIssue == nil && activeAgentRun?.busy != true
    }
    func submitAgent() { submitAgent(prompt: nil) }
    func submitAgent(prompt optionPrompt: String?) {
        guard optionPrompt == nil ? canSubmitAgent : canApplyAgentOption else { return }
        saving = true
        let sourceID = composerProjectID
        let sourcePage = page
        // Treat clips added in the editor as request attachments before taking the
        // input snapshot, so the automatic save does not look like new user typing.
        if let run = composerTimelineRun, let edit = editorDrafts[run.id], edit.dirty {
            var value = composerDraft
            let ids = Set(edit.shots.map(\.mediaId))
            value.attach(items.filter { ids.contains($0.id) })
            setDraft(value, for: sourceID)
        }
        let submitted = composerDraft
        let effectivePrompt = optionPrompt ?? (submitted.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (activeAgentRun?.prompt ?? "") : submitted.prompt)
        let messageMediaIDs = composerPendingAttachments.map(\.id)
        let mode = agentMode
        let target = composerEditTarget
        let baseRun = composerTimelineRun
        let localEdit = baseRun.flatMap { editorDrafts[$0.id] }
        editorPauseRequest += 1
        perform {
            defer { self.saving = false }
            struct Response: Decodable { var run: AgentRun }
            if let current = self.latestRun(for: sourceID), current.busy {
                let _: Response = try await self.service.post("/api/desktop/agent/action", ["id": current.id, "action": "stop"], native: true)
            }
            var acceptedRun = baseRun
            if let baseRun, let localEdit, localEdit.dirty {
                let photos = Set(self.items.filter { $0.kind == "image" }.map(\.id))
                let durations = Dictionary(uniqueKeysWithValues: self.items.compactMap { item in
                    item.kind == "image" ? (item.id, 60.0) : item.metadata?.duration.map { (item.id, $0) }
                })
                if let issue = localEdit.validation(durations: durations, photoIDs: photos) { throw ServiceError(message: issue) }
                acceptedRun = try await self.saveAgentTimeline(baseRun, shots: localEdit.shots, version: localEdit.version, finishing: localEdit.finishing)
            }
            if mode != "local", let config = CloudSettings.read() {
                struct OK: Decodable { var ok: Bool }
                let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
                let _: OK = try await self.service.post("/api/desktop/agent/configure", object, native: true)
            }
            var payload: [String: Any] = ["prompt": effectivePrompt, "mediaIds": submitted.attachments.map(\.id), "mode": mode, "requestId": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), "skill": NSNull()]
            payload["messageMediaIds"] = messageMediaIDs
            if let id = submitted.projectId { payload["id"] = id }
            if let acceptedRun {
                payload["editBase"] = ["runId": acceptedRun.id, "version": acceptedRun.version]
                if var scope = target, !scope.shotIds.isEmpty {
                    scope.version = acceptedRun.version
                    payload["editScope"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(scope))
                }
                // Added timeline sources are part of the saved draft, even if they were not in the original composer snapshot.
                payload["mediaIds"] = Array(Set(submitted.attachments.map(\.id) + (acceptedRun.mediaIds ?? []))).sorted()
            }
            if let skill = submitted.skill { payload["skill"] = ["id": skill.id, "title": skill.title, "strategy": skill.strategy] }
            let response: Response = try await self.service.post("/api/desktop/agent/start", payload, native: true)
            self.agentRuns.removeAll { $0.id == response.run.id }
            self.agentRuns.insert(response.run, at: 0)
            self.completeSubmission(submitted, sourceID: sourceID, sourcePage: sourcePage, projectID: response.run.projectId, preservePrompt: optionPrompt != nil)
            try await self.refresh()
        }
    }
    func completeSubmission(_ submitted: Draft, sourceID: String?, sourcePage: WorkspacePage?, projectID: String, preservePrompt: Bool = false) {
        let unchanged = draft(for: sourceID) == submitted
        if unchanged {
            if let sourceID { composerEditTargets[sourceID] = nil }
            var next = submitted; next.prompt = preservePrompt ? submitted.prompt : ""; next.projectId = projectID
            next.skill = nil
            projectDrafts[projectID] = next
            if sourceID == nil { draft = Draft() }
        }
        // A response must not steal navigation or erase input typed during the request.
        if unchanged && page == sourcePage && composerProjectID == sourceID {
            selectedProjectID = projectID; page = .project
        }
    }
    func agentAction(_ action: String, run: AgentRun) {
        guard !agentActionPending, !saving else { return }
        saving = true
        let pendingEdit = editorDrafts[run.id]
        perform {
            defer { self.agentActionPending = false; self.saving = false }
            struct Response: Decodable { var run: AgentRun }
            var accepted = run
            if action == "approve", let edit = pendingEdit, edit.dirty {
                guard edit.version == run.version else { throw ServiceError(message: "Reload the updated timeline before generating. Your draft is kept.") }
                accepted = try await self.saveAgentTimeline(run, shots: edit.shots, version: edit.version, finishing: edit.finishing)
                guard self.editorDrafts[run.id]?.dirty != true else {
                    throw ServiceError(message: "The draft changed while saving. Your latest edits are kept; try again.")
                }
            }
            self.agentActionPending = true
            let response: Response = try await self.service.post("/api/desktop/agent/action", ["id": accepted.id, "action": action], native: true)
            if ["use_videos", "use_visuals"].contains(action), let ids = response.run.mediaIds {
                var next = self.draft(for: run.projectId)
                // Keep attachments added while the action was in flight; only remove excluded sources.
                let original = Set(run.mediaIds ?? next.attachments.map(\.id))
                next.attachments.removeAll { original.contains($0.id) && !ids.contains($0.id) }
                self.setDraft(next, for: run.projectId)
            }
            self.agentRuns.removeAll { $0.id == response.run.id }; self.agentRuns.insert(response.run, at: 0)
            try await self.refresh()
        }
    }
    func agentTripCorrection(_ run: AgentRun, numbers: [Int], anchorNumber: Int, onSuccess: @escaping () -> Void = {}) {
        guard !agentActionPending, !saving else { return }
        agentActionPending = true
        perform {
            defer { self.agentActionPending = false }
            struct Response: Decodable { var run: AgentRun }
            let payload: [String: Any] = ["id": run.id, "action": "trip_correction",
                                          "numbers": numbers, "anchorNumber": anchorNumber]
            let response: Response = try await self.service.post("/api/desktop/agent/action", payload, native: true)
            self.agentRuns.removeAll { $0.id == response.run.id }
            self.agentRuns.insert(response.run, at: 0)
            onSuccess()
            try await self.refresh()
        }
    }
    @discardableResult
    func saveAgentTimeline(_ run: AgentRun, shots: [AgentShot], version: Int, finishing: AgentFinishing? = nil) async throws -> AgentRun {
            guard !agentActionPending else { throw ServiceError(message: "Wait for the current action to finish.") }
            agentActionPending = true
            defer { agentActionPending = false }
            struct Response: Decodable { var run: AgentRun }
            let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(shots))
            var payload: [String: Any] = ["id": run.id, "action": "timeline", "timeline": value, "version": version]
            let known = Set(run.mediaIds ?? [])
            let added = Set(shots.map(\.mediaId)).subtracting(known)
            if !added.isEmpty { payload["additionalMediaIds"] = added.sorted() }
            if let finishing { payload["finishing"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(finishing)) }
            let response: Response = try await self.service.post("/api/desktop/agent/action", payload, native: true)
            agentRuns.removeAll { $0.id == response.run.id }; agentRuns.insert(response.run, at: 0)
            if !added.isEmpty {
                var value = draft(for: run.projectId); value.attach(items.filter { added.contains($0.id) }); setDraft(value, for: run.projectId)
            }
            // A successful save is authoritative even if a subsequent list refresh fails.
            if let cached = editorDrafts[run.id], cached.shots == shots, cached.finishing == finishing {
                var accepted = cached
                accepted.base = response.run.timeline; accepted.shots = response.run.timeline; accepted.version = response.run.version
                accepted.finishing = response.run.finishing ?? .empty; accepted.baseFinishing = accepted.finishing
                editorDrafts[run.id] = accepted; editorAcceptedDraftRevision += 1
            }
            if var target = composerEditTargets[run.projectId], target.runId == run.id, target.version == version {
                target.version = response.run.version; composerEditTargets[run.projectId] = target
            }
            return response.run
    }
    func canUndoAgentEdit(_ run: AgentRun) -> Bool {
        guard let receipt = run.editReceipt, receipt.hasChanges, !receipt.undone, receipt.version == run.version,
              ["completed", "review", "failed"].contains(run.status), latestRun(for: run.projectId)?.id == run.id,
              !agentActionPending, !saving, !agentRuns.contains(where: \.busy) else { return false }
        return editorDrafts[run.id]?.dirty != true
    }
    func undoAgentEdit(_ run: AgentRun) {
        guard canUndoAgentEdit(run) else { return }
        agentActionPending = true; editorPauseRequest += 1
        perform {
            defer { self.agentActionPending = false }
            struct Response: Decodable { var run: AgentRun }
            let response: Response = try await self.service.post("/api/desktop/agent/action",
                ["id": run.id, "action": "undo_edit", "version": run.version], native: true)
            self.editorDrafts[run.id] = EditorDraft(run: response.run)
            self.agentRuns.removeAll { $0.id == run.id }; self.agentRuns.insert(response.run, at: 0)
            self.editorAcceptedDraftRevision += 1
        }
    }
    func viewAgentEdit(_ run: AgentRun) {
        guard latestRun(for: run.projectId)?.id == run.id else { return }
        openEditor(run.projectId)
        editorRequestedShotID = run.editReceipt?.changedShotIds.first ?? run.timeline.first?.id
        editorReviewShotID = editorRequestedShotID
    }
    func saveCloudSettings(_ config: CloudSettings, mode: String) async throws {
        if config.model.isEmpty && mode == "local" { agentMode = mode; return }
        guard !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ServiceError(message: "Enter a text model ID.") }
        if mode != "local" && config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw ServiceError(message: "Enter an API key.") }
        if mode == "cloud" && config.visionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw ServiceError(message: "Enter a vision model ID.") }
            struct Response: Decodable { var ok: Bool }
            let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
            let _: Response = try await self.service.post("/api/desktop/agent/configure", value, native: true)
            try config.save()
            self.agentCapabilities = try await self.service.get("/api/desktop/agent/capabilities", native: true)
            agentMode = mode
    }
    func exportArtifact(_ artifact: AgentArtifact, resolution: String = "1080p") {
        if ["preview", "previous_preview"].contains(artifact.type) {
            guard let run = agentRuns.first(where: { $0.artifacts.contains(where: { $0.id == artifact.id }) }),
                  artifact.type == "preview", artifact.timelineVersion == nil || artifact.timelineVersion == run.version else {
                error = language == .chinese ? "请打开当前时间线导出，旧预览不会被放大成高清文件。" : "Open the current timeline to export. Historical previews are not upscaled."
                return
            }
            exportVideo(run, resolution: resolution)
            return
        }
        guard let path = artifact.path, FileManager.default.fileExists(atPath: path) else { error = "Artifact is missing. Rebuild the preview."; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = URL(fileURLWithPath: path).lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let resolved = destination.resolvingSymlinksInPath().standardizedFileURL.path
        guard !locations.values.contains(where: { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().standardizedFileURL.path == resolved }) else {
            error = "Choose a different destination. Original media cannot be overwritten."; return
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                // NSSavePanel obtains overwrite confirmation; use atomic replacement.
                let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
                try data.write(to: destination, options: .atomic)
            } else { try FileManager.default.copyItem(atPath: path, toPath: destination.path) }
        } catch { self.error = error.localizedDescription }
    }
    func exportVideo(_ run: AgentRun, resolution: String = "1080p") {
        guard ["1080p", "4k"].contains(resolution) else { return }
        guard !videoExportBusy, !run.busy, !run.timeline.isEmpty else { return }
        guard editorDrafts[run.id]?.dirty != true else {
            error = language == .chinese ? "请先保存时间线修改，再导出。" : "Save timeline changes before exporting."
            return
        }
        let chinese = language == .chinese
        let panel = NSSavePanel()
        panel.title = chinese ? "导出视频" : "Export video"
        panel.nameFieldStringValue = "Pixfun-v\(run.version).mp4"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let expected: VideoExportFiles.Identity?
        let protectedOriginals = locations.values.map { URL(fileURLWithPath: $0.path) }
        do {
            try VideoExportFiles.protect(destination, originals: protectedOriginals)
            expected = try VideoExportFiles.identity(destination)
        } catch { self.error = error.localizedDescription; return }
        videoExportSaving = true; exportedVideoURL = nil
        videoExportTask = Task {
            defer { videoExportSaving = false; videoExportTask = nil }
            do {
                struct Response: Decodable { var export: VideoExportJob }
                let started: Response = try await service.post("/api/desktop/agent/export",
                    ["id":run.id, "version":run.version, "resolution":resolution], native:true)
                videoExport = started.export
                while videoExport?.busy == true {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    let update: Response = try await service.post("/api/desktop/agent/export",
                        ["action":"status", "exportId":started.export.id], native:true)
                    videoExport = update.export
                }
                guard let job = videoExport else { return }
                if job.status == "cancelled" || cancelledVideoExportIDs.contains(job.id) { return }
                guard job.status == "completed", let path = job.path else { throw ServiceError(message:job.message) }
                let originals = protectedOriginals + locations.values.map { URL(fileURLWithPath: $0.path) }
                try await Task.detached(priority: .utility) {
                    try VideoExportFiles.install(source:URL(fileURLWithPath:path), destination:destination, expected:expected, originals:originals)
                }.value
                exportedVideoURL = destination
            } catch {
                videoExport?.status = "failed"
                self.error = error.localizedDescription
            }
        }
    }
    func cancelVideoExport() {
        guard let job = videoExport, job.busy else { return }
        cancelledVideoExportIDs.insert(job.id)
        perform {
            struct Response: Decodable { var export: VideoExportJob }
            let response: Response = try await self.service.post("/api/desktop/agent/export",
                ["action":"cancel", "exportId":job.id], native:true)
            self.videoExport = response.export
        }
    }
    func saveProject() {
        guard !saving, !composerDraft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        saving = true
        let sourceID = composerProjectID
        let sourcePage = page
        let submitted = composerDraft
        perform {
            defer { self.saving = false }
            var payload: [String: Any] = ["prompt": submitted.prompt, "mediaIds": submitted.attachments.map(\.id), "skill": NSNull()]
            if let id = submitted.projectId { payload["id"] = id }
            if let skill = submitted.skill { payload["skill"] = ["id": skill.id, "title": skill.title, "strategy": skill.strategy] }
            struct Response: Decodable { var project: Project }
            let response: Response = try await self.service.post("/api/desktop/projects", payload)
            // Do not erase edits made while a save is in flight.
            self.completeSubmission(submitted, sourceID: sourceID, sourcePage: sourcePage, projectID: response.project.id)
            try await self.refresh()
        }
    }
    func pick(folder: Bool = false, attach: Bool = false, locate: String? = nil) {
        guard ready, !importing else { return }
        let destinationID = composerProjectID
        let panel = NSOpenPanel()
        panel.title = locate == nil ? "Add local files — originals stay in place" : "Locate original file"
        panel.canChooseDirectories = folder; panel.canChooseFiles = !folder
        panel.allowsMultipleSelection = locate == nil
        panel.prompt = locate == nil ? "Add files" : "Reconnect"
        if !folder { panel.allowedContentTypes = [.movie, .image, .audio] + [UTType(filenameExtension: "lrf")].compactMap { $0 } }
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        importing = true
        perform {
            defer { self.importing = false }
            let paths = try await Task.detached { try Self.collect(urls) }.value
            guard !paths.isEmpty else { throw ServiceError(message: "No supported media files were found.") }
            struct Response: Decodable { var items: [MediaItem]; var errors: [String] }
            var payload: [String: Any] = ["paths": paths]
            if let locate { payload["id"] = locate }
            let response: Response = try await self.service.post(locate == nil ? "/api/desktop/register" : "/api/desktop/locate", payload, native: true)
            try await self.refresh()
            if attach {
                var value = self.draft(for: destinationID); value.attach(response.items)
                self.setDraft(value, for: destinationID)
            }
            if !response.errors.isEmpty { self.error = response.errors.joined(separator: "\n") }
        }
    }
    nonisolated static func collect(_ urls: [URL]) throws -> [String] {
        let extensions = Set("mp4 mov m4v mkv webm avi mts m2ts ogv lrf jpg jpeg png webp gif avif heic heif bmp tif tiff mp3 wav m4a aac flac ogg aiff aif opus".split(separator: " ").map(String.init))
        var files: [String] = [], seen: Set<String> = []
        func add(_ url: URL) throws {
            let resource = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard resource.isRegularFile == true, resource.isSymbolicLink != true, extensions.contains(url.pathExtension.lowercased()) else { return }
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted { files.append(path) }
            if files.count > 100 { throw ServiceError(message: "Choose up to 100 files per import. Nothing was imported.") }
        }
        for url in urls {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { continue }
            if values.isDirectory == true {
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let file as URL in enumerator { try add(file) }
            } else { try add(url) }
        }
        return files
    }
    func favorite(_ item: MediaItem) {
        perform { try await self.service.update("/api/desktop/update", ["id": item.id, "favorite": item.favorite != true]); try await self.refresh() }
    }
    func remove(_ item: MediaItem) {
        requestMediaRemoval([item])
    }
    func requestMediaRemoval(_ candidates: [MediaItem]) {
        guard !removingMedia else { return }
        let ids = Set(candidates.map(\.id))
        let targets = libraryItems.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }
        guard targets.allSatisfy({ ["ready", "error", "cancelled"].contains($0.status) }) else {
            error = language == .chinese ? "部分素材仍在导入，请等待导入完成后再删除。" : "Some files are still being imported. Wait for import to finish before removing them."
            return
        }
        // Freeze the targets before confirmation; polling/filter changes cannot expand them.
        mediaRemovalRequest = targets
    }
    func removeConfirmedMedia(_ targets: [MediaItem]) {
        guard !removingMedia, !targets.isEmpty else { return }
        mediaRemovalRequest = []
        removingMedia = true
        Task {
            defer { removingMedia = false }
            var completed: [MediaItem] = []
            do {
                for item in targets {
                    try await service.update("/api/desktop/remove", ["id": item.id])
                    completed.append(item)
                }
            } catch { self.error = error.localizedDescription }
            if !completed.isEmpty {
                removedItems = completed
                let ids = Set(completed.map(\.id))
                if let detail, ids.contains(detail.id) { self.detail = nil }
                draft.attachments.removeAll { ids.contains($0.id) }
                selection.subtract(ids)
                if selecting && selection.isEmpty { cancelSelection() }
            }
            // Refresh even after a partial failure; only successful removals are undoable.
            do { try await refresh() } catch { self.error = error.localizedDescription }
        }
    }
    func undoRemove() {
        guard !removingMedia, !removedItems.isEmpty else { return }
        let targets = removedItems
        removingMedia = true
        Task {
            defer { removingMedia = false }
            do {
                for item in targets {
                    try await service.update("/api/desktop/restore", ["id": item.id])
                    removedItems.removeAll { $0.id == item.id }
                }
            } catch { self.error = error.localizedDescription }
            do { try await refresh() } catch { self.error = error.localizedDescription }
        }
    }
    func retry(_ item: MediaItem) {
        perform { try await self.service.update("/api/desktop/retry", ["id": item.id]); try await self.refresh() }
    }
    func retryFailedAnalysis() {
        perform {
            struct Response: Decodable { var ok: Bool; var queued: Int }
            let _: Response = try await self.service.post("/api/desktop/analysis/retry-failed", [:], native: true)
            try await self.refresh()
        }
    }
    func reanalyzeMedia() {
        perform {
            struct Response: Decodable { var ok: Bool; var queued: Int }
            let _: Response = try await self.service.post("/api/desktop/analysis/reanalyze", [:], native: true)
            try await self.refresh()
        }
    }
    func describeVideo(_ item: MediaItem, force: Bool = false) {
        guard item.kind == "video" else { return }
        perform {
            struct Response: Decodable { var description: VideoDescription }
            let _: Response = try await self.service.post("/api/desktop/description/start", ["id": item.id, "force": force], native: true)
            try await self.refresh()
        }
    }
    func stopDescription(_ item: MediaItem) {
        perform {
            struct Response: Decodable { var ok: Bool }
            let _: Response = try await self.service.post("/api/desktop/description/stop", ["id": item.id], native: true)
            try await self.refresh()
        }
    }
    func analyzeShots(_ item: MediaItem, force: Bool = false) {
        guard item.kind == "video" else { return }
        perform {
            struct Response: Decodable { var analysis: ShotAnalysis }
            let _: Response = try await self.service.post("/api/desktop/shots/start", ["id":item.id,"force":force], native:true)
            try await self.refresh()
        }
    }
    func stopShots(_ item: MediaItem) {
        perform {
            struct Response: Decodable { var ok: Bool }
            let _: Response = try await self.service.post("/api/desktop/shots/stop", ["id":item.id], native:true)
            try await self.refresh()
        }
    }
    func reveal(_ item: MediaItem) {
        perform { let url = try await self.service.original(item.id); NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    func openSourceFolder(_ item: MediaItem) {
        guard let location = locations[item.id] else { error = "Original folder is unavailable."; return }
        let folder = URL(fileURLWithPath: location.folder, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            error = "Original folder is unavailable. Reconnect the drive or locate the original file."; return
        }
        if !NSWorkspace.shared.open(folder) { error = "Could not open the original folder in Finder." }
    }
}
