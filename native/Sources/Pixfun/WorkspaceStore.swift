import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class WorkspaceStore: ObservableObject {
    let service = LocalService()
    @Published var page: WorkspacePage? = .home { didSet { if page != .media { detail = nil } } }
    @Published var ready = false
    @Published var startupError: String?
    @Published var error: String?
    @Published var items: [MediaItem] = []
    @Published var projects: [Project] = []
    @Published var skills: [CreatorSkill] = []
    @Published var draft = Draft() { didSet { if restoredDraft { persistDraft() } } }
    @Published var projectDrafts: [String: Draft] = [:] { didSet { if restoredDraft { persistProjectDrafts() } } }
    @Published var selectedProjectID: String?
    private var selectionProjectID: String?
    @Published var query = ""
    @Published var category = MediaCategory.all
    @Published var folder = ""
    @Published var searchScope = MediaSearchScope.name
    @Published var sort = MediaSort.original
    @Published var locations: [String: MediaLocation] = [:]
    var lastOpenedMediaID: String?
    var mediaSeekTime: Double = 0
    @Published var selecting = false
    @Published var selection: Set<String> = []
    @Published var detail: MediaItem?
    @Published var importing = false
    @Published var saving = false
    @Published var agentRuns: [AgentRun] = []
    @Published var agentCapabilities: AgentCapabilities?
    @Published var agentMode = "local"
    @Published var agentActionPending = false
    @Published var editorProjectID: String?
    @Published var editorSelection: EditorSelection?
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
        if editorProjectID == composerProjectID, let run = editorTimelineRun, let edit = editorDrafts[run.id] {
            if edit.dirty { return "Save timeline changes before asking Agent to edit." }
            if edit.version != run.version { return "Reload the updated timeline before sending." }
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
    var canSubmitAgent: Bool {
        !saving && !importing && !agentActionPending && composerIssue == nil &&
            (!composerDraft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || canResumeWithMaterials)
    }
    var composerDraft: Draft {
        get { draft(for: composerProjectID) }
        set { setDraft(newValue, for: composerProjectID) }
    }
    func draft(for id: String?) -> Draft {
        guard let id else { return draft }
        if let saved = projectDrafts[id] { return saved }
        let project = projects.first { $0.id == id }
        return Draft(attachments: project?.attachments ?? [], projectId: id, skill: project?.skill)
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
        MediaFilter(category: category, query: query, scope: searchScope, folder: folder, sort: sort).apply(items, locations: locations)
    }
    var folders: [MediaFolder] {
        let paths = items.filter { $0.kind != "audio" }.compactMap { locations[$0.id]?.folder }
        return Dictionary(grouping: paths, by: { $0 }).map { MediaFolder(path: $0.key, count: $0.value.count) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
    var hasMediaFilters: Bool { !query.isEmpty || !folder.isEmpty || category != .all }
    func resetMediaFilters() { query = ""; folder = ""; category = .all; searchScope = .name }
    func openMedia(_ item: MediaItem, at seconds: Double = 0) { mediaSeekTime = max(0, seconds); lastOpenedMediaID = item.id; detail = item; page = .media }
    func backToMedia() { detail = nil; page = .media }
    func start() async {
        guard !ready else { return }
        startupError = nil
        do {
            try await service.start()
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
    func stop() { poller?.cancel(); service.stop() }
    func refresh() async throws {
        struct Library: Decodable { var items: [MediaItem] }
        struct Projects: Decodable { var projects: [Project] }
        struct Locations: Decodable { var items: [MediaLocation] }
        let library: Library = try await service.get("/api/desktop/library")
        let history: Projects = try await service.get("/api/desktop/projects")
        let paths: Locations = try await service.get("/api/desktop/locations", native: true)
        locations = Dictionary(uniqueKeysWithValues: paths.items.map { ($0.id, $0) })
        items = library.items; projects = history.projects
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
    func beginSelection() { selectionProjectID = composerProjectID; detail = nil; selection = Set(composerDraft.attachments.map(\.id)); selecting = true; page = .media }
    func finishSelection() {
        var value = draft(for: selectionProjectID); value.attach(items.filter { selection.contains($0.id) })
        setDraft(value, for: selectionProjectID)
        cancelSelection()
    }
    func cancelSelection() {
        let destination = selectionProjectID
        selecting = false; selection.removeAll(); selectionProjectID = nil
        if let destination { selectedProjectID = destination; page = .project } else { page = .home }
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
    func submitAgent() {
        guard canSubmitAgent else { return }
        saving = true
        let sourceID = composerProjectID
        let sourcePage = page
        let submitted = composerDraft
        let effectivePrompt = submitted.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (activeAgentRun?.prompt ?? "") : submitted.prompt
        let mode = agentMode
        let editScope = editorProjectID == sourceID ? editorSelection : nil
        perform {
            defer { self.saving = false }
            struct Response: Decodable { var run: AgentRun }
            if let current = self.latestRun(for: sourceID), current.busy {
                let _: Response = try await self.service.post("/api/desktop/agent/action", ["id": current.id, "action": "stop"], native: true)
            }
            if mode != "local", let config = CloudSettings.read() {
                struct OK: Decodable { var ok: Bool }
                let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
                let _: OK = try await self.service.post("/api/desktop/agent/configure", object, native: true)
            }
            var payload: [String: Any] = ["prompt": effectivePrompt, "mediaIds": submitted.attachments.map(\.id), "mode": mode, "requestId": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), "skill": NSNull()]
            if let id = submitted.projectId { payload["id"] = id }
            if let editScope { payload["editScope"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(editScope)) }
            if let skill = submitted.skill { payload["skill"] = ["id": skill.id, "title": skill.title, "strategy": skill.strategy] }
            let response: Response = try await self.service.post("/api/desktop/agent/start", payload, native: true)
            self.agentRuns.removeAll { $0.id == response.run.id }
            self.agentRuns.insert(response.run, at: 0)
            self.completeSubmission(submitted, sourceID: sourceID, sourcePage: sourcePage, projectID: response.run.projectId)
            try await self.refresh()
        }
    }
    func completeSubmission(_ submitted: Draft, sourceID: String?, sourcePage: WorkspacePage?, projectID: String) {
        let unchanged = draft(for: sourceID) == submitted
        if unchanged {
            var next = submitted; next.prompt = ""; next.projectId = projectID
            projectDrafts[projectID] = next
            if sourceID == nil { draft = Draft() }
        }
        // A response must not steal navigation or erase input typed during the request.
        if unchanged && page == sourcePage && composerProjectID == sourceID {
            selectedProjectID = projectID; page = .project
        }
    }
    func agentAction(_ action: String, run: AgentRun) {
        guard !agentActionPending else { return }
        agentActionPending = true
        perform {
            defer { self.agentActionPending = false }
            struct Response: Decodable { var run: AgentRun }
            let response: Response = try await self.service.post("/api/desktop/agent/action", ["id": run.id, "action": action], native: true)
            self.agentRuns.removeAll { $0.id == response.run.id }; self.agentRuns.insert(response.run, at: 0)
            try await self.refresh()
        }
    }
    func saveAgentTimeline(_ run: AgentRun, shots: [AgentShot], version: Int) async throws {
            guard !agentActionPending else { throw ServiceError(message: "Wait for the current action to finish.") }
            agentActionPending = true
            defer { agentActionPending = false }
            struct Response: Decodable { var run: AgentRun }
            let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(shots))
            let response: Response = try await self.service.post("/api/desktop/agent/action", ["id": run.id, "action": "timeline", "timeline": value, "version": version], native: true)
            agentRuns.removeAll { $0.id == response.run.id }; agentRuns.insert(response.run, at: 0)
            try await self.refresh()
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
    func exportArtifact(_ artifact: AgentArtifact) {
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
        if !folder { panel.allowedContentTypes = [.movie, .image, .audio] }
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
        let extensions = Set("mp4 mov m4v mkv webm avi mts m2ts ogv jpg jpeg png webp gif avif heic heif bmp tif tiff mp3 wav m4a aac flac ogg aiff aif opus".split(separator: " ").map(String.init))
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
        perform {
            try await self.service.update("/api/desktop/remove", ["id": item.id])
            self.removed = item; self.detail = nil
            self.draft.attachments.removeAll { $0.id == item.id }
            try await self.refresh()
        }
    }
    func undoRemove() {
        guard let item = removed else { return }
        perform { try await self.service.update("/api/desktop/restore", ["id": item.id]); self.removed = nil; try await self.refresh() }
    }
    func retry(_ item: MediaItem) {
        perform { try await self.service.update("/api/desktop/retry", ["id": item.id]); try await self.refresh() }
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
