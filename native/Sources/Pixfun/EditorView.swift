import SwiftUI
import AVKit

struct EditorWorkspaceView: View {
    @EnvironmentObject var store: WorkspaceStore
    let projectID: String
    @State private var draft: EditorDraft?
    @State private var selectedID: String?
    @State private var inText = ""
    @State private var outText = ""
    @State private var issue: String?
    @State private var saving = false
    @State private var sourceMode = false
    @State private var zoom = 36.0
    @StateObject private var sourcePlayer = PlaybackController()
    var run: AgentRun? { store.editorTimelineRun }
    var selected: AgentShot? { draft?.shots.first { $0.id == selectedID } }
    var busy: Bool { store.activeAgentRun?.busy == true || saving || store.agentActionPending || store.saving }
    var preview: AgentArtifact? {
        run?.lastPreview ?? store.agentRuns.filter { $0.projectId == projectID }.sorted { $0.updatedAt > $1.updatedAt }.compactMap(\.lastPreview).first
    }
    var stalePreview: Bool { draft?.dirty == true || run?.preview?.id != preview?.id }
    var conflict: Bool { draft != nil && run != nil && draft!.runID == run!.id && draft!.version != run!.version }
    var durations: [String: Double] { Dictionary(uniqueKeysWithValues: store.items.compactMap { item in item.metadata?.duration.map { (item.id, $0) } }) }
    var validation: String? { draft?.validation(durations: durations) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { store.closeEditor() } label: { Label("Conversation", systemImage: "arrow.left") }.buttonStyle(PixfunButtonStyle(kind: .quiet))
                Text(store.currentProject?.title ?? "Editor").font(.pixfun(16, semibold: true)).lineLimit(1)
                Spacer()
                Text(draft?.dirty == true ? "Draft saved locally" : "Saved timeline").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
            }.padding(16)
            Divider()
            HSplitView {
                if let active = store.activeAgentRun {
                    AgentWorkspaceView(run: active, compact: true).frame(minWidth: 300, idealWidth: 340, maxWidth: 430)
                }
                ScrollView { VStack(alignment: .leading, spacing: 14) {
                    previewPane
                    Divider()
                    HStack(spacing: 10) {
                        Text("Timeline").font(.pixfun(15, semibold: true))
                        Text("\(timestamp(draft?.duration ?? 0)) · v\(draft?.version ?? 1)").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                        Spacer()
                        Button { draft?.undo(); syncSelection() } label: { Image(systemName: "arrow.uturn.backward") }
                            .help("Undo timeline edit").accessibilityLabel("Undo timeline edit").disabled(busy || draft?.undoStack.isEmpty != false)
                        Button { draft?.redo(); syncSelection() } label: { Image(systemName: "arrow.uturn.forward") }
                            .help("Redo timeline edit").accessibilityLabel("Redo timeline edit").disabled(busy || draft?.redoStack.isEmpty != false)
                        Button(saving ? "Saving…" : "Save changes", action: save).buttonStyle(PixfunButtonStyle(kind: .primary))
                            .disabled(busy || draft?.dirty != true || validation != nil || conflict)
                    }
                    timeline
                    inspector
                    if conflict {
                        HStack {
                            Text("The saved timeline changed. Your draft is retained; reload before continuing.").foregroundStyle(.orange)
                            Button("Reload saved") { reload() }
                        }.font(.pixfun(12))
                    }
                    if let message = issue ?? validation { Text(message).font(.pixfun(12)).foregroundStyle(.orange).textSelection(.enabled) }
                    Spacer(minLength: 0)
                }.padding(20).frame(maxWidth: .infinity, alignment: .topLeading) }.frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Color.pixfunBackground)
            .onAppear { loadDraft() }
            .onChange(of: run?.id) { _ in loadDraft() }
            .onChange(of: run?.version) { _ in
                if !saving && draft?.dirty != true { loadDraft(force: true) }
            }
            .onChange(of: draft) { value in
                if let value { store.editorDrafts[value.runID] = value }
                refreshScope()
            }
            .onChange(of: store.editorSelection) { value in
                if value == nil { selectedID = nil }
            }
            .onDisappear { sourcePlayer.stop() }
            .task(id: selected.map { "\($0.id):\($0.start):\($0.end):\(sourceMode)" }) { await loadSource() }
    }
    var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Preview mode", selection: $sourceMode) {
                    Text("Cut preview").tag(false)
                    Text("Selected source").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 280)
                Spacer()
                if !sourceMode && stalePreview { Text("Previous render · rebuild after saving").font(.pixfun(12)).foregroundStyle(Color.pixfunGold) }
            }
            if sourceMode {
                if let player = sourcePlayer.player {
                    NativeVideoPlayer(player: player).aspectRatio(16/9, contentMode: .fit).frame(maxHeight: 300)
                } else {
                    Text(selected == nil ? "Select a timeline shot to inspect its original footage." : "Loading original…")
                        .font(.pixfun(13)).foregroundStyle(Color.pixfunMuted).frame(maxWidth: .infinity, minHeight: 190)
                }
                if let error = sourcePlayer.error { Text(error).font(.pixfun(12)).foregroundStyle(.orange) }
                if sourcePlayer.error != nil || (issue != nil && sourcePlayer.player == nil) {
                    Button("Retry source") { Task { issue = nil; await loadSource() } }
                }
                if let selected {
                    Text("Source \(timestamp(selected.start))–\(timestamp(selected.end)) · \(selected.label)").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).lineLimit(2)
                    Button("Split at playhead") {
                        if let seconds = sourcePlayer.player?.currentTime().seconds {
                            if seconds - selected.start >= 0.25 && selected.end - seconds >= 0.25 {
                                draft?.split(selected.id, at: seconds); syncSelection()
                            } else { issue = "Move the playhead at least 0.25 seconds from either edge." }
                        }
                    }.disabled(busy || selected.locked || sourcePlayer.player == nil)
                }
            } else if let preview {
                AgentVideoMessage(artifact: preview, aspect: run?.aspect ?? "16:9")
            } else {
                Text("Save your timeline, then choose Build preview in the conversation.").font(.pixfun(14)).foregroundStyle(Color.pixfunMuted)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }
    var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Select a shot to reference it in chat").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                Spacer()
                Slider(value: $zoom, in: 20...100).frame(width: 100).accessibilityLabel("Timeline zoom")
            }
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 6) {
                    track(audio: false)
                    track(audio: true)
                }.padding(2)
            }.frame(height: 132)
        }
    }
    func track(audio: Bool) -> some View {
        HStack(spacing: 3) {
            Text(audio ? "A1\nOriginal" : "V1\nVideo").font(.pixfun(11)).foregroundStyle(Color.pixfunMuted).frame(width: 56)
            ForEach(draft?.shots ?? []) { shot in
                Button { select(shot) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        if !audio {
                            ServiceImage(path: store.items.first { $0.id == shot.mediaId }?.cover)
                                .frame(height: 40).clipped()
                        }
                        HStack(spacing: 4) {
                            if shot.locked { Image(systemName: "lock.fill") }
                            Text(audio ? (store.items.first { $0.id == shot.mediaId }?.metadata?.hasAudio == false ? "No audio" : "Linked audio") : shot.label).lineLimit(1)
                        }.font(.pixfun(11)).padding(.horizontal, 6)
                        if !audio { Text("\(timestamp(offset(shot.id))) · \(String(format: "%.2fs", shot.end-shot.start))").font(.pixfun(10)).foregroundStyle(Color.pixfunMuted).padding(.horizontal, 6) }
                    }.frame(width: max(40, (shot.end-shot.start)*zoom), height: audio ? 27 : 85, alignment: .topLeading)
                        .background(selectedID == shot.id ? Color.pixfunGold.opacity(0.18) : Color.pixfunSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(selectedID == shot.id ? Color.pixfunGold : Color.pixfunLine, lineWidth: selectedID == shot.id ? 2 : 1))
                }.buttonStyle(.plain).accessibilityLabel("\(audio ? "Linked audio" : "Video"): \(shot.label), timeline \(timestamp(offset(shot.id)))")
                    .accessibilityAddTraits(selectedID == shot.id ? [.isSelected] : [])
            }
        }
    }
    var inspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selected {
                HStack {
                    Text(selected.label).font(.pixfun(14, semibold: true)).lineLimit(1)
                    Spacer()
                    Button(selected.locked ? "Unlock" : "Lock") {
                        mutate { shots in if let i = shots.firstIndex(where: { $0.id == selected.id }) { shots[i].locked.toggle() } }
                    }.disabled(busy)
                    Button("Clear") { selectedID = nil; refreshScope() }.buttonStyle(PixfunButtonStyle(kind: .quiet))
                }
                HStack {
                    Text("Source in/out").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                    TextField("In seconds", text: $inText).frame(width: 64).accessibilityLabel("Source in seconds")
                    TextField("Out seconds", text: $outText).frame(width: 64).accessibilityLabel("Source out seconds")
                    Button("Apply trim", action: trim)
                    Spacer()
                }.disabled(busy || selected.locked || (draft?.base.first { $0.id == selected.id }?.locked == true))
                HStack {
                    Button { move(-1) } label: { Image(systemName: "arrow.left") }.accessibilityLabel("Move shot earlier").disabled(!canMove(-1))
                    Button { move(1) } label: { Image(systemName: "arrow.right") }.accessibilityLabel("Move shot later").disabled(!canMove(1))
                    Button { mutate { $0.removeAll { $0.id == selected.id } }; selectedID = nil; refreshScope() } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Remove from timeline, keep original").disabled((draft?.shots.count ?? 0) <= 1)
                    Spacer()
                }.disabled(busy || selected.locked)
                if selected.locked { Text("Unlock and save before changing this shot.").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted) }
            } else { Text("Original audio follows video edits. Original files are never changed.").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted) }
        }
    }
    func offset(_ id: String) -> Double { (draft?.shots.prefix { $0.id != id } ?? []).reduce(0) { $0 + $1.end - $1.start } }
    func select(_ shot: AgentShot) { selectedID = shot.id; sourceMode = true; issue = nil; syncSelection() }
    func syncSelection() {
        if let selected { inText = String(format: "%.3f", selected.start); outText = String(format: "%.3f", selected.end) }
        else { selectedID = nil }
        refreshScope()
    }
    func refreshScope() {
        guard let draft, let selectedID, draft.shots.contains(where: { $0.id == selectedID }) else { store.editorSelection = nil; return }
        store.editorSelection = EditorSelection(runId: draft.runID, version: draft.version, shotIds: [selectedID])
    }
    func mutate(_ change: (inout [AgentShot]) -> Void) {
        guard !busy, var value = draft else { return }
        var shots = value.shots; change(&shots); value.replace(shots); draft = value; issue = nil
    }
    func trim() {
        guard let selected, let start = Double(inText), let end = Double(outText), var proposed = draft else { issue = "Enter valid source times in seconds."; return }
        var shots = proposed.shots
        guard let i = shots.firstIndex(where: { $0.id == selected.id }) else { return }
        shots[i].start = start; shots[i].end = end; proposed.replace(shots)
        if let error = proposed.validation(durations: durations) { issue = error; return }
        draft = proposed; issue = nil
    }
    func move(_ amount: Int) {
        guard let selected, !selected.locked else { return }
        mutate { shots in
            if let i = shots.firstIndex(where: { $0.id == selected.id }), shots.indices.contains(i+amount), !shots[i+amount].locked { shots.swapAt(i, i+amount) }
        }
    }
    func canMove(_ amount: Int) -> Bool {
        guard let selected, let shots = draft?.shots, !selected.locked,
              let index = shots.firstIndex(where: { $0.id == selected.id }), shots.indices.contains(index + amount) else { return false }
        return !shots[index + amount].locked
    }
    func loadDraft(force: Bool = false) {
        guard let run else { return }
        let cached = store.editorDrafts[run.id]
        draft = !force && (cached?.dirty == true || cached?.version == run.version) ? cached : EditorDraft(run: run)
        issue = nil; selectedID = nil; refreshScope()
    }
    func reload() {
        let alert = NSAlert(); alert.messageText = "Replace this local draft with the saved timeline?"
        alert.informativeText = "Your local changes have not been applied to the project."
        alert.addButton(withTitle: "Reload saved"); alert.addButton(withTitle: "Keep draft")
        if alert.runModal() == .alertFirstButtonReturn { loadDraft(force: true) }
    }
    func save() {
        guard let run, let value = draft, !busy, validation == nil, !conflict else { return }
        saving = true; issue = nil
        Task {
            do {
                try await store.saveAgentTimeline(run, shots: value.shots, version: value.version)
                if let updated = store.agentRuns.first(where: { $0.id == run.id }) {
                    var accepted = value; accepted.base = updated.timeline; accepted.shots = updated.timeline; accepted.version = updated.version
                    draft = accepted; refreshScope()
                }
            } catch { issue = error.localizedDescription }
            saving = false
        }
    }
    func loadSource() async {
        sourcePlayer.stop()
        guard sourceMode, let selected else { return }
        do {
            let url = try await store.service.original(selected.mediaId)
            guard !Task.isCancelled, sourceMode, selectedID == selected.id else { return }
            sourcePlayer.open(url, at: selected.start)
            sourcePlayer.player?.currentItem?.forwardPlaybackEndTime = CMTime(seconds: selected.end, preferredTimescale: 600)
        } catch { if !Task.isCancelled { issue = error.localizedDescription } }
    }
}
