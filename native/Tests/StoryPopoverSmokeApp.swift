import SwiftUI

/// Interactive fixture: never starts the service or restores/persists user drafts.
@main
struct StoryPopoverSmokeApp: App {
    @StateObject private var store: WorkspaceStore

    init() {
        let store = WorkspaceStore()
        store.items = try! JSONDecoder().decode([MediaItem].self, from: Data(#"[{"id":"fixture-a","kind":"video","file":{"name":"Lake.mp4"},"status":"ready","metadata":{"duration":10,"hasAudio":true}},{"id":"fixture-b","kind":"video","file":{"name":"Trail.mp4"},"status":"ready","metadata":{"duration":10,"hasAudio":true}}]"#.utf8))
        let shots = [
            AgentShot(id: "a", mediaId: "fixture-a", start: 0, end: 5, label: "Lake · test clip", reason: "", locked: false),
            AgentShot(id: "b", mediaId: "fixture-b", start: 0, end: 5, label: "Trail · test clip", reason: "", locked: false)
        ]
        var run = AgentRun(id: "popover-fixture", projectId: "popover-fixture", prompt: "Popover interaction test", mode: "local", status: "review", stage: "plan", message: "", summary: "", intent: "create", question: "", resultText: "", events: [], artifacts: [], timeline: shots, version: 1, completed: 2, total: 2, duration: 10, aspect: "16:9", updatedAt: 0)
        var finish = AgentFinishing.empty
        finish.captions = [.init(id: "caption-a", start: 0, end: 2, text: "By the lake"), .init(id: "caption-b", start: 4, end: 6, text: "Along the trail")]
        run.finishing = finish
        store.agentRuns = [run]
        store.editorProjectID = run.projectId
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup("Popover test · in-memory fixture") {
            StoryEditorWorkspace(projectID: "popover-fixture")
                .environmentObject(store).preferredColorScheme(.dark)
                .tint(.pixfunGold).foregroundStyle(Color.pixfunInk)
                .frame(minWidth: 940, minHeight: 640)
        }.defaultSize(width: 1040, height: 720)
    }
}
