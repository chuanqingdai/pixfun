import SwiftUI

/// Deliberately limited to the generators exercised by the release render test.
/// Uses the same draft/undo/save transaction as sound and captions.
struct StoryTitlePicker: View {
    let current: AgentFinishing.MotionTitle?
    let suggestedText: String
    var embedded = false
    var dismiss: (() -> Void)? = nil
    var canPlaceOpening = true
    var canPlaceEnding = true
    let commit: (AgentFinishing.MotionTitle?) -> Void
    @State private var open = false
    @State private var style = "keep"
    @State private var text = ""
    @State private var origin = ""
    @State private var destination = ""
    @State private var total = ""
    var label: String {
        switch current?.kind {
        case "title": return "Reveal title"
        case "place": return "Corner title"
        case "route": return "Route card"
        case "airport": return "Airport board"
        case "counter": return "Animated count"
        case "end": return "End card"
        case "none": return "No motion title"
        default: return "Follow plan"
        }
    }
    var body: some View {
        Group {
            if embedded {
                controls.onAppear(perform: prepare)
            } else {
                Button { prepare(); open = true } label: {
                    Label { Text("Graphics") + Text(" · ") + Text(LocalizedStringKey(label)) } icon: { Image(systemName: "textformat") }
                        .font(.pixfun(12))
                }.buttonStyle(.borderless).help("Choose a title style before rendering")
                    .popover(isPresented: $open, arrowEdge: .bottom) { controls }
            }
        }
    }
    func prepare() {
        style = current?.kind ?? "keep"; text = current?.text ?? suggestedText
        origin = current?.origin ?? ""; destination = current?.destination ?? ""
        total = current?.total.map(String.init) ?? ""
    }
    private func valid(_ value: String, limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.unicodeScalars.count <= limit && !value.unicodeScalars.contains { $0.value < 32 }
    }
    var validSelection: Bool {
        if ["title","place","route","airport","counter"].contains(style) && !canPlaceOpening { return false }
        if style == "end" && !canPlaceEnding { return false }
        if style == "route" {
            return valid(origin, limit: 24) && valid(destination, limit: 24) && origin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != destination.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if style == "airport" { return valid(text.uppercased(), limit: 24) && !text.unicodeScalars.contains { $0.value > 0xffff } }
        if style == "counter" { return valid(text, limit: 24) && Int(total).map { (1...9999).contains($0) } == true }
        return !["title","place","end"].contains(style) || valid(text, limit: 64)
    }
    func close() { open = false; dismiss?() }
    var controls: some View {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Motion graphics").font(.pixfun(14, semibold: true))
                    Picker("Style", selection: $style) {
                        Text("Follow plan").tag("keep")
                        Text("Reveal title").tag("title").disabled(!canPlaceOpening)
                        Text("Corner title").tag("place").disabled(!canPlaceOpening)
                        Text("Route card").tag("route").disabled(!canPlaceOpening)
                        Text("Airport board").tag("airport").disabled(!canPlaceOpening)
                        Text("Animated count").tag("counter").disabled(!canPlaceOpening)
                        Text("End card").tag("end").disabled(!canPlaceEnding)
                        Text("No motion title").tag("none")
                    }
                    if style == "route" {
                        TextField("Departure", text: $origin, prompt: PixfunTypography.placeholder("Departure")).textFieldStyle(.roundedBorder)
                        TextField("Arrival", text: $destination, prompt: PixfunTypography.placeholder("Arrival")).textFieldStyle(.roundedBorder)
                        Text("Schematic only, not a geographic map. Enter your actual locations.")
                            .font(.pixfun(11)).foregroundStyle(Color.pixfunMuted).fixedSize(horizontal: false, vertical: true)
                    } else if style == "counter" {
                        TextField("Label · e.g. Days on the road", text: $text, prompt: PixfunTypography.placeholder("Label · e.g. Days on the road")).textFieldStyle(.roundedBorder)
                        TextField("Actual total · 1–9999", text: $total, prompt: PixfunTypography.placeholder("Actual total · 1–9999")).textFieldStyle(.roundedBorder)
                        Text("Animates to your number; does not count objects in the footage.")
                            .font(.pixfun(11)).foregroundStyle(Color.pixfunMuted).fixedSize(horizontal: false, vertical: true)
                    } else if ["title", "place", "airport", "end"].contains(style) {
                        TextField(LocalizedStringKey(style == "airport" ? "Board text · up to 24 characters" : "Title text"), text: $text, prompt: PixfunTypography.placeholder(LocalizedStringKey(style == "airport" ? "Board text · up to 24 characters" : "Title text"))).textFieldStyle(.roundedBorder)
                    }
                    if !["keep","none"].contains(style) {
                        Text(LocalizedStringKey(style == "end" ? "Overlays the final seconds without extending your film. Requires at least 2.5s of footage." : "Appears over the first clip lasting at least 2.5s. Keeps your existing opening and film duration."))
                            .font(.pixfun(11)).foregroundStyle(Color.pixfunMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button("Cancel", action: close)
                        Spacer()
                        Button("Apply") {
                            commit(style == "keep" ? nil : .init(kind: style,
                                text: style == "none" ? "" : (style == "route" ? "\(origin) → \(destination)" : text).trimmingCharacters(in: .whitespacesAndNewlines),
                                origin: style == "route" ? origin.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                                destination: style == "route" ? destination.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                                total: style == "counter" ? Int(total) : nil))
                            close()
                        }.buttonStyle(PixfunButtonStyle(kind: .primary))
                            .disabled(!validSelection)
                    }
                }.padding(18).frame(width: 330).background(Color.pixfunSurface)
    }
}
