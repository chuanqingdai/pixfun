import Foundation
import Security

struct AgentExample: Identifiable {
    let id: String
    let title: String
    let outcome: String
    let prompt: String
    static let starters: [AgentExample] = [
        .init(id: "analyze", title: "Analyze footage", outcome: "A summary and editing suggestions", prompt: "Analyze these materials. Summarize each file, explain its editing value, and include useful time ranges. Do not create a video."),
        .init(id: "search", title: "Find a moment", outcome: "Matching clips with time ranges", prompt: "Find moments with a campfire in these videos. Return the matching clips and time ranges. If none match, say so. Do not create a video."),
        .init(id: "plan", title: "Plan a story", outcome: "A shot order to review first", prompt: "Suggest a travel story using these videos. Explain the shot order and suggested durations. Give me a plan first; do not render a video."),
        .init(id: "create", title: "Make a rough cut", outcome: "Review a plan, then build an MP4", prompt: "Make a 30-second 16:9 rough cut from these videos, keeping the original sound. Do not add music, captions, voiceover or effects. If there is not enough footage, ask me before changing the duration."),
        .init(id: "subtitles", title: "Extract subtitles", outcome: "Spoken words and an SRT file", prompt: "Transcribe the speech in these files and provide an SRT file. If there is no usable speech, tell me. Do not create a video or add captions to one.")
    ]
    func applying(to draft: String) -> String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? prompt : draft + "\n" + prompt
    }
}

struct AgentArtifact: Codable, Identifiable {
    var id: String; var type: String; var title: String; var text: String
    var mediaId: String?; var start: Double?; var end: Double?; var path: String?
}
struct AgentShot: Codable, Identifiable, Equatable {
    var id: String; var mediaId: String; var start: Double; var end: Double
    var label: String; var reason: String; var locked: Bool
    var section: String? = nil
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
struct AgentRun: Codable, Identifiable {
    var id: String; var projectId: String; var prompt: String; var mode: String
    var status: String; var stage: String; var message: String; var summary: String; var intent: String
    var question: String; var resultText: String; var events: [String]; var artifacts: [AgentArtifact]
    var timeline: [AgentShot]; var version: Int; var completed: Int; var total: Int
    var duration: Double; var aspect: String; var updatedAt: Double
    var editedAt: Double? = nil
    var createdAt: Double? = nil
    var clarificationKind: String? = nil
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
        case "failed": return message.isEmpty ? "Something went wrong. Please retry." : message
        case "cancelled": return "Stopped"
        case "interrupted": return "Paused. Retry to continue."
        case "consent": return question.isEmpty ? "Permission needed to continue." : nil
        case "clarify": return question.isEmpty ? "Tell me a little more to continue." : nil
        case "review": return "Your plan is ready. Review it, then build the preview."
        default: return nil
        }
    }
    var preview: AgentArtifact? { artifacts.last { $0.type == "preview" } }
    var lastPreview: AgentArtifact? { preview ?? artifacts.last { $0.type == "previous_preview" } }
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
