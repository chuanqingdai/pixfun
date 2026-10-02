import Foundation

@main struct NativeModelTests {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            guard value() else { fatalError("FAIL: \(label)") }; checks += 1
        }
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
