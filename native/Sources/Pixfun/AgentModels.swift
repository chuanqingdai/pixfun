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
}
struct AgentShot: Codable, Identifiable, Equatable {
    var id: String; var mediaId: String; var start: Double; var end: Double
    var label: String; var reason: String; var locked: Bool
    var section: String? = nil
}

/// Source evidence and its uses in the edit share one material entry.
struct AgentConversationMaterial: Identifiable {
    var id: String
    var mediaID: String?
    var title: String
    var summary: String
    static func collect(_ run: AgentRun) -> [Self] {
        let groups = AgentSourceGroup.groups(run.artifacts)
        var result: [Self] = []
        var seen = Set<String>()
        for id in run.timeline.map(\.mediaId) + (run.mediaIds ?? []) {
            guard seen.insert(id).inserted else { continue }
            let group = groups.first { $0.findings.first?.mediaId == id }
            let shot = run.timeline.first { $0.mediaId == id }
            result.append(Self(id: id, mediaID: id, title: group?.title ?? shot?.label ?? "Source", summary: group?.summary ?? shot?.reason ?? ""))
        }
        for group in groups where seen.insert(group.id).inserted {
            result.append(Self(id: group.id, mediaID: group.findings.first?.mediaId, title: group.title, summary: group.summary))
        }
        return result
    }
}
struct AgentFinishing: Codable, Equatable {
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

struct AgentRun: Codable, Identifiable {
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
    var storySummary: String? = nil
    var arrangementSummary: String? {
        guard !timeline.isEmpty, ["create", "modify", "plan"].contains(intent) else { return nil }
        // Legacy edits saved the actual story on the first line of resultText.
        // The routing summary describes an unseen request, not an editorial decision.
        let text = (storySummary ?? resultText.components(separatedBy: "\n").first ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return text.count > 420 ? String(text.prefix(417)) + "…" : text
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
        if status == "queued" { return "Getting started" }
        switch stage {
        case "intent": return "Reading your request"
        case "understand": return total > 1 ? "Reviewing your clips · \(min(max(completed + 1, 1), total))/\(total)" : "Reviewing your clips"
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
struct AgentCapabilities: Codable {
    var localText: Bool; var localVision: Bool; var localSpeech: Bool
    var cloudText: Bool; var cloudVision: Bool
    var baseURL: String; var model: String; var visionModel: String; var localModel: String; var note: String
    var tools: [AgentToolCapability]?
}
struct AgentToolCapability: Codable, Identifiable {
    var id: String; var name: String; var installed: Bool; var lastExecution: String
}
struct CloudSettings: Codable {
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
