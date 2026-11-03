import Foundation
import Security

struct AgentExample: Identifiable {
    let id: String
    let title: String
    let outcome: String
    let prompt: String
    var symbol: String {
        switch id {
        case "analyze": return "text.magnifyingglass"
        case "highlights": return "scissors"
        default: return "film"
        }
    }
    static let starters: [AgentExample] = [
        .init(id: "analyze", title: "Summarize my media", outcome: "Summarize my media.", prompt: "Summarize my media and suggest what to use."),
        .init(id: "create", title: "Create a travel video", outcome: "Create a travel video.", prompt: "Create a travel video with a clear story."),
        .init(id: "highlights", title: "Make a short highlight reel", outcome: "Make a short highlight reel.", prompt: "Make a short travel highlight reel from the best moments.")
    ]
    func applying(to draft: String) -> String {
        requiresReplacementConfirmation(for: draft) ? draft : prompt
    }
    func requiresReplacementConfirmation(for draft: String) -> Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && !Self.starters.contains { $0.prompt == text }
    }
}

struct AgentArtifact: Codable, Identifiable {
    var id: String; var type: String; var title: String; var text: String
    var mediaId: String?; var start: Double?; var end: Double?; var path: String?
    var timelineVersion: Int? = nil
    var findingParts: (content: String, metadata: String?, suggestion: String?) {
        guard type == "analysis" else { return (text, nil, nil) }
        let lines = text.components(separatedBy: "\n")
        let pattern = #"(^| · )(Keep|Recommended|Shorten|Remove|必留|推荐|可压缩|可删除) · [0-9.]+s$"#
        guard let index = lines.indices.first(where: { lines[$0].range(of: pattern, options: .regularExpression) != nil }), index > 0 else {
            return (text, nil, nil)
        }
        let suggestion = lines.dropFirst(index + 1).joined(separator: "\n")
        return (lines.prefix(index).joined(separator: "\n"), lines[index], suggestion.isEmpty ? nil : suggestion)
    }
}
struct AgentSourceGroup: Identifiable {
    var id: String; var title: String; var findings: [AgentArtifact]
    static func groups(_ artifacts: [AgentArtifact]) -> [AgentSourceGroup] {
        var result: [AgentSourceGroup] = []
        for artifact in artifacts where ["analysis", "observation", "subtitle", "match"].contains(artifact.type) {
            let key = artifact.mediaId ?? artifact.title
            if let index = result.firstIndex(where: { $0.id == key }) { result[index].findings.append(artifact) }
            else { result.append(.init(id: key, title: artifact.title, findings: [artifact])) }
        }
        return result
    }
    var summary: String {
        var seen = Set<String>()
        return findings.map { $0.findingParts.content }.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: " ")
    }
    /// A visual description is not a concatenation of dialogue and processing notes.
    var visualSummary: String {
        let visual = findings.filter { ["observation", "analysis"].contains($0.type) }
        let preferred = visual.last(where: { $0.type == "observation" }) ?? visual.first
        return preferred?.findingParts.content.components(separatedBy: "\n").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
struct AgentShot: Codable, Identifiable, Equatable {
    var id: String; var mediaId: String; var start: Double; var end: Double
    var label: String; var reason: String; var locked: Bool
    var section: String? = nil
}

/// User-facing fields of the compiled story; no second model interpretation.
struct AgentStoryExecution: Codable {
    struct Chapter: Codable, Identifiable {
        var id: String; var title: String; var intent: String; var bridge: String
        var shotIds: [String]
    }
    var summary: String? = nil
    var chapterNotice: String? = nil
    var outline: [Chapter]? = nil
    var sourceNames: [String: String]? = nil
    var sourceKinds: [String: String]? = nil
    var timelineVersion: Int? = nil
    var stale: Bool? = nil

    func matches(version: Int, shots: [AgentShot]) -> Bool {
        stale != true && timelineVersion == version && outline?.flatMap(\.shotIds) == shots.map(\.id)
    }
}

/// Source evidence and its uses in the edit share one material entry.
struct AgentConversationMaterial: Identifiable {
    var id: String
    var mediaID: String?
    var title: String
    var summary: String
    var progress: AgentMaterialProgress? = nil
    static func collect(_ run: AgentRun) -> [Self] {
        let groups = AgentSourceGroup.groups(run.artifacts)
        var result: [Self] = []
        var seen = Set<String>()
        let sourceIDs = run.mediaIds ?? run.materialProgress?.map(\.mediaId) ?? run.attachments?.map(\.id) ?? []
        for id in sourceIDs + (run.analysisReport?.materials.map(\.mediaId) ?? []) + run.timeline.map(\.mediaId) {
            guard seen.insert(id).inserted else { continue }
            let group = groups.first { $0.findings.first?.mediaId == id }
            let shot = run.timeline.first { $0.mediaId == id }
            let name = run.attachments?.first { $0.id == id }?.name ?? run.analysisReport?.materials.first { $0.mediaId == id }?.title
            result.append(Self(id: id, mediaID: id, title: name ?? group?.title ?? shot?.label ?? "Source", summary: group?.visualSummary ?? ""))
        }
        for group in groups where seen.insert(group.id).inserted {
            result.append(Self(id: group.id, mediaID: group.findings.first?.mediaId, title: group.title, summary: group.visualSummary))
        }
        return result
    }
}
struct AgentFinishing: Codable, Equatable {
    struct MotionTitle: Codable, Equatable {
        var kind: String; var text: String
        var origin: String? = nil; var destination: String? = nil
        var total: Int? = nil
    }
    struct Music: Codable, Equatable { var mediaId: String; var volume: Double; var ducking: Bool; var sourceStart: Double?; var loop: Bool? }
    struct Narration: Codable, Equatable { var start: Double; var end: Double; var text: String; var voice: String; var rate: Double? }
    struct Transition: Codable, Equatable { var kind: String; var duration: Double }
    struct Caption: Codable, Equatable, Identifiable { var id: String; var start: Double; var end: Double; var text: String }
    struct ClipAudio: Codable, Equatable { var shotId: String; var volume: Double; var muted: Bool }
    struct Seam: Codable, Equatable { var afterShotId: String; var beforeShotId: String; var kind: String; var duration: Double }
    var music: Music?
    var narration: [Narration]
    var transition: Transition
    var originalVolume: Double
    var originalMuted: Bool?
    var captions: [Caption]?
    var clipAudio: [ClipAudio]?
    var seams: [Seam]?
    var musicMuted: Bool? = nil
    var narrationMuted: Bool? = nil
    var narrationVolume: Double? = nil
    var motionTitle: MotionTitle? = nil
    static var empty: Self { Self(narration: [], transition: .init(kind: "none", duration: 0.25), originalVolume: 1) }
    func audio(for id: String) -> ClipAudio { clipAudio?.first { $0.shotId == id } ?? .init(shotId: id, volume: 1, muted: false) }
    func gain(for id: String) -> Double {
        let clip = audio(for: id)
        return originalMuted == true || clip.muted ? 0 : originalVolume * clip.volume
    }
    func seam(_ left: String, _ right: String) -> Seam {
        seams?.first { $0.afterShotId == left && $0.beforeShotId == right } ?? .init(afterShotId: left, beforeShotId: right, kind: transition.kind, duration: transition.duration)
    }
}
struct AgentAnalysisMaterial: Codable, Identifiable {
    var mediaId: String
    var title: String
    var content: String
    var suggestion: String
    var kind: String? = nil
    var id: String { mediaId }
}
struct AgentAnalysisReport: Codable {
    var overview: String
    var materials: [AgentAnalysisMaterial]
    var synthesized: Bool? = nil
}
struct AgentDecision: Codable, Identifiable {
    struct Option: Codable, Identifiable { var id: String; var label: String }
    var id: String; var state: String; var question: String; var options: [Option]
    var selected: String?; var response: String?; var resultText: String?
    var kind: String? = nil
    var detail: String? = nil
    var timeline: [AgentShot]? = nil
    var storyExecution: AgentStoryExecution? = nil
    var version: Int? = nil
    var tripEntries: [AgentTripEntry]? = nil
    var tripRows: [AgentTripDisplayRow]? {
        guard isTrip else { return nil }
        if let tripEntries, !tripEntries.isEmpty { return tripEntries.map(AgentTripDisplayRow.init) }
        return AgentTripDisplayRow.legacy(detail ?? "")
    }
    var isTrip: Bool { kind == "trip" || ["confirm_trip", "ignore_trip"].contains(selected ?? "") }
    var isProductionConfirmation: Bool {
        state == "answered" && (kind == "trip" || kind == "script" ||
            ["confirm_trip", "ignore_trip"].contains(selected ?? "") ||
            (selected == "approve" && !(resultText ?? "").isEmpty))
    }
}
struct AgentChoice: Codable, Identifiable {
    var id: String; var label: String; var prompt: String
}
struct AgentProgressUpdate: Codable, Identifiable {
    var id: String
    var kind: String
    var stage: String? = nil
    var mediaId: String? = nil
    var label: String? {
        ["intent": "Reviewing your request", "understand": "Reviewing your material",
         "transcribe": "Checking speech", "plan": "Arranging your story", "search": "Finding matching moments",
         "report": "Preparing your summary", "render": "Rendering your video",
         "finishing": "Planning sound and finishing touches", "verify": "Checking the finished video"][stage ?? ""]
    }
}

struct AgentScrollState {
    var followingLatest = true
    var contentHeight: CGFloat = 0
    mutating func observe(bottom: CGFloat, height: CGFloat, viewport: CGFloat) -> Bool {
        let resized = abs(height - contentHeight) > 0.5
        contentHeight = height
        // Content growth is not a user scrolling away from the latest message.
        if !resized { followingLatest = bottom <= viewport + 70 }
        return resized && followingLatest
    }
}

struct AgentEditReceipt: Codable, Equatable {
    var changedShotIds: [String]
    var removedCount: Int
    var soundOrCaptions: Bool
    var aspectChanged: Bool
    var version: Int
    var undone: Bool
    var packagingChanged: Bool? = nil
    var hasChanges: Bool { !changedShotIds.isEmpty || removedCount > 0 || soundOrCaptions || aspectChanged || packagingChanged == true }
    var summary: String {
        if undone { return "Change undone" }
        var parts: [String] = []
        if !changedShotIds.isEmpty { parts.append("\(changedShotIds.count) \(changedShotIds.count == 1 ? "clip" : "clips") updated") }
        if removedCount > 0 { parts.append("\(removedCount) removed") }
        if soundOrCaptions { parts.append("Audio / effects updated") }
        if aspectChanged { parts.append("Format updated") }
        if packagingChanged == true { parts.append("Titles updated") }
        return parts.isEmpty ? "No timeline changes" : parts.joined(separator: " · ")
    }
}

struct StoryVersion: Identifiable {
    var id: String
    var number: Int
    var shots: [AgentShot]
    var preview: AgentArtifact?
    var prompt: String
    var duration: Double { shots.reduce(0) { $0 + $1.end - $1.start } }
    static func collect(_ runs: [AgentRun]) -> [Self] {
        var result: [Self] = []
        for run in runs.sorted(by: { ($0.createdAt ?? $0.updatedAt, $0.id) < ($1.createdAt ?? $1.updatedAt, $1.id) }) {
            var snapshots: [Int: [AgentShot]] = [:]
            for entry in run.timelineHistory ?? [] { snapshots[entry.version] = entry.shots }
            if !run.timeline.isEmpty && !run.busy { snapshots[run.version] = run.timeline }
            var renders: [Int: AgentArtifact] = [:]
            for artifact in run.artifacts where ["preview", "previous_preview"].contains(artifact.type) {
                let version = artifact.timelineVersion ?? (artifact.type == "preview" ? run.version : Int(artifact.title.components(separatedBy: " · v").last ?? ""))
                if let version { renders[version] = artifact }
            }
            for version in Set(snapshots.keys).union(renders.keys).sorted() {
                result.append(Self(id: "\(run.id):\(version)", number: result.count + 1, shots: snapshots[version] ?? [],
                                   preview: renders[version], prompt: run.prompt))
            }
        }
        return result.reversed()
    }
}

struct AgentMaterialProgress: Codable, Identifiable {
    var mediaId: String
    var name: String
    var status: String
    var id: String { mediaId }
    var finished: Bool { ["completed", "prepared"].contains(status) }
    var label: String {
        switch status {
        case "completed": return "Analysis complete"
        case "prepared": return "Ready to use"
        case "running": return "Analyzing"
        case "failed": return "Analysis failed"
        case "paused": return "Analysis paused"
        case "unknown": return "Status unavailable"
        default: return "Waiting to analyze"
        }
    }
    var symbol: String {
        switch status {
        case "completed", "prepared": return "checkmark.circle.fill"
        case "running": return "circle.dotted"
        case "failed": return "exclamationmark.circle"
        case "paused": return "pause.circle"
        default: return "clock"
        }
    }
}

struct AgentRun: Codable, Identifiable {
    var creationSurface: String? = nil
    struct SavedTimeline: Codable { var version: Int; var shots: [AgentShot] }
    var timelineHistory: [SavedTimeline]? = nil
    var id: String; var projectId: String; var prompt: String; var mode: String
    var status: String; var stage: String; var message: String; var summary: String; var intent: String
    var question: String; var resultText: String; var events: [String]; var artifacts: [AgentArtifact]
    var timeline: [AgentShot]; var version: Int; var completed: Int; var total: Int
    var duration: Double; var aspect: String; var updatedAt: Double
    var editedAt: Double? = nil
    var createdAt: Double? = nil
    var clarificationKind: String? = nil
    var mediaIds: [String]? = nil
    var skillNotice: String? = nil
    var finishing: AgentFinishing? = nil
    var attachments: [Attachment]? = nil
    var messageAttachments: [Attachment]? = nil
    var originalMediaIds: [String]? = nil
    var conversationHistory: [AgentDecision]? = nil
    var choices: [AgentChoice]? = nil
    var progressUpdates: [AgentProgressUpdate]? = nil
    var materialProgress: [AgentMaterialProgress]? = nil
    var storySummary: String? = nil
    var storyExecution: AgentStoryExecution? = nil
    var tripConfirmation: AgentTripConfirmation? = nil
    var previousTimeline: [AgentShot]? = nil
    var awaitingScriptConfirmation: Bool {
        status == "review" || (status == "completed" && intent == "plan" && !timeline.isEmpty && preview == nil)
    }
    var needsRouteConfirmation: Bool {
        awaitingScriptConfirmation && (previousTimeline ?? []).isEmpty && tripConfirmation?.status != "confirmed"
    }
    var currentScriptConfirmed: Bool {
        (conversationHistory ?? []).contains { $0.isProductionConfirmation && $0.kind == "script" && $0.version == version }
    }
    var arrangementSummary: String? {
        guard !timeline.isEmpty, ["create", "modify", "plan"].contains(intent) else { return nil }
        // Replanning keeps the old timeline for recovery, not as a new proposal.
        guard !busy || ["render", "verify", "finishing"].contains(stage) else { return nil }
        guard status != "failed" || ["render", "verify", "finishing"].contains(stage) else { return nil }
        // Legacy edits saved the actual story on the first line of resultText.
        // The routing summary describes an unseen request, not an editorial decision.
        let text = (storySummary ?? resultText.components(separatedBy: "\n").first ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return text
    }
    var arrangementDetails: String {
        guard let arrangementSummary, resultText.hasPrefix(arrangementSummary) else { return resultText }
        return String(resultText.dropFirst(arrangementSummary.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var visibleProgress: [AgentProgressUpdate] {
        let findings = artifacts.filter { ["analysis", "observation", "subtitle"].contains($0.type) && !$0.text.isEmpty }
        var updates = progressUpdates ?? []
        // Old saved tasks still expose their existing findings, without inventing stages.
        for finding in findings {
            if let id = finding.mediaId, !updates.contains(where: { $0.kind == "media" && $0.mediaId == id }) {
                updates.append(AgentProgressUpdate(id: "media-" + id, kind: "media", mediaId: id))
            }
        }
        let liveStep = busy ? updates.last(where: { $0.kind == "stage" })?.id : nil
        return updates.filter { $0.id != liveStep && ($0.kind == "media" || $0.label != nil) }
    }
    var activityLabel: String {
        if busy, status != "queued", let step = progressUpdates?.last(where: { $0.kind == "stage" }),
           ["finishing", "verify"].contains(step.stage ?? ""), let label = step.label { return label }
        return stageLabel
    }
    var showsUnifiedMaterials: Bool { !["search", "subtitles"].contains(intent) }
    var analyzingMaterials: Bool { busy && ["highlights", "understand", "transcribe"].contains(stage) }
    var conciseSkillTitle: String? {
        skillNotice?.components(separatedBy: " · ").first
    }
    var conciseFailure: String {
        if let reason = explainedFailure { return reason }
        switch stage {
        case "highlights", "understand", "transcribe", "report": return "Analysis failed. Completed results are kept."
        case "plan": return "Story planning failed. Your analysis is kept."
        case "render", "verify", "finishing": return "Video generation failed. Your plan is kept."
        default: return "This task failed. Saved results are kept."
        }
    }
    private var explainedFailure: String? {
        let error = message.lowercased()
        if error.contains("while decompressing data") || error.contains("failed to unmarshal pyz") {
            return "A component could not load after the app update. Your analysis is kept. Restart Pixfun, then retry."
        }
        if message.localizedCaseInsensitiveContains("file is missing") || message.localizedCaseInsensitiveContains("file not found") {
            return "The original file is missing. Reconnect it to continue."
        }
        if error.contains("no space left") { return "There is not enough disk space. Free some space, then retry; your saved results are kept." }
        if error.contains("out of memory") { return "There is not enough memory. Close other apps or use fewer clips, then retry; your analysis is kept." }
        if error.contains("exit -9") || error.contains("signal 9") { return "The system stopped the analysis process. Close other apps, then retry; completed results are kept." }
        if error.contains("timed out") || error.contains("timeout") { return "The processing service did not respond in time. Retry; completed results are kept." }
        if error.contains("connection refused") || error.contains("connection reset") || error.contains("network is unreachable") {
            return "The processing service could not be reached. Check the connection or model service, then retry."
        }
        if error.contains("coverage is incomplete") { return "The story plan did not include all required clips. Retry planning; your analysis is kept." }
        if error.contains("story chapters") {
            return "Story chapters did not match the shot sequence. Retry planning; your analysis and confirmed route are kept."
        }
        if error.contains("more than 160 windows") || error.contains("planning context limit") { return "There is too much material for one story plan. Select fewer clips; your analysis is kept." }
        if error.contains("story adapter is unavailable") { return "The story engine is unavailable. Restart Pixfun or reinstall the update; your analysis is kept." }
        if error.contains("preview stream validation failed") || error.contains("rendered duration failed validation") {
            return "The generated video did not pass playback checks. Retry generation; your plan is kept."
        }
        return nil
    }
    var failureDetail: String? {
        guard explainedFailure == nil else { return nil }
        // Preserve the actual cause for unfamiliar errors, without dumping a traceback.
        let cause = message.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cause.isEmpty ? nil : String(cause.prefix(240))
    }
    func materialCards(in items: [MediaItem]) -> [AgentConversationMaterial] {
        let states = analysisMaterials(in: items)
        return AgentConversationMaterial.collect(self).map { material in
            var card = material
            let saved = states.first { $0.mediaId == card.mediaID }
            card.progress = saved ?? AgentMaterialProgress(mediaId: card.id, name: card.title, status: "unknown")
            if let saved { card.title = saved.name }
            // Prefer this task's visual evidence. Never pull a later library result into history.
            if card.summary.isEmpty, let report = analysisReport?.materials.first(where: { $0.mediaId == card.mediaID }) {
                card.summary = report.content.components(separatedBy: "\n").first ?? ""
            }
            return card
        }
    }
    func analysisMaterials(in items: [MediaItem]) -> [AgentMaterialProgress] {
        if let materialProgress, !materialProgress.isEmpty {
            return materialProgress.filter { (mediaIds ?? materialProgress.map(\.mediaId)).contains($0.mediaId) }.map { entry in
                var entry = entry
                if entry.status == "running", !busy {
                    entry.status = status == "failed" ? "failed" : "paused"
                }
                return entry
            }
        }
        // Older runs count fully processed materials before the current one.
        // Partial finding cards alone never establish that a material is complete.
        let analyzing = ["highlights", "understand", "transcribe"].contains(stage)
        let analyzed = ["trip", "report", "plan", "search", "render", "verify"].contains(stage)
        guard let mediaIds, !mediaIds.isEmpty, total > 0, analyzing || analyzed else { return [] }
        let files = attachments ?? sentAttachments(in: items)
        return mediaIds.enumerated().map { index, id in
            let name = files.first { $0.id == id }?.name ?? items.first { $0.id == id }?.file.name ?? "Unavailable file"
            let state: String
            if analyzed || index < completed { state = "completed" }
            else if index == completed {
                state = status == "running" ? "running" : status == "failed" ? "failed" : status == "queued" ? "pending" : "paused"
            } else { state = "pending" }
            return AgentMaterialProgress(mediaId: id, name: name, status: state)
        }
    }
    func sentAttachments(in items: [MediaItem]) -> [Attachment] {
        if let messageAttachments { return messageAttachments }
        if let attachments { return attachments }
        return (originalMediaIds ?? mediaIds ?? []).map { id in
            let item = items.first { $0.id == id }
            return Attachment(id: id, name: item?.file.name ?? "Unavailable file", kind: item?.kind ?? "video")
        }
    }
    var canUseVideosOnly: Bool {
        status == "clarify" && (["video_only", "visual_only"].contains(clarificationKind ?? "") ||
            question.hasPrefix("This rough-cut workflow currently uses video and its original sound only."))
    }
    var hasConversationActions: Bool {
        status == "consent" || canUseVideosOnly || canResumePhotoEdit || status == "review" ||
        (status == "clarify" && choices?.isEmpty == false) ||
        (status == "completed" && intent == "plan" && !timeline.isEmpty && preview == nil) ||
        ["failed", "cancelled", "interrupted"].contains(status)
    }
    var canResumePhotoEdit: Bool {
        status == "clarify" && question.contains("photo slideshows are not supported yet")
            && attachments?.contains(where: { $0.kind == "image" }) == true
    }
    var displayQuestion: String {
        if canResumePhotoEdit { return "Photo editing is now available. Your material is ready to use." }
        if canUseVideosOnly && clarificationKind == nil {
            return "This earlier task was paused by a material limit. Continue with videos only, or send a new request to include photos too."
        }
        return question
    }
    var editScope: EditorSelection? = nil
    var editReceipt: AgentEditReceipt? = nil
    var analysisReport: AgentAnalysisReport? = nil
    // Older runs already contain source findings. Present these without rerunning a model
    // or mistaking the old generic resultText for an actual report.
    var displayAnalysisReport: AgentAnalysisReport? {
        guard intent == "analyze", status == "completed" else { return nil }
        if let analysisReport, !analysisReport.materials.isEmpty { return analysisReport }
        let sources = artifacts.filter { ["analysis", "subtitle"].contains($0.type) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var keys: [String] = []
        for source in sources {
            let key = source.mediaId ?? source.title
            if !keys.contains(key) { keys.append(key) }
        }
        let materials = keys.map { key -> AgentAnalysisMaterial in
            let findings = sources.filter { ($0.mediaId ?? $0.title) == key }
            let first = findings[0]
            var suggestions: [String] = []
            var descriptions: [String] = []
            for finding in findings {
                let description = finding.text.components(separatedBy: "\n")[0]
                if !description.isEmpty, !descriptions.contains(description) { descriptions.append(description) }
            }
            for finding in findings where finding.type == "analysis" {
                let lines = finding.text.components(separatedBy: "\n")
                if lines.count > 1, let last = lines.last, !last.isEmpty, !suggestions.contains(last) { suggestions.append(last) }
            }
            return AgentAnalysisMaterial(mediaId: key, title: first.title,
                content: descriptions.joined(separator: "\n"), suggestion: suggestions.joined(separator: "\n"))
        }
        return AgentAnalysisReport(overview: materials.isEmpty ? "No usable analysis was found. Try analyzing the material again." :
            "Here are the available findings for \(materials.count) materials.", materials: materials, synthesized: false)
    }
    var busy: Bool { ["queued", "running"].contains(status) }
    var showsDirectEvidence: Bool { status == "completed" && ["search", "subtitles"].contains(intent) }
    var directEvidence: [AgentArtifact] { artifacts.filter { $0.type == (intent == "search" ? "match" : "subtitle") } }
    // Router output has not seen footage: do not present it as visual evidence
    // or as a claim that editing has already finished.
    var taskDescription: String? {
        switch intent {
        case "analyze": return "Analyze the selected material"
        case "search": return "Find matching moments in the selected material"
        case "subtitles": return "Extract or transcribe speech · no video generation"
        case "plan": return "Prepare a story plan for your review"
        case "create": return "Prepare a rough cut · review before rendering"
        case "modify": return editScope == nil ? "Revise the existing timeline" : "Revise only the selected shots"
        default: return nil
        }
    }
    var statusLabel: String {
        switch status {
        case "queued": return "Preparing"
        case "running": return "Working"
        case "clarify": return "Your input needed"
        case "consent": return "Permission needed"
        case "review": return "Ready for your review"
        case "completed": return "Ready"
        case "cancelled": return "Stopped"
        case "interrupted": return "Paused after restart"
        case "failed": return "Needs attention"
        default: return status.capitalized
        }
    }
    var stageLabel: String {
        if status == "queued", total > 0 { return "Analyzing clips · \(min(max(completed + 1, 1), total))/\(total)" }
        if status == "queued" { return "Preparing analysis" }
        switch stage {
        case "intent": return "Reading your request"
        case "highlights": return total > 1 ? "Analyzing highlights · \(min(max(completed + 1, 1), total))/\(total)" : "Analyzing highlights"
        case "understand": return total > 1 ? "Reviewing your clips · \(min(max(completed + 1, 1), total))/\(total)" : "Reviewing your clips"
        case "trip": return "Confirming the trip"
        case "transcribe": return "Listening to your audio"
        case "search": return "Finding the moments you asked for"
        case "plan": return "Putting your story together"
        case "render": return "Making your preview"
        case "report": return "Summarizing your footage"
        default: return "Working on your request"
        }
    }
    var activityNotice: String? {
        guard !busy else { return nil }
        switch status {
        case "failed":
            if message.hasPrefix("Shot output failed validation:") {
                return "The model couldn't produce a valid shot description. Retry to continue from saved results."
            }
            if message.contains("has no attribute") || message.contains("Traceback") || message.contains("NoneType") {
                return "A local processing error stopped this task. Try again to continue."
            }
            if message.hasPrefix("Invalid source range") || message == "Value outside allowed range" {
                return "I couldn't make a valid edit from these clips. Retry, or try fewer videos."
            }
            return message.isEmpty ? "Something went wrong. Please retry." : message
        case "cancelled": return "Stopped"
        case "interrupted": return "Paused. Retry to continue."
        case "consent": return question.isEmpty ? "Permission needed to continue." : nil
        case "clarify": return question.isEmpty ? "Tell me a little more to continue." : nil
        case "review": return "Your plan is ready. Review it, then build the preview."
        default: return nil
        }
    }
    var failureTitle: String {
        switch stage {
        case "understand", "transcribe", "report": return "Couldn't finish analyzing your footage"
        case "render": return "Couldn't create your preview"
        default: return "Couldn't finish this task"
        }
    }
    var preview: AgentArtifact? { artifacts.last { $0.type == "preview" } }
    var lastPreview: AgentArtifact? { preview ?? artifacts.last { $0.type == "previous_preview" } }
    var resultHeading: String? {
        if status == "review", !timeline.isEmpty { return "Script confirmation" }
        guard status == "completed" else { return nil }
        if preview != nil { return "Video preview" }
        if intent == "plan", !timeline.isEmpty { return "Story plan" }
        if intent == "analyze", displayAnalysisReport?.materials.isEmpty == false { return "Footage summary" }
        return nil
    }
    var resultDetail: String? {
        guard resultHeading != nil else { return nil }
        if preview != nil { return "Watch, edit, or export your video." }
        if intent == "plan" {
            let seconds = timeline.reduce(0) { $0 + $1.end - $1.start }
            return "\(timeline.count) shots · \(String(format: "%.1f", seconds))s · \(aspect)"
        }
        let count = displayAnalysisReport?.materials.count ?? 0
        return "\(count) \(count == 1 ? "file" : "files") · Open a card for details"
    }
}
struct AgentTripLocation: Codable {
    var latitude: Double; var longitude: Double
}
struct AgentTripCorrection: Codable {
    var kind: String?; var anchorNumber: Int?; var anchorMediaId: String?
}
struct AgentTripEntry: Codable, Identifiable {
    var number: Int; var mediaId: String; var name: String; var capturedAt: String; var place: String
    var originalLocation: AgentTripLocation?; var location: AgentTripLocation?; var correction: AgentTripCorrection?
    var id: Int { number }
}
struct AgentTripConfirmation: Codable {
    var status: String; var useLocations: Bool; var entries: [AgentTripEntry]
    var updatedAt: Double? = nil
}
/// Presentation only: preserve the confirmed snapshot, never resolve it against today's library.
struct AgentTripDisplayRow {
    var number: Int; var name: String; var capturedAt: String; var place: String; var corrected: Bool
    var mediaID: String? = nil
    var day: String? {
        capturedAt.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$"#, options: .regularExpression) != nil ? String(capturedAt.prefix(10)) : nil
    }
    var timeLabel: String { day == nil ? capturedAt : String(capturedAt.suffix(5)) }
    init(_ entry: AgentTripEntry) {
        number = entry.number; name = entry.name
        mediaID = entry.mediaId
        capturedAt = entry.capturedAt.isEmpty ? "Time not recorded" : String(entry.capturedAt.prefix(16)).replacingOccurrences(of: "T", with: " ")
        place = entry.place.isEmpty ? "Location to confirm" : entry.place
        corrected = entry.correction != nil
    }
    private init(number: Int, name: String, capturedAt: String, place: String, corrected: Bool) {
        self.number = number; self.name = name; self.capturedAt = capturedAt; self.place = place; self.corrected = corrected
    }
    func referencedMediaID(in items: [MediaItem], allowedIDs: [String]) -> String? {
        if let mediaID { return mediaID }
        // Historic text has no ID. Only link a unique filename within this run's sources.
        let matches = items.filter { allowedIDs.contains($0.id) && $0.file.name == name }
        return matches.count == 1 ? matches.first?.id : nil
    }
    static func legacy(_ detail: String) -> [Self]? {
        // Only parse the exact historic detailed_text format. Unknown formats stay verbatim.
        let lines = detail.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty, let regex = try? NSRegularExpression(pattern: #"^([0-9]+)\. (.+) · ([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}|时间未记录) · (.+)$"#) else { return nil }
        var rows: [Self] = []
        for line in lines {
            let source = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: source.length)),
                  let number = Int(source.substring(with: match.range(at: 1))) else { return nil }
            let stamp = source.substring(with: match.range(at: 3))
            var place = source.substring(with: match.range(at: 4))
            let corrected = place.hasSuffix(" · 已纠偏")
            if corrected { place = String(place.dropLast(" · 已纠偏".count)) }
            rows.append(Self(number: number, name: source.substring(with: match.range(at: 2)),
                             capturedAt: stamp == "时间未记录" ? "Time not recorded" : stamp,
                             place: place == "地点待确认" ? "Location to confirm" : place, corrected: corrected))
        }
        return rows
    }
}
enum AgentPlanCopy {
    static func durationChange(_ text: String) -> (proposed: String, requested: String)? {
        let pattern = #"^Duration differs from request: ([0-9.]+)s proposed vs ([0-9.]+)s requested\. Review before rendering\.$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let proposed = Range(match.range(at: 1), in: text),
              let requested = Range(match.range(at: 2), in: text) else { return nil }
        return (String(text[proposed]), String(text[requested]))
    }
}
struct AgentCapabilities: Codable {
    var localText: Bool; var localVision: Bool; var localSpeech: Bool
    var cloudText: Bool; var cloudVision: Bool
    var baseURL: String; var model: String; var visionModel: String; var localModel: String; var note: String
    var tools: [AgentToolCapability]?
    var engineVersion: String? = nil
}
struct AgentQualityReport: Codable {
    var version: Int; var status: String; var summary: String; var note: String
    var checks: [String]; var issues: [AgentQualityIssue]
    var audioProcessing: AgentAudioProcessing? = nil
}
struct AgentQualityIssue: Codable {
    var kind: String; var message: String; var start: Double?; var end: Double?; var shotIds: [String]
    var cueIndex: Int? = nil
    var text: String? = nil
}
struct EditorNarrationRequest: Hashable {
    var runID: String; var version: Int; var index: Int; var text: String
    var start: Double; var end: Double
    func matches(_ cues: [AgentFinishing.Narration]) -> Bool {
        cues.indices.contains(index) && cues[index].text == text &&
            cues[index].start == start && cues[index].end == end
    }
}
struct AgentAudioProcessing: Codable {
    var narrationDucking: Bool; var reusedNarration: Int; var totalNarration: Int
    var loudnessNormalized: Bool? = nil
}
struct AgentToolCapability: Codable, Identifiable {
    var id: String; var name: String; var installed: Bool; var lastExecution: String
}
struct CloudSettings: Codable, Equatable {
    var baseURL = "https://api.openai.com/v1"
    var model = ""
    var visionModel = ""
    var apiKey = ""
    static let account = "cloud-agent-configuration"
    static func read() -> CloudSettings? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.pixfun.native", kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(CloudSettings.self, from: data)
    }
    func save() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.pixfun.native", kSecAttrAccount as String: Self.account]
        let data = try JSONEncoder().encode(self)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var added = query; added[kSecValueData as String] = data
            added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(added as CFDictionary, nil) == errSecSuccess else { throw ServiceError(message: "Could not save model settings in Keychain.") }
        } else if status != errSecSuccess { throw ServiceError(message: "Could not update model settings in Keychain.") }
    }
}
