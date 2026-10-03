import Foundation

struct EditorSelection: Codable, Equatable {
    var runId: String
    var version: Int
    var shotIds: [String]
}

struct EditorDraft: Codable, Equatable {
    var runID: String
    var version: Int
    var base: [AgentShot]
    var shots: [AgentShot]
    var undoStack: [[AgentShot]] = []
    var redoStack: [[AgentShot]] = []
    struct LayerSnapshot: Codable, Equatable { var finishing: AgentFinishing? }
    var finishing: AgentFinishing?
    var baseFinishing: AgentFinishing?
    var undoLayers: [LayerSnapshot]?
    var redoLayers: [LayerSnapshot]?
    var dirty: Bool { shots != base || finishing != baseFinishing }
    var duration: Double { shots.reduce(0) { $0 + $1.end - $1.start } }
    init(run: AgentRun) { runID = run.id; version = run.version; base = run.timeline; shots = run.timeline; finishing = run.finishing ?? .empty; baseFinishing = finishing }
    mutating func hydrateLayers(from run: AgentRun) {
        if finishing == nil && baseFinishing == nil { finishing = run.finishing ?? .empty; baseFinishing = finishing }
    }
    mutating func remember() {
        if undoLayers == nil { undoLayers = undoStack.map { _ in LayerSnapshot(finishing: finishing) } }
        undoLayers = Array(((undoLayers ?? []) + [LayerSnapshot(finishing: finishing)]).suffix(30))
        undoStack = Array((undoStack + [shots]).suffix(30)); redoStack = []; redoLayers = []
    }
    mutating func setFinishing(_ next: AgentFinishing) {
        guard next != finishing else { return }
        remember(); finishing = next
    }
    mutating func replace(_ next: [AgentShot]) {
        guard next != shots else { return }
        remember(); shots = next
        let ids = Set(next.map(\.id))
        finishing?.clipAudio?.removeAll { !ids.contains($0.shotId) }
        finishing?.seams?.removeAll { seam in !zip(next, next.dropFirst()).contains { $0.id == seam.afterShotId && $1.id == seam.beforeShotId } }
    }
    mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(shots); shots = previous
        redoLayers = (redoLayers ?? []) + [LayerSnapshot(finishing: finishing)]
        if let old = undoLayers?.popLast() { finishing = old.finishing }
    }
    mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(shots); shots = next
        undoLayers = (undoLayers ?? []) + [LayerSnapshot(finishing: finishing)]
        if let next = redoLayers?.popLast() { finishing = next.finishing }
    }
    /// A drag preview is not an undo transaction. Commit once when the handle is released.
    func trimming(_ id: String, leading: Bool, delta: Double, durations: [String: Double], photoIDs: Set<String>) -> [AgentShot]? {
        guard delta.isFinite, let index = shots.firstIndex(where: { $0.id == id }),
              !shots[index].locked, base.first(where: { $0.id == id })?.locked != true else { return nil }
        var next = shots
        let shot = shots[index]
        let isPhoto = photoIDs.contains(shot.mediaId)
        let available = min(durations[shot.mediaId] ?? shot.end, shot.end + max(0, 600 - duration))
        if isPhoto {
            next[index].start = 0
            next[index].end = min(60, max(0.25, min(available, shot.end + (leading ? -delta : delta))))
        } else if leading {
            next[index].start = min(shot.end - 0.25, max(max(0, shot.start - max(0, 600 - duration)), shot.start + delta))
        } else {
            next[index].end = min(available, max(shot.start + 0.25, shot.end + delta))
        }
        var candidate = self; candidate.shots = next
        return candidate.validation(durations: durations, photoIDs: photoIDs) == nil ? next : nil
    }
    static func time(at x: Double, zoom: Double, duration: Double) -> Double {
        guard x.isFinite, zoom.isFinite, zoom > 0, duration.isFinite else { return 0 }
        return min(max(0, duration), max(0, x / zoom))
    }
    static func fitZoom(duration: Double, width: Double) -> Double {
        guard duration.isFinite, duration > 0, width.isFinite, width > 0 else { return 36 }
        return min(160, max(1, width / duration))
    }
    func validation(durations: [String: Double], photoIDs: Set<String> = []) -> String? {
        guard !shots.isEmpty else { return "Keep at least one shot in the timeline." }
        guard shots.count <= 80, Set(shots.map(\.id)).count == shots.count else { return "Use up to 80 unique shots." }
        for shot in shots {
            if photoIDs.contains(shot.mediaId) && (shot.start != 0 || shot.end > 60) { return "Set a photo display duration up to 60 seconds, starting at 0." }
            guard shot.start.isFinite, shot.end.isFinite, shot.start >= 0, shot.end - shot.start >= 0.25 else { return "Each shot needs valid in/out points and at least 0.25 seconds." }
            if let length = durations[shot.mediaId], shot.end > length + 0.001 { return "The out point exceeds the original file’s duration." }
        }
        guard duration <= 600 else { return "This build supports cuts up to 10 minutes." }
        if let finishing {
            let gains: [Double] = [finishing.originalVolume, finishing.music?.volume ?? 1, finishing.narrationVolume ?? 1]
            guard gains.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return "Keep audio levels between 0 and 100%." }
            var voiceEnd = 0.0
            guard finishing.narration.count <= 40 else { return "Use up to 40 narration segments." }
            for cue in finishing.narration {
                guard cue.start.isFinite, cue.end.isFinite, cue.start >= voiceEnd, cue.end - cue.start >= 0.25, cue.end <= duration,
                      !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cue.text.count <= 1500,
                      !cue.text.contains("[["), !cue.text.contains("]]"), ["Samantha", "Tingting"].contains(cue.voice),
                      (cue.rate ?? 175).isFinite, (120...220).contains(cue.rate ?? 175) else {
                    return "Keep narration within the film, without overlapping, and use plain text."
                }
                voiceEnd = cue.end
            }
            var end = 0.0
            let captions = (finishing.captions ?? []).sorted { $0.start < $1.start }
            guard captions.count <= 80, Set(captions.map(\.id)).count == captions.count else { return "Use up to 80 unique captions." }
            for cue in captions {
                guard cue.start.isFinite, cue.end.isFinite, cue.start >= end, cue.end-cue.start >= 0.25, cue.end <= duration,
                      !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cue.text.count <= 180 else { return "Keep captions within the film, at least 0.25s long, and not overlapping." }
                end = cue.end
            }
        }
        return nil
    }
    mutating func split(_ id: String, at seconds: Double, photoIDs: Set<String> = []) {
        guard let index = shots.firstIndex(where: { $0.id == id }), !shots[index].locked,
              base.first(where: { $0.id == id })?.locked != true, shots.count < 80, seconds.isFinite,
              seconds - shots[index].start >= 0.25, shots[index].end - seconds >= 0.25 else { return }
        var next = shots; var tail = next[index]
        tail.id = UUID().uuidString.lowercased(); tail.start = seconds; next[index].end = seconds
        // Photos are durations, not source ranges: both halves must start at zero.
        if photoIDs.contains(tail.mediaId) { tail.end -= seconds; tail.start = 0 }
        next.insert(tail, at: index + 1); replace(next)
    }
}
