import SwiftUI

/// Every lane shares one seconds-to-points transform; silent sources leave gaps, not fake audio.
struct EditorTimelineView: View {
    let shots: [AgentShot]
    let items: [MediaItem]
    let finishing: AgentFinishing?
    let selectedID: String?
    let zoom: Double
    let playhead: Double
    let showsPlayhead: Bool
    let canSeek: Bool
    let canTrim: (AgentShot) -> Bool
    let onSelect: (AgentShot) -> Void
    let onSeek: (Double) -> Void
    let onTrim: (AgentShot, Bool, Double) -> Void
    let onTrimEnd: () -> Void
    let onOriginal: (AgentShot) -> Void
    let onMove: (AgentShot, Int) -> Void
    var duration: Double { shots.reduce(0) { $0 + $1.end - $1.start } }
    var width: Double { max(1, duration * zoom) }
    var audioIDs: Set<String> { Set(items.filter { $0.kind == "video" && $0.metadata?.hasAudio == true }.map(\.id)) }
    var hasOriginal: Bool { shots.contains { audioIDs.contains($0.mediaId) } }
    var hasVoice: Bool { finishing?.narration.isEmpty == false }
    var laneHeight: Double { 82 + (hasOriginal ? 34 : 0) + (finishing?.music != nil ? 34 : 0) + (hasVoice ? 34 : 0) }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 6) {
                Color.clear.frame(height: 26)
                trackIcon("film", label: "Visuals", height: 76)
                if hasOriginal { trackIcon(finishing?.originalVolume == 0 ? "speaker.slash" : "waveform", label: "Original audio", height: 28) }
                if finishing?.music != nil { trackIcon("music.note", label: "Music", height: 28) }
                if hasVoice { trackIcon("mic", label: "Narration", height: 28) }
            }.frame(width: 24)
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        ruler.zIndex(1)
                        visualLane
                        if hasOriginal { originalLane }
                        if let music = finishing?.music {
                            audioBar(symbol: "music.note", label: items.first { $0.id == music.mediaId }?.title ?? "Background music", width: width)
                                .help("Background music · adjust in the conversation")
                        }
                        if let narration = finishing?.narration, !narration.isEmpty {
                            ZStack(alignment: .leading) {
                                ForEach(Array(narration.enumerated()), id: \.offset) { _, cue in
                                    if cue.start < duration {
                                        audioBar(symbol: "mic", label: cue.text, width: max(1, (min(duration, cue.end) - cue.start) * zoom))
                                            .offset(x: max(0, cue.start) * zoom).help(cue.text)
                                    }
                                }
                            }.frame(width: width, height: 28, alignment: .leading).clipped()
                        }
                    }
                    if showsPlayhead {
                        VStack(spacing: 0) {
                            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 12))
                            Rectangle().frame(width: 1.5)
                        }.foregroundStyle(Color.pixfunGold).frame(width: 14, height: laneHeight + 26)
                            .offset(x: min(width, max(0, playhead * zoom)) - 7)
                            .allowsHitTesting(false).accessibilityLabel("Playhead \(timestamp(playhead))")
                    }
                }.frame(width: width, alignment: .leading).padding(.horizontal, 8).padding(.bottom, 10)
                    .coordinateSpace(name: "editor-timeline")
            }.frame(height: laneHeight + 46)
        }
    }
    func trackIcon(_ symbol: String, label: String, height: Double) -> some View {
        Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Color.pixfunMuted)
            .frame(width: 24, height: height).help(label).accessibilityLabel(label)
    }
    var ruler: some View {
        let step = zoom < 2 ? 60 : zoom < 4 ? 30 : zoom < 10 ? 10 : zoom < 35 ? 5 : zoom < 75 ? 2 : 1
        return ZStack(alignment: .topLeading) {
            Color.pixfunSurface
            ForEach(Array(stride(from: 0, through: Int(ceil(duration)), by: step)), id: \.self) { second in
                VStack(alignment: .leading, spacing: 3) {
                    Text(timestamp(Double(second))).font(.pixfun(10)).monospacedDigit()
                    Rectangle().frame(width: 1, height: 5)
                }.foregroundStyle(Color.pixfunMuted).offset(x: Double(second) * zoom)
            }
        }.frame(width: width, height: 26).clipped()
            .overlay {
                TimelineScrubber(enabled: canSeek) { x in
                    onSeek(EditorDraft.time(at: x, zoom: zoom, duration: duration))
                }
            }
            .help(canSeek ? "Click or drag to seek" : "Rebuild the preview to seek the updated timeline")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Timeline position")
            .accessibilityValue(timestamp(playhead))
            .accessibilityAdjustableAction { direction in
                guard canSeek else { return }
                onSeek(min(duration, max(0, playhead + (direction == .increment ? 1 : -1))))
            }
    }
    var visualLane: some View {
        HStack(spacing: 0) {
            ForEach(shots) { shot in clip(shot) }
        }.frame(width: width, height: 76, alignment: .leading)
    }
    func clip(_ shot: AgentShot) -> some View {
        let clipWidth = (shot.end - shot.start) * zoom
        return Button { onSelect(shot) } label: {
            ZStack(alignment: .bottomLeading) {
                ServiceImage(path: items.first { $0.id == shot.mediaId }?.cover)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                HStack(spacing: 4) {
                    if shot.locked { Image(systemName: "lock.fill") }
                    Text(shot.label).lineLimit(1)
                }.font(.pixfun(11)).foregroundStyle(.white).padding(.horizontal, 12).padding(.bottom, 7)
            }.frame(width: clipWidth, height: 76).clipped().contentShape(Rectangle())
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(selectedID == shot.id ? Color.pixfunGold : Color.pixfunBackground, lineWidth: selectedID == shot.id ? 2 : 1))
        }.buttonStyle(.plain)
            .help("\(shot.label) · \(String(format: "%.2fs", shot.end - shot.start))")
            .accessibilityLabel("Clip: \(shot.label)")
            .accessibilityAddTraits(selectedID == shot.id ? [.isSelected] : [])
            .overlay(alignment: .leading) { if selectedID == shot.id && canTrim(shot) { handle(shot, leading: true, width: clipWidth) } }
            .overlay(alignment: .trailing) { if selectedID == shot.id && canTrim(shot) { handle(shot, leading: false, width: clipWidth) } }
            .contentShape(Rectangle())
            .contextMenu {
                Button("View original") { onOriginal(shot) }
                Button("Move earlier") { onMove(shot, -1) }.disabled(!canTrim(shot) || shots.first?.id == shot.id)
                Button("Move later") { onMove(shot, 1) }.disabled(!canTrim(shot) || shots.last?.id == shot.id)
            }
    }
    func handle(_ shot: AgentShot, leading: Bool, width: Double) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(Color.pixfunGold)
            .frame(width: min(10, width / 3), height: 72)
            .overlay { Capsule().fill(Color.black.opacity(0.6)).frame(width: 2, height: 22) }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("editor-timeline"))
                .onChanged { value in onTrim(shot, leading, value.translation.width / zoom) }
                .onEnded { _ in onTrimEnd() })
            .help(leading ? "Drag to adjust start" : "Drag to adjust end")
            .accessibilityLabel(leading ? "Clip start handle" : "Clip end handle")
            .accessibilityAdjustableAction { direction in
                onTrim(shot, leading, direction == .increment ? 0.1 : -0.1); onTrimEnd()
            }
    }
    var originalLane: some View {
        HStack(spacing: 0) {
            ForEach(shots) { shot in
                if audioIDs.contains(shot.mediaId) {
                    audioBar(symbol: finishing?.originalVolume == 0 ? "speaker.slash" : "waveform", label: "", width: (shot.end - shot.start) * zoom)
                        .opacity(finishing?.originalVolume == 0 ? 0.35 : 1)
                } else {
                    Color.clear.frame(width: (shot.end - shot.start) * zoom, height: 28)
                }
            }
        }
    }
    func audioBar(symbol: String, label: String, width: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            if !label.isEmpty { Text(label).lineLimit(1) }
            Spacer(minLength: 0)
        }.font(.pixfun(11)).foregroundStyle(Color.pixfunGold).padding(.horizontal, 8)
            .frame(width: width, height: 28).background(Color.pixfunGold.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// An AppKit hit surface keeps ruler scrubbing independent of nested SwiftUI scroll gestures.
struct TimelineScrubber: NSViewRepresentable {
    var enabled: Bool
    var seek: (Double) -> Void
    func makeNSView(context: Context) -> ScrubView { ScrubView() }
    func updateNSView(_ view: ScrubView, context: Context) {
        view.enabled = enabled; view.seek = seek
    }
    final class ScrubView: NSView {
        var enabled = true
        var seek: ((Double) -> Void)?
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { scrub(event) }
        override func mouseDragged(with event: NSEvent) { scrub(event) }
        override func mouseUp(with event: NSEvent) { scrub(event) }
        private func scrub(_ event: NSEvent) {
            guard enabled else { return }
            seek?(convert(event.locationInWindow, from: nil).x)
        }
        override func resetCursorRects() {
            if enabled { addCursorRect(bounds, cursor: .pointingHand) }
        }
    }
}
