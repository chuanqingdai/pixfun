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
    var quickTags: [MediaFacetTag]
    init(_ item: MediaItem) {
        quickTags = MediaQuickTags.tags(item)
        fields = [
            .init(.name, "Title", item.name, priority: 100),
            .init(.name, "Filename", item.file.name, priority: 100),
            .init(.content, "Suggested title", item.displayVideoDescription?.title, priority: 80),
            .init(.content, "Description", item.displayVideoDescription?.full_description, priority: 80),
            .init(.content, "Description", item.description, priority: 80),
            .init(.content, "Video summary", item.shotAnalysis?.summary, priority: 80),
            .init(.context, "Location", item.recordedLocation, priority: 75),
            .init(.context, "Recorded coordinates", item.metadata?.location?.coordinates, priority: 70),
            .init(.context, "Device", item.context?["device"], priority: 65)
        ]
        for tag in item.searchTags {
            fields.append(.init(tag.scope, "Tag", tag.text, priority: 65))
        }
        for tag in item.evidenceTags {
            let text = ([tag.label] + tag.aliases).joined(separator: " · ")
            if tag.evidence.isEmpty { fields.append(.init(.content, "User tag", text, priority: 65)) }
            for ref in tag.evidence {
                fields.append(.init(.content, "Observed tag", text, start: Self.safeTime(ref.start, item: item), segmentID: ref.shotIds.first, priority: 86))
            }
        }
        for segment in item.segments {
            let time = Self.safeTime(segment.start, item: item)
            fields.append(.init(.content, "Shot", segment.label, start: time, segmentID: segment.id, priority: 85))
            guard let shot = segment.editorial else { continue }
            fields.append(.init(.content, "Shot description", shot.description, start: time, segmentID: segment.id, priority: 90))
            fields.append(.init(.content, "Framing & movement", [shot.shot_size, shot.capture_type, shot.camera_motion, CameraMotionLabel.display(shot.camera_motion, chinese: true)].joined(separator: " · "), start: time, segmentID: segment.id))
            fields.append(.init(.content, "Reaction", shot.reaction, start: time, segmentID: segment.id))
            fields.append(.init(.content, "Described sound", shot.audio.joined(separator: " · "), start: time, segmentID: segment.id))
            fields.append(.init(.content, "Model-reported dialogue", shot.dialogue, start: time, segmentID: segment.id))
            let edit = (shot.story_role + [shot.edit_recommendation.level, shot.edit_recommendation.reason] + (shot.isHighlight ? ["Highlight"] : [])).joined(separator: " · ")
            fields.append(.init(.editing, "Editing suggestion", edit, start: time, segmentID: segment.id, priority: 70))
        }
        for cue in item.transcriptCues {
            fields.append(.init(.transcript, "Transcript", cue.text, start: Self.safeTime(cue.start, item: item), priority: 88))
        }
        for text in item.analysisEvidence?.onScreenText ?? [] {
            fields.append(.init(.content, "On-screen text", text.text, start: Self.safeTime(text.start, item: item), priority: 80))
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

/// Display/search aliases only: keep original model evidence and tag IDs intact.
/// A '+' lists motions; only an explicit 'then' implies their order.
enum CameraMotionLabel {
    private static let chinese: [String: String] = [
        "pushing in": "向前推进", "push in": "向前推进", "dolly in": "向前推进",
        "pulling out": "向后拉远", "pull out": "向后拉远", "dolly out": "向后拉远",
        "horizontal pan right": "向右摇镜", "horizontal panning right": "向右摇镜",
        "panning right": "向右摇镜", "pan right": "向右摇镜",
        "horizontal pan left": "向左摇镜", "horizontal panning left": "向左摇镜",
        "panning left": "向左摇镜", "pan left": "向左摇镜",
        "panning": "水平摇镜", "horizontal pan": "水平摇镜", "slow pan": "缓慢摇镜",
        "tilt up": "向上摇镜", "tilting up": "向上摇镜",
        "tilt down": "向下摇镜", "tilting down": "向下摇镜",
        "zoom in": "变焦放大", "zooming in": "变焦放大",
        "zoom out": "变焦缩小", "zooming out": "变焦缩小",
        "following": "跟随拍摄", "tracking": "跟拍", "tracking shot": "跟拍",
        "static": "固定机位", "stationary": "固定机位", "minimal movement": "轻微运动",
        "handheld": "手持拍摄", "orbit": "环绕拍摄", "orbiting": "环绕拍摄"
    ]
    static func display(_ value: String, chinese enabled: Bool) -> String {
        guard enabled else { return value }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = text.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if let translated = chinese[key] { return translated }
        let ordered = text.replacingOccurrences(of: #"\s+then\s+|\s*→\s*"#, with: "\n", options: [.regularExpression, .caseInsensitive]).components(separatedBy: "\n")
        if ordered.count > 1 { return ordered.map { display($0, chinese: true) }.joined(separator: " → ") }
        let parts = text.replacingOccurrences(of: #"\s*[+&·;,]\s*|\s+and\s+"#, with: "\n", options: [.regularExpression, .caseInsensitive]).components(separatedBy: "\n")
        if parts.count > 1 { return parts.map { display($0, chinese: true) }.joined(separator: " · ") }
        return value // Unknown or already Chinese: do not guess a different motion.
    }
}

extension MediaItem {
    /// Compact content chips, not repeated editorial classifications. Older imports
    /// can reuse their saved descriptions without another vision-model request.
    var contentTags: [MediaSearchTag] {
        if hasStructuredTags {
            return evidenceTags.filter { $0.category == "detail" }.map { .init(text: $0.label, scope: .content, symbol: "number") }
        }
        let shots = segments.compactMap(\.editorial)
        let technical = Set(shots.flatMap { [$0.shot_size, $0.camera_motion, $0.capture_type] + $0.story_role }.map(MediaSearchQuery.fold))
        let saved = (analysisTags ?? []).filter {
            !technical.contains(MediaSearchQuery.fold($0)) && MediaTagPresentation.isContent($0)
        }
        let observations = ([displayVideoDescription?.full_description, description, shotAnalysis?.summary].compactMap { $0 }
                            + shots.map(\.description)).joined(separator: "\n")
        let extracted = MediaContentTags.extract(observations)
        return MediaContentTags.normalized((saved + extracted).map { .init(text: $0, scope: .content, symbol: "number") })
    }

    /// Only saved model observations and structured editorial fields; no guessed metadata.
    var searchTags: [MediaSearchTag] {
        var tags = contentTags + (hasStructuredTags ? evidenceTags.map(\.label) : (analysisTags ?? [])).map { MediaSearchTag(text: $0, scope: .content, symbol: "number") }
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

struct MediaDetailTagGroup: Identifiable {
    let title: String
    let symbol: String
    let tags: [MediaSearchTag]
    var id: String { title }
}

/// Presentation-only ranking of saved evidence, never additional inference.
enum MediaTagPresentation {
    static func isContent(_ text: String) -> Bool {
        let key = MediaSearchQuery.fold(text)
        return !MediaContentTags.generic.contains(key) && !["static shot", "wide angle", "video", "photo", "scene", "footage"].contains(key)
            && key.range(of: #"\b(no|not|without|unknown|uncertain|possibly|maybe)\b|未见|没有|未知|可能|无法确认"#, options: .regularExpression) == nil
    }
    static func content(_ item: MediaItem) -> [MediaSearchTag] {
        MediaContentTags.normalized(item.contentTags.filter { isContent($0.text) })
    }
    /// A small display selection only. Full evidence remains in the search index.
    static func visualDetails(_ item: MediaItem) -> [MediaSearchTag] {
        let redundant: Set<String> = ["river", "lake", "mountain", "mountains", "people", "person", "plants", "trees", "vegetation", "cars", "vehicles", "road", "natural landscape", "landscape", "key change", "opening view", "editing note", "verification note", "trees along bank", "河流", "湖泊", "山地", "人物", "植物", "车辆", "关键变化", "开场画面"]
        let families = [
            #"\b(sky|skies)\b|天空|蓝天"#,
            #"\b(shore|shoreline|riverbank|bank)\b|河岸|岸边"#,
            #"\b(utility|power|electricity) (lines?|wires?)\b|电线|输电线"#,
            #"\b(stone|retaining) wall\b|石墙|护岸"#,
            #"\bparked (cars?|vehicles?)\b|停放.*车"#
        ]
        var chosen: [MediaSearchTag] = [], positions: [String: Int] = [:]
        for tag in content(item) {
            let key = MediaSearchQuery.fold(tag.text)
            guard !redundant.contains(key), key.split(separator: " ").count <= 4,
                  key.range(of: #"\b(background|foreground|stretch|change|note|view|standing|flowing)\b|背景|前景|说明"#, options: .regularExpression) == nil else { continue }
            let family = families.firstIndex { key.range(of: $0, options: .regularExpression) != nil }
            let identity = family.map { "family:\($0)" } ?? key
            if let index = positions[identity] {
                // Keep a concise original phrase, never an invented synonym.
                if tag.text.count < chosen[index].text.count { chosen[index] = tag }
            } else {
                positions[identity] = chosen.count; chosen.append(tag)
            }
        }
        return Array(chosen.prefix(6))
    }
    static func frequencies(_ items: [MediaItem]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for item in items {
            for key in Set(MediaQuickTags.tags(item).map(\.id)) { counts[key, default: 0] += 1 }
        }
        return counts
    }
    static func core(_ item: MediaItem, frequencies: [String: Int]) -> [MediaFacetTag] {
        let tags = MediaQuickTags.tags(item)
        // Same IDs and labels as the toolbar. Rarity only chooses between
        // supported tags within one category; it never invents a new label.
        func best(_ facet: MediaFacet) -> MediaFacetTag? {
            if facet == .subject { return tags.first { $0.facet == .subject } }
            return tags.filter { $0.facet == facet }.sorted {
                let a = frequencies[$0.id, default: 1], b = frequencies[$1.id, default: 1]
                return a == b ? $0.text.localizedStandardCompare($1.text) == .orderedAscending : a < b
            }.first
        }
        let candidates = [best(.location) ?? best(.scene), best(.activity), best(.subject), best(.scene)].compactMap { $0 }
        var texts = Set<String>(), facets = Set<MediaFacet>()
        return Array(candidates.filter {
            guard !facets.contains($0.facet), !texts.contains(MediaSearchQuery.fold($0.text)) else { return false }
            facets.insert($0.facet); texts.insert(MediaSearchQuery.fold($0.text)); return true
        }.prefix(3))
    }
    static func detailGroups(_ item: MediaItem) -> [MediaDetailTagGroup] {
        let shots = item.segments.compactMap(\.editorial)
        func group(_ title: String, _ symbol: String, _ values: [String], scope: MediaSearchScope = .content) -> MediaDetailTagGroup {
            .init(title: title, symbol: symbol, tags: MediaContentTags.normalized(values.map { .init(text: $0, scope: scope, symbol: symbol) }))
        }
        return [group("Framing", "viewfinder", shots.map(\.shot_size)),
                group("Movement", "video", shots.map(\.camera_motion))]
            .filter { !$0.tags.isEmpty }
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

enum MediaFacet: String, CaseIterable, Hashable {
    case location = "Location", scene = "Scene", subject = "Subject", activity = "Activity"
    var symbol: String {
        switch self {
        case .location: return "mappin.and.ellipse"
        case .scene: return "mountain.2"
        case .subject: return "person.crop.rectangle"
        case .activity: return "figure.walk"
        }
    }
    var help: String {
        self == .location ? "Saved locations only; scene descriptions are not treated as shooting locations."
            : "Common tags from saved visual analysis. Filtering never starts a new analysis."
    }
}

struct MediaFacetTag: Identifiable, Hashable {
    var facet: MediaFacet
    var key: String
    var text: String
    var id: String { facet.rawValue + ":" + key }
}

struct MediaFacetOption: Identifiable {
    var tag: MediaFacetTag
    var count: Int
    var id: String { tag.id }
}

struct MediaFacetSelection {
    var values: [MediaFacet: MediaFacetTag] = [:]
    var isEmpty: Bool { values.isEmpty }
    func matches(_ tags: [MediaFacetTag], excluding: MediaFacet? = nil) -> Bool {
        values.allSatisfy { facet, selected in facet == excluding || tags.contains { $0.id == selected.id } }
    }
    /// Count files, not occurrences. Keep a selected zero-result option so it can
    /// always be cleared; never silently broaden the user's selection.
    func options(for facet: MediaFacet, documents: [MediaSearchDocument]) -> [MediaFacetOption] {
        var options: [String: MediaFacetOption] = [:]
        for document in documents where matches(document.quickTags, excluding: facet) {
            for tag in document.quickTags where tag.facet == facet {
                if options[tag.id] != nil { options[tag.id]!.count += 1 }
                else { options[tag.id] = .init(tag: tag, count: 1) }
            }
        }
        if let selected = values[facet], options[selected.id] == nil {
            options[selected.id] = .init(tag: selected, count: 0)
        }
        return options.values.sorted {
            $0.count == $1.count ? $0.tag.text.localizedStandardCompare($1.tag.text) == .orderedAscending : $0.count > $1.count
        }
    }
}

/// Small, evidence-backed vocabulary instead of exposing every detected object.
/// Aliases group common English/Chinese observations; they never infer a city,
/// identity, relationship, mood or activity from filenames, dialogue or edit advice.
enum MediaQuickTags {
    /// Cards have one compact tag group. A saved place takes the scene slot;
    /// all scene tags remain available in the full search/filter document.
    static func cardTags(_ tags: [MediaFacetTag]) -> [MediaFacetTag] {
        let place = tags.first { $0.facet == .location } ?? tags.first { $0.facet == .scene }
        let candidates = [place, tags.first { $0.facet == .activity }, tags.first { $0.facet == .subject }].compactMap { $0 }
        var seen = Set<String>()
        return Array(candidates.filter { seen.insert(MediaSearchQuery.fold($0.text)).inserted }.prefix(2))
    }

    private struct Rule {
        var tag: MediaFacetTag
        var expression: NSRegularExpression
        init(_ facet: MediaFacet, _ key: String, _ text: String, _ aliases: String) {
            tag = .init(facet: facet, key: key, text: text)
            expression = try! NSRegularExpression(pattern: aliases, options: [.caseInsensitive])
        }
    }
    private static let rules: [Rule] = [
        .init(.scene, "water", "Lakes & rivers", #"\b(lakes?|lakeside|rivers?|riverside|wetlands?|ponds?)\b|湖泊|湖边|湖畔|河流|河边|湿地|池塘"#),
        .init(.scene, "mountain", "Mountains", #"\b(mountains?|mountainside|hills?|hillside|mountaintop)\b|山地|山林|山峰|山顶|山景|群山|山坡"#),
        .init(.scene, "coast", "Coast & beach", #"\b(beach(?:es)?|coast|coastal|seaside|ocean|sea)\b|海边|海岸|沙滩|海滩|大海"#),
        .init(.scene, "park", "Parks & gardens", #"\b(parks?|gardens?)\b|公园|花园|园林"#),
        .init(.scene, "forest", "Forest", #"\b(forests?|woodlands?|woods)\b|森林|树林|竹林"#),
        .init(.scene, "city", "Streets & city", #"\b(streets?|city|cities|urban|skyline|town|downtown)\b|街道|街头|城市|市区|小镇"#),
        .init(.scene, "indoor", "Indoors", #"\b(indoors?|interior|bedroom|living room|kitchen)\b|室内|卧室|客厅|厨房"#),
        .init(.scene, "dining", "Cafés & restaurants", #"\b(caf[eé]s?|restaurants?|cafeteria)\b|咖啡馆|餐厅|餐馆|饭店"#),
        .init(.subject, "people", "People", #"\b(people|persons?|boys?|girls?|men|women|man|woman|children|child|travelers?|travellers?|hikers?|cyclists?)\b|人物|人群|男孩|女孩|孩子|儿童|男子|女子|游客|行人|骑行者|的人"#),
        .init(.subject, "animals", "Animals", #"\b(animals?|dogs?|cats?|birds?|swans?|ducks?|squirrels?|horses?)\b|动物|小狗|小猫|鸟类|天鹅|鸭子|松鼠|马匹"#),
        .init(.subject, "food", "Food & drinks", #"\b(food|meals?|dishes|coffee|tea|drinks?|desserts?|cakes?|noodles|bread)\b|食物|美食|饮料|咖啡|甜点|蛋糕|面条|面包"#),
        .init(.subject, "buildings", "Buildings", #"\b(buildings?|architecture|temples?|pavilions?|gazebos?|bridges?|towers?|houses?|fountains?)\b|建筑|寺庙|亭子|楼房|桥梁|房屋|喷泉"#),
        .init(.subject, "landscape", "Scenery", #"\b(landscape|scenery|sunset|sunrise|waterfalls?|lakes?|mountains?)\b|风景|日落|日出|瀑布|湖泊|群山"#),
        .init(.subject, "plants", "Plants", #"\b(plants?|trees?|flowers?|blossoms?|grass|grassy)\b|植物|树木|柳树|花朵|鲜花|草地|草坪"#),
        .init(.subject, "vehicles", "Vehicles", #"\b(cars?|buses|trains?|boats?|bicycles?|bikes?|airplanes?)\b|汽车|公交车|火车|船只|自行车|飞机"#),
        .init(.activity, "walking", "Walking & hiking", #"\b(walk(?:s|ing)?|hik(?:e|es|ing)|stroll(?:s|ing)?|hikers?)\b|步行|散步|徒步|行走|走路"#),
        .init(.activity, "cycling", "Cycling", #"\b(cycling|cyclists?|biking|riding (?:a |the )?(?:bike|bicycle))\b|骑行|骑车|骑自行车"#),
        .init(.activity, "running", "Running", #"\b(running|jogging|jogs)\b|跑步|慢跑|奔跑"#),
        .init(.activity, "dining", "Eating & drinking", #"\b(eating|drinking|sipping|tasting)\b|吃饭|用餐|品尝|喝茶|喝咖啡|喝水"#),
        .init(.activity, "posing", "Posing", #"\b(posing|poses|peace sign|waving)\b|摆拍|摆姿势|比耶|挥手"#),
        .init(.activity, "swimming", "Swimming", #"\b(swimming|swims)\b|游泳"#)
    ]

    static func tags(_ item: MediaItem) -> [MediaFacetTag] {
        var result: [MediaFacetTag] = []
        if let value = item.locationGroup?.split(whereSeparator: \.isWhitespace).joined(separator: " "),
           !value.isEmpty, !["unknown", "none", "n/a", "unspecified", "未知", "无"].contains(MediaSearchQuery.fold(value)) {
            result.append(.init(facet: .location, key: MediaSearchQuery.fold(item.locationGroupKey ?? value), text: value))
        }
        if item.hasStructuredTags {
            return limitSubjects(result + item.evidenceTags.compactMap { tag in
                guard let facet = tag.facet else { return nil }
                return .init(facet: facet, key: tag.key, text: tag.label)
            }, item: item)
        }
        let observations = (item.analysisTags ?? []) + [item.description, item.displayVideoDescription?.full_description, item.shotAnalysis?.summary].compactMap { $0 }
            + item.segments.compactMap { $0.editorial?.description }
        let evidence = observations.map { positiveVisualText($0) }.joined(separator: "\n")
        let range = NSRange(evidence.startIndex..<evidence.endIndex, in: evidence)
        result += rules.filter { $0.expression.firstMatch(in: evidence, range: range) != nil }.map(\.tag)
        return limitSubjects(result, item: item)
    }

    private static func limitSubjects(_ tags: [MediaFacetTag], item: MediaItem) -> [MediaFacetTag] {
        // The engine owns focus selection. User corrections override it. Legacy
        // inventories remain searchable, but are not a main-subject vote.
        let corrected = item.evidenceTags.filter { $0.category == "subject" && $0.source == "user" }
        let explicit = corrected.isEmpty ? item.evidenceTags.filter { $0.category == "subject" && $0.source == "visual-primary-subject" } : corrected
        let summary = item.shotAnalysis?.summary ?? item.displayVideoDescription?.full_description ?? item.description ?? ""
        let boundary = summary.range(of: "[，,。.!?！？;；\\n]|背景|远处|background|in the distance", options: [.regularExpression, .caseInsensitive])
        let head = positiveVisualText(boundary.map { String(summary[..<$0.lowerBound]) } ?? summary)
        let range = NSRange(head.startIndex..., in: head)
        let hidden = Set(item.tagCorrections?.hidden ?? [])
        func legacyCandidates(_ facet: MediaFacet) -> [MediaFacetTag] {
            rules.filter { $0.tag.facet == facet
                && $0.expression.firstMatch(in: head, range: range) != nil }.map(\.tag)
        }
        let selected: [String]
        if !explicit.isEmpty {
            var seen = Set<String>()
            selected = Array(explicit.map(\.key).filter { seen.insert($0).inserted }.prefix(2))
        } else if item.hasFocusContract {
            selected = [] // Explicit abstention is not permission to guess from keywords.
        } else {
            let candidates = legacyCandidates(.subject)
            selected = candidates.count == 1 ? candidates.map(\.key).filter { !hidden.contains("subject:"+$0) } : []
        }
        let subjects = selected.compactMap { key in tags.first { $0.facet == .subject && $0.key == key }
            ?? rules.first { $0.tag.facet == .subject && $0.tag.key == key }?.tag }
        var actions = item.evidenceTags.filter { tag in
            tag.category == "activity" && (tag.source == "user" || corrected.isEmpty && tag.source == "visual-primary-activity"
                && tag.evidence.contains { $0.subject.map { selected.contains($0) } == true })
        }.map { MediaFacetTag(facet: .activity, key: $0.key, text: $0.label) }
        if actions.isEmpty && !item.hasFocusContract && explicit.isEmpty && selected.count == 1 {
            let candidates = legacyCandidates(.activity)
            if candidates.count == 1 { actions = candidates.filter { !hidden.contains("activity:"+$0.key) } }
        }
        return tags.filter { $0.facet != .subject && $0.facet != .activity } + subjects + actions
    }

    private static func positiveVisualText(_ text: String) -> String {
        let visual = String(text.prefix(6000)).replacingOccurrences(of: #"(?<!\w)'[^'\n]+'(?!\w)|"[^"\n]+"|“[^”\n]+”|「[^」\n]+」|\([^\)\n]*\)"#, with: " ", options: .regularExpression)
        return visual.components(separatedBy: CharacterSet(charactersIn: ".!?;,\n。！？；，")).filter {
            $0.range(of: #"\b(no|not|without|neither|maybe|perhaps|possibly|might|could|unseen|says|said|spoken|dialogue|voiceover)\b|没有|未见|无人|可能|并非|字幕|旁白|说到|提到"#, options: [.regularExpression, .caseInsensitive]) == nil
        }.joined(separator: "\n")
    }
}
