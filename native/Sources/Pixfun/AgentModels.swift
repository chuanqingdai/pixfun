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
        .init(id: "analyze", title: "Summarize my footage", outcome: "Summarize my footage.", prompt: "Summarize each video and suggest the best moments to use."),
        .init(id: "create", title: "Create a travel video", outcome: "Create a travel video.", prompt: "Create a travel video with a clear story and original sound."),
        .init(id: "highlights", title: "Make a short highlight reel", outcome: "Make a short highlight reel.", prompt: "Make a short travel highlight reel from the best moments, with original sound.")
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
struct AgentFinishing: Codable {
    struct Music: Codable { var mediaId: String; var volume: Double; var ducking: Bool }
    struct Narration: Codable { var start: Double; var end: Double; var text: String; var voice: String }
    struct Transition: Codable { var kind: String; var duration: Double }
    var music: Music?
    var narration: [Narration]
    var transition: Transition
    var originalVolume: Double
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
struct AgentRun: Codable, Identifiable {
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
