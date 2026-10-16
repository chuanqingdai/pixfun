import Foundation

struct MediaFile: Codable { var name: String; var size: Int64?; var type: String? }
struct Metadata: Codable {
    var width: Double?; var height: Double?; var duration: Double?; var fps: Double?; var hasAudio: Bool?
    var capturedAt: String? = nil
    var camera: String? = nil
    var location: CaptureLocation? = nil
    var videoCodec: String? = nil
    var audioCodec: String? = nil
    var mediaCreatedAt: String? = nil
    var dateSource: String? = nil
    var frameRateLabel: String? {
        guard let fps, fps.isFinite, fps > 0 else { return nil }
        return fps.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))) + " fps"
    }
    static func codecLabel(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !["unknown", "none", "n/a"].contains(value.lowercased()) else { return nil }
        switch value.lowercased() {
        case "hevc", "h265": return "HEVC (H.265)"
        case "h264": return "H.264"
        case "aac": return "AAC"
        case "prores": return "Apple ProRes"
        default: return value.uppercased()
        }
    }
    var captureDate: Date? {
        guard let capturedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: capturedAt) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: capturedAt)
    }
}
struct CaptureLocation: Codable {
    var name: String?; var latitude: Double?; var longitude: Double?; var altitude: Double?; var source: String?
    // Native local-cache overlay; never written into the source file or model evidence.
    var resolvedName: String? = nil
    var coordinates: String? {
        guard let latitude, let longitude, latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return String(format: "%.5f, %.5f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }
    var label: String? { name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? name : (resolvedName ?? coordinates) }
}
struct Segment: Codable, Identifiable {
    var id: String; var label: String; var start: Double; var end: Double
    var thumbnailUrl: String?; var note: String?; var boundary: Boundary?
    var editorial: EditorialShot?
    var assessments: ShotAssessments? = nil
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
    var conciseDescription: String { ShotReadingText.summary(description) }
    // Editorial recommendation, not a claim of verified technical image quality.
    var isHighlight: Bool {
        importance_score.isFinite && importance_score >= 80 && importance_score <= 100
            && ["Keep", "Recommended", "必留", "推荐"].contains(edit_recommendation.level)
            && edit_recommendation.recommended_duration_sec > 0
            && !duplicate_candidate && !unusable_candidate
    }
}

/// Presentation excerpt, not a rewrite of saved model evidence.
enum ShotReadingText {
    static func summary(_ source: String, limit: Int = 180) -> String {
        let text = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { return "No shot description yet." }
        let end = text.range(of: #"[。！？]|[.!?](?=\s|$)"#, options: .regularExpression)?.upperBound ?? text.endIndex
        let sentence = String(text[..<end])
        guard sentence.count > limit else { return sentence }
        var prefix = String(sentence.prefix(max(1, limit - 1)))
        if let space = prefix.lastIndex(of: " "), prefix.distance(from: prefix.startIndex, to: space) > limit / 2 {
            prefix = String(prefix[..<space])
        }
        return prefix + "…"
    }
}
struct ShotAnalysis: Codable {
    var status: String; var message: String?; var summary: String?; var segments: [Segment]?; var limitations: [String]?
    var revision: String? = nil
    var tags: [EvidenceTag]? = nil
    var focusVersion: Int? = nil
    var busy: Bool { ["queued", "running"].contains(status) }
}
struct Cue: Codable { var start: Double; var end: Double?; var text: String }
struct Analysis: Codable {
    var segments: [Segment]?; var subtitleCues: [Cue]?; var subtitleMessage: String?; var subtitleState: String?
    var subtitleSource: String? = nil
    var subtitleLanguage: String? = nil
}
struct MediaResult: Codable { var analysis: Analysis? }
struct VideoDescription: Codable {
    var status: String; var message: String?
    var title: String?; var full_description: String?; var coverage: String?; var model: String?
    var shotRevision: String? = nil
    var busy: Bool { ["queued", "running"].contains(status) }
    var readingBlocks: [VideoDescriptionBlock] { VideoDescriptionBlock.parse(full_description ?? "") }
    var contentBlocks: [VideoDescriptionBlock] { readingBlocks.filter { !$0.isEditingAdvice } }
    var editingNotes: [VideoDescriptionBlock] { readingBlocks.filter(\.isEditingAdvice) }
}

/// Presentation only: preserve stored analysis and never infer shot boundaries.
struct VideoDescriptionBlock: Equatable {
    enum Kind { case overview, moment, note, paragraph }
    var kind: Kind
    var text: String
    var number: String? = nil
    var label: String? = nil
    var isEditingAdvice: Bool { kind == .note && label?.lowercased() == "editing note" }

    static func parse(_ source: String) -> [Self] {
        let numbered = try! NSRegularExpression(pattern: #"^(\d{1,2})[.)、]\s*(.+)$"#)
        let note = try! NSRegularExpression(pattern: #"^(Editing note|Verification note|核验说明|核实说明)[：:]\s*(.+)$"#, options: .caseInsensitive)
        var blocks: [Self] = []
        var paragraph = ""
        func appendParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(Self(kind: blocks.isEmpty ? .overview : .paragraph, text: paragraph))
            paragraph = ""
        }
        for raw in source.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { appendParagraph(); continue }
            let range = NSRange(line.startIndex..., in: line)
            if let match = numbered.firstMatch(in: line, range: range),
               let n = Range(match.range(at: 1), in: line), let body = Range(match.range(at: 2), in: line) {
                appendParagraph()
                var block = Self(kind: .moment, text: String(line[body]), number: String(line[n]))
                if let colon = block.text.firstIndex(where: { $0 == ":" || $0 == "：" }), block.text.distance(from: block.text.startIndex, to: colon) <= 48,
                   block.text[..<colon].contains(where: { $0.isLetter }) {
                    block.label = String(block.text[..<colon])
                    block.text = String(block.text[block.text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                }
                blocks.append(block)
            } else if let match = note.firstMatch(in: line, range: range),
                      let label = Range(match.range(at: 1), in: line), let body = Range(match.range(at: 2), in: line) {
                appendParagraph()
                blocks.append(Self(kind: .note, text: String(line[body]), label: String(line[label])))
            } else if paragraph.isEmpty, let last = blocks.last, last.kind == .moment || last.kind == .note {
                // A wrapped line is still part of the preceding numbered item/note.
                blocks[blocks.count - 1].text += " " + line
            } else {
                paragraph += (paragraph.isEmpty ? "" : " ") + line
            }
        }
        appendParagraph()
        // Legacy single-paragraph results become readable paragraphs, not invented shots.
        if blocks.count == 1, blocks[0].text.count > 280, blocks[0].kind == .overview {
            let text = blocks[0].text
            let boundary = try! NSRegularExpression(pattern: #"(?<=[.!?。！？])\s+(?=[A-Z\p{Han}])"#)
            let separated = boundary.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n")
            let sentences = separated.components(separatedBy: "\n")
            if sentences.count > 1 {
                blocks = [Self(kind: .overview, text: sentences[0])]
                for start in stride(from: 1, to: sentences.count, by: 2) {
                    blocks.append(Self(kind: .paragraph, text: sentences[start..<min(start + 2, sentences.count)].joined(separator: " ")))
                }
            }
        }
        return blocks
    }
}
struct MediaAnalysisState: Codable {
    var status: String
    var message: String?
    var attempt: Int? = nil
    var maxAttempts: Int? = nil
    var nextRetryAt: Double? = nil
    var stage: String? = nil
}
struct ShotAssessments: Codable {
    struct Estimate: Codable { var status: String; var value: Double?; var reason: String?; var source: String? }
    struct Metric: Codable, Identifiable { var key: String; var value: Double; var samples: Int; var id: String { key } }
    struct Technical: Codable { var status: String; var metrics: [Metric]; var source: String; var scope: String }
    var editorial: Estimate; var technical: Technical; var aesthetic: Estimate; var projectRelevance: Estimate
}
struct EvidenceTag: Codable, Identifiable {
    struct Reference: Codable {
        var start: Double; var end: Double; var shotIds: [String]; var text: String
        var subject: String? = nil
        var subjectDescription: String? = nil
    }
    var id: String; var category: String; var key: String; var label: String
    var aliases: [String]; var source: String; var evidence: [Reference]
    var facet: MediaFacet? { MediaFacet.allCases.first { $0.rawValue.lowercased() == category } }
}
struct ScreenText: Codable { var text: String; var start: Double; var end: Double; var confidence: Double }
struct MediaEvidence: Codable {
    var version: Int; var tags: [EvidenceTag]; var onScreenText: [ScreenText]? = nil
    var focusVersion: Int? = nil
}
struct TagCorrections: Codable { var hidden: [String]; var added: [EvidenceTag] }
struct ResolvedPlace: Codable, Equatable {
    var version: Int
    var label: String
    var area: String?
    var nearbyName: String?
    var latitude: Double
    var longitude: Double
    var language: String
    var provider: String
    var resolvedAt: Double
    var displayName: String? = nil
    var boundaryID: String? = nil
    var areaRelation: String? = nil
    var placeKind: String? = nil
    var supported: Bool {
        if version == 2 { return provider == "apple-geocoder" }
        guard version == 3, provider == "apple-osm", let id = boundaryID, let name = displayName,
              let area, !area.isEmpty, name.contains(area), label.contains(area),
              ["campus", "lake", "scenic", "park", "attraction"].contains(placeKind ?? "") else { return false }
        if areaRelation == "inside" { return id.range(of: #"^(area|way)/[1-9][0-9]*$"#, options: .regularExpression) != nil }
        return areaRelation == "nearby" && placeKind == "lake" &&
            id.range(of: #"^(way|relation)/[1-9][0-9]*$"#, options: .regularExpression) != nil &&
            name.hasSuffix(area + (language == "zh-Hans" ? "附近" : " vicinity"))
    }
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
    var analysisTags: [String]? = nil
    var analysisEvidence: MediaEvidence? = nil
    var tagCorrections: TagCorrections? = nil
    var resolvedPlace: ResolvedPlace? = nil
    var validResolvedPlace: ResolvedPlace? {
        guard let place = resolvedPlace, place.supported,
              place.latitude == metadata?.location?.latitude, place.longitude == metadata?.location?.longitude else { return nil }
        return place
    }
    var locationGroup: String? {
        hasSavedPlaceName ? recordedLocation : validResolvedPlace?.displayName ?? validResolvedPlace?.area ?? recordedLocation
    }
    var locationGroupKey: String? {
        if !hasSavedPlaceName, let place = validResolvedPlace, let id = place.boundaryID {
            return "osm:\(id):\(place.areaRelation ?? "inside")"
        }
        guard !hasSavedPlaceName, let place = validResolvedPlace, let area = place.area else { return recordedLocation }
        let parts = place.label.components(separatedBy: " · ")
        guard let index = parts.firstIndex(of: area) else { return recordedLocation }
        // Keep administrative context: identically named parks in different
        // cities must not collapse into the same location filter.
        return parts.prefix(index + 1).joined(separator: " · ")
    }
    var hasStructuredTags: Bool { analysisEvidence != nil || shotAnalysis?.tags?.isEmpty == false || shotAnalysis?.focusVersion == 2 || tagCorrections != nil }
    var hasFocusContract: Bool {
        // Follow the evidence source used by generatedTags, not an unrelated newer cache.
        if shotAnalysis?.tags?.isEmpty == false || shotAnalysis?.focusVersion == 2 { return shotAnalysis?.focusVersion == 2 }
        return analysisEvidence?.focusVersion == 2
    }
    var generatedTags: [EvidenceTag] {
        if shotAnalysis?.focusVersion == 2 { return shotAnalysis?.tags ?? [] }
        if let tags = shotAnalysis?.tags, !tags.isEmpty { return tags }
        return analysisEvidence?.tags ?? []
    }
    var evidenceTags: [EvidenceTag] {
        let added = tagCorrections?.added ?? []
        let excluded = Set((tagCorrections?.hidden ?? []) + added.map(\.id))
        return generatedTags.filter { !excluded.contains($0.id) } + added
    }
    var mediaAnalysis: MediaAnalysisState? = nil
    var syncSourceId: String? = nil
    var syncSourceName: String? = nil
    var syncSourceKind: String? = nil
    var importBatchId: String? = nil
    var importedAt: Double? = nil
    var importDate: Date? {
        guard let importedAt, importedAt.isFinite, importedAt > 0 else { return nil }
        return Date(timeIntervalSince1970: importedAt / 1000)
    }
    var cardSummary: String? {
        let candidates = [description, shotAnalysis?.summary, displayVideoDescription?.full_description]
        return candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != name }
    }
    var name: String {
        if isExample == true, let curated = sampleCopy?.title ?? title, !curated.isEmpty { return curated }
        // Analysis titles are editorial metadata, never a filename replacement.
        return (title?.isEmpty == false ? title : nil) ?? file.name
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
    // Prefer the concise, cross-window synthesis over repeating raw shot evidence.
    // Search continues to index both full_description and original segment descriptions.
    var descriptionMoments: [VideoDescriptionBlock] {
        displayVideoDescription?.contentBlocks.filter { $0.kind == .moment } ?? []
    }
    // Only reviewed segments become numbered shots; observation windows are not cuts.
    var descriptionShots: [Segment] {
        // An overview-only result intentionally has no distinct changes.
        // Do not fill that space with redundant raw descriptions.
        if let text = displayVideoDescription?.full_description,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        let shots = (shotAnalysis?.segments ?? []).sorted { $0.start < $1.start }
        return shots.count > 1 ? shots : []
    }
    var descriptionParagraphs: [String] {
        let blocks = displayVideoDescription?.contentBlocks.filter { $0.kind != .note } ?? []
        let visible = blocks.filter { $0.kind != .moment }
        var paragraphs = visible.map(\.text).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if paragraphs.isEmpty {
            // A single shot's full evidence is the video description, never a second section.
            let single = segments.count == 1 ? segments.first?.editorial?.description : nil
            let fallback = [single, description, shotAnalysis?.summary].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
            if let fallback { paragraphs = [fallback] }
        }
        var seen = Set<String>()
        return paragraphs.filter { seen.insert($0).inserted }
    }
    var cues: [Cue] { result?.analysis?.subtitleCues ?? [] }
    var transcriptCues: [Cue] { cues.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    var subtitleDisplayMessage: String? {
        guard let message = result?.analysis?.subtitleMessage else { return nil }
        if message.contains("Speech recognition is not bundled") {
            return "No saved transcript yet. Analyze this file to extract subtitles and speech."
        }
        return message
    }
    var recordedLocation: String? {
        if let value = context?["location"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty, !["unknown", "unspecified", "none", "n/a", "未知", "无"].contains(value.lowercased()) { return value }
        if metadata?.location?.name?.isEmpty != false, let place = validResolvedPlace { return place.label }
        return metadata?.location?.label
    }
    var hasSavedPlaceName: Bool {
        if let value = context?["location"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty, !["unknown", "unspecified", "none", "n/a", "未知", "无"].contains(value.lowercased()) { return true }
        return metadata?.location?.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
    var locationAttribution: String {
        if !hasSavedPlaceName, validResolvedPlace?.provider == "apple-osm" {
            return "Location context · © OpenStreetMap contributors (ODbL) · Not proof of visible landmarks"
        }
        if !hasSavedPlaceName, metadata?.location?.resolvedName != nil || validResolvedPlace != nil { return "Apple Maps · Approximate area around the recorded coordinates" }
        if !hasSavedPlaceName, metadata?.location?.coordinates != nil { return "Coordinates read from original file" }
        return recordedLocation == metadata?.location?.label ? "Read from original file metadata · No online lookup" : "Saved location"
    }
    var subtitleSourceLabel: String {
        if result?.analysis?.subtitleSource == "local-asr" { return "Speech transcription" }
        switch result?.analysis?.subtitleState {
        case "embedded": return "Embedded subtitles"
        case "sidecar": return "Local subtitle file"
        case "transcribed", "partial", "unreliable": return "Speech transcription"
        default: return "Saved subtitles"
        }
    }
    var processing: Bool { processingLabel != nil }
    var analysisNeedsAttention: Bool {
        let failures = ["error", "failed", "cancelled", "interrupted"]
        if ["queued", "running", "retrying"].contains(mediaAnalysis?.status ?? "") {
            return ["error", "cancelled"].contains(status)
        }
        return failures.contains(status) || failures.contains(mediaAnalysis?.status ?? "") || failures.contains(shotAnalysis?.status ?? "") || failures.contains(videoDescription?.status ?? "")
    }
    var processingLabel: String? {
        if mediaAnalysis?.status == "retrying" { return "Waiting to retry…" }
        if status == "analyzing" || mediaAnalysis?.status == "running" || shotAnalysis?.status == "running" || videoDescription?.status == "running" { return "Analyzing…" }
        if status == "queued" || mediaAnalysis?.status == "queued" || shotAnalysis?.status == "queued" || videoDescription?.status == "queued" { return "Queued…" }
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
/// Presentation identity uses declared source metadata, never image-based device guesses.
struct MediaSourceIdentity {
    let name: String
    let symbol: String
    init(item: MediaItem, sourceName: String? = nil, sourceKind: String? = nil) {
        let raw = (sourceName ?? item.syncSourceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let readable = raw.hasPrefix("/") ? URL(fileURLWithPath: raw).lastPathComponent : raw
        let opaque = UUID(uuidString: readable) != nil || readable.range(of: "^[a-fA-F0-9]{24,}$", options: .regularExpression) != nil
        let kind = sourceKind ?? item.syncSourceKind
        switch kind {
        case "phone": symbol = "iphone"
        case "camera": symbol = "camera"
        case "drone": symbol = "airplane"
        case "folder": symbol = "folder"
        default: symbol = item.syncSourceId == nil ? "desktopcomputer" : "externaldrive"
        }
        let fallback = kind == "phone" ? "Phone" : kind == "camera" ? "Camera card" : kind == "drone" ? "Drone" : item.syncSourceId == nil ? "Local files" : "Imported source"
        name = readable.isEmpty || opaque ? fallback : readable
    }
}

/// The card badge describes the recorded camera, not how the file was imported.
/// Keep source identity separate so folder/device filters retain their meaning.
struct MediaCaptureIdentity {
    let name: String
    let symbol: String
    init(camera: String?, source: MediaSourceIdentity) {
        let recorded = camera?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !recorded.isEmpty else {
            name = source.name; symbol = source.symbol
            return
        }
        name = recorded
        let model = recorded.lowercased()
        if model.contains("iphone") { symbol = "iphone" }
        else if model.contains("ipad") { symbol = "ipad" }
        else if model.range(of: #"\b(pixel|galaxy|android)\b|\bsm-[a-z0-9]+\b"#, options: .regularExpression) != nil { symbol = "smartphone" }
        else { symbol = "camera" }
    }
}

struct MediaImportSection: Identifiable {
    var id: String
    var date: Date?
    var items: [MediaSearchResult]
    var title: String {
        guard let date else { return "Earlier imports" }
        return Calendar.current.isDateInToday(date) ? "Imported today" : Calendar.current.isDateInYesterday(date) ? "Imported yesterday" : "Imported " + date.formatted(.dateTime.month(.abbreviated).day().year())
    }
    static func grouped(_ results: [MediaSearchResult]) -> [Self] {
        var groups: [Self] = []
        var indexes: [String: Int] = [:]
        for result in results {
            let item = result.item
            let day = item.importDate.map { String(Calendar.current.startOfDay(for: $0).timeIntervalSince1970) } ?? "earlier"
            // New imports use real batch IDs. Legacy and phone transfers fall back to source/day.
            let key = [day, item.syncSourceId ?? "local", item.importBatchId ?? "legacy"].joined(separator: ":")
            if let index = indexes[key] {
                groups[index].items.append(result)
                if let date = item.importDate, date > (groups[index].date ?? .distantPast) { groups[index].date = date }
            } else {
                indexes[key] = groups.count
                groups.append(Self(id: key, date: item.importDate, items: [result]))
            }
        }
        return groups.sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
        }
    }
}
struct Attachment: Codable, Identifiable, Equatable { var id: String; var name: String; var kind: String }
struct ChosenSkill: Codable, Equatable { var id: String; var title: String; var strategy: String; var applicability: String? = nil }
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
    var applicability: String?; var notFor: String?
    var coverLabel: String?; var coverTone: String?
    var category: String?; var coverSymbol: String?
    var materialCases: [SkillHighlight]?; var templates: [SkillHighlight]?; var workflow: [SkillHighlight]?
    var specificationURL: URL? {
        guard let source, let root = Bundle.main.resourceURL else { return nil }
        let url = root.appendingPathComponent("CreatorSkills").appendingPathComponent(source)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    var chosen: ChosenSkill { ChosenSkill(id: id, title: title, strategy: strategy, applicability: applicability) }
}
enum WorkspacePage: String, CaseIterable, Identifiable {
    case home = "Create", media = "Library", skills = "Templates", project = "Projects", mediaSync = "Media Sync"
    static let mediaPages: [WorkspacePage] = [.media, .mediaSync]
    static let creationPages: [WorkspacePage] = [.home, .project, .skills]
    static let primaryPages: [WorkspacePage] = mediaPages + creationPages
    // Keep route identifiers stable; navigation labels describe the destination.
    var navigationTitle: String {
        switch self { case .home: return "New video"; case .skills: return "Skills"; default: return rawValue }
    }
    var isCreation: Bool { Self.creationPages.contains(self) }
    var id: String { rawValue }
    var symbol: String {
        switch self { case .home: return "sparkles"; case .media: return "photo.on.rectangle.angled"; case .skills: return "wand.and.stars"; case .project: return "folder"; case .mediaSync: return "arrow.triangle.2.circlepath" }
    }
}
enum MediaAddedRange: String, CaseIterable {
    case all = "Any import date", today = "Added today", week = "Last 7 days", month = "Last 30 days"
    func includes(_ item: MediaItem, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard self != .all else { return true }
        guard let date = item.importDate, date <= now else { return false }
        let days = self == .today ? 0 : self == .week ? 6 : 29
        guard let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) else { return false }
        return date >= start
    }
}
enum MediaWorkFilter: String {
    case all, analyzing = "Analyzing", attention = "Needs attention"
    func includes(_ item: MediaItem) -> Bool {
        switch self {
        case .all: return true
        case .analyzing: return item.processingLabel != nil
        case .attention: return item.missing == true || item.analysisNeedsAttention
        }
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
    case beauty = "Aesthetic quality"
}
struct MediaFilter {
    var category = MediaCategory.all
    var query = ""
    var scope = MediaSearchScope.all
    var folder = ""
    var sort = MediaSort.original
    var facets = MediaFacetSelection()
    var syncSourceID: String? = nil
    func apply(_ items: [MediaItem], locations: [String: MediaLocation]) -> [MediaItem] {
        results(items, locations: locations).map(\.item)
    }
    func results(_ items: [MediaItem], locations: [String: MediaLocation], documents: [String: MediaSearchDocument] = [:]) -> [MediaSearchResult] {
        let query = MediaSearchQuery(query)
        let filtered: [MediaSearchResult] = items.compactMap { item in
            guard item.kind != "audio" else { return nil }
            guard syncSourceID == nil || item.syncSourceId == syncSourceID else { return nil }
            guard category == .all || (category == .favorites && item.favorite == true) ||
                    (category == .video && item.kind == "video") || (category == .image && item.kind == "image") else { return nil }
            guard folder.isEmpty || locations[item.id]?.isInside(folder) == true else { return nil }
            let document = documents[item.id] ?? MediaSearchDocument(item)
            guard facets.matches(document.quickTags), let hits = document.match(query, scope: scope, location: locations[item.id]) else { return nil }
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
