import SwiftUI

struct StoryAudioPopover: View {
    let finish: AgentFinishing
    let duration: Double
    let musicSources: [MediaItem]
    let originalControls: AnyView?
    @Binding var selectedNarration: Int?
    let commit: (AgentFinishing, Bool) -> Void
    let locate: (Double) -> Void
    let request: (String) -> Void
    var body: some View {
        Group {
            if finish.narration.count > 2 {
                ScrollView { contents }.frame(height: 510)
            } else { contents }
        }.frame(width: 350)
            .help("Music and narration changes are heard after updating the preview")
    }
    var contents: some View {
        VStack(alignment: .leading, spacing: 14) {
                Text("Audio").font(.pixfun(13, semibold: true))
                if let originalControls {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Original sound").font(.pixfun(12, semibold: true))
                        originalControls
                    }
                    Divider()
                }
                musicControls
                Divider()
                narrationControls
        }.padding(14).fixedSize(horizontal: false, vertical: true)
    }
    var musicControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Music").font(.pixfun(12, semibold: true))
                Spacer()
                if finish.music == nil { Button("Add with AI") { request("Add background music to this film.") }.font(.pixfun(11)) }
            }
            if !musicSources.isEmpty || finish.music != nil {
                Picker("Track", selection: Binding(get: { finish.music?.mediaId ?? "" }, set: { id in
                    var next = finish
                    next.music = id.isEmpty ? nil : .init(mediaId: id, volume: finish.music?.volume ?? 0.18, ducking: true, sourceStart: 0, loop: true)
                    next.musicMuted = false; commit(next, false)
                })) {
                    Text("None").tag("")
                    if let current = finish.music, !musicSources.contains(where: { $0.id == current.mediaId }) {
                        Text("Current music").tag(current.mediaId)
                    }
                    ForEach(musicSources) { Text($0.name).tag($0.id) }
                }.font(.pixfun(11))
            }
            if let music = finish.music {
                StoryMixGain(label: "Music", volume: music.volume, muted: finish.musicMuted == true,
                    setVolume: { value in var next = finish; next.music?.volume = value; commit(next, false) },
                    toggleMute: { var next = finish; next.musicMuted = !(next.musicMuted ?? false); commit(next, false) })
                Toggle("Lower music under speech", isOn: Binding(get: { music.ducking }, set: { enabled in
                    var next = finish; next.music?.ducking = enabled; commit(next, false)
                })).font(.pixfun(11))
            }
        }
    }
    var narrationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Narration").font(.pixfun(12, semibold: true))
                Spacer()
                Button("Add with AI") { request("Add narration to this film.") }.font(.pixfun(11))
            }
            if !finish.narration.isEmpty {
                StoryMixGain(label: "Narration", volume: finish.narrationVolume ?? 1, muted: finish.narrationMuted == true,
                    setVolume: { value in var next = finish; next.narrationVolume = value; commit(next, false) },
                    toggleMute: { var next = finish; next.narrationMuted = !(next.narrationMuted ?? false); commit(next, false) })
                ForEach(finish.narration.indices, id: \.self) { index in
                    let cue = finish.narration[index]
                    Button { selectedNarration = selectedNarration == index ? nil : index } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text(selectedNarration == index ? "Segment \(index + 1)" : cue.text).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(timestamp(cue.start))–\(timestamp(cue.end))").monospacedDigit().foregroundStyle(Color.pixfunMuted)
                        }.font(.pixfun(11)).padding(7)
                            .background(selectedNarration == index ? Color.pixfunBrandSoft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                    if selectedNarration == index { narrationEditor(index, cue) }
                }
            }
        }
    }
    func narrationEditor(_ index: Int, _ cue: AgentFinishing.Narration) -> some View {
        VStack(spacing: 8) {
            TextField("Narration text", text: Binding(get: { cue.text }, set: { text in
                var next = finish; next.narration[index].text = text; commit(next, true)
            }), axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder).font(.pixfun(12))
            HStack(spacing: 6) {
                Text("In")
                StoryTimeField(value: cue.start, label: "Narration start", valid: {
                    $0 >= (index == 0 ? 0 : finish.narration[index-1].end) && $0 <= cue.end - 0.25
                }) { value in var next = finish; next.narration[index].start = value; commit(next, false) }
                Text("Out")
                StoryTimeField(value: cue.end, label: "Narration end", valid: {
                    $0 >= cue.start + 0.25 && $0 <= (index+1 < finish.narration.count ? finish.narration[index+1].start : duration)
                }) { value in var next = finish; next.narration[index].end = value; commit(next, false) }
                Button { locate(cue.start) } label: { Image(systemName: "scope") }.help("Locate narration").accessibilityLabel("Locate narration")
                Button { var next = finish; next.narration.remove(at: index); selectedNarration = nil; commit(next, false) } label: { Image(systemName: "trash") }
                    .help("Remove narration").accessibilityLabel("Remove narration")
            }.font(.pixfun(11))
        }
    }
}

/// Commit a slider gesture once, so Undo reverses the gesture, not every pixel.
struct StoryMixGain: View {
    let label: String
    let volume: Double
    let muted: Bool
    let setVolume: (Double) -> Void
    let toggleMute: () -> Void
    @State private var editing = false
    @State private var pending = 0.0
    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleMute) { Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 24) }
                .accessibilityLabel("\(muted ? "Unmute" : "Mute") \(label)").help(muted ? "Unmute" : "Mute")
            Slider(value: Binding(get: { editing ? pending : volume }, set: { pending = $0; if !editing { setVolume($0) } }), in: 0...1,
                   onEditingChanged: { value in
                       if value { pending = volume; editing = true }
                       else { editing = false; setVolume(pending) }
                   }).accessibilityLabel("\(label) volume")
            Text("\(Int(((editing ? pending : volume) * 100).rounded()))%").font(.pixfun(11)).monospacedDigit().frame(width: 34)
        }.buttonStyle(.borderless)
    }
}
