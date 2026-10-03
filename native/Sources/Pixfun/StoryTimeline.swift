import Foundation

/// Content order and timing shared by the story list, player, and AI scope.
enum StoryTimeline {
    struct Chapter: Identifiable, Equatable {
        var id: String
        var title: String
        var start: Double
    }
    static func chapters(_ shots: [AgentShot]) -> [Chapter] {
        let names = ["intro": "Opening", "body": "Story", "outro": "Ending"]
        var result: [Chapter] = [], previous: String?
        var time = 0.0
        for shot in shots {
            if let section = shot.section, let title = names[section], section != previous {
                result.append(Chapter(id: shot.id, title: title, start: time))
            }
            previous = shot.section
            time += shot.end - shot.start
        }
        return Set(result.map(\.title)).count > 1 ? result : []
    }
    static func narrationIndices(for shotID: String, shots: [AgentShot], cues: [AgentFinishing.Narration]) -> [Int] {
        guard let shot = shots.first(where: { $0.id == shotID }) else { return [] }
        let start = offset(shotID, in: shots), end = start + shot.end - shot.start
        return cues.indices.filter { cues[$0].start < end && cues[$0].end > start }
    }
    static func thumbnailTimes(start: Double, end: Double, count: Int) -> [Double] {
        guard start.isFinite, end.isFinite, start >= 0, end > start else { return [] }
        let count = min(6, max(1, count))
        return (0..<count).map { start + (end-start) * (Double($0)+0.5) / Double(count) }
    }
    static func filmstripTileCount(width: Double) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        return Int(min(128, max(1, ceil(width / 78))))
    }
    /// Output timeline uses 30 fps; arrow keys move on that grid, not source frame rate.
    static func steppedTime(_ time: Double, direction: Int, duration: Double, seconds: Bool = false) -> Double {
        guard time.isFinite, duration.isFinite, duration >= 0 else { return 0 }
        let next = seconds ? time + Double(direction) : ((time * 30).rounded() + Double(direction)) / 30
        return min(duration, max(0, next))
    }
    static func timelineScale(viewport: Double, duration: Double, zoom: Double) -> Double {
        max(1, viewport) / max(0.01, duration) * min(32, max(1, zoom))
    }
    static func rulerStep(scale: Double) -> Double {
        [0.1, 0.5, 1, 2, 5, 10, 15, 30, 60, 120].first { $0 * scale >= 48 } ?? 120
    }
    static func inserting(_ item: MediaItem, before target: String?, in shots: [AgentShot]) -> [AgentShot]? {
        guard shots.count < 80, item.status == "ready", item.missing != true, ["image", "video"].contains(item.kind),
              target == nil || shots.contains(where: { $0.id == target }) else { return nil }
        let limit = item.kind == "image" ? 3 : min(3, item.metadata?.duration ?? 0)
        guard limit.isFinite, limit >= 0.25, shots.reduce(0, { $0+$1.end-$1.start })+limit <= 600 else { return nil }
        let index = target.flatMap { id in shots.firstIndex(where: { $0.id == id }) } ?? shots.count
        guard !shots.dropFirst(index).contains(where: \.locked) else { return nil }
        var next = shots
        next.insert(AgentShot(id: UUID().uuidString.lowercased(), mediaId: item.id, start: 0, end: limit, label: item.name, reason: "", locked: false), at: index)
        return next
    }
    static func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00.00" }
        let ticks = Int((max(0, seconds) * 100).rounded())
        return String(format: "%d:%02d.%02d", ticks / 6000, (ticks / 100) % 60, ticks % 100)
    }
    static func parseTime(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            guard let value = Double(part), value.isFinite, value >= 0,
                  parts.count == 1 || index == 0 || value < 60,
                  index == parts.count - 1 || value.rounded() == value else { return nil }
            total = total * 60 + value
        }
        return total
    }
    static func range(start: Double, end: Double, sourceDuration: Double, delta: Double, edge: Int) -> ClosedRange<Double> {
        let limit = max(end, sourceDuration)
        if edge < 0 { return min(end - 0.25, max(0, start + delta))...end }
        if edge > 0 { return start...max(start + 0.25, min(limit, end + delta)) }
        let shifted = max(0, min(limit - (end - start), start + delta))
        return shifted...(shifted + end - start)
    }
    static func replacing(_ shot: AgentShot, with item: MediaItem) -> AgentShot? {
        guard !shot.locked, item.missing != true, item.status == "ready", ["image", "video"].contains(item.kind) else { return nil }
        let limit = item.kind == "image" ? 60 : (item.metadata?.duration ?? 0)
        guard limit.isFinite, limit >= 0.25 else { return nil }
        var next = shot
        next.mediaId = item.id; next.start = 0; next.end = min(limit, shot.end - shot.start)
        next.label = item.name; next.reason = ""
        return next
    }
    static func description(for shot: AgentShot, item: MediaItem?) -> String? {
        guard let item else { return nil }
        let matching = item.segments.first { $0.start < shot.end && $0.end > shot.start && $0.editorial?.description.isEmpty == false }
        let text = matching?.editorial?.description ?? item.cardSummary
        guard let text, text != shot.label else { return nil }
        return text
    }
    static func offset(_ id: String, in shots: [AgentShot]) -> Double {
        shots.prefix { $0.id != id }.reduce(0) { $0 + $1.end - $1.start }
    }
    static func index(at time: Double, in shots: [AgentShot]) -> Int? {
        guard !shots.isEmpty, time.isFinite else { return nil }
        var end = 0.0
        for (index, shot) in shots.enumerated() {
            end += shot.end - shot.start
            if time < end { return index }
        }
        return shots.count - 1
    }
    static func move(_ ids: Set<String>, before target: String?, in shots: [AgentShot], locked: Set<String>) -> [AgentShot]? {
        guard !ids.isEmpty, ids.isDisjoint(with: locked), target.map({ !ids.contains($0) }) ?? true,
              ids.isSubset(of: Set(shots.map(\.id))), target == nil || shots.contains(where: { $0.id == target }) else { return nil }
        let moving = shots.filter { ids.contains($0.id) }
        var next = shots.filter { !ids.contains($0.id) }
        let position = target.flatMap { id in next.firstIndex { $0.id == id } } ?? next.count
        next.insert(contentsOf: moving, at: position)
        // A reorder may not move a locked clip indirectly by crossing it.
        guard shots.indices.allSatisfy({ !locked.contains(shots[$0].id) || next[$0].id == shots[$0].id }) else { return nil }
        return next == shots ? nil : next
    }
    static func narration(at index: Int, shots: [AgentShot], cues: [AgentFinishing.Narration]) -> [(text: String, continued: Bool)] {
        guard shots.indices.contains(index) else { return [] }
        let start = offset(shots[index].id, in: shots), end = start + shots[index].end - shots[index].start
        return cues.filter { $0.start < end && $0.end > start }.map { ($0.text, $0.start < start) }
    }
}
