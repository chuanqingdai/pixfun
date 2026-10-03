import SwiftUI
import AVKit

/// Return/focus loss commits a valid value; Escape restores it. No extra Apply button.
struct StoryTimeField: View {
    let value: Double
    let label: String
    var secondsOnly = false
    var invalidHelp = "Enter a valid time within the source range; minimum clip length is 0.25s."
    let valid: (Double) -> Bool
    let commit: (Double) -> Void
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool
    func format(_ seconds: Double) -> String { secondsOnly ? String(format: "%.2f", seconds) : StoryTimeline.timecode(seconds) }
    var formatted: String { format(value) }
    var body: some View {
        TextField(label, text: $text).textFieldStyle(.plain).font(.pixfun(11)).monospacedDigit()
            .padding(5).frame(width: secondsOnly ? 52 : 80)
            .background(Color.pixfunBackground, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(invalid ? Color.orange : Color.pixfunLine))
            .focused($focused).accessibilityLabel(label)
            .help(invalid ? invalidHelp : label)
            .onAppear { text = formatted }
            .onChange(of: value) { next in if !focused { text = format(next); invalid = false } }
            .onChange(of: focused) { active in if !active { apply() } }
            .onSubmit { apply() }
            .onExitCommand { text = formatted; invalid = false; focused = false }
    }
    func apply() {
        guard let next = StoryTimeline.parseTime(text), valid(next) else { invalid = true; return }
        invalid = false
        if abs(next - value) > 0.0001 { commit(next) }
    }
}

/// Frames are sampled from this original file, not repeated copies of its cover.
struct StorySourceRange: View {
    @EnvironmentObject var store: WorkspaceStore
    let item: MediaItem
    let start: Double
    let end: Double
    let enabled: Bool
    let changing: (ClosedRange<Double>, Int) -> Void
    let editing: (Bool) -> Void
    @State private var frames: [NSImage] = []
    var length: Double { max(end, item.metadata?.duration ?? end) }
    var body: some View {
        GeometryReader { geo in
            let left = geo.size.width * start / max(0.25, length)
            let right = geo.size.width * end / max(0.25, length)
            ZStack(alignment: .leading) {
                Color.pixfunRaised
                HStack(spacing: 1) {
                    ForEach(frames.indices, id: \.self) { index in
                        Image(nsImage: frames[index]).resizable().scaledToFill()
                            .frame(width: max(1, (geo.size.width - 5) / 6), height: 46).clipped()
                    }
                }
                Color.black.opacity(0.65).frame(width: max(0, left))
                Color.black.opacity(0.65).frame(width: max(0, geo.size.width - right)).offset(x: right)
                Rectangle().strokeBorder(Color.pixfunGold, lineWidth: 2).frame(width: max(2, right - left)).offset(x: left)
                handle.offset(x: max(0, left - 5))
                handle.offset(x: min(geo.size.width - 10, right - 5))
                StoryRangeTracking(start: start, end: end, length: length, enabled: enabled, changing: changing, editing: editing)
            }.clipped().cornerRadius(5)
        }.frame(height: 46)
            .help("Drag either edge to trim. Drag the selected area to use a different moment at the same length. Use In/Out fields for precise times.")
            .task(id: item.id) {
                frames = []
                do {
                    let url = try await store.service.original(item.id)
                    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 160, height: 100)
                    try await withTaskCancellationHandler(operation: {
                        for index in 0..<6 {
                            try Task.checkCancellation()
                            let result = try await generator.image(at: CMTime(seconds: length * (Double(index) + 0.5) / 6, preferredTimescale: 600))
                            try Task.checkCancellation()
                            frames.append(NSImage(cgImage: result.image, size: .zero))
                        }
                    }, onCancel: { generator.cancelAllCGImageGeneration() })
                } catch { /* Exact-time fields remain usable when thumbnails cannot be decoded. */ }
            }
    }
    var handle: some View {
        RoundedRectangle(cornerRadius: 3).fill(Color.pixfunGold).frame(width: 10, height: 46)
            .overlay(Capsule().fill(Color.pixfunBackground).frame(width: 2, height: 16))
    }
}

struct StoryRangeTracking: NSViewRepresentable {
    let start: Double, end: Double, length: Double
    let enabled: Bool
    let changing: (ClosedRange<Double>, Int) -> Void
    let editing: (Bool) -> Void
    func makeNSView(context: Context) -> RangeView { RangeView() }
    func updateNSView(_ view: RangeView, context: Context) {
        view.enabled = enabled; view.changing = changing; view.editing = editing
        if !view.tracking { view.start = start; view.end = end; view.length = length }
    }
    final class RangeView: NSView {
        var start = 0.0, end = 1.0, length = 1.0, initialX = 0.0
        var edge = 0
        var tracking = false, enabled = true
        var changing: ((ClosedRange<Double>, Int) -> Void)?
        var editing: ((Bool) -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard enabled, bounds.width > 0 else { return }
            let x = Double(convert(event.locationInWindow, from: nil).x)
            let a = start / length * bounds.width, b = end / length * bounds.width
            if abs(x - a) <= 14 || abs(x - b) <= 14 { edge = abs(x - a) < abs(x - b) ? -1 : 1 }
            else { edge = x < a ? -1 : x > b ? 1 : 0 }
            initialX = x; tracking = true; editing?(true)
        }
        override func mouseDragged(with event: NSEvent) {
            guard tracking else { return }
            let delta = (Double(convert(event.locationInWindow, from: nil).x) - initialX) / max(1, bounds.width) * length
            changing?(StoryTimeline.range(start: start, end: end, sourceDuration: length, delta: delta, edge: edge), edge)
        }
        override func mouseUp(with event: NSEvent) {
            guard tracking else { return }
            mouseDragged(with: event); tracking = false; editing?(false)
        }
    }
}

struct StoryReplacementPicker: View {
    let items: [MediaItem]
    let current: String
    let choose: (MediaItem) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Replace with project media").font(.pixfun(17, semibold: true)); Spacer(); Button("Cancel") { dismiss() } }
            TextField("Search project media…", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(items.filter { $0.id != current && ($0.matches(query) || query.isEmpty) }) { item in
                        Button { choose(item) } label: {
                            HStack(spacing: 12) {
                                ServiceImage(path: item.cover).frame(width: 80, height: 54).clipped().cornerRadius(6)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.pixfun(13, semibold: true)).lineLimit(1)
                                    if let summary = item.cardSummary { Text(summary).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).lineLimit(2) }
                                }
                                Spacer()
                                Image(systemName: item.kind == "image" ? "photo" : "film")
                            }.padding(8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                if items.filter({ $0.id != current && ($0.matches(query) || query.isEmpty) }).isEmpty {
                    Text("No matching project media").font(.pixfun(13)).foregroundStyle(Color.pixfunMuted).padding()
                }
            }
        }.padding(20).frame(width: 520, height: 420).background(Color.pixfunBackground)
    }
}
