import Foundation

struct MediaFile: Codable { var name: String; var size: Int64?; var type: String? }
struct Metadata: Codable {
    var width: Double?; var height: Double?; var duration: Double?; var fps: Double?; var hasAudio: Bool?
}
struct Segment: Codable, Identifiable {
    var id: String; var label: String; var start: Double; var end: Double
    var thumbnailUrl: String?; var note: String?; var boundary: Boundary?
    var editorial: EditorialShot?
    struct Boundary: Codable { var type: String }
    func hoverDescription(analysisStatus: String?) -> String {
        let description = editorial?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !description.isEmpty { return description }
        switch analysisStatus {
        case "queued", "running": return "Analyzing this footage. The shot description will appear when ready."
        case "failed", "interrupted", "cancelled": return "Shot description unavailable. Retry shot analysis to generate it."
        default: return "No shot description yet. Choose Analyze shots to generate one."
        }
    }
    func hoverHelp(analysisStatus: String?) -> String {
        "\(label) · \(timestamp(start))–\(timestamp(end))\n\n\(hoverDescription(analysisStatus: analysisStatus))"
    }
    var splitReason: String {
        switch boundary?.type {
        case "video_start": return "Video start"
        case "detected_cut": return "Detected visual cut"
        case "semantic_change": return "Semantic change · review timing"
        default: return "Time-based split"
        }
    }
}
struct EditorialShot: Codable {
    var shot_id: String; var start_time: String; var end_time: String; var description: String
    var shot_size: String; var capture_type: String; var camera_motion: String
    var story_role: [String]; var dialogue: String; var reaction: String; var audio: [String]
    var importance_score: Double; var duplicate_candidate: Bool; var unusable_candidate: Bool
    var edit_recommendation: Recommendation
    struct Recommendation: Codable { var level: String; var recommended_duration_sec: Double; var reason: String }
    // Editorial recommendation, not a claim of verified technical image quality.
    var isHighlight: Bool {
        importance_score.isFinite && importance_score >= 80 && importance_score <= 100
            && ["Keep", "Recommended", "必留", "推荐"].contains(edit_recommendation.level)
            && edit_recommendation.recommended_duration_sec > 0
            && !duplicate_candidate && !unusable_candidate
    }
}
struct ShotAnalysis: Codable {
    var status: String; var message: String?; var summary: String?; var segments: [Segment]?; var limitations: [String]?
    var busy: Bool { ["queued", "running"].contains(status) }
}
struct Cue: Codable { var start: Double; var end: Double?; var text: String }
struct Analysis: Codable {
    var segments: [Segment]?; var subtitleCues: [Cue]?; var subtitleMessage: String?; var subtitleState: String?
}
struct MediaResult: Codable { var analysis: Analysis? }
struct VideoDescription: Codable {
    var status: String; var message: String?
    var title: String?; var full_description: String?; var coverage: String?; var model: String?
    var busy: Bool { ["queued", "running"].contains(status) }
}
struct MediaItem: Codable, Identifiable {
    var id: String; var file: MediaFile; var kind: String; var status: String
    var metadata: Metadata?; var result: MediaResult?; var error: String?; var favorite: Bool?
    var description: String?; var title: String?; var context: [String: String]?; var url: String?; var missing: Bool?
    var videoDescription: VideoDescription?
    var shotAnalysis: ShotAnalysis?
    var isExample: Bool?
    var coverUrl: String?
    var sampleCopy: VideoDescription?
    var name: String {
        if isExample == true, let curated = sampleCopy?.title ?? title, !curated.isEmpty { return curated }
        return videoDescription?.title ?? (title?.isEmpty == false ? title : nil) ?? file.name
    }
    var displayVideoDescription: VideoDescription? {
        guard isExample == true, let sampleCopy else { return videoDescription }
        let text = videoDescription?.full_description ?? ""
        // A legacy Chinese result must not replace authored English sample copy.
        // Keep the original result and its running status for analysis controls.
        if text.isEmpty || text.range(of: "\\p{Han}", options: .regularExpression) != nil { return sampleCopy }
        return videoDescription
    }
    var segments: [Segment] { shotAnalysis?.segments ?? result?.analysis?.segments ?? [] }
    var cues: [Cue] { result?.analysis?.subtitleCues ?? [] }
    var transcriptCues: [Cue] { cues.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    var processing: Bool { ["queued", "analyzing"].contains(status) }
    var processingLabel: String? {
        if status == "analyzing" || shotAnalysis?.status == "running" || videoDescription?.status == "running" { return "Analyzing…" }
        if status == "queued" || shotAnalysis?.status == "queued" || videoDescription?.status == "queued" { return "Queued…" }
        return nil
    }
    var aspect: CGFloat {
        guard let w = metadata?.width, let h = metadata?.height, w > 0, h > 0 else { return 16 / 9 }
        return min(2.4, max(0.45, w / h))
    }
    var cover: String? { coverUrl ?? segments.first?.thumbnailUrl ?? (kind == "image" ? url : nil) }
    func matches(_ query: String) -> Bool {
        MediaSearchDocument(self).match(MediaSearchQuery(query), scope: .all, location: nil) != nil
    }
}
struct Attachment: Codable, Identifiable, Equatable { var id: String; var name: String; var kind: String }
struct ChosenSkill: Codable, Equatable { var id: String; var title: String; var strategy: String }
struct BriefMessage: Codable { var text: String; var createdAt: Double; var attachments: [Attachment]?; var skill: ChosenSkill? }
struct Project: Codable, Identifiable {
    var id: String; var title: String; var updatedAt: Double; var attachments: [Attachment]; var skill: ChosenSkill?; var messages: [BriefMessage]
}
struct Draft: Codable, Equatable {
    var prompt = ""; var attachments: [Attachment] = []; var projectId: String?; var skill: ChosenSkill?
    var hasContent: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty || skill != nil }
    mutating func attach(_ items: [MediaItem]) {
        for item in items where !attachments.contains(where: { $0.id == item.id }) {
            attachments.append(Attachment(id: item.id, name: item.file.name, kind: item.kind))
        }
    }
}
struct SkillHighlight: Codable { var title: String; var body: String }
struct CreatorSkill: Codable, Identifiable {
    var id: String; var title: String; var image: String; var copy: String
    var materials: [String]; var structure: [String]; var pacing: String; var sound: String; var avoid: String
    var value: String; var beats: [String]; var handling: [String]; var example: String; var strategy: String
    var source: String?; var version: String?; var highlights: [SkillHighlight]?
    var actionTitle: String?; var capabilityNote: String?
    var materialCases: [SkillHighlight]?; var templates: [SkillHighlight]?; var workflow: [SkillHighlight]?
    var specificationURL: URL? {
        guard let source, let root = Bundle.main.resourceURL else { return nil }
        let url = root.appendingPathComponent("CreatorSkills").appendingPathComponent(source)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    var chosen: ChosenSkill { ChosenSkill(id: id, title: title, strategy: strategy) }
}
enum WorkspacePage: String, CaseIterable, Identifiable {
    case home = "Home", media = "Media", skills = "Skills", project = "Project"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .home: return "sparkles"; case .media: return "photo.on.rectangle.angled"; case .skills: return "wand.and.stars"; case .project: return "folder" }
    }
}
enum MediaCategory: String, CaseIterable { case all = "All", video = "Videos", image = "Photos", favorites = "Favorites" }
struct MediaLocation: Codable, Equatable, Identifiable {
    var id: String
    var path: String
    var folder: String { URL(fileURLWithPath: path).deletingLastPathComponent().path }
    func isInside(_ directory: String) -> Bool {
        let selected = URL(fileURLWithPath: directory).standardizedFileURL.path
        let parent = URL(fileURLWithPath: folder).standardizedFileURL.path
        return parent == selected || parent.hasPrefix(selected == "/" ? "/" : selected + "/")
    }
}
struct MediaFolder: Identifiable {
    var path: String; var count: Int
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}
enum MediaSort: String, CaseIterable {
    case original = "Newest first", nameAscending = "Name A–Z", nameDescending = "Name Z–A", longest = "Longest first"
}
struct MediaFilter {
    var category = MediaCategory.all
    var query = ""
    var scope = MediaSearchScope.all
    var folder = ""
    var sort = MediaSort.original
    func apply(_ items: [MediaItem], locations: [String: MediaLocation]) -> [MediaItem] {
        results(items, locations: locations).map(\.item)
    }
    func results(_ items: [MediaItem], locations: [String: MediaLocation], documents: [String: MediaSearchDocument] = [:]) -> [MediaSearchResult] {
        let query = MediaSearchQuery(query)
        let filtered: [MediaSearchResult] = items.compactMap { item in
            guard item.kind != "audio" else { return nil }
            guard category == .all || (category == .favorites && item.favorite == true) ||
                    (category == .video && item.kind == "video") || (category == .image && item.kind == "image") else { return nil }
            guard folder.isEmpty || locations[item.id]?.isInside(folder) == true else { return nil }
            guard let hits = (documents[item.id] ?? MediaSearchDocument(item)).match(query, scope: scope, location: locations[item.id]) else { return nil }
            return MediaSearchResult(item: item, hits: hits)
        }
        // The library API returns stable insertion order (SQLite rowid ascending).
        // Reverse it for browsing; analysis updates must not move cards or pin samples.
        if sort == .original && query.isEmpty { return Array(filtered.reversed()) }
        return filtered.enumerated().sorted { lhs, rhs in
            if sort == .original {
                if lhs.element.score != rhs.element.score { return lhs.element.score > rhs.element.score }
                return lhs.offset < rhs.offset
            }
            let left = lhs.element.item, right = rhs.element.item
            if sort == .longest {
                let a = left.metadata?.duration ?? -1, b = right.metadata?.duration ?? -1
                if a != b { return a > b }
            }
            let comparison = left.file.name.localizedStandardCompare(right.file.name)
            if comparison == .orderedSame { return left.id < right.id }
            return sort == .nameDescending ? comparison == .orderedDescending : comparison == .orderedAscending
        }.map(\.element)
    }
}
func timestamp(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let value = max(0, Int(seconds))
    return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
}
