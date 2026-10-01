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
    var dirty: Bool { shots != base }
    var duration: Double { shots.reduce(0) { $0 + $1.end - $1.start } }
    init(run: AgentRun) { runID = run.id; version = run.version; base = run.timeline; shots = run.timeline }
    mutating func replace(_ next: [AgentShot]) {
        guard next != shots else { return }
        undoStack = Array((undoStack + [shots]).suffix(30)); redoStack = []; shots = next
    }
    mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(shots); shots = previous
    }
    mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(shots); shots = next
    }
    func validation(durations: [String: Double]) -> String? {
        guard !shots.isEmpty else { return "Keep at least one shot in the timeline." }
        guard shots.count <= 80, Set(shots.map(\.id)).count == shots.count else { return "Use up to 80 unique shots." }
        for shot in shots {
            guard shot.start.isFinite, shot.end.isFinite, shot.start >= 0, shot.end - shot.start >= 0.25 else { return "Each shot needs valid in/out points and at least 0.25 seconds." }
            if let length = durations[shot.mediaId], shot.end > length + 0.001 { return "The out point exceeds the original file’s duration." }
        }
        guard duration <= 600 else { return "This build supports cuts up to 10 minutes." }
        return nil
    }
    mutating func split(_ id: String, at seconds: Double) {
        guard let index = shots.firstIndex(where: { $0.id == id }), !shots[index].locked,
              seconds - shots[index].start >= 0.25, shots[index].end - seconds >= 0.25 else { return }
        var next = shots; var tail = next[index]
        tail.id = UUID().uuidString.lowercased(); tail.start = seconds; next[index].end = seconds
        next.insert(tail, at: index + 1); replace(next)
    }
}
