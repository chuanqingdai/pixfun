import Foundation
import NaturalLanguage

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
        case .all: return "Names, analysis tags, descriptions, shots, transcripts, editing notes, places, devices and folder paths. Click a material tag to search for similar footage."
        case .name: return "Original filenames and saved titles."
        case .content: return "Saved analysis tags, descriptions, subjects, actions, reactions, framing, camera movement and described sounds."
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
        for tag in item.searchTags {
            fields.append(.init(tag.scope, "Tag", tag.text, priority: 65))
        }
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

struct MediaSearchTag: Identifiable {
    let text: String
    let scope: MediaSearchScope
    let symbol: String
    var id: String { MediaSearchQuery.fold(text) }
}

extension MediaItem {
    /// Compact content chips, not repeated editorial classifications. Older imports
    /// can reuse their saved descriptions without another vision-model request.
    var contentTags: [MediaSearchTag] {
        let shots = segments.compactMap(\.editorial)
        let technical = Set(shots.flatMap { [$0.shot_size, $0.camera_motion, $0.capture_type] + $0.story_role }.map(MediaSearchQuery.fold))
        let saved = (analysisTags ?? []).filter {
            !technical.contains(MediaSearchQuery.fold($0)) && !MediaContentTags.generic.contains(MediaSearchQuery.fold($0))
        }
        let observations = ([displayVideoDescription?.full_description, description, shotAnalysis?.summary].compactMap { $0 }
                            + shots.map(\.description)).joined(separator: "\n")
        let extracted = MediaContentTags.extract(observations)
        return MediaContentTags.normalized((saved + extracted).map { .init(text: $0, scope: .content, symbol: "number") })
    }

    /// Only saved model observations and structured editorial fields; no guessed metadata.
    var searchTags: [MediaSearchTag] {
        var tags = contentTags + (analysisTags ?? []).map { MediaSearchTag(text: $0, scope: .content, symbol: "number") }
        let shots = segments.compactMap(\.editorial)
        // Interleave categories, so one long list of shot sizes cannot hide all movement/roles.
        for shot in shots {
            tags.append(.init(text: shot.shot_size, scope: .content, symbol: "viewfinder"))
            tags.append(.init(text: shot.camera_motion, scope: .content, symbol: "video"))
            tags += shot.story_role.map { .init(text: $0, scope: .editing, symbol: "scissors") }
            tags.append(.init(text: shot.capture_type, scope: .content, symbol: "camera"))
        }
        if shots.contains(where: \.isHighlight) { tags.append(.init(text: "Highlight", scope: .editing, symbol: "sparkles")) }
        return MediaContentTags.normalized(tags)
    }
}

/// Local linguistic extraction: every chip is an unchanged phrase from saved
/// analysis, never a new model inference, translation, or inferred location.
enum MediaContentTags {
    static let generic: Set<String> = ["highlight", "action", "reaction", "transition", "establishing", "recommended", "keep", "wide shot", "medium shot", "close-up", "static", "tracking", "following", "panning right", "panning left", "pan right", "pan left", "handheld", "推荐", "动作", "转场", "全景", "跟拍", "特写"]
    private static let boilerplate: Set<String> = ["camera", "shot", "scene", "video", "image", "photo", "footage", "frame", "view", "perspective", "movement", "motion", "pan", "push", "tracking", "panning", "background", "foreground", "distance", "side", "left", "right", "front", "moment", "sequence", "time", "second", "seconds", "vocalization", "dialogue", "audio", "sound", "composition", "镜头", "画面", "视频", "照片", "背景", "前景", "运镜"]
    private static let cache: NSCache<NSString, NSArray> = {
        let result = NSCache<NSString, NSArray>(); result.countLimit = 512; return result
    }()

    static func extract(_ description: String) -> [String] {
        // Bound work for long analyses; the cache key includes the actual content,
        // so a completed/revised analysis immediately replaces earlier tags.
        let text = String(description.prefix(6000))
        guard !text.isEmpty else { return [] }
        if let result = cache.object(forKey: text as NSString) { return result.compactMap { $0 as? String } }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        var candidates: [(text: String, score: Int)] = []
        // Negated/uncertain clauses are deliberately omitted rather than turning
        // "no people or boats" into misleading positive tags.
        // Keep quoted dialogue/sign text searchable in the full description,
        // but do not turn fragments of it into claims about visible subjects.
        let visualText = text.replacingOccurrences(of: #"(?<!\w)'[^'\n]+'(?!\w)|"[^"\n]+"|“[^”\n]+”|\([^\)\n]*\)"#, with: " ", options: .regularExpression)
        let clauses = visualText.components(separatedBy: CharacterSet(charactersIn: ".!?;,\n。！？；，"))
        for clause in clauses where !clause.isEmpty {
            let folded = MediaSearchQuery.fold(clause)
            if folded.range(of: #"\b(no|not|without|neither|maybe|perhaps|possibly)\b|没有|未见|无人|可能|并非"#, options: .regularExpression) != nil { continue }
            tagger.string = clause
            var words: [(text: String, noun: Bool)] = []
            func flush() {
                defer { words = [] }
                while words.last?.noun == false { words.removeLast() }
                guard words.contains(where: { $0.noun }) else { return }
                // Retain the noun and its nearest modifiers, not a whole sentence.
                let phrase = Array(words.suffix(3))
                let chinese = phrase.contains { $0.text.range(of: #"\p{Han}"#, options: .regularExpression) != nil }
                let label = phrase.map(\.text).joined(separator: chinese ? "" : " ")
                guard label.count >= 2, label.count <= 28 else { return }
                // "a calm body of water" must not become the misleading chip
                // "calm body" when the preposition closes the noun phrase.
                if ["body", "kind", "type", "part", "sense", "word", "words", "speaker", "day", "beginning", "end", "lighting"].contains(MediaSearchQuery.fold(phrase.last?.text ?? "")) { return }
                let nouns = phrase.filter(\.noun).count
                candidates.append((label, min(phrase.count, 2) + (nouns > 1 ? 2 : 0)))
            }
            tagger.enumerateTags(in: clause.startIndex..<clause.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace]) { tag, range in
                let word = String(clause[range])
                let key = MediaSearchQuery.fold(word)
                // Some short camera clauses tag "tracks"/"captures" as nouns.
                let cameraVerb = ["tracks", "pans", "captures", "moves", "follows", "reveals"].contains(key)
                if (tag == .noun || tag == .adjective), !cameraVerb, !boilerplate.contains(key), !generic.contains(key), word.count > 1 {
                    words.append((word, tag == .noun))
                } else { flush() }
                return true
            }
            flush()
        }
        let ordered = candidates.enumerated().sorted { $0.element.score == $1.element.score ? $0.offset < $1.offset : $0.element.score > $1.element.score }
        var seen = Set<String>()
        var result: [String] = []
        for candidate in ordered {
            let key = MediaSearchQuery.fold(candidate.element.text)
            guard !generic.contains(key), seen.insert(key).inserted else { continue }
            // Avoid both "coffee cup" and "cup" taking up chip space.
            if result.contains(where: { MediaSearchQuery.fold($0).hasSuffix(" " + key) }) { continue }
            result.append(candidate.element.text)
            if result.count == 8 { break }
        }
        cache.setObject(result as NSArray, forKey: text as NSString)
        return result
    }

    static func normalized(_ tags: [MediaSearchTag]) -> [MediaSearchTag] {
        var seen = Set<String>()
        let empty = Set(["unknown", "none", "n/a", "unspecified", "not applicable", "未知", "无"])
        return tags.compactMap { tag in
            let text = tag.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let key = MediaSearchQuery.fold(text)
            guard text.count >= 2, text.count <= 48, !empty.contains(key), seen.insert(key).inserted else { return nil }
            return MediaSearchTag(text: text, scope: tag.scope, symbol: tag.symbol)
        }
    }
}

struct MediaSearchResult: Identifiable {
    var item: MediaItem
    var hits: [MediaSearchHit]
    var id: String { item.id }
    var score: Int { (hits.first?.priority ?? 0) + min(hits.count, 3) }
}
