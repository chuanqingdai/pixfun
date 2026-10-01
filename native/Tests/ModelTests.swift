import Foundation

@main struct NativeModelTests {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            guard value() else { fatalError("FAIL: \(label)") }; checks += 1
        }
        check(AgentExample.starters.count == 5, "five supported starter workflows")
        check(Set(AgentExample.starters.map(\.id)).count == 5, "starter intent IDs are unique")
        let example = AgentExample.starters[0]
        check(example.applying(to: " \n") == example.prompt, "example fills an empty draft")
        check(example.applying(to: "Keep my instruction").hasPrefix("Keep my instruction\n"), "example never erases existing instructions")
        check(AgentExample.starters.first(where: { $0.id == "create" })!.prompt.contains("original sound"), "rough-cut example stays within renderer capabilities")
        let raw = #"{"id":"a","file":{"name":"trip.mov","size":123},"kind":"video","status":"ready","metadata":{"width":1080,"height":1920,"duration":690,"hasAudio":true},"favorite":true,"context":{"location":"Glacier","device":"iPhone"},"description":"A mountain walk","result":{"analysis":{"segments":[{"id":"seg-1","label":"Chapter 1","start":0,"end":86.25,"boundary":{"type":"time_split"}}],"subtitleCues":[{"start":0.2,"end":3,"text":"Complete spoken sentence"}]}}}"#
        let item = try JSONDecoder().decode(MediaItem.self, from: Data(raw.utf8))
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
        check(described.name == "林间徒步抵达观景点" && described.file.name == "trip.mov", "editorial title never renames source")
        check(described.matches("故事转折") && described.matches("trip.mov"), "search full description and original filename")
        let restoredDescription = try JSONDecoder().decode(MediaItem.self, from: JSONEncoder().encode(described))
        check(restoredDescription.videoDescription?.full_description == described.videoDescription?.full_description, "description survives round trip")
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
        highlight.edit_recommendation.recommended_duration_sec = 0
        check(!highlight.isHighlight, "zero-duration recommendations are not highlighted")
        check(item.segments[0].editorial?.isHighlight != true, "legacy unanalysed segments have no badge")
        check(!item.processing && item.favorite == true, "legacy favorite and status")
        check(item.processingLabel == nil, "ready media has no loading badge")
        var loadingItem = item
        loadingItem.status = "queued"
        check(loadingItem.processingLabel == "Queued", "queued import shows on its cover")
        loadingItem.status = "analyzing"
        check(loadingItem.processingLabel == "Processing", "active import shows on its cover")
        loadingItem.status = "ready"
        loadingItem.shotAnalysis = ShotAnalysis(status: "running")
        check(loadingItem.processingLabel == "Analyzing", "semantic analysis remains visible on covers")
        loadingItem.shotAnalysis = nil
        loadingItem.videoDescription = VideoDescription(status: "running")
        check(loadingItem.processingLabel == "Analyzing", "description analysis is also shown")
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
        var filter = MediaFilter()
        filter.folder = "/Volumes/Travel/Day 1"
        check(filter.apply(fixtures, locations: locations).map(\.id) == ["clip10", "clip2"], "folder includes descendants, not similarly named siblings")
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
        workspace.items = fixtures; workspace.locations = locations
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
        var analysisRun = legacyRun
        analysisRun.intent = "analyze"
        analysisRun.resultText = "Results are linked to original files and sampled time ranges. Visual descriptions are not transcripts."
        analysisRun.artifacts = [
            AgentArtifact(id: "a", type: "analysis", title: "camp.mp4", text: "Packing a bag.\nAction · 3s\nUse as preparation.", mediaId: "camp"),
            AgentArtifact(id: "b", type: "analysis", title: "camp.mp4", text: "Closing the bag.\nAction · 2s\nUse as preparation.", mediaId: "camp"),
            AgentArtifact(id: "c", type: "analysis", title: "coffee.jpg", text: "Two people at camp.", mediaId: "coffee")]
        let legacyReport = analysisRun.displayAnalysisReport!
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
        activityRun.status = "consent"; activityRun.question = "Allow this task to send selected frames to the cloud?"
        check(activityRun.activityNotice == nil && !activityRun.question.isEmpty, "consent question is preserved without duplicate notices")
        workspace.agentRuns = [legacyRun]
        check(workspace.projectEditedAt(projectA) == 1000, "background run timestamps do not masquerade as edits")
        legacyRun.editedAt = 3000; workspace.agentRuns = [legacyRun]
        check(workspace.projectEditedAt(projectA) == 3000 && workspace.sortedProjects.first?.id == projectA.id, "timeline edits update project timestamp and sorting")
        workspace.navigate(.home); workspace.draft = Draft(prompt: String(repeating: "字", count: 5001))
        check(!workspace.canSubmitAgent && workspace.composerIssue != nil, "oversized input is blocked before service request")
        workspace.draft.prompt = "Analyze"
        legacyRun.status = "running"; workspace.agentRuns = [legacyRun]
        check(workspace.blockingAgentRun?.id == legacyRun.id && !workspace.canSubmitAgent, "a different running project cannot be silently stopped")
        workspace.open(projectA)
        workspace.composerDraft.prompt = "Update this project"
        check(workspace.canSubmitAgent, "explicit same-project stop and update remains available")
        workspace.importing = true
        check(!workspace.canSubmitAgent, "wait for imported attachments before submitting")
        workspace.importing = false
        legacyRun.status = "clarify"; legacyRun.clarificationKind = "materials"; workspace.agentRuns = [legacyRun]
        workspace.composerDraft = Draft(attachments: projectA.attachments, projectId: projectA.id)
        check(workspace.canResumeWithMaterials && workspace.canSubmitAgent, "materials-only reply can continue the previous request")
        legacyRun.clarificationKind = nil; workspace.agentRuns = [legacyRun]
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
        check(!workspace.hasMediaFilters && workspace.searchScope == .name, "clear filters restores normal library")
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
        edit.split("s1", at: 1.5)
        check(edit.shots.count == 2 && edit.duration == 3 && edit.dirty, "split preserves source coverage and duration")
        edit.undo(); check(edit.shots == editRun.timeline && !edit.dirty, "undo restores exact baseline")
        edit.redo(); check(edit.shots.count == 2, "redo restores split")
        let restored = try JSONDecoder().decode(EditorDraft.self, from: JSONEncoder().encode(edit))
        check(restored == edit, "draft and undo/redo survive persistence")
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
        print("Passed \(checks) native model/import checks.")
    }
}
