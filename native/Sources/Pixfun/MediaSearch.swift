import Foundation

enum MediaSearchScope: String, CaseIterable {
    case all = "Everything", name = "Names", content = "Scenes & shots"
    case transcript = "Transcript", editing = "Editing", context = "Place & device", folder = "Folders"
    var placeholder: String {
        switch self {
        case .all: return "Search names, scenes, dialogue…"
        case .name: return "Search filenames or titles…"
        case .content: return "Search scenes, actions, sounds…"
        case .transcript: return "Search spoken words or subtitles…"
        case .editing: return "Search roles or editing notes…"
        case .context: return "Search places or devices…"
        case .folder: return "Search folder paths…"
        }
    }
    var explanation: String {
        switch self {
        case .all: return "Names, descriptions, shots, transcripts, editing notes, places, devices and folder paths."
        case .name: return "Original filenames and saved titles."
        case .content: return "Descriptions, subjects, actions, reactions, framing, camera movement and described sounds."
        case .transcript: return "Saved speech transcripts and extracted subtitle tracks, not inferred dialogue."
        case .editing: return "Story roles, editing recommendations, reasons and Highlight picks."
        case .context: return "Saved location and device information; no guessed locations."
        case .folder: return "Original folder paths, including parent folders."
        }
    }
}

struct MediaSearchQuery {
    let terms: [String]
    init(_ text: String) {
        terms = Array(Set(Self.fold(text).split(whereSeparator: \.isWhitespace).map(String.init))).sorted()
    }
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    var isEmpty: Bool { terms.isEmpty }
}

struct MediaSearchField {
    var scope: MediaSearchScope
    var label: String
    var text: String
    var folded: String
    var start: Double?
    var segmentID: String?
    var priority: Int
    init(_ scope: MediaSearchScope, _ label: String, _ text: String?, start: Double? = nil, segmentID: String? = nil, priority: Int = 60) {
        self.scope = scope; self.label = label
        self.text = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        folded = MediaSearchQuery.fold(self.text)
        self.start = start; self.segmentID = segmentID; self.priority = priority
    }
}

struct MediaSearchHit: Identifiable {
    var id: Int
    var label: String
    var text: String
    var start: Double?
    var segmentID: String?
    var priority: Int
    func excerpt(query: String) -> String {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let ranges = terms.compactMap { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) }
        let first = ranges.map(\.lowerBound).min() ?? text.startIndex
        let begin = text.index(first, offsetBy: -35, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(begin, offsetBy: 160, limitedBy: text.endIndex) ?? text.endIndex
        return (begin > text.startIndex ? "…" : "") + String(text[begin..<end]) + (end < text.endIndex ? "…" : "")
    }
}

struct MediaSearchDocument {
    var fields: [MediaSearchField]
    init(_ item: MediaItem) {
        fields = [
            .init(.name, "Title", item.name, priority: 100),
            .init(.name, "Filename", item.file.name, priority: 100),
            .init(.content, "Description", item.displayVideoDescription?.full_description, priority: 80),
            .init(.content, "Description", item.description, priority: 80),
            .init(.content, "Video summary", item.shotAnalysis?.summary, priority: 80),
            .init(.context, "Location", item.context?["location"], priority: 75),
            .init(.context, "Device", item.context?["device"], priority: 65)
        ]
        for segment in item.segments {
            let time = Self.safeTime(segment.start, item: item)
            fields.append(.init(.content, "Shot", segment.label, start: time, segmentID: segment.id, priority: 85))
            guard let shot = segment.editorial else { continue }
            fields.append(.init(.content, "Shot description", shot.description, start: time, segmentID: segment.id, priority: 90))
            fields.append(.init(.content, "Framing & movement", [shot.shot_size, shot.capture_type, shot.camera_motion].joined(separator: " · "), start: time, segmentID: segment.id))
            fields.append(.init(.content, "Reaction", shot.reaction, start: time, segmentID: segment.id))
            fields.append(.init(.content, "Described sound", shot.audio.joined(separator: " · "), start: time, segmentID: segment.id))
            fields.append(.init(.content, "Model-reported dialogue", shot.dialogue, start: time, segmentID: segment.id))
            let edit = (shot.story_role + [shot.edit_recommendation.level, shot.edit_recommendation.reason] + (shot.isHighlight ? ["Highlight"] : [])).joined(separator: " · ")
            fields.append(.init(.editing, "Editing suggestion", edit, start: time, segmentID: segment.id, priority: 70))
        }
        for cue in item.transcriptCues {
            fields.append(.init(.transcript, "Transcript", cue.text, start: Self.safeTime(cue.start, item: item), priority: 88))
        }
        // Empty fields and duplicate presentation copy are not search evidence.
        var seen = Set<String>()
        fields = fields.filter { !$0.folded.isEmpty && seen.insert("\($0.scope.rawValue)|\($0.folded)|\($0.start ?? -1)").inserted }
    }
    private static func safeTime(_ seconds: Double, item: MediaItem) -> Double? {
        guard item.kind == "video", seconds.isFinite, seconds >= 0 else { return nil }
        if let duration = item.metadata?.duration, duration.isFinite, seconds >= duration { return nil }
        return seconds
    }
    func match(_ query: MediaSearchQuery, scope: MediaSearchScope, location: MediaLocation?) -> [MediaSearchHit]? {
        guard !query.isEmpty else { return [] }
        var candidates = fields
        if let location { candidates.append(.init(.folder, "Folder", location.folder, priority: 40)) }
        candidates = candidates.filter { scope == .all || $0.scope == scope }
        // All keywords must occur in this file, but may match different fields.
        guard query.terms.allSatisfy({ term in candidates.contains { $0.folded.contains(term) } }) else { return nil }
        return candidates.enumerated().compactMap { index, field in
            guard query.terms.contains(where: { field.folded.contains($0) }) else { return nil }
            return MediaSearchHit(id: index, label: field.label, text: field.text, start: field.start, segmentID: field.segmentID, priority: field.priority)
        }.sorted { $0.priority == $1.priority ? $0.id < $1.id : $0.priority > $1.priority }
    }
}

struct MediaSearchResult: Identifiable {
    var item: MediaItem
    var hits: [MediaSearchHit]
    var id: String { item.id }
    var score: Int { (hits.first?.priority ?? 0) + min(hits.count, 3) }
}
