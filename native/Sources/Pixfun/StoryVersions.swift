import SwiftUI
import AVKit

/// Browsing history never swaps the editable run or writes the user's draft.
struct StoryVersionsPopover: View {
    let versions: [StoryVersion]
    @State private var selectedID: String?
    @StateObject private var playback = AgentPlayback()
    var selected: StoryVersion? { versions.first { $0.id == selectedID } ?? versions.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Versions").font(.pixfun(13, semibold: true))
            if let version = selected {
                if version.preview != nil {
                    ZStack {
                        Color.black
                        if let player = playback.player { NativeVideoPlayer(player: player, showsControls: true) }
                        if let issue = playback.issue { Text(issue).font(.pixfun(12)).padding() }
                    }.frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Label("Saved draft · \(version.shots.count) clips · \(timestamp(version.duration))", systemImage: "doc.text")
                        .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).padding(.vertical, 8)
                }
                Text(version.prompt).font(.pixfun(11)).lineLimit(2).foregroundStyle(Color.pixfunMuted)
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(versions) { version in
                        Button { selectedID = version.id } label: {
                            HStack {
                                Image(systemName: version.preview == nil ? "doc.text" : "play.rectangle")
                                Text("Version \(version.number)")
                                Spacer()
                                if !version.shots.isEmpty { Text(timestamp(version.duration)).monospacedDigit() }
                                if version.id == selected?.id { Image(systemName: "checkmark") }
                            }.font(.pixfun(12)).padding(8).contentShape(Rectangle())
                                .background(version.id == selected?.id ? Color.pixfunBrandSoft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).help(version.prompt)
                    }
                }
            }.frame(height: min(180, CGFloat(versions.count) * 34))
        }.padding(14).frame(width: 380)
            .onAppear { playback.load(selected?.preview?.path) }
            .onChange(of: selected?.id) { _ in playback.load(selected?.preview?.path) }
            .onDisappear { playback.player?.pause() }
    }
}
