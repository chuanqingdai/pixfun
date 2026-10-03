import SwiftUI
import AVKit

struct EditorWorkspaceView: View {
    @EnvironmentObject var store: WorkspaceStore
    let projectID: String
    @State private var draft: EditorDraft?
    @State private var selectedID: String?
    @State private var dragShots: [AgentShot]?
    @State private var dragBase: EditorDraft?
    @StateObject private var playback = AgentPlayback()
    @State private var issue: String?
    @State private var saving = false
    @State private var sourceMode = false
    @State private var zoom = 36.0
    @State private var timelineWidth = 800.0
    @State private var previewHeight = 320.0
    @State private var cursor = 0.0
    @StateObject private var sourcePlayer = PlaybackController()
    var run: AgentRun? { store.editorTimelineRun }
    var selected: AgentShot? { draft?.shots.first { $0.id == selectedID } }
    var selectedPhoto: MediaItem? { store.items.first { $0.id == selected?.mediaId && $0.kind == "image" } }
    var busy: Bool { store.activeAgentRun?.busy == true || saving || store.agentActionPending || store.saving }
    var preview: AgentArtifact? {
        run?.lastPreview ?? store.agentRuns.filter { $0.projectId == projectID }.sorted { $0.updatedAt > $1.updatedAt }.compactMap(\.lastPreview).first
    }
    var stalePreview: Bool { draft?.dirty == true || run?.preview?.id != preview?.id }
    var conflict: Bool { draft != nil && run != nil && draft!.runID == run!.id && draft!.version != run!.version }
    var durations: [String: Double] { Dictionary(uniqueKeysWithValues: store.items.compactMap { item in item.kind == "image" ? (item.id, 60.0) : item.metadata?.duration.map { (item.id, $0) } }) }
    var photoIDs: Set<String> { Set(store.items.filter { $0.kind == "image" }.map(\.id)) }
    var validation: String? { draft?.validation(durations: durations, photoIDs: photoIDs) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { store.closeEditor() } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(PixfunButtonStyle(kind: .quiet)).help("Collapse editor").accessibilityLabel("Collapse editor")
                Text(store.currentProject?.title ?? "Editor").font(.pixfun(16, semibold: true)).lineLimit(1)
                Spacer()
                Text(draft?.dirty == true ? "Draft saved locally" : "Saved timeline").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
            }.padding(16)
            Divider()
            VSplitView {
                HSplitView {
                    if let active = store.activeAgentRun {
                        AgentWorkspaceView(run: active, compact: true).frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                    }
                    GeometryReader { geometry in
                        previewPane.padding(16).frame(width: geometry.size.width, height: geometry.size.height)
                            .onAppear { previewHeight = max(100, geometry.size.height - 100) }
                            .onChange(of: geometry.size.height) { previewHeight = max(100, Double($0) - 100) }
                    }.frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                    inspector.frame(width: 200).frame(maxHeight: .infinity, alignment: .top)
                }.frame(minHeight: 260, idealHeight: 460, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    timelineToolbar
                    ScrollView(.vertical) { timeline }
                    if conflict {
                        HStack {
                            Text("The saved timeline changed. Your draft is retained; reload before continuing.").foregroundStyle(.orange)
                            Button("Reload saved") { reload() }
                        }.font(.pixfun(12))
                    }
                    if let message = issue ?? validation { Text(message).font(.pixfun(12)).foregroundStyle(.orange).textSelection(.enabled) }
                }.padding(12).frame(minHeight: 200, idealHeight: 240, maxHeight: 400)
                    .background(Color.pixfunSurface.opacity(0.4))
                    .background(GeometryReader { geometry in
                        Color.clear.onAppear { timelineWidth = geometry.size.width - 72 }
                            .onChange(of: geometry.size.width) { timelineWidth = Double($0) - 72 }
                    })
            }
        }.background(Color.pixfunBackground)
            .onAppear { loadDraft(); playback.load(preview?.path) }
            .onChange(of: run?.id) { _ in loadDraft() }
            .onChange(of: run?.version) { _ in
                dragShots = nil; dragBase = nil
                if !saving && draft?.dirty != true { loadDraft(force: true) }
            }
            .onChange(of: draft) { value in
                if let value { store.editorDrafts[value.runID] = value }
                cursor = min(cursor, value?.duration ?? 0)
                refreshScope()
            }
            .onChange(of: playback.currentTime) { value in
                if !stalePreview && !sourceMode { cursor = value }
            }
            .onChange(of: store.editorSelection) { value in
                if value == nil { selectedID = nil }
            }
            .onDisappear { sourcePlayer.stop(); playback.player?.pause() }
            .onChange(of: preview?.path) { _ in playback.load(preview?.path) }
            .onChange(of: stalePreview) { stale in
                if stale { playback.player?.pause() }
                else if playback.ready { playback.seek(cursor) }
            }
            .onChange(of: selectedID) { value in
                if value == nil { sourceMode = false; sourcePlayer.stop() }
            }
            .task(id: selected.map { "\($0.id):\($0.start):\($0.end):\(sourceMode)" }) { await loadSource() }
    }
    var timelineToolbar: some View {
        HStack(spacing: 12) {
            Button { draft?.undo(); syncSelection() } label: { Image(systemName: "arrow.uturn.backward") }
                .help("Undo timeline edit").accessibilityLabel("Undo timeline edit").disabled(busy || draft?.undoStack.isEmpty != false)
            Button { draft?.redo(); syncSelection() } label: { Image(systemName: "arrow.uturn.forward") }
                .help("Redo timeline edit").accessibilityLabel("Redo timeline edit").disabled(busy || draft?.redoStack.isEmpty != false)
            Divider().frame(height: 18)
            Button { splitSelected() } label: { Image(systemName: "scissors") }
                .help("Split at playhead").accessibilityLabel("Split at playhead").disabled(!canSplit)
            Button { removeSelected() } label: { Image(systemName: "trash") }
                .help("Remove clip; keep original").accessibilityLabel("Remove clip; keep original")
                .disabled((selected.map { !canEdit($0) } ?? true) || (draft?.shots.count ?? 0) <= 1)
            Text("\(timestamp(cursor)) / \(timestamp(draft?.duration ?? 0))")
                .font(.pixfun(12)).monospacedDigit().foregroundStyle(Color.pixfunMuted)
            Spacer(minLength: 8)
            Button { zoom = EditorDraft.fitZoom(duration: draft?.duration ?? 0, width: timelineWidth) } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }.help("Fit timeline").accessibilityLabel("Fit timeline")
            Image(systemName: "minus.magnifyingglass").foregroundStyle(Color.pixfunMuted)
            Slider(value: $zoom, in: 1...160).frame(width: 100).accessibilityLabel("Timeline zoom")
            Image(systemName: "plus.magnifyingglass").foregroundStyle(Color.pixfunMuted)
            Button(saving ? "Saving…" : "Save & preview", action: save).buttonStyle(PixfunButtonStyle(kind: .primary))
                .disabled(busy || draft?.dirty != true || validation != nil || conflict)
        }.buttonStyle(.borderless)
    }
    var inspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(selected == nil ? "Project" : "Clip").font(.pixfun(13, semibold: true))
                Spacer()
                if selected != nil {
                    Button { selectedID = nil; syncSelection() } label: { Image(systemName: "xmark") }
                        .help("Clear selection").accessibilityLabel("Clear selection")
                }
            }
            if let selected {
                let item = store.items.first { $0.id == selected.mediaId }
                ServiceImage(path: item?.cover, fit: .fit).frame(height: 95).clipped()
                Text(item?.file.name ?? selected.label).font(.pixfun(12, semibold: true)).lineLimit(2)
                LabeledContent("Duration", value: String(format: "%.2fs", selected.end - selected.start))
                if selectedPhoto == nil {
                    LabeledContent("Source", value: "\(timestamp(selected.start))–\(timestamp(selected.end))")
                }
                Divider()
                Button { seek(offset(selected.id)) } label: { Label("Go to clip", systemImage: "location") }
                    .help("Move the playhead to this clip")
                Button { sourceMode = true; playback.player?.pause() } label: { Label("View original", systemImage: "arrow.up.right") }
                Button { mutate { shots in if let i = shots.firstIndex(where: { $0.id == selected.id }) { shots[i].locked.toggle() } } } label: {
                    Label(selected.locked ? "Unlock clip" : "Lock clip", systemImage: selected.locked ? "lock.fill" : "lock.open")
                }.disabled(busy || conflict).help("Save an unlocked clip before trimming")
            } else {
                LabeledContent("Format", value: run?.aspect ?? "16:9")
                LabeledContent("Clips", value: String(draft?.shots.count ?? 0))
                Text("Select a clip to edit.").foregroundStyle(Color.pixfunMuted)
            }
            Spacer(minLength: 0)
        }.font(.pixfun(12)).padding(16).buttonStyle(.borderless)
    }
    var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sourceMode {
                Button { sourceMode = false; sourcePlayer.stop() } label: {
                    Label("Back to preview", systemImage: "arrow.left")
                }.buttonStyle(PixfunButtonStyle(kind: .quiet))
            } else if stalePreview {
                HStack {
                    Text("Previous render · rebuild after saving").font(.pixfun(12)).foregroundStyle(Color.pixfunGold)
                    if draft?.dirty != true, let run, run.status == "review" {
                        Button("Update preview") { store.agentAction("approve", run: run) }.disabled(busy || conflict)
                    }
                }
            }
            if sourceMode {
                if let photo = selectedPhoto {
                    ServiceImage(path: photo.cover, fit: .fit).aspectRatio(photo.aspect, contentMode: .fit).frame(maxHeight: 300)
                } else if let player = sourcePlayer.player {
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
                    Text(selectedPhoto != nil ? "Photo · \(String(format: "%.2fs", selected.end)) display · \(selected.label)" : "Source \(timestamp(selected.start))–\(timestamp(selected.end)) · \(selected.label)").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).lineLimit(2)
                    if selectedPhoto == nil {
                    Button("Split at playhead") {
                        if let seconds = sourcePlayer.player?.currentTime().seconds {
                            if seconds - selected.start >= 0.25 && selected.end - seconds >= 0.25 {
                                draft?.split(selected.id, at: seconds); syncSelection()
                            } else { issue = "Move the playhead at least 0.25 seconds from either edge." }
                        }
                    }.disabled(!canEdit(selected) || sourcePlayer.player == nil)
                    }
                }
            } else if let preview {
                VStack(spacing: 8) {
                    if let player = playback.player {
                        NativeVideoPlayer(player: player)
                            .overlay {
                                if (!playback.hasStarted || playback.currentTime < 0.001), let poster = playback.poster {
                                    Image(nsImage: poster).resizable().scaledToFit().allowsHitTesting(false)
                                }
                            }
                            .aspectRatio(run?.aspect == "9:16" ? 9/16 : run?.aspect == "1:1" ? 1 : 16/9, contentMode: .fit)
                            .frame(maxHeight: previewHeight).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    if let error = playback.issue {
                        Text(error).font(.pixfun(12)).foregroundStyle(.orange)
                        Button("Reload preview") { playback.load(preview.path) }
                    }
                    HStack(spacing: 12) {
                        Button { playback.toggle() } label: { Image(systemName: playback.playing ? "pause.fill" : "play.fill") }
                            .accessibilityLabel(playback.playing ? "Pause preview" : "Play preview").disabled(!playback.ready)
                        Text("\(timestamp(playback.currentTime)) / \(playback.durationLabel)").font(.pixfun(12)).monospacedDigit()
                        Spacer()
                        Button { store.exportArtifact(preview) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                            .buttonStyle(PixfunButtonStyle(kind: .quiet))
                    }
                }
            } else {
                Text("Save your timeline, then choose Build preview in the conversation.").font(.pixfun(14)).foregroundStyle(Color.pixfunMuted)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }
    var timeline: some View {
        VStack(spacing: 8) {
            EditorTimelineView(
                shots: dragShots ?? draft?.shots ?? [], items: store.items, finishing: run?.finishing,
                selectedID: selectedID, zoom: zoom, playhead: cursor,
                showsPlayhead: !sourceMode, canSeek: !busy,
                canTrim: { canEdit($0) }, onSelect: select, onSeek: seek,
                onTrim: updateTrim, onTrimEnd: commitTrim,
                onOriginal: { shot in select(shot); sourceMode = true; playback.player?.pause() },
                onMove: { shot, amount in select(shot); move(amount) }
            )
        }
    }
    func canEdit(_ shot: AgentShot) -> Bool {
        !busy && !conflict && !shot.locked && draft?.base.first(where: { $0.id == shot.id })?.locked != true
    }
    var canSplit: Bool {
        guard let selected, canEdit(selected), !sourceMode else { return false }
        let local = cursor - offset(selected.id)
        return local >= 0.25 && selected.end - selected.start - local >= 0.25
    }
    func splitSelected() {
        guard canSplit, let selected else { return }
        draft?.split(selected.id, at: selected.start + cursor - offset(selected.id), photoIDs: photoIDs); syncSelection()
    }
    func removeSelected() {
        guard let selected, canEdit(selected), (draft?.shots.count ?? 0) > 1 else { return }
        mutate { $0.removeAll { $0.id == selected.id } }; selectedID = nil; syncSelection()
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite, !busy else { return }
        sourceMode = false; sourcePlayer.stop()
        cursor = min(draft?.duration ?? 0, max(0, seconds))
        // A draft cursor remains editable; it must never pretend the previous render is updated.
        if !stalePreview && playback.ready { playback.seek(cursor) }
    }
    func updateTrim(_ shot: AgentShot, _ leading: Bool, _ delta: Double) {
        guard canEdit(shot) else { return }
        if dragBase == nil { dragBase = draft; playback.player?.pause() }
        dragShots = dragBase?.trimming(shot.id, leading: leading, delta: delta, durations: durations, photoIDs: photoIDs)
    }
    func commitTrim() {
        defer { dragBase = nil; dragShots = nil }
        guard !busy, !conflict, let baseline = dragBase, baseline == draft, let shots = dragShots else { return }
        draft?.replace(shots); issue = nil
    }
    func offset(_ id: String) -> Double { (draft?.shots.prefix { $0.id != id } ?? []).reduce(0) { $0 + $1.end - $1.start } }
    func select(_ shot: AgentShot) {
        selectedID = shot.id; sourceMode = false; issue = nil
        syncSelection()
    }
    func syncSelection() {
        if selected == nil { selectedID = nil }
        refreshScope()
    }
    func refreshScope() {
        guard let draft, let selectedID, draft.shots.contains(where: { $0.id == selectedID }) else { store.editorSelection = nil; return }
        store.editorSelection = EditorSelection(runId: draft.runID, version: draft.version, shotIds: [selectedID])
    }
    func mutate(_ change: (inout [AgentShot]) -> Void) {
        guard !busy, !conflict, var value = draft else { return }
        var shots = value.shots; change(&shots); value.replace(shots); draft = value; issue = nil
    }
    func move(_ amount: Int) {
        guard let selected, canEdit(selected), canMove(amount) else { return }
        mutate { shots in
            if let i = shots.firstIndex(where: { $0.id == selected.id }), shots.indices.contains(i+amount), !shots[i+amount].locked, draft?.base.first(where: { $0.id == shots[i+amount].id })?.locked != true { shots.swapAt(i, i+amount) }
        }
    }
    func canMove(_ amount: Int) -> Bool {
        guard let selected, let shots = draft?.shots, !selected.locked,
              let index = shots.firstIndex(where: { $0.id == selected.id }), shots.indices.contains(index + amount) else { return false }
        return canEdit(shots[index + amount])
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
                    store.agentAction("approve", run: updated)
                }
            } catch { issue = error.localizedDescription }
            saving = false
        }
    }
    func loadSource() async {
        sourcePlayer.stop()
        guard sourceMode, let selected, selectedPhoto == nil else { return }
        do {
            let url = try await store.service.original(selected.mediaId)
            guard !Task.isCancelled, sourceMode, selectedID == selected.id else { return }
            sourcePlayer.open(url, at: selected.start)
            sourcePlayer.player?.currentItem?.forwardPlaybackEndTime = CMTime(seconds: selected.end, preferredTimescale: 600)
        } catch { if !Task.isCancelled { issue = error.localizedDescription } }
    }
}
