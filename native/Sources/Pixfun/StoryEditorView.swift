import SwiftUI
import AVKit
import UniformTypeIdentifiers

enum StoryFloatingTool: Equatable { case sound, captions, transition }

struct StoryEditorWorkspace: View {
    @EnvironmentObject var store: WorkspaceStore
    let projectID: String
    @State private var draft: EditorDraft?
    @State private var selection = Set<String>()
    @State private var primary: String?
    @State private var filter = ""
    @State private var following = true
    @State private var sourcePreview = false
    @State private var saving = false
    @State private var issue: String?
    @State private var trimBase: EditorDraft?
    @State private var trimShots: [AgentShot]?
    @State private var dragging = Set<String>()
    @State private var dropTarget: String?
    @State private var replacing: AgentShot?
    @State private var removedCount = 0
    @State private var showCaptions = false
    @State private var showAudio = false
    @State private var tool: StoryTool?
    @State private var floatingTool: StoryFloatingTool?
    @State private var addingClip = false
    @State private var insertBefore: String?
    @State private var selectedCaption: String?
    @State private var captionTypingID: String?
    @State private var audioBase: AgentFinishing?
    @State private var selectedNarration: Int?
    @State private var narrationTyping = false
    @State private var versionsOpen = false
    @State private var keyboardHelpOpen = false
    @State private var keyboardScrollID: String?
    @StateObject private var rendered = AgentPlayback()
    @StateObject private var sequence = StorySequencePlayer()
    @StateObject private var boundary = StorySequencePlayer()

    var run: AgentRun? { store.editorTimelineRun }
    var shots: [AgentShot] { trimShots ?? draft?.shots ?? [] }
    var duration: Double { shots.reduce(0) { $0 + $1.end - $1.start } }
    var currentTime: Double { sourcePreview ? sequence.time : rendered.currentTime }
    var playing: Bool { sourcePreview ? sequence.playing : rendered.playing }
    var activeID: String? { !sourcePreview && stale ? nil : StoryTimeline.index(at: currentTime, in: shots).map { shots[$0].id } }
    var preview: AgentArtifact? { run?.lastPreview }
    var busy: Bool { saving || store.activeAgentRun?.busy == true || store.agentActionPending || store.saving }
    var conflict: Bool { draft != nil && (run?.id != draft?.runID || run?.version != draft?.version) }
    var stale: Bool { draft?.dirty == true || run?.preview?.id != preview?.id }
    var photoIDs: Set<String> { Set(store.items.filter { $0.kind == "image" }.map(\.id)) }
    var durations: [String: Double] { Dictionary(uniqueKeysWithValues: store.items.compactMap { item in item.kind == "image" ? (item.id, 60) : item.metadata?.duration.map { (item.id, $0) } }) }
    var locked: Set<String> { Set((draft?.shots ?? []).filter(\.locked).map(\.id) + (draft?.base ?? []).filter(\.locked).map(\.id)) }
    var validation: String? { draft?.validation(durations: durations, photoIDs: photoIDs) }
    var visible: [AgentShot] { shots.filter { filter.isEmpty || $0.label.localizedCaseInsensitiveContains(filter) || (item($0)?.file.name.localizedCaseInsensitiveContains(filter) == true) } }
    func item(_ shot: AgentShot) -> MediaItem? { store.items.first { $0.id == shot.mediaId } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                if let active = store.activeAgentRun {
                    AgentWorkspaceView(run: active, compact: true).frame(minWidth: 270, idealWidth: 300, maxWidth: 370)
                        .background(Color.pixfunStoryChat)
                }
                previewPane.frame(minWidth: 330, maxWidth: .infinity, maxHeight: .infinity)
                storyPane.frame(minWidth: 320, idealWidth: 360, maxWidth: 460)
            }
        }.background(Color.pixfunBackground)
            .background(StoryPlaybackKeys(enabled: trimBase == nil && floatingTool == nil && !versionsOpen && !keyboardHelpOpen && !addingClip && replacing == nil && dragging.isEmpty, perform: performShortcut))
            .onAppear { load(); rendered.load(preview?.path) }
            .onDisappear { sequence.stop(); boundary.stop(); rendered.player?.pause() }
            .sheet(item: $replacing) { shot in
                StoryReplacementPicker(items: replacementItems, current: shot.mediaId) { replacement in replace(shot, with: replacement) }
            }
            .sheet(isPresented: $addingClip) {
                StoryAddClipPicker { insertClip($0) }.environmentObject(store)
            }
            .onChange(of: run?.id) { _ in if draft?.dirty != true { load() } }
            .onChange(of: run?.version) { _ in captionTypingID = nil; if !saving && draft?.dirty != true { load() } }
            .onChange(of: store.editorAcceptedDraftRevision) { _ in
                guard let current = draft, let accepted = store.editorDrafts[current.runID], !accepted.dirty else { return }
                draft = accepted; syncSelection(); configureSequence()
            }
            .onChange(of: store.editorPauseRequest) { _ in
                sequence.pause(); boundary.pause(); rendered.player?.pause()
            }
            .onChange(of: preview?.path) { _ in
                rendered.load(preview?.path)
                if draft?.dirty != true {
                    sourcePreview = run?.preview == nil
                    if !sourcePreview { sequence.stop() }
                }
            }
            .onChange(of: draft) { value in
                if let value { store.editorDrafts[value.runID] = value }
                syncSelection()
            }
            .onChange(of: store.editorSelection) { scope in
                if scope == nil { selection = []; primary = nil }
            }
            .onChange(of: selectedCaption) { _ in captionTypingID = nil }
            .onChange(of: selectedNarration) { _ in narrationTyping = false }
            .onChange(of: floatingTool) { value in if value != nil { versionsOpen = false } }
            .onChange(of: versionsOpen) { open in
                if open { closeFloatingTools(); store.editorPauseRequest += 1 }
            }
            .onChange(of: tool) { value in
                switch value {
                case .sound: floatingTool = .sound
                case .caption: floatingTool = .captions
                case .seam: floatingTool = .transition
                case .clip, nil: floatingTool = nil
                }
            }
    }
    var replacementItems: [MediaItem] {
        let ids = Set(run?.mediaIds ?? [])
        return store.items.filter { ids.contains($0.id) && $0.status == "ready" && $0.missing != true && ["video", "image"].contains($0.kind) }
    }

    var header: some View {
        HStack(spacing: 12) {
            Button { store.closeEditor() } label: { Image(systemName: "chevron.down") }
                .help("Collapse editor · ⇧⌘E").accessibilityLabel("Collapse editor")
            Text(store.currentProject?.title ?? "Story").font(.pixfun(14, semibold: true)).lineLimit(1)
            Button { versionsOpen.toggle() } label: {
                Label("Versions", systemImage: "clock.arrow.circlepath").font(.pixfun(11))
            }.help("View saved versions without changing the current draft")
                .popover(isPresented: $versionsOpen, arrowEdge: .bottom) {
                    StoryVersionsPopover(versions: StoryVersion.collect(store.agentRuns.filter { $0.projectId == projectID }))
                }
            if draft?.dirty == true { Text("Draft saved locally").font(.pixfun(11)).foregroundStyle(Color.pixfunMuted) }
            Spacer()
            Button { undoStory() } label: { Image(systemName: "arrow.uturn.backward") }
                .help("Undo story edit · ⌘Z").accessibilityLabel("Undo story edit").disabled(busy || conflict || trimBase != nil || draft?.undoStack.isEmpty != false)
            Button { redoStory() } label: { Image(systemName: "arrow.uturn.forward") }
                .help("Redo story edit · ⇧⌘Z").accessibilityLabel("Redo story edit").disabled(busy || conflict || trimBase != nil || draft?.redoStack.isEmpty != false)
            Button(saving ? "Saving…" : busy ? "Generating…" : draft?.dirty == true ? "Update preview" : "Render", action: save)
                .buttonStyle(PixfunButtonStyle(kind: .primary))
                .help("Save changes and update preview · ⌘S")
                .disabled(busy || conflict || trimBase != nil || validation != nil || (draft?.dirty != true && !(run?.status == "review" && run?.preview == nil)))
        }.buttonStyle(PixfunButtonStyle(kind: .quiet)).padding(12)
    }

    var previewPane: some View {
        VStack(spacing: 14) {
            HStack {
                Text(trimBase != nil && boundary.shotID != nil ? "Trim preview" : sourcePreview ? "Draft preview" : stale ? "Previous render" : "Video preview").font(.pixfun(12, semibold: true))
                if sourcePreview {
                    Image(systemName: "info.circle").foregroundStyle(Color.pixfunMuted)
                        .help("Source-only preview. Music, narration, transitions and packaging are applied when rendered.")
                }
                Spacer()
                if preview != nil {
                    Button(sourcePreview ? "View rendered video" : "Review sources") { switchPreview() }
                        .font(.pixfun(11)).buttonStyle(.borderless)
                }
            }
            ZStack {
                Color.black
                if trimBase != nil, boundary.shotID != nil {
                    if let player = boundary.player { NativeVideoPlayer(player: player, showsControls: false) }
                    if boundary.loading { ProgressView().padding(16) }
                } else if sourcePreview {
                    if let image = sequence.photo { Image(nsImage: image).resizable().scaledToFit() }
                    else if let player = sequence.player { NativeVideoPlayer(player: player, showsControls: false) }
                    if sequence.loading { ProgressView("Loading source…").padding(16).background(Color.pixfunSurface).cornerRadius(8) }
                } else if let player = rendered.player {
                    NativeVideoPlayer(player: player, showsControls: false)
                        .overlay {
                            if !rendered.hasStarted, let poster = rendered.poster { Image(nsImage: poster).resizable().scaledToFit().allowsHitTesting(false) }
                        }
                    if !rendered.ready && rendered.issue == nil { ProgressView("Loading preview…").padding(12).background(Color.pixfunSurface).cornerRadius(8) }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 10)).frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = trimBase != nil ? boundary.issue : sourcePreview ? sequence.issue : rendered.issue {
                HStack { Text(error).font(.pixfun(12)).foregroundStyle(.orange); Button("Retry") { retry() } }
            }
            if !sourcePreview && stale {
                Slider(value: Binding(get: { rendered.currentTime }, set: { rendered.seek($0) }), in: 0...max(0.01, rendered.duration))
                    .accessibilityLabel("Previous render position")
            } else {
                StoryTimeArea(shots: shots, captions: captions, finish: finish, duration: duration, time: currentTime, playing: playing,
                    tool: tool, showCaptions: showCaptions, showAudio: showAudio,
                    audioIDs: Set(shots.filter { item($0)?.metadata?.hasAudio == true }.map(\.id)),
                    covers: Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, $0.cover ?? "") }),
                    photoIDs: photoIDs,
                    seek: { seek($0, play: false) }, selectClip: { id in if let shot = shots.first(where: { $0.id == id }) { select(shot) } },
                    selectCaption: selectCaption, selectSeam: selectSeam, moveCaption: moveCaption)
                    .frame(height: 100 + (showAudio && shots.contains(where: { item($0)?.metadata?.hasAudio == true }) ? 26 : 0) + (showCaptions && !captions.isEmpty ? 30 : 0))
                    .popover(isPresented: floatingPresentation(.transition), arrowEdge: .bottom) {
                        selectedTools.frame(width: 340).padding(4)
                    }
            }
            HStack(spacing: 14) {
                Button { step(-1) } label: { Image(systemName: "backward.end.fill") }.help("Previous clip").accessibilityLabel("Previous clip").disabled(!sourcePreview && stale)
                Button { toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                    .help("Space: play/pause · R: replay current clip · ?: shortcuts · Right-click for options").accessibilityLabel(playing ? "Pause story" : "Play story")
                    .contextMenu {
                        Button("Replay current clip · R", action: replayCurrentClip).disabled(shots.isEmpty)
                        Divider()
                        Button("Keyboard shortcuts…") { keyboardHelpOpen = true }
                    }
                    .popover(isPresented: $keyboardHelpOpen, arrowEdge: .bottom) { StoryKeyboardHelp() }
                Button { step(1) } label: { Image(systemName: "forward.end.fill") }.help("Next clip").accessibilityLabel("Next clip").disabled(!sourcePreview && stale)
                Spacer()
                finishingBar
                if let preview {
                    Button { store.exportArtifact(preview) } label: { Image(systemName: "square.and.arrow.up") }
                        .help(stale ? "Render your changes before exporting" : "Export video").accessibilityLabel("Export video").disabled(stale || busy)
                }
            }.buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(trimBase != nil)
            if let issue = issue ?? validation { Text(issue).font(.pixfun(12)).foregroundStyle(.orange).textSelection(.enabled) }
            if conflict {
                HStack { Text("A newer edit is available. Your draft is kept."); Button("Reload") { reload() } }.font(.pixfun(12))
            }
            if removedCount > 0 {
                HStack {
                    Text("\(removedCount) clip\(removedCount == 1 ? "" : "s") removed").font(.pixfun(12))
                    Button("Undo") { undoStory() }.disabled(busy || conflict || trimBase != nil)
                    Spacer()
                    Button { removedCount = 0 } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss removal notice")
                }.foregroundStyle(Color.pixfunMuted)
            }
        }.padding(18).background(Color.pixfunStoryPreview)
    }

    var storyPane: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Story").font(.pixfun(15, semibold: true))
                Text("\(shots.count) clips · \(timestamp(duration))").font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
                Spacer()
                if selection.count > 1 {
                    Button { removeSelection() } label: { Image(systemName: "trash") }.help("Remove selected clips; keep originals").accessibilityLabel("Remove selected clips")
                        .disabled(busy || conflict || !selection.isDisjoint(with: locked) || selection.count >= shots.count)
                }
                if !selection.isEmpty { Button { selection = []; primary = nil; tool = nil; syncSelection() } label: { Image(systemName: "xmark") }.help("Clear selection").accessibilityLabel("Clear story selection") }
            }
            HStack { Image(systemName: "magnifyingglass"); TextField("Find a moment…", text: $filter).textFieldStyle(.plain) }
                .font(.pixfun(12)).padding(8).background(Color.pixfunStoryInput).cornerRadius(7)
            if !StoryTimeline.chapters(shots).isEmpty {
                Menu {
                    ForEach(StoryTimeline.chapters(shots)) { chapter in
                        Button("\(chapter.title) · \(timestamp(chapter.start))") {
                            store.editorRequestedShotID = chapter.id
                        }
                    }
                } label: { Label("Chapters", systemImage: "list.bullet.indent") }
                    .menuStyle(.borderlessButton).font(.pixfun(11)).frame(maxWidth: .infinity, alignment: .leading)
                    .help("Jump to a chapter without starting playback")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visible) { shot in
                            StoryInsertionGap { insertBefore = shot.id; addingClip = true }.disabled(busy || conflict)
                            if Set(shots.compactMap(\.section)).count > 1, let section = shot.section, !section.isEmpty,
                               shots.firstIndex(where: { $0.id == shot.id }).map({ $0 == 0 || shots[$0 - 1].section != section }) == true {
                                Text(section.capitalized).font(.pixfun(11, semibold: true)).foregroundStyle(Color.pixfunMuted).padding(.top, 6)
                            }
                            card(shot).id(shot.id)
                                .onDrop(of: [UTType.plainText], delegate: StoryDrop(target: shot.id, dragging: $dragging, highlight: $dropTarget, move: reorder))
                        }
                        if !dragging.isEmpty {
                            Text("Move to end").font(.pixfun(11)).frame(maxWidth: .infinity).padding(14)
                                .background(Color.pixfunSurface).onDrop(of: [UTType.plainText], delegate: StoryDrop(target: nil, dragging: $dragging, highlight: $dropTarget, move: reorder))
                        }
                        if visible.isEmpty { Text("No matching moments").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).padding() }
                        Button { insertBefore = nil; addingClip = true } label: { Label("Add clip", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 8) }
                            .buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(busy || conflict || shots.count >= 80)
                    }.padding(.vertical, 2)
                }.background(StoryScrollIntent { following = false })
                    .task(id: "\(draft?.runID ?? ""):\(store.editorRequestedShotID ?? "")") {
                        guard let id = store.editorRequestedShotID, shots.contains(where: { $0.id == id }) else { return }
                        filter = ""; selectRequested(id)
                        if store.editorReviewShotID == id {
                            seek(StoryTimeline.offset(id, in: shots), play: false)
                            store.editorReviewShotID = nil
                        }
                        // Let the expanded card enter layout before resolving its scroll anchor.
                        await Task.yield()
                        guard !Task.isCancelled, store.editorRequestedShotID == id else { return }
                        proxy.scrollTo(id, anchor: .center)
                        store.editorRequestedShotID = nil
                    }
                    .onChange(of: activeID) { id in
                        guard following, filter.isEmpty, playing, let id else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: keyboardScrollID) { id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                if !following || !filter.isEmpty {
                    Button { filter = ""; following = true; if let id = activeID { withAnimation { proxy.scrollTo(id, anchor: .center) } } } label: {
                        Label("Back to playhead", systemImage: "location.fill")
                    }.buttonStyle(PixfunButtonStyle(kind: .quiet)).font(.pixfun(12))
                }
            }
        }.padding(12).background(Color.pixfunStoryRail).buttonStyle(.borderless)
    }

    func card(_ shot: AgentShot) -> some View {
        let index = shots.firstIndex { $0.id == shot.id } ?? 0
        let start = StoryTimeline.offset(shot.id, in: shots)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Button { playClip(shot) } label: {
                    ServiceImage(path: item(shot)?.cover).frame(width: 82, height: 58).clipped().cornerRadius(6)
                        .overlay { Image(systemName: "play.circle.fill").font(.system(size: 24)).foregroundStyle(.white).shadow(radius: 3) }
                }.buttonStyle(.plain).help("Play this selected range").accessibilityLabel("Play clip \(index + 1)")
                Button { select(shot) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(shot.label).font(.pixfun(12, semibold: true)).lineLimit(1).foregroundStyle(Color.pixfunInk).help(shot.label)
                            .padding(.trailing, 28)
                        if let tags = item(shot)?.contentTags, !tags.isEmpty {
                            Text(tags.prefix(3).map(\.text).joined(separator: " · ")).font(.pixfun(10)).foregroundStyle(Color.pixfunMuted).lineLimit(1)
                                .padding(.trailing, 28)
                        }
                        Spacer(minLength: 0)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(index + 1)")
                            if run?.editReceipt?.undone == false && run?.editReceipt?.changedShotIds.contains(shot.id) == true {
                                Image(systemName: "pencil.circle.fill").foregroundStyle(Color.pixfunGold)
                                    .help("Updated by the latest AI edit").accessibilityLabel("Updated by AI")
                            }
                            if shot.id == activeID { Image(systemName: playing ? "speaker.wave.2.fill" : "location.fill").foregroundStyle(Color.pixfunGold) }
                            if item(shot)?.metadata?.hasAudio == true && finish.gain(for: shot.id) == 0 { Image(systemName: "speaker.slash.fill").help("Original sound muted") }
                            Text("Cut \(timestamp(start))–\(timestamp(start + shot.end - shot.start))").monospacedDigit()
                            Spacer(minLength: 0)
                            Text(String(format: "%.1fs", shot.end - shot.start)).monospacedDigit().fixedSize()
                        }.font(.pixfun(10)).foregroundStyle(Color.pixfunMuted)
                    }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 58, alignment: .top).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Select to edit · Command-click to select multiple clips").accessibilityLabel("Select clip \(index + 1): \(shot.label)")
                    .accessibilityAddTraits(selection.contains(shot.id) ? [.isSelected] : [])
            }.overlay(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(Color.pixfunMuted).help("Drag to reorder")
                    .frame(width: 24, height: 24).contentShape(Rectangle())
                    .onDrag {
                        guard canEdit(shot) else { return NSItemProvider() }
                        dragging = selection.contains(shot.id) ? selection : [shot.id]
                        return NSItemProvider(object: shot.id as NSString)
                    }
            }
            if primary == shot.id && selection.count == 1 {
                let linked = StoryTimeline.narrationIndices(for: shot.id, shots: shots, cues: finish.narration)
                if !linked.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(linked, id: \.self) { index in
                            let cue = finish.narration[index]
                            Button {
                                selectedNarration = index; floatingTool = .sound
                            } label: {
                                Label((cue.start < start ? "↳ " : "") + cue.text, systemImage: "waveform")
                                    .font(.pixfun(11)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain).foregroundStyle(Color.pixfunMuted)
                                .help(cue.start < start ? "Continued narration · edit in Audio" : "Edit narration in Audio")
                                .disabled(busy || conflict)
                        }
                    }
                }
                if tool == .clip(shot.id) {
                    Divider()
                    trimControls(shot)
                    if item(shot)?.metadata?.hasAudio == true { clipAudioControls(shot) }
                }
                HStack(spacing: 12) {
                    Button { replacing = shot } label: { Image(systemName: "arrow.triangle.2.circlepath").frame(width: 28, height: 28).contentShape(Rectangle()) }
                        .help("Replace with project media").accessibilityLabel("Replace clip").disabled(!canEdit(shot))
                    Button { editWithAI(shot) } label: { Image(systemName: "sparkles").frame(width: 28, height: 28).contentShape(Rectangle()) }
                        .help("Edit this clip with AI").accessibilityLabel("Edit selected clip with AI").disabled(!canEdit(shot))
                    Menu {
                        Button("Locate in preview") { seek(start, play: false) }
                        Divider()
                        Button("Move earlier") { moveAdjacent(shot, -1) }.disabled(index == 0)
                        Button("Move later") { moveAdjacent(shot, 1) }.disabled(index + 1 == shots.count)
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("Clip order options").disabled(!canEdit(shot))
                    Spacer()
                    Button { removeSelection() } label: { Image(systemName: "trash").frame(width: 28, height: 28).contentShape(Rectangle()) }.help("Remove clip; keep original").accessibilityLabel("Remove selected clip").disabled(!canEdit(shot) || shots.count <= 1)
                    Button { selection = []; primary = nil; tool = nil; syncSelection() } label: {
                        Image(systemName: "xmark").frame(width: 28, height: 28).contentShape(Rectangle())
                    }.help("Collapse clip controls").accessibilityLabel("Collapse clip controls")
                }.foregroundStyle(Color.pixfunMuted)
            }
            if shot.locked { Label("Locked", systemImage: "lock.fill").font(.pixfun(10)).foregroundStyle(Color.pixfunMuted) }
        }.padding(11).background(Color.pixfunStoryCard).cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selection.contains(shot.id) ? Color.pixfunGold : Color.pixfunLine, lineWidth: selection.contains(shot.id) ? 2 : 1))
            .overlay(alignment: .top) { if dropTarget == shot.id { Rectangle().fill(Color.pixfunGold).frame(height: 3).offset(y: -5) } }
    }

    @ViewBuilder func trimControls(_ shot: AgentShot) -> some View {
        if photoIDs.contains(shot.mediaId) {
            HStack {
                Image(systemName: "timer").help("Photo duration")
                StoryValueSlider(value: Binding(get: { shot.end }, set: { value in setTrim(shot, leading: false, to: (value * 20).rounded() / 20) }), range: 0.25...max(15, ceil(shot.end / 15) * 15), enabled: canEdit(shot), label: "Photo duration", editing: trimEditing)
                StoryTimeField(value: shot.end, label: "Photo duration in seconds", secondsOnly: true, valid: { $0 >= 0.25 && $0 <= 60 }) { setTrim(shot, leading: false, to: $0) }
            }.disabled(!canEdit(shot))
        } else {
            VStack(spacing: 8) {
                if let item = item(shot) {
                    StorySourceRange(item: item, start: shot.start, end: shot.end, enabled: canEdit(shot), changing: { range, edge in
                        setRange(shot, range, edge: edge)
                    }, editing: trimEditing)
                }
                HStack {
                    Text("In")
                    StoryTimeField(value: shot.start, label: "Source in point", valid: { $0 >= 0 && $0 <= shot.end - 0.25 }) { setTrim(shot, leading: true, to: $0) }
                    Spacer(minLength: 3)
                    Text("Out")
                    StoryTimeField(value: shot.end, label: "Source out point", valid: { $0 >= shot.start + 0.25 && $0 <= (durations[shot.mediaId] ?? shot.end) }) { setTrim(shot, leading: false, to: $0) }
                }
            }.font(.pixfun(10)).foregroundStyle(Color.pixfunMuted).disabled(!canEdit(shot))
        }
    }

    func selectRequested(_ id: String) {
        guard shots.contains(where: { $0.id == id }) else { return }
        selection = [id]; primary = id; tool = .clip(id); selectedCaption = nil; following = false; syncSelection()
    }
    // Reuse the same guarded actions as the buttons; never steal native text undo.
    func performShortcut(_ action: StoryKeyAction) -> Bool {
        switch action {
        case .toggle: if !shots.isEmpty { toggle() }
        case .replay: replayCurrentClip()
        case .nudge(let direction, let seconds): nudgePlayhead(direction, seconds)
        case .select(let direction):
            let ids = visible.map(\.id)
            if !ids.isEmpty {
                let index = primary.flatMap { ids.firstIndex(of: $0) }
                let next = index.map { min(ids.count - 1, max(0, $0 + direction)) } ?? (direction > 0 ? 0 : ids.count - 1)
                selectRequested(ids[next]); keyboardScrollID = ids[next]
            }
        case .start: jumpToTime(0)
        case .end: jumpToTime(playbackDuration)
        case .undo: undoStory()
        case .redo: redoStory()
        case .save: save()
        case .remove:
            // A subtitle/seam selection must not delete a previously selected clip.
            if case .clip = tool { removeSelection() }
            else if tool == nil && !selection.isEmpty { removeSelection() }
        case .clearSelection:
            guard !selection.isEmpty || tool != nil else { return false }
            selection = []; primary = nil; tool = nil; selectedCaption = nil; syncSelection()
        case .collapse: store.closeEditor()
        case .help: keyboardHelpOpen = true
        }
        return true
    }
    func undoStory() {
        guard !busy, !conflict, trimBase == nil, draft?.undoStack.isEmpty == false else { return }
        draft?.undo(); edited()
    }
    func redoStory() {
        guard !busy, !conflict, trimBase == nil, draft?.redoStack.isEmpty == false else { return }
        draft?.redo(); edited()
    }
    func playClip(_ shot: AgentShot) {
        rendered.player?.pause(); configureSequence(); sourcePreview = true
        sequence.seek(StoryTimeline.offset(shot.id, in: shots), play: true, stoppingAt: shot.id)
    }
    func replayCurrentClip() {
        guard let id = activeID ?? primary ?? shots.first?.id, let shot = shots.first(where: { $0.id == id }) else { return }
        playClip(shot)
    }
    func replace(_ shot: AgentShot, with item: MediaItem) {
        guard canEdit(shot), replacementItems.contains(where: { $0.id == item.id }),
              let replacement = StoryTimeline.replacing(shot, with: item), let index = draft?.shots.firstIndex(where: { $0.id == shot.id }), var next = draft?.shots else { return }
        next[index] = replacement; draft?.replace(next); replacing = nil; edited()
    }
    func editWithAI(_ shot: AgentShot) {
        guard canEdit(shot) else { return }
        selection = [shot.id]; primary = shot.id; syncSelection()
        store.chooseComposerTarget(wholeFilm: false); store.editorComposerFocus += 1
    }

    func canEdit(_ shot: AgentShot) -> Bool { !busy && !conflict && !locked.contains(shot.id) }
    func select(_ shot: AgentShot) {
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            if selection.contains(shot.id) { selection.remove(shot.id) } else { selection.insert(shot.id) }
        } else { selection = [shot.id] }
        primary = selection.contains(shot.id) ? shot.id : shots.first { selection.contains($0.id) }?.id
        tool = selection.count == 1 ? primary.map(StoryTool.clip) : nil
        selectedCaption = nil
        syncSelection()
    }
    func syncSelection() {
        selection.formIntersection(Set(shots.map(\.id)))
        if primary.map({ !selection.contains($0) }) == true { primary = shots.first { selection.contains($0.id) }?.id }
        guard let draft, !selection.isEmpty else { store.editorSelection = nil; return }
        store.editorSelection = EditorSelection(runId: draft.runID, version: draft.version, shotIds: shots.filter { selection.contains($0.id) }.map(\.id))
    }
    func configureSequence() {
        sequence.configure(shots: draft?.shots ?? [], photos: photoIDs, service: store.service, volume: draft?.finishing?.originalVolume ?? 1)
        sequence.updateFinishing(draft?.finishing)
    }
    func seek(_ seconds: Double, play: Bool) {
        guard !shots.isEmpty else { return }
        if sourcePreview || stale || preview == nil {
            if !sourcePreview { configureSequence(); rendered.player?.pause(); sourcePreview = true }
            sequence.seek(seconds, play: play)
        } else {
            rendered.seek(seconds)
            if play { rendered.player?.play() }
        }
    }
    func toggle() { if sourcePreview { sequence.toggleAll() } else { rendered.toggle() } }
    var playbackDuration: Double { sourcePreview ? duration : max(0, rendered.duration) }
    func jumpToTime(_ value: Double) {
        if !sourcePreview && stale { rendered.player?.pause(); rendered.seek(value) }
        else { seek(value, play: false) }
    }
    func nudgePlayhead(_ direction: Int, _ seconds: Bool) {
        jumpToTime(StoryTimeline.steppedTime(currentTime, direction: direction, duration: playbackDuration, seconds: seconds))
    }
    func step(_ delta: Int) {
        guard let index = StoryTimeline.index(at: currentTime, in: shots) else { return }
        let next = min(shots.count - 1, max(0, index + delta))
        seek(StoryTimeline.offset(shots[next].id, in: shots), play: playing)
    }
    func switchPreview() {
        let time = currentTime
        if sourcePreview { sequence.pause(); sourcePreview = false; rendered.seek(min(time, rendered.duration)) }
        else { rendered.player?.pause(); configureSequence(); sourcePreview = true; sequence.seek(time) }
    }
    func retry() { if sourcePreview { sequence.seek(sequence.time) } else { rendered.load(preview?.path) } }
    func edited() {
        captionTypingID = nil
        if case .clip(let id) = tool, !shots.contains(where: { $0.id == id }) { tool = nil }
        if case .caption(let id) = tool, !captions.contains(where: { $0.id == id }) { tool = nil }
        if case .seam(let left, let right) = tool, !zip(shots, shots.dropFirst()).contains(where: { $0.id == left && $1.id == right }) { tool = nil }
        trimBase = nil; trimShots = nil; issue = nil; removedCount = 0; boundary.stop(); rendered.player?.pause()
        syncSelection(); configureSequence(); sourcePreview = true
        sequence.seek(primary.map { StoryTimeline.offset($0, in: shots) } ?? min(currentTime, duration))
    }
    func trim(_ shot: AgentShot, leading: Bool, to value: Double) {
        guard canEdit(shot) else { return }
        if trimBase == nil { trimBase = draft; sequence.pause(); rendered.player?.pause() }
        guard let original = trimBase?.shots.first(where: { $0.id == shot.id }) else { return }
        trimShots = trimBase?.trimming(shot.id, leading: leading, delta: value - (leading ? original.start : original.end), durations: durations, photoIDs: photoIDs)
    }
    func trimEditing(_ editing: Bool) {
        if editing {
            trimBase = draft; sequence.pause(); rendered.player?.pause()
            if let shot = shots.first(where: { $0.id == primary }), !photoIDs.contains(shot.mediaId) {
                var source = shot; source.start = 0; source.end = durations[shot.mediaId] ?? shot.end
                boundary.configure(shots: [source], photos: [], service: store.service, volume: 0)
                boundary.seek(shot.start)
            }
        }
        else { commitTrim() }
    }
    func setRange(_ shot: AgentShot, _ range: ClosedRange<Double>, edge: Int) {
        guard canEdit(shot), let base = trimBase, let index = base.shots.firstIndex(where: { $0.id == shot.id }) else { return }
        var next = base.shots; next[index].start = range.lowerBound; next[index].end = range.upperBound
        var candidate = base; candidate.shots = next
        guard candidate.validation(durations: durations, photoIDs: photoIDs) == nil else { return }
        trimShots = next
        boundary.seek(edge > 0 ? max(range.lowerBound, range.upperBound - 0.03) : range.lowerBound)
    }
    func setTrim(_ shot: AgentShot, leading: Bool, to value: Double) {
        let discrete = trimBase == nil
        trim(shot, leading: leading, to: value)
        if discrete { commitTrim() }
    }
    func commitTrim() {
        guard !busy, !conflict, trimBase == draft, let next = trimShots else { trimBase = nil; trimShots = nil; boundary.stop(); return }
        draft?.replace(next); edited()
    }
    func reorder(_ ids: Set<String>, _ target: String?) {
        guard !busy, !conflict, let next = StoryTimeline.move(ids, before: target, in: shots, locked: locked) else { return }
        draft?.replace(next); edited()
    }
    func moveAdjacent(_ shot: AgentShot, _ delta: Int) {
        guard let index = shots.firstIndex(where: { $0.id == shot.id }), shots.indices.contains(index + delta) else { return }
        let target = delta < 0 ? shots[index - 1].id : (index + 2 < shots.count ? shots[index + 2].id : nil)
        reorder([shot.id], target)
    }
    func removeSelection() {
        guard !busy, !conflict, trimBase == nil, !selection.isEmpty, selection.isDisjoint(with: locked), selection.count < shots.count else { return }
        let count = selection.count
        draft?.replace(shots.filter { !selection.contains($0.id) }); selection = []; primary = nil; edited(); removedCount = count
    }
    func load() {
        guard let run else { return }
        let cached = store.editorDrafts[run.id]
        draft = cached?.dirty == true || cached?.version == run.version ? cached : EditorDraft(run: run)
        draft?.hydrateLayers(from: run)
        selection = []; primary = nil; trimBase = nil; trimShots = nil; selectedNarration = nil; narrationTyping = false; syncSelection()
        configureSequence()
        sourcePreview = draft?.dirty == true || run.preview == nil
        if sourcePreview { sequence.seek(0) }
    }
    func reload() {
        let alert = NSAlert(); alert.messageText = "Replace your local draft with the latest saved edit?"
        alert.addButton(withTitle: "Reload"); alert.addButton(withTitle: "Keep draft")
        if alert.runModal() == .alertFirstButtonReturn, let run {
            store.editorDrafts[run.id] = EditorDraft(run: run); load()
        }
    }
    func save() {
        guard let run, let value = draft, !busy, !conflict, trimBase == nil, validation == nil else { return }
        if !value.dirty {
            if run.status == "review", run.preview == nil { store.agentAction("approve", run: run) }
            return
        }
        saving = true; issue = nil; sequence.pause(); rendered.player?.pause()
        Task {
            defer { saving = false }
            do {
                try await store.saveAgentTimeline(run, shots: value.shots, version: value.version, finishing: value.finishing)
                if let updated = store.agentRuns.first(where: { $0.id == run.id }) {
                    var accepted = value; accepted.base = updated.timeline; accepted.shots = updated.timeline; accepted.version = updated.version
                    accepted.finishing = updated.finishing ?? .empty; accepted.baseFinishing = accepted.finishing
                    draft = accepted; syncSelection(); store.agentAction("approve", run: updated)
                }
            } catch { issue = error.localizedDescription }
        }
    }
}

extension StoryEditorWorkspace {
    var finish: AgentFinishing { draft?.finishing ?? .empty }
    var captions: [AgentFinishing.Caption] { (finish.captions ?? []).sorted { $0.start < $1.start } }
    // A single presentation state keeps popovers mutually exclusive. Dismissal
    // clears only its own tool, so a retiring popover cannot close its successor.
    func floatingPresentation(_ target: StoryFloatingTool) -> Binding<Bool> {
        Binding(get: { floatingTool == target }, set: { presented in
            if !presented && floatingTool == target { closeFloatingTools() }
        })
    }
    func closeFloatingTools() {
        floatingTool = nil; captionTypingID = nil; narrationTyping = false
        if !clipToolsInRail { tool = nil; selectedCaption = nil }
    }
    var finishingBar: some View {
        HStack(spacing: 14) {
            Group {
                Button {
                    if floatingTool == .sound { closeFloatingTools() }
                    else { floatingTool = .sound }
                } label: { Image(systemName: finish.originalMuted == true ? "speaker.slash" : "speaker.wave.2") }
                    .accessibilityLabel("Audio").help("Music, narration and original sound")
                    .popover(isPresented: floatingPresentation(.sound), arrowEdge: .top) {
                        StoryAudioPopover(finish: finish, duration: duration,
                            musicSources: store.items.filter { $0.kind == "audio" && $0.status == "ready" && $0.missing != true && (run?.mediaIds ?? []).contains($0.id) },
                            originalControls: shots.contains(where: { item($0)?.metadata?.hasAudio == true }) ? AnyView(VStack {
                                soundControls(nil)
                                Toggle("Show audio track", isOn: $showAudio).font(.pixfun(11))
                            }) : nil, selectedNarration: $selectedNarration, commit: applyMixLayers,
                            locate: { seek($0, play: false) }, request: requestAudioWithAI)
                            .disabled(busy || conflict)
                    }
            }
            HStack(spacing: 14) {
                Button {
                    if floatingTool == .captions { closeFloatingTools() }
                    else { floatingTool = .captions }
                } label: { Image(systemName: "captions.bubble") }
                    .accessibilityLabel("Captions").help("View and edit captions")
                Button(action: addCaption) { Image(systemName: "plus") }
                    .accessibilityLabel("Add caption").help("Add caption").disabled(captions.count >= 80 || duration < 0.25)
            }
            .popover(isPresented: floatingPresentation(.captions), arrowEdge: .top) { captionPopover }
        }.foregroundStyle(Color.pixfunMuted).buttonStyle(.borderless).disabled(busy || conflict)
    }
    var captionPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Captions").font(.pixfun(12, semibold: true))
                Spacer()
                Button(action: addCaption) { Image(systemName: "plus") }
                    .accessibilityLabel("Add caption").disabled(captions.count >= 80 || duration < 0.25)
                Button(action: closeFloatingTools) { Image(systemName: "xmark") }
                    .accessibilityLabel("Close captions").keyboardShortcut(.cancelAction)
            }
            if captions.isEmpty {
                Button("Add caption", action: addCaption).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .disabled(duration < 0.25)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(captions) { cue in
                                Button { selectCaption(cue.id) } label: {
                                    HStack {
                                        Text(cue.text).lineLimit(1)
                                        Spacer()
                                        Text("\(timestamp(cue.start))–\(timestamp(cue.end))").monospacedDigit().foregroundStyle(Color.pixfunMuted)
                                    }.font(.pixfun(11)).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(selectedCaption == cue.id ? Color.pixfunBrandSoft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                }.buttonStyle(.plain).id(cue.id)
                            }
                        }
                    }.frame(height: min(160, CGFloat(captions.count) * 36))
                        .onChange(of: selectedCaption) { id in if let id { proxy.scrollTo(id) } }
                }
                if let cue = captions.first(where: { $0.id == selectedCaption }) {
                    Divider()
                    captionTools(cue)
                }
                Toggle("Show caption track", isOn: $showCaptions).font(.pixfun(11))
            }
        }.padding(14).frame(width: 360).buttonStyle(.borderless).disabled(busy || conflict)
    }
    var clipToolsInRail: Bool { if case .clip = tool { return true }; return false }
    @ViewBuilder var selectedTools: some View {
        if let tool {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(toolTitle).font(.pixfun(12, semibold: true)).lineLimit(1)
                    Spacer()
                    if let time = toolTime {
                        Button { seek(time, play: false) } label: { Image(systemName: "scope") }
                            .accessibilityLabel("Locate selected item").help("Show selected item without playing")
                    }
                    if case .clip(let id) = tool, let shot = shots.first(where: { $0.id == id }) {
                        Button { playClip(shot) } label: { Image(systemName: "play.rectangle") }
                            .accessibilityLabel("Preview selected clip").help("Play only this selected range")
                    }
                    Button { self.tool = nil; closeFloatingTools() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close selected tools")
                }
                switch tool {
                case .clip(let id):
                    if let shot = shots.first(where: { $0.id == id }) {
                        trimControls(shot)
                        if item(shot)?.metadata?.hasAudio == true { clipAudioControls(shot) }
                    }
                case .caption(let id):
                    if let cue = captions.first(where: { $0.id == id }) { captionTools(cue) }
                case .seam(let left, let right):
                    if let a = shots.first(where: { $0.id == left }), let b = shots.first(where: { $0.id == right }) { seamTools(a, b) }
                case .sound: soundControls(nil)
                }
            }.padding(12).background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 9))
                .buttonStyle(.borderless).disabled(busy || conflict)
        }
    }
    var toolTitle: String {
        switch tool {
        case .clip(let id): return shots.first(where: { $0.id == id })?.label ?? "Clip"
        case .caption: return "Caption"
        case .seam: return "Transition"
        case .sound: return "Original sound"
        case nil: return ""
        }
    }
    var toolTime: Double? {
        switch tool {
        case .clip(let id): return StoryTimeline.offset(id, in: shots)
        case .caption(let id): return captions.first { $0.id == id }?.start
        case .seam(_, let right): return max(0, StoryTimeline.offset(right, in: shots)-0.5)
        default: return nil
        }
    }
    func selectCaption(_ id: String) {
        selection = []; primary = nil; syncSelection(); selectedCaption = id; tool = .caption(id); floatingTool = .captions
    }
    func selectSeam(_ left: String, _ right: String) {
        selection = []; primary = nil; syncSelection(); selectedCaption = nil; tool = .seam(left, right)
    }
    func soundControls(_ shot: AgentShot?) -> some View {
        let audio = shot.map { finish.audio(for: $0.id) }
        let volume = audio?.volume ?? finish.originalVolume
        let muted = audio?.muted ?? (finish.originalMuted == true)
        return HStack(spacing: 8) {
            Button {
                var next = finish
                if let shot { var value = next.audio(for: shot.id); value.muted.toggle(); next.clipAudio = (next.clipAudio ?? []).filter { $0.shotId != shot.id } + [value] }
                else { next.originalMuted = !muted }
                applyLayers(next, audio: true)
            } label: { Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 28, height: 28) }
                .accessibilityLabel(muted ? "Unmute original sound" : "Mute original sound").help(muted ? "Unmute" : "Mute")
            StoryValueSlider(value: Binding(get: { volume }, set: { value in
                var next = finish
                if let shot { var clip = next.audio(for: shot.id); clip.volume = value; next.clipAudio = (next.clipAudio ?? []).filter { $0.shotId != shot.id } + [clip] }
                else { next.originalVolume = value }
                if audioBase == nil { audioBase = finish }
                draft?.finishing = next; sequence.updateFinishing(next)
            }), range: 0...1, enabled: !busy && !conflict, label: "Original sound volume", editing: { editing in
                if editing { audioBase = finish; beginSoundPreview() }
                else if let base = audioBase { let next = finish; draft?.finishing = base; audioBase = nil; applyLayers(next, audio: true) }
            })
            Text("\(Int((volume * 100).rounded()))%").font(.pixfun(11)).monospacedDigit().frame(width: 34)
        }.buttonStyle(.borderless)
    }
    func clipAudioControls(_ shot: AgentShot) -> some View { soundControls(shot).disabled(!canEdit(shot)) }
    func beginSoundPreview() {
        if !sourcePreview {
            let time = currentTime; let play = playing
            rendered.player?.pause(); configureSequence(); sourcePreview = true; sequence.seek(time, play: play)
        }
    }
    func applyLayers(_ value: AgentFinishing, audio: Bool = false) {
        guard !busy, !conflict else { return }
        captionTypingID = nil; narrationTyping = false
        draft?.setFinishing(value); issue = nil
        if audio { beginSoundPreview(); sequence.updateFinishing(value) }
    }
    func applyMixLayers(_ value: AgentFinishing, typing: Bool) {
        guard !busy, !conflict else { return }
        sequence.pause(); rendered.player?.pause()
        if typing {
            if !narrationTyping { draft?.remember(); narrationTyping = true }
            draft?.finishing = value
        } else { applyLayers(value) }
        issue = nil
    }
    func requestAudioWithAI(_ prompt: String) {
        closeFloatingTools()
        store.chooseComposerTarget(wholeFilm: true)
        let previous = store.composerDraft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        store.composerDraft.prompt = previous.isEmpty ? prompt : previous + "\n" + prompt
        store.editorComposerFocus += 1
    }
    func seamTools(_ left: AgentShot, _ right: AgentShot) -> some View {
        let value = finish.seam(left.id, right.id)
        let maximum = min(1, (left.end-left.start)/3, (right.end-right.start)/3)
        return VStack(alignment: .leading, spacing: 12) {
                        Picker("Transition", selection: Binding(get: { value.kind }, set: { kind in setSeam(left, right, kind: kind, duration: min(value.duration, maximum)) })) {
                            Text("Cut").tag("none"); Text("Fade through black").tag("fade")
                        }
                        if value.kind == "fade" {
                            HStack { Text("Fade per side"); StoryTimeField(value: min(value.duration, maximum), label: "Transition duration per side", secondsOnly: true,
                                valid: { $0 >= 0.05 && $0 <= maximum }) { setSeam(left, right, kind: "fade", duration: $0) }; Text("s") }
                        }
        }.font(.pixfun(12)).disabled(busy || conflict || left.locked || right.locked)
    }
    func setSeam(_ left: AgentShot, _ right: AgentShot, kind: String, duration: Double) {
        var next = finish
        next.seams = (next.seams ?? []).filter { !($0.afterShotId == left.id && $0.beforeShotId == right.id) } + [.init(afterShotId: left.id, beforeShotId: right.id, kind: kind, duration: duration)]
        applyLayers(next)
    }
    func captionTools(_ cue: AgentFinishing.Caption) -> some View {
        VStack(spacing: 8) {
                TextField("Caption", text: Binding(get: { cue.text }, set: { text in var next = cue; next.text = text; updateCaption(next, typing: true) }))
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Caption text")
                HStack {
                    Text("In")
                    StoryTimeField(value: cue.start, label: "Caption in point", valid: { validCaption(cue, start: $0, end: cue.end) }) { var next = cue; next.start = $0; updateCaption(next) }
                    Text("Out")
                    StoryTimeField(value: cue.end, label: "Caption out point", valid: { validCaption(cue, start: cue.start, end: $0) }) { var next = cue; next.end = $0; updateCaption(next) }
                    Spacer()
                    Button { var next = finish; next.captions = captions.filter { $0.id != cue.id }; applyLayers(next); selectedCaption = nil; tool = nil } label: { Image(systemName: "trash") }.accessibilityLabel("Delete caption")
                }.font(.pixfun(11))
        }.buttonStyle(.borderless).disabled(busy || conflict)
    }
    func validCaption(_ cue: AgentFinishing.Caption, start: Double, end: Double) -> Bool {
        start.isFinite && end.isFinite && start >= 0 && end <= duration && end-start >= 0.25 && !captions.contains { $0.id != cue.id && start < $0.end && end > $0.start }
    }
    func updateCaption(_ cue: AgentFinishing.Caption, typing: Bool = false) {
        guard !busy, !conflict else { return }
        var next = finish; next.captions = captions.map { $0.id == cue.id ? cue : $0 }
        if typing && captionTypingID == cue.id { draft?.finishing = next }
        else { applyLayers(next) }
        captionTypingID = typing ? cue.id : nil
    }
    func moveCaption(_ id: String, _ delta: Double) {
        guard var cue = captions.first(where: { $0.id == id }) else { return }
        let length = cue.end-cue.start
        let start = min(max(0, cue.start+delta), duration-length)
        guard validCaption(cue, start: start, end: start+length) else { return }
        cue.start = start; cue.end = start+length; updateCaption(cue)
    }
    func addCaption() {
        guard !busy, !conflict, captions.count < 80 else { return }
        var start = min(primary.map { StoryTimeline.offset($0, in: shots) } ?? currentTime, max(0, duration-0.25))
        for cue in captions where cue.end > start {
            if cue.start-start >= 0.25 { break }
            start = cue.end
        }
        let end = min(duration, start+3, captions.first(where: { $0.start >= start })?.start ?? duration)
        guard end-start >= 0.25 else { issue = "Move the playhead to a free caption range."; return }
        let cue = AgentFinishing.Caption(id: UUID().uuidString, start: start, end: end, text: "Caption")
        var next = finish; next.captions = captions + [cue]; applyLayers(next); selectCaption(cue.id)
    }
    func insertClip(_ item: MediaItem) -> String? {
        guard !busy, !conflict, var value = draft,
              let next = StoryTimeline.inserting(item, before: insertBefore, in: shots) else { return "Cannot insert here. Check locked clips and timeline limits." }
        value.replace(next)
        if let error = value.validation(durations: durations, photoIDs: photoIDs) { return error }
        let oldIDs = Set(shots.map(\.id))
        let added = next.first { !oldIDs.contains($0.id) }!
        draft = value; addingClip = false; selection = [added.id]; primary = added.id; tool = .clip(added.id); edited()
        store.editorRequestedShotID = added.id
        return nil
    }
}

struct StoryCaptionTrack: View {
    let captions: [AgentFinishing.Caption]
    let duration: Double
    let time: Double
    let selected: String?
    let select: (String) -> Void
    let move: (String, Double) -> Void
    @GestureState private var drag: CGFloat = 0
    @GestureState private var draggedID: String?
    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / max(0.01, duration)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.pixfunBackground)
                ForEach(captions) { cue in
                    Text(cue.text).font(.pixfun(10)).lineLimit(1).padding(.horizontal, 4)
                        .frame(width: max(4, (cue.end-cue.start)*scale), height: 28, alignment: .leading)
                        .background(selected == cue.id ? Color.pixfunGold : Color.pixfunBrandSoft, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(selected == cue.id ? Color.pixfunOnAccent : Color.pixfunInk)
                        .offset(x: cue.start*scale + (draggedID == cue.id ? drag : 0))
                        .onTapGesture { select(cue.id) }
                        .gesture(DragGesture(minimumDistance: 4)
                            .updating($draggedID) { _, state, _ in state = cue.id }
                            .updating($drag) { value, state, _ in state = value.translation.width }
                            .onEnded { value in move(cue.id, value.translation.width/scale) })
                        .accessibilityLabel("Caption: \(cue.text), \(StoryTimeline.timecode(cue.start)) to \(StoryTimeline.timecode(cue.end))")
                        .accessibilityAddTraits(.isButton).accessibilityAction { select(cue.id) }
                }
            }.clipped()
        }
    }
}

/// Native tracking survives card re-layout while a duration change moves later cards.
struct StoryValueSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let enabled: Bool
    let label: String
    let editing: (Bool) -> Void
    func makeNSView(context: Context) -> TrackingSlider {
        let slider = TrackingSlider(); slider.isContinuous = true; slider.target = slider
        slider.action = #selector(TrackingSlider.changed); slider.controlSize = .small
        return slider
    }
    func updateNSView(_ slider: TrackingSlider, context: Context) {
        slider.editing = editing; slider.commit = { value = $0 }; slider.isEnabled = enabled
        slider.setAccessibilityLabel(label)
        if !slider.tracking { slider.minValue = range.lowerBound; slider.maxValue = range.upperBound; slider.doubleValue = value }
    }
    final class TrackingSlider: NSSlider {
        var tracking = false
        var editing: ((Bool) -> Void)?
        var commit: ((Double) -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            tracking = true; editing?(true); track(event)
        }
        override func mouseDragged(with event: NSEvent) { if tracking { track(event) } }
        override func mouseUp(with event: NSEvent) {
            guard tracking else { return }
            track(event); tracking = false; editing?(false)
        }
        private func track(_ event: NSEvent) {
            let x = convert(event.locationInWindow, from: nil).x
            let fraction = min(1, max(0, Double((x - 8) / max(1, bounds.width - 16))))
            doubleValue = minValue + fraction * (maxValue - minValue); changed()
        }
        @objc func changed() { commit?(doubleValue) }
    }
}

struct StoryOverview: View {
    let shots: [AgentShot]
    let time: Double
    let seek: (Double) -> Void
    var total: Double { shots.reduce(0) { $0 + $1.end - $1.start } }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(shots) { shot in
                        Rectangle().fill(Color.pixfunGold.opacity(time >= StoryTimeline.offset(shot.id, in: shots) ? 0.65 : 0.2))
                            .frame(width: geometry.size.width * (shot.end - shot.start) / max(0.01, total))
                            .overlay(alignment: .trailing) { Rectangle().fill(Color.pixfunBackground).frame(width: 1) }
                    }
                }.frame(height: 7)
                Capsule().fill(Color.pixfunGold).frame(width: 3, height: 17)
                    .offset(x: max(0, min(geometry.size.width - 3, geometry.size.width * time / max(0.01, total))))
            }.frame(height: 24).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in seek(min(total, max(0, value.location.x / max(1, geometry.size.width) * total))) })
        }.accessibilityElement(children: .ignore).accessibilityLabel("Story position").accessibilityValue(timestamp(time))
            .accessibilityAdjustableAction { direction in seek(min(total, max(0, time + (direction == .increment ? 1 : -1)))) }
    }
}

private struct StoryDrop: DropDelegate {
    let target: String?
    @Binding var dragging: Set<String>
    @Binding var highlight: String?
    let move: (Set<String>, String?) -> Void
    func validateDrop(info: DropInfo) -> Bool { !dragging.isEmpty && !(target.map { dragging.contains($0) } ?? false) }
    func dropEntered(info: DropInfo) { if validateDrop(info: info) { highlight = target } }
    func dropExited(info: DropInfo) { highlight = nil }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: validateDrop(info: info) ? .move : .forbidden) }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info), let provider = info.itemProviders(for: [UTType.plainText]).first else { return false }
        let ids = dragging
        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let id = value as? String, ids.contains(id) else { return }
            DispatchQueue.main.async { move(ids, target); dragging = []; highlight = nil }
        }
        return true
    }
}

/// Observe only user scroll input inside this list. Programmatic playback following is unaffected.
private struct StoryScrollIntent: NSViewRepresentable {
    let action: () -> Void
    func makeNSView(context: Context) -> ScrollIntentView { ScrollIntentView() }
    func updateNSView(_ view: ScrollIntentView, context: Context) { view.action = action }
    final class ScrollIntentView: NSView {
        var action: (() -> Void)?
        var monitor: Any?
        override func viewDidMoveToWindow() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown]) { [weak self] event in
                guard let self, event.window === self.window, self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                self.action?(); return event
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
