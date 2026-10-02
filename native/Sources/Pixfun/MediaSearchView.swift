import SwiftUI

struct MediaSearchControls: View {
    @EnvironmentObject var store: WorkspaceStore
    @FocusState private var focused: Bool
    @State private var showingHelp = false
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 380
            HStack(spacing: 8) {
                Button { focused = true } label: {
                    Image(systemName: "magnifyingglass").frame(width: 24, height: 30)
                }.buttonStyle(.plain).accessibilityLabel("Focus Media search").keyboardShortcut("f", modifiers: .command)
                TextField(compact && store.searchScope == .all ? "Search footage…" : store.searchScope.placeholder, text: $store.query)
                    .textFieldStyle(.plain).font(.pixfun(13)).focused($focused)
                    .accessibilityLabel("Search Media").accessibilityHint(store.searchScope.explanation)
                    .onExitCommand { store.query = "" }
                if !store.query.isEmpty {
                    Button { store.query = ""; focused = true } label: { Image(systemName: "xmark.circle.fill").frame(width: 28, height: 30) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search").help("Clear search · Esc")
                }
                Divider().frame(height: 18)
                Menu {
                    Picker("Search in", selection: $store.searchScope) {
                        ForEach(MediaSearchScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    HStack(spacing: 7) {
                        if !compact { Text(store.searchScope.rawValue) }
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }.font(.pixfun(12)).frame(minWidth: compact ? 18 : 94, minHeight: 30)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Search in \(store.searchScope.rawValue)").help(store.searchScope.explanation)
                Button { showingHelp.toggle() } label: { Image(systemName: "info.circle").frame(width: 28, height: 30) }
                    .buttonStyle(.plain).accessibilityLabel("What can I search?")
                    .popover(isPresented: $showingHelp) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Search your footage").font(.pixfun(16, semibold: true))
                            ForEach(MediaSearchScope.allCases.filter { $0 != .all }, id: \.self) { scope in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(scope.rawValue).font(.pixfun(12, semibold: true))
                                    Text(scope.explanation).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                                }
                            }
                            Divider()
                            Text("Keywords match saved text, not unseen footage. All words must match the same file. Use the language of the saved text; translation and semantic search are not included.")
                                .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                            Text("Missing details? Open a clip and choose Generate or Analyze shots. Searching and opening results never start analysis or upload files.")
                                .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                        }.padding(20).frame(width: 370)
                    }
            }.foregroundStyle(Color.pixfunMuted).padding(.horizontal, 10).frame(height: 36)
                .background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.pixfunFocus : .pixfunLine, lineWidth: focused ? 2 : 1))
        }.frame(height: 36)
    }
}

struct MediaSearchHighlight: View {
    let text: String
    let query: String
    var highlighted: Text {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        var remaining = text.startIndex
        var output = Text("")
        while remaining < text.endIndex {
            let range = terms.compactMap { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], range: remaining..<text.endIndex) }
                .min { $0.lowerBound < $1.lowerBound }
            guard let range else { return output + Text(String(text[remaining...])) }
            output = output + Text(String(text[remaining..<range.lowerBound])) + Text(String(text[range])).foregroundColor(.pixfunGold)
            remaining = range.upperBound
        }
        return output
    }
    var body: some View { highlighted }
}

struct MediaSearchEvidence: View {
    let hit: MediaSearchHit
    let query: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hit.label + (hit.start.map { " · \(timestamp($0))" } ?? ""))
                .font(.pixfun(11, semibold: true)).foregroundStyle(Color.pixfunGold)
            MediaSearchHighlight(text: hit.excerpt(query: query), query: query)
                .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).lineLimit(3)
        }.frame(maxWidth: .infinity, alignment: .leading).help(hit.text)
    }
}

struct MediaDetailSearchMatches: View {
    @EnvironmentObject var store: WorkspaceStore
    let item: MediaItem
    let seek: (Double) -> Void
    var hits: [MediaSearchHit] {
        MediaSearchDocument(item).match(MediaSearchQuery(store.query), scope: store.searchScope, location: store.locations[item.id]) ?? []
    }
    var body: some View {
        if store.isSearchingMedia && !hits.isEmpty {
            DisclosureGroup("\(hits.count) matching \(hits.count == 1 ? "entry" : "entries") for “\(store.query)”") {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(hits) { hit in
                        HStack(alignment: .top, spacing: 12) {
                            MediaSearchEvidence(hit: hit, query: store.query)
                            if let seconds = hit.start {
                                Button { seek(seconds) } label: { Label(timestamp(seconds), systemImage: "play.circle") }
                                    .buttonStyle(PixfunButtonStyle(kind: .quiet)).accessibilityLabel("Jump to matching moment at \(timestamp(seconds))")
                            }
                        }
                    }
                }.padding(.top, 12)
            }.font(.pixfun(13)).tint(.pixfunGold)
        }
    }
}
