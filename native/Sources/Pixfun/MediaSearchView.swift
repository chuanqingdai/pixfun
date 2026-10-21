import SwiftUI

struct MediaCatalogControls: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var confirmIndex = false
    var body: some View {
        HStack(spacing: 10) {
            if store.catalogBusy { ProgressView().controlSize(.small) }
            Text(store.visionFlowStatus?.connected == true ? "VisionFlow 镜头库已接入；现有素材无需重复索引。" : store.catalogMessage).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            if store.catalogBusy {
                Button("Stop") { store.stopCatalog() }.buttonStyle(.plain)
            } else if store.libraryItems.contains(where: { $0.kind == "video" && $0.vfCatalog == nil }) {
                Button("Build visual index…") { confirmIndex = true }.buttonStyle(.plain)
                    .foregroundStyle(Color.pixfunGold)
            }
        }.font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
            .task(id: store.ready) { await store.refreshCatalogStatus() }
            .alert("Build a local visual index?", isPresented: $confirmIndex) {
                Button("Build index") { store.startCatalogIndex() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Scan video frames and save searchable vectors on this Mac. This uses local processing and disk space, but does not rewrite descriptions, upload files or change originals. Some HDR and rotated videos are not supported yet.")
            }
    }
}
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
                TextField(LocalizedStringKey(compact ? "Search…" : "Search filenames, scenes, tags or dialogue…"), text: $store.query)
                    .textFieldStyle(.plain).font(.pixfun(13)).focused($focused)
                    .accessibilityLabel("Search Media").accessibilityHint(store.searchScope.explanation)
                    .onExitCommand { store.query = "" }
                    .onSubmit { store.searchVisualMedia() }
                if store.visionFlowStatus?.connected == true || (store.catalogStatus?.indexed ?? 0) > 0 {
                    Button { store.searchVisualMedia() } label: { Image(systemName: "arrow.right").frame(width: 28, height: 30) }
                        .buttonStyle(.plain).disabled(store.catalogBusy || store.query.isEmpty)
                        .accessibilityLabel("Search indexed video frames")
                }
                if !store.query.isEmpty {
                    Button { store.query = ""; focused = true } label: { Image(systemName: "xmark.circle.fill").frame(width: 28, height: 30) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search").help("Clear search · Esc")
                }
                Button { showingHelp.toggle() } label: { Image(systemName: "info.circle").frame(width: 28, height: 30) }
                    .buttonStyle(.plain).accessibilityLabel("What can I search?")
                    .popover(isPresented: $showingHelp) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Search your footage").font(.pixfun(16, semibold: true))
                            ForEach(MediaSearchScope.allCases.filter { $0 != .all }, id: \.self) { scope in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(LocalizedStringKey(scope.rawValue)).font(.pixfun(12, semibold: true))
                                    Text(LocalizedStringKey(scope.explanation)).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                                }
                            }
                            Divider()
                            Text("Typing searches filenames, tags and saved descriptions. With a local visual index, press Return to include matching video frames. Text matches stay visible. Frame matches are suggestions, not verified facts.")
                                .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                            MediaCatalogControls()
                            Text(LocalizedStringKey("Missing details? Open a clip and choose Generate or Analyze shots. Searching and opening results never start analysis or upload files."))
                                .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                        }.padding(20).frame(width: 370)
                    }
            }.foregroundStyle(Color.pixfunMuted).padding(.horizontal, 8).frame(height: 30)
                .background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.pixfunFocus : .pixfunLine, lineWidth: focused ? 2 : 1))
        }.frame(height: 30)
            .task(id: store.ready) { await store.refreshCatalogStatus() }
    }
}
