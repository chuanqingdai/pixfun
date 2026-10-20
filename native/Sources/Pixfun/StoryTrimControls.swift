import SwiftUI
import AVKit

/// A compact optional row inside the existing trim controls, not another tool.
struct StorySpeechHints: View {
    let kind: String
    let inPoint: StorySpeechBoundary?
    let outPoint: StorySpeechBoundary?
    let disabled: Bool
    let choose: (StorySpeechBoundary, Bool) -> Void
    var body: some View {
        if inPoint != nil || outPoint != nil {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(kind == "subtitle" ? "Subtitle boundary reference · check the original audio" : "Speech boundary reference · check the original audio")).font(.pixfun(10))
                HStack {
                    if let inPoint { choice(inPoint, leading: true) }
                    Spacer(minLength: 3)
                    if let outPoint { choice(outPoint, leading: false) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    func choice(_ point: StorySpeechBoundary, leading: Bool) -> some View {
        Button { choose(point, leading) } label: {
            HStack(spacing: 3) {
                Text(LocalizedStringKey(leading ? "In" : "Out"))
                Text("→ \(StoryTimeline.timecode(point.time))").monospacedDigit()
            }
        }.buttonStyle(.plain).foregroundStyle(Color.pixfunGold).help(point.text).disabled(disabled)
    }
}

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
            // Explicit boundary choices, slider edits and undo must update the
            // displayed time even if AppKit leaves this text field focused.
            .onChange(of: value) { next in text = format(next); invalid = false }
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
    var speechBoundaries: [StorySpeechBoundary] = []
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
                ForEach(speechBoundaries.filter { $0.time.isFinite && $0.time >= 0 && $0.time <= length }.prefix(80)) { mark in
                    Rectangle().fill(Color.pixfunGold.opacity(0.85)).frame(width: 1, height: 9)
                        .offset(x: min(geo.size.width - 1, geo.size.width * mark.time / max(0.25, length)), y: 15)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
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
    @EnvironmentObject var store: WorkspaceStore
    let items: [MediaItem]
    let shot: AgentShot
    let runID: String
    let version: Int
    let shots: [AgentShot]
    let choose: (MediaItem, StoryReplacement?) async throws -> Void
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var recommendations: [StoryReplacement] = []
    @State private var loading = true
    @State private var unavailable = false
    @State private var applying = false
    @State private var failure: String?
    var matches: [MediaItem] { items.filter { $0.id != shot.mediaId && ($0.matches(query) || query.isEmpty) } }
    var suggestions: [StoryReplacement] { recommendations.filter { c in items.contains { $0.id == c.mediaId && ($0.matches(query) || query.isEmpty || c.description.localizedCaseInsensitiveContains(query)) } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Replace with project media").font(.pixfun(17, semibold: true)); Spacer(); Button("Cancel") { dismiss() }.disabled(applying) }
            TextField("Search project media…", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if loading { ProgressView("Finding alternatives from saved analysis…").font(.pixfun(12)) }
                    else if unavailable {
                        HStack {
                            Text("Suggestions unavailable. You can still choose project media.")
                            Button("Retry") { Task { await loadSuggestions() } }
                        }.font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                    } else if recommendations.isEmpty {
                        Text("No suitable alternatives in saved analysis. Choose project media below.").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                    }
                    if !suggestions.isEmpty {
                        Text("Suggested moments · same duration").font(.pixfun(12, semibold: true)).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(suggestions) { candidate in
                            if let item = items.first(where: { $0.id == candidate.mediaId }) {
                                Button { apply(item, candidate) } label: {
                                    HStack(spacing: 12) {
                                        ServiceImage(path: item.cover).frame(width: 80, height: 54).clipped().cornerRadius(6)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.name).font(.pixfun(13, semibold: true)).lineLimit(1)
                                            Text(LocalizedStringKey(candidate.reasonKey)).font(.pixfun(11)).foregroundStyle(Color.pixfunGold)
                                            Text("\(StoryTimeline.timecode(candidate.start))–\(StoryTimeline.timecode(candidate.end))").font(.pixfun(11)).monospacedDigit()
                                            Text(candidate.description).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).lineLimit(2)
                                        }
                                        Spacer()
                                    }.padding(8).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                        Divider()
                    }
                    Text("All project media").font(.pixfun(12, semibold: true)).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(matches) { item in
                        Button { apply(item, nil) } label: {
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
                if matches.isEmpty && suggestions.isEmpty && !loading {
                    Text("No matching project media").font(.pixfun(13)).foregroundStyle(Color.pixfunMuted).padding()
                }
            }
            .disabled(applying)
            if applying { ProgressView("Replacing clip…").font(.pixfun(12)) }
            if let failure { Text(failure).font(.pixfun(12)).foregroundStyle(.orange) }
        }.padding(20).frame(width: 520, height: 420).background(Color.pixfunBackground)
            .interactiveDismissDisabled(applying)
            .task { await loadSuggestions() }
    }
    func loadSuggestions() async {
        loading = true; unavailable = false
        do {
            let payload = try StoryAssistance.payload(runID: runID, version: version, shots: shots, action: "replace", shotID: shot.id)
            let result: StoryAssistance = try await store.service.post("/api/desktop/agent/editor-assist", payload, native: true)
            try Task.checkCancellation()
            recommendations = result.recommendations
        } catch { if !Task.isCancelled { unavailable = true } }
        loading = false
    }
    func apply(_ item: MediaItem, _ candidate: StoryReplacement?) {
        guard !applying else { return }
        applying = true; failure = nil
        Task {
            do { try await choose(item, candidate) }
            catch { failure = error.localizedDescription }
            applying = false
        }
    }
}
