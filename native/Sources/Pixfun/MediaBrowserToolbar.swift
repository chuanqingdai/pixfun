import SwiftUI

struct MediaBrowserToolbar: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var confirmReanalysis = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    categories
                    Spacer(minLength: 12)
                    sourceAndSearch
                }
                VStack(alignment: .leading, spacing: 10) {
                    categories
                    sourceAndSearch
                }
            }
            if store.catalogBusy || store.catalogError != nil {
                HStack(spacing: 8) {
                    if store.catalogBusy { ProgressView().controlSize(.small) }
                    Text(store.catalogMessage).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                    Spacer()
                    if store.catalogBusy { Button("Stop") { store.stopCatalog() }.buttonStyle(.plain) }
                    else { Button("Dismiss") { store.catalogError = nil }.buttonStyle(.plain) }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                MediaTagFlow(spacing: 10) {
                    Menu {
                        ForEach(MediaAddedRange.allCases, id: \.self) { range in
                            Button { store.mediaAddedRange = range } label: {
                                if store.mediaAddedRange == range { Label(LocalizedStringKey(range.rawValue), systemImage: "checkmark") }
                                else { Text(LocalizedStringKey(range.rawValue)) }
                            }
                        }
                    } label: {
                        MediaFilterLabel(title: store.mediaAddedRange == .all ? "Import date" : store.mediaAddedRange.rawValue,
                                         symbol: "calendar", selected: store.mediaAddedRange != .all)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).buttonStyle(.plain).fixedSize()
                        .modifier(MediaMenuSurface(selected: store.mediaAddedRange != .all))
                        .tint(store.mediaAddedRange == .all ? Color.pixfunMuted : .pixfunGold)
                        .accessibilityLabel("Import date: \(store.mediaAddedRange.rawValue)")
                        .help("Filter by when files were added to Pixfun. Older files without a recorded import date remain under Any import date.")
                    ForEach(MediaFacet.allCases, id: \.self) { facet in
                        MediaFacetMenu(facet: facet)
                    }
                    if store.mediaWorkFilter != .all {
                        Button { store.mediaWorkFilter = .all } label: { Label(LocalizedStringKey(store.mediaWorkFilter.rawValue), systemImage: "xmark.circle") }
                            .buttonStyle(PixfunButtonStyle(kind: .quiet)).font(.pixfun(12)).foregroundStyle(Color.pixfunGold)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Reserve the small reset slot: applying a filter never moves rows.
                Button("Clear", action: store.resetMediaFilters)
                    .buttonStyle(.plain).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                    .opacity(store.hasMediaFilters ? 1 : 0).disabled(!store.hasMediaFilters)
                    .accessibilityHidden(!store.hasMediaFilters).accessibilityLabel("Clear all Media filters").frame(height: 36)
            }
        }.padding(.bottom, 18)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.pixfunLine.opacity(0.55)).frame(height: 1) }
            .alert("Reanalyze all Media?", isPresented: $confirmReanalysis) {
                Button("Reanalyze") { store.reanalyzeMedia() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Refresh tags, descriptions and shot analysis locally. Originals, favorites and projects are kept. This may take a while.")
            }
    }

    private var categories: some View {
        Picker("Media type", selection: $store.category) {
            ForEach(MediaCategory.allCases, id: \.self) { category in
                Text(LocalizedStringKey(category.rawValue)).tag(category)
            }
        }.labelsHidden().pickerStyle(.segmented).controlSize(.regular).frame(width: 240)
    }

    private var sourceAndSearch: some View {
        HStack(spacing: 8) {
            folderMenu
            MediaSearchControls().frame(minWidth: 180, idealWidth: 260, maxWidth: .infinity)
            sortMenu
        }
    }

    private var folderMenu: some View {
        Menu {
            Button { store.folder = ""; store.syncSourceID = nil; store.syncSourceName = nil } label: {
                if store.folder.isEmpty && store.syncSourceID == nil { Label("All sources", systemImage: "checkmark") }
                else { Text("All sources") }
            }
            if !store.importedSources.isEmpty {
                Section("Imported devices") {
                    ForEach(store.importedSources, id: \.id) { source in
                        Button { store.folder = ""; store.syncSourceName = source.name; store.syncSourceID = source.id } label: {
                            if store.syncSourceID == source.id { Label(source.name, systemImage: "checkmark") }
                            else { Label(source.name, systemImage: source.symbol) }
                        }
                    }
                }
            }
            Divider()
            ForEach(store.folders) { folder in
                Button { store.syncSourceID = nil; store.syncSourceName = nil; store.folder = folder.path } label: {
                    let name = URL(fileURLWithPath: folder.path).lastPathComponent
                    Label("\(name) (\(folder.count))", systemImage: store.folder == folder.path ? "checkmark" : "folder")
                }.help(folder.path)
            }
        } label: {
            MediaFilterLabel(title: store.syncSourceName ?? (store.folder.isEmpty ? "All sources" : URL(fileURLWithPath: store.folder).lastPathComponent),
                             symbol: "folder", selected: !store.folder.isEmpty || store.syncSourceID != nil, height: 30, expanded: true)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).buttonStyle(.plain)
            .tint(store.folder.isEmpty && store.syncSourceID == nil ? .pixfunMuted : .pixfunGold).frame(width: 160)
            .modifier(MediaMenuSurface(selected: !store.folder.isEmpty || store.syncSourceID != nil, height: 30))
            .accessibilityLabel("Filter by folder or imported device").help(store.syncSourceName ?? (store.folder.isEmpty ? "Filter by original folder, including subfolders" : store.folder))
    }

    private var sortMenu: some View {
        Menu {
            Button("Reanalyze all Media…") { confirmReanalysis = true }.disabled(store.items.isEmpty || store.items.contains(where: \.processing))
            Divider()
            ForEach(MediaSort.allCases.filter { $0 != .beauty || store.sort == .beauty }, id: \.self) { sort in
                Button { store.sort = sort } label: {
                    let title = sort == .original && store.isSearchingMedia ? "Best matches" : sort.rawValue
                    if store.sort == sort { Label(LocalizedStringKey(title), systemImage: "checkmark") }
                    else { Text(LocalizedStringKey(title)) }
                }
            }
            if store.canCompareBeauty {
                Divider()
                Button(LocalizedStringKey(store.comparingBeauty ? "Comparing aesthetics…" : "Compare aesthetic quality")) { store.compareBeauty() }
                    .disabled(store.comparingBeauty || store.visibleItems.isEmpty)
                Text("Sampled frames only · film order stays unchanged")
            }
            if store.items.contains(where: \.processing) {
                Divider()
                Button("Stop analysis") { store.perform { try await store.service.update("/api/desktop/stop", [:]); try await store.refresh() } }.disabled(store.importing)
            }
        } label: {
            Image(systemName: store.comparingBeauty ? "hourglass" : "arrow.up.arrow.down").font(.system(size: 15)).foregroundStyle(Color.pixfunMuted)
                .frame(width: 16, height: 16)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).buttonStyle(.plain).tint(.pixfunMuted).frame(width: 40)
            .modifier(MediaMenuSurface(height: 30))
            .accessibilityLabel("Sort options").help("Sort results")
    }
}

struct MediaFacetMenu: View {
    @EnvironmentObject var store: WorkspaceStore
    let facet: MediaFacet
    private var selected: MediaFacetTag? { store.mediaFacets.values[facet] }
    private var options: [MediaFacetOption] { store.mediaFacetOptions[facet] ?? [] }
    var body: some View {
        Menu {
            Button { store.mediaFacets.values[facet] = nil } label: {
                if selected == nil { Label("All", systemImage: "checkmark") }
                else { Text("All") }
            }
            Divider()
            ForEach(options) { option in
                Button { store.mediaFacets.values[facet] = option.tag } label: {
                    if selected?.id == option.id {
                        Label { Text(LocalizedStringKey(option.tag.text)) + Text(verbatim: " (\(option.count))") } icon: { Image(systemName: "checkmark") }
                    } else { Text(LocalizedStringKey(option.tag.text)) + Text(verbatim: " (\(option.count))") }
                }.disabled(option.count == 0 && selected?.id != option.id)
            }
        } label: {
            MediaFilterLabel(title: selected?.text ?? facet.rawValue, symbol: facet.symbol, selected: selected != nil, categoryTint: MediaTagPalette.facet(facet))
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).buttonStyle(.plain)
            .tint(MediaTagPalette.facet(facet))
            .fixedSize(horizontal: true, vertical: false)
            .modifier(MediaMenuSurface(selected: selected != nil, tint: MediaTagPalette.facet(facet)))
            .disabled(options.isEmpty)
            .accessibilityLabel("\(facet.rawValue): \(selected?.text ?? "Any")")
            .help(options.isEmpty ? "No matching \(facet.rawValue.lowercased()) tags yet. \(facet.help)" : "\(selected?.text ?? facet.rawValue) · \(facet.help)")
    }
}

/// Consistent, single-chevron labels for source and metadata filters.
private struct MediaFilterLabel: View {
    let title: String
    let symbol: String
    var selected = false
    var height: CGFloat = 30
    var expanded = false
    var categoryTint: Color? = nil
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 16)
            Text(LocalizedStringKey(title)).font(.pixfun(13)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: expanded ? .infinity : 120, alignment: .leading)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium)).frame(width: 10)
        }
        .foregroundStyle(categoryTint ?? (selected ? Color.pixfunGold : .pixfunMuted))
        .padding(.horizontal, 10).frame(height: height)
    }
}

/// Style the menu control itself: macOS can flatten decoration inside Menu labels.
private struct MediaMenuSurface: ViewModifier {
    var selected = false
    var height: CGFloat = 30
    var tint: Color = .pixfunGold
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    func body(content: Content) -> some View {
        content.padding(.horizontal, 10).frame(height: height)
        .background(selected ? tint.opacity(0.08) : hovered ? .pixfunRaised : .pixfunSurface,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.pixfunFocus : selected ? tint.opacity(0.45) : .pixfunLine.opacity(0.8), lineWidth: focused ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .opacity(enabled ? 1 : 0.5).onHover { hovered = $0 }
    }
}
