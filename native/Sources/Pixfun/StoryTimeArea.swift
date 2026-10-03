import SwiftUI

enum StoryTool: Equatable {
    case clip(String), caption(String), seam(String, String), sound
}

/// All lanes use one scale, one horizontal scroll position, and one playhead.
struct StoryTimeArea: View {
    let shots: [AgentShot]
    let captions: [AgentFinishing.Caption]
    let finish: AgentFinishing
    let duration: Double
    let time: Double
    let playing: Bool
    let tool: StoryTool?
    let showCaptions: Bool
    let showAudio: Bool
    let audioIDs: Set<String>
    let covers: [String: String]
    let photoIDs: Set<String>
    let seek: (Double) -> Void
    let selectClip: (String) -> Void
    let selectCaption: (String) -> Void
    let selectSeam: (String, String) -> Void
    let moveCaption: (String, Double) -> Void
    @State private var zoom = 1.0
    @State private var following = true
    @State private var scrollOffset = 0.0
    var body: some View {
        GeometryReader { geometry in
            let scale = StoryTimeline.timelineScale(viewport: geometry.size.width, duration: duration, zoom: zoom)
            let width = max(geometry.size.width, duration*scale)
            ScrollViewReader { proxy in
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    Button { following = true; reveal(time, proxy: proxy) } label: { Image(systemName: "location.fill") }
                        .foregroundStyle(following ? Color.pixfunGold : Color.pixfunMuted)
                        .accessibilityLabel("Follow playhead").accessibilityValue(following ? "On" : "Paused").help("Return to playhead and follow playback")
                    Spacer()
                    Button { zoom = max(1, zoom / 2) } label: { Image(systemName: "minus.magnifyingglass") }
                        .disabled(zoom <= 1).accessibilityLabel("Zoom out timeline")
                    Button { zoom = 1 } label: { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                        .accessibilityLabel("Fit whole timeline").help("Fit the whole video")
                    Button { zoom = min(32, zoom * 2) } label: { Image(systemName: "plus.magnifyingglass") }
                        .disabled(zoom >= 32).accessibilityLabel("Zoom in timeline")
                }.font(.system(size: 12)).buttonStyle(.borderless).foregroundStyle(Color.pixfunMuted).frame(height: 22)
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 4) {
                        ruler(width: width, scale: scale)
                        ZStack(alignment: .leading) {
                            HStack(spacing: 0) {
                                ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                                    let clipWidth = (shot.end-shot.start)*scale
                                    let clipStart = StoryTimeline.offset(shot.id, in: shots)*scale
                                    Button { selectClip(shot.id) } label: {
                                        StoryFilmstrip(shot: shot, cover: covers[shot.mediaId], isPhoto: photoIDs.contains(shot.mediaId), width: clipWidth,
                                            visible: clipStart + clipWidth >= scrollOffset && clipStart <= scrollOffset + geometry.size.width)
                                            .overlay(alignment: .bottomLeading) {
                                                if clipWidth >= 28 {
                                                    Text("\(index+1)").font(.pixfun(10, semibold: true)).foregroundStyle(.white)
                                                        .padding(.horizontal, 4).padding(.vertical, 2)
                                                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 3)).padding(3)
                                                }
                                            }
                                            .overlay(Rectangle().strokeBorder(tool == .clip(shot.id) ? Color.pixfunGold : Color.pixfunStoryPreview, lineWidth: tool == .clip(shot.id) ? 2 : 1))
                                    }.buttonStyle(.plain).help(shot.label).accessibilityLabel("Select timeline clip \(index+1)")
                                }
                            }
                            ForEach(Array(shots.dropFirst().enumerated()), id: \.element.id) { index, right in
                                let left = shots[index]
                                let value = finish.seam(left.id, right.id)
                                Button { selectSeam(left.id, right.id) } label: {
                                    Image(systemName: value.kind == "fade" ? "circle.lefthalf.filled" : "line.diagonal")
                                        .font(.system(size: 9, weight: .semibold)).frame(width: min(18, max(8, min(left.end-left.start,right.end-right.start)*scale*0.6)), height: 20)
                                        .background(tool == .seam(left.id, right.id) ? Color.pixfunGold : Color.pixfunLine, in: RoundedRectangle(cornerRadius: 3))
                                        .foregroundStyle(tool == .seam(left.id, right.id) ? Color.pixfunOnAccent : Color.pixfunInk)
                                }.buttonStyle(.plain).position(x: StoryTimeline.offset(right.id, in: shots)*scale, y: 10)
                                    .help(value.kind == "fade" ? "Fade through black" : "Add transition")
                                    .accessibilityLabel("Transition before \(right.label)")
                            }
                        }.frame(height: 44)
                        if showAudio && !audioIDs.isEmpty {
                            HStack(spacing: 0) {
                                ForEach(shots) { shot in
                                    Button { selectClip(shot.id) } label: {
                                        Group {
                                            if audioIDs.contains(shot.id) {
                                                Image(systemName: finish.gain(for: shot.id) == 0 ? "speaker.slash" : "speaker.wave.2")
                                                    .font(.system(size: 10)).frame(maxWidth: .infinity, maxHeight: .infinity)
                                                    .background(Color.pixfunFocus.opacity(finish.gain(for: shot.id) == 0 ? 0.08 : 0.22))
                                            } else { Color.clear }
                                        }.frame(width: (shot.end-shot.start)*scale, height: 22)
                                    }.buttonStyle(.plain).disabled(!audioIDs.contains(shot.id)).accessibilityLabel("Original audio: \(shot.label)")
                                }
                            }
                        }
                        if showCaptions && !captions.isEmpty {
                            StoryCaptionTrack(captions: captions, duration: duration, time: time, selected: captionID, select: selectCaption, move: moveCaption).frame(height: 28)
                        }
                    }.frame(width: width)
                    HStack(spacing: 0) {
                        ForEach(0...Int(ceil(duration)), id: \.self) { second in
                            Color.clear.frame(width: min(scale, max(0, width-Double(second)*scale)), height: 1).id(second)
                        }
                    }.allowsHitTesting(false).accessibilityHidden(true)
                    Rectangle().fill(Color.pixfunGold).frame(width: 2, height: geometry.size.height-30)
                        .offset(x: min(duration,max(0,time))*scale).allowsHitTesting(false)
                }.frame(width: width, alignment: .leading).background(GeometryReader { position in
                    Color.clear.preference(key: StoryTimeOffset.self, value: -position.frame(in: .named("storyTimeScroll")).minX)
                })
            }.coordinateSpace(name: "storyTimeScroll").scrollIndicators(.hidden)
                .onPreferenceChange(StoryTimeOffset.self) { scrollOffset = $0 }
                .background(StoryTimeScrollIntent { following = false })
                .onChange(of: time) { value in
                    if following && !visible(value, scale: scale, viewport: geometry.size.width) { reveal(value, proxy: proxy) }
                }
                .onChange(of: playing) { active in if active { following = true; reveal(time, proxy: proxy) } }
                .onChange(of: tool) { _ in
                    if let value = selectedTime, !visible(value, scale: scale, viewport: geometry.size.width) { reveal(value, proxy: proxy) }
                }
                .task(id: zoom) { await Task.yield(); reveal(selectedTime ?? time, proxy: proxy) }
            }
            }
        }
    }
    var selectedTime: Double? {
        switch tool {
        case .clip(let id): return StoryTimeline.offset(id, in: shots)
        case .caption(let id): return captions.first { $0.id == id }?.start
        case .seam(_, let right): return StoryTimeline.offset(right, in: shots)
        default: return nil
        }
    }
    func visible(_ time: Double, scale: Double, viewport: Double) -> Bool {
        time*scale >= scrollOffset && time*scale <= scrollOffset+viewport-12
    }
    func reveal(_ value: Double, proxy: ScrollViewProxy) {
        proxy.scrollTo(Int(min(duration, max(0,value))), anchor: .center)
    }
    var captionID: String? { if case .caption(let id) = tool { return id }; return nil }
    func ruler(width: Double, scale: Double) -> some View {
        ZStack(alignment: .leading) {
            Color.clear
            let step = StoryTimeline.rulerStep(scale: scale)
            ForEach(Array(stride(from: 0.0, through: duration, by: step)), id: \.self) { value in
                Text(step < 1 ? StoryTimeline.timecode(value) : timestamp(value)).font(.pixfun(9)).foregroundStyle(Color.pixfunMuted).offset(x: min(max(0,width-42),value*scale+3))
            }
        }.frame(width: width, height: 20).clipped().contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in seek(min(duration,max(0,value.location.x/scale))) })
            .accessibilityElement(children: .ignore).accessibilityLabel("Story playback position").accessibilityValue(timestamp(time))
            .accessibilityAdjustableAction { direction in seek(min(duration,max(0,time+(direction == .increment ? 1 : -1)))) }
    }
}

private struct StoryTimeOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Manual panning suspends automatic following so it never fights the user's scroll.
private struct StoryTimeScrollIntent: NSViewRepresentable {
    let action: () -> Void
    func makeNSView(context: Context) -> Observer { Observer() }
    func updateNSView(_ view: Observer, context: Context) { view.action = action }
    final class Observer: NSView {
        var action: (() -> Void)?
        var monitor: Any?
        override func viewDidMoveToWindow() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window, self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                self.action?(); return event
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

struct StoryInsertionGap: View {
    let insert: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: insert) { Image(systemName: "plus").font(.system(size: 11)).frame(maxWidth: .infinity).frame(height: 14).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(hovering ? Color.pixfunGold : Color.clear)
            .onHover { hovering = $0 }.accessibilityLabel("Insert clip here")
    }
}

struct StoryAddClipPicker: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var issue: String?
    let choose: (MediaItem) -> String?
    var items: [MediaItem] { store.items.filter { ["image", "video"].contains($0.kind) && $0.missing != true && (query.isEmpty || $0.matches(query)) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Add clip").font(.pixfun(17, semibold: true))
                Spacer()
                Button("Import files…") { store.pick() }.disabled(store.importing)
                Button("Cancel") { dismiss() }
            }
            TextField("Search media…", text: $query).textFieldStyle(.roundedBorder)
            if store.importing { ProgressView("Importing…").controlSize(.small) }
            if let issue { Text(issue).font(.pixfun(12)).foregroundStyle(.orange) }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in
                        Button { issue = choose(item) } label: {
                            HStack(spacing: 12) {
                                ServiceImage(path: item.cover).frame(width: 74, height: 50).clipped().cornerRadius(5)
                                Text(item.name).font(.pixfun(12)).lineLimit(2)
                                Spacer()
                                if item.status != "ready" { ProgressView().controlSize(.small) }
                                else { Image(systemName: "plus") }
                            }.padding(6).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(item.status != "ready")
                    }
                }
                if items.isEmpty { Text("Import photos or videos to add a clip.").foregroundStyle(Color.pixfunMuted).padding() }
            }
        }.padding(20).frame(width: 540, height: 430).background(Color.pixfunStoryRail)
    }
}
