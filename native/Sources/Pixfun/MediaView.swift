import SwiftUI
import AVKit

struct MediaView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var knownMediaIDs: Set<String> = []
    @State private var selectingForRemoval = false
    private var hasMedia: Bool { !store.libraryItems.isEmpty }
    private var grouped: Bool { !store.hasMediaFilters && store.sort == .original }
    private var sections: [MediaImportSection] {
        grouped ? MediaImportSection.grouped(store.mediaSearchResults) : [.init(id: "results", date: nil, items: store.mediaSearchResults)]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if hasMedia || store.selecting { HStack {
                PageHeading(title: "Library", subtitle: store.selecting ? (store.language == .chinese ? "已选择 \(store.selection.count) 个素材" : "\(store.selection.count) selected") : !hasMedia ? "Your media, organized and easy to find." : store.mediaResultSummary)
                Spacer()
                if store.importing {
                    ProgressView().controlSize(.small)
                    Text("Adding files…").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                }
                if store.selecting {
                    Button("Cancel", action: store.cancelSelection)
                    Button("Select all visible") { store.selection.formUnion(store.visibleItems.map(\.id)) }
                        .disabled(store.visibleItems.isEmpty)
                    if !selectingForRemoval {
                        Button("Favorite") { for item in store.items where store.selection.contains(item.id) && item.favorite != true { store.favorite(item) } }.disabled(store.selection.isEmpty)
                        Button("Create rough cut · Beta", action: store.finishSelection).buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(store.selection.isEmpty)
                    }
                    Button {
                        store.requestMediaRemoval(store.libraryItems.filter { store.selection.contains($0.id) })
                    } label: { Text("Delete…").frame(height: 36).contentShape(Rectangle()) }
                        .buttonStyle(.plain).font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                        .disabled(store.selection.isEmpty)
                        .help("Remove selected items from the library. Original files are kept.")
                } else if hasMedia {
                    HStack(spacing: 16) {
                        Button(action: store.beginSelection) {
                            Text("Select").frame(height: 36).contentShape(Rectangle())
                        }
                        Button { selectingForRemoval = true; store.beginSelection() } label: {
                            Text("Delete…").frame(height: 36).contentShape(Rectangle())
                        }.help("Select items to remove from the library. Original files are kept.")
                    }.buttonStyle(.plain).font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                        .padding(.trailing, 8)
                    Menu {
                        Button("Add local files…") { store.pick() }
                        Button("Add local folder…") { store.pick(folder: true) }
                        Divider()
                        Button("Connect a device or sync folder…") { store.navigate(.mediaSync) }
                    } label: { Label("Import", systemImage: "plus").foregroundStyle(Color.pixfunBackground) }
                        .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 14).frame(height: 36)
                        .tint(.pixfunBackground).foregroundStyle(Color.pixfunBackground).background(Color.pixfunGold, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Import media")
                        .help("Add files in place, or use Media Sync for verified copies")
                }
            }.disabled(store.importing || store.removingMedia) }
            if store.removingMedia {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Updating library…").font(.caption) }
            }
            if hasMedia { MediaBrowserToolbar() }
            if hasMedia { MediaLibraryActivityView() }
            GeometryReader { proxy in
                let columns = Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: proxy.size.width > 1100 ? 4 : proxy.size.width > 730 ? 3 : 2)
                ScrollViewReader { scroll in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            if store.visibleItems.isEmpty {
                                if !hasMedia { MediaLibraryWelcomeView() }
                                else {
                                    EmptyWorkspace(symbol: "magnifyingglass", title: "No matching media", detail: "Try fewer keywords or clear a filter. Content results appear as analysis finishes; filenames and sources remain searchable.")
                                        .frame(minHeight: 240)
                                }
                                if hasMedia && store.hasMediaFilters {
                                    HStack {
                                        if store.searchScope != .all { Button("Search everything") { store.searchScope = .all } }
                                        Button("Reset filters", action: store.resetMediaFilters)
                                    }.buttonStyle(PixfunButtonStyle()).frame(maxWidth: .infinity)
                                }
                            } else {
                                ForEach(sections, id: \.id) { section in
                                    VStack(alignment: .leading, spacing: 14) {
                                        HStack(spacing: 10) {
                                            Text(LocalizedStringKey(grouped ? section.title : store.hasMediaFilters ? "Results" : store.sort.rawValue))
                                                .font(.pixfun(14, semibold: true))
                                            if grouped, let item = section.items.first?.item {
                                                let source = store.mediaSource(item)
                                                Text("·").foregroundStyle(Color.pixfunSubtle)
                                                Label(LocalizedStringKey(source.name), systemImage: source.symbol).lineLimit(1).help(source.name)
                                                if item.importBatchId != nil, let date = section.date { Text(date, style: .time) }
                                            }
                                            Spacer(minLength: 4)
                                            Text("\(section.items.count) items").monospacedDigit()
                                                .foregroundStyle(Color.pixfunSubtle)
                                        }.font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                                            ForEach(section.items) { result in MediaCard(item: result.item).id(result.id) }
                                        }
                                    }
                                }.padding(.bottom, 16)
                            }
                        }.id("media-list-top")
                    }.onAppear {
                        knownMediaIDs = Set(store.items.map(\.id))
                        if let id = store.lastOpenedMediaID { scroll.scrollTo(id, anchor: .center) }
                    }.onChange(of: store.items.map(\.id)) { ids in
                        let current = Set(ids), added = current.subtracting(knownMediaIDs)
                        knownMediaIDs = current
                        // Surface imports without disturbing manual sorting or active searches.
                        if !added.isEmpty, store.sort == .original, !store.isSearchingMedia,
                           let first = store.mediaSearchResults.first, added.contains(first.id) {
                            scroll.scrollTo("media-list-top", anchor: .top)
                        }
                    }
                }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
            }
        }.padding(PixfunLayout.pageInset).navigationTitle("Library")
            .onChange(of: store.selecting) { active in if !active { selectingForRemoval = false } }
            .alert(store.language == .chinese ? "从素材库删除这 \(store.mediaRemovalRequest.count) 个素材？" : "Remove \(store.mediaRemovalRequest.count) items from the library?",
                   isPresented: Binding(get: { !store.mediaRemovalRequest.isEmpty }, set: { if !$0 { store.mediaRemovalRequest = [] } }),
                   presenting: store.mediaRemovalRequest) { targets in
                Button("Cancel", role: .cancel) { store.mediaRemovalRequest = [] }
                Button("Remove from Media", role: .destructive) { store.removeConfirmedMedia(targets) }
            } message: { _ in
                Text("Only library references will be removed. Original photos and videos on your Mac or external drive will not be deleted. Analysis of these items will stop. You can import them again.")
            }
    }
}

struct MediaCard: View {
    @EnvironmentObject var store: WorkspaceStore
    let item: MediaItem
    @State private var hovered = false
    var isSelected: Bool { store.selecting && store.selection.contains(item.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if store.selecting { store.toggleSelection(item.id) } else { store.openMedia(item, at: store.visualMatchTime(item.id) ?? 0) }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    // Fill the fixed thumbnail area; playback keeps the original aspect ratio.
                    ServiceImage(path: item.cover, fit: .fill).aspectRatio(16.0 / 10.0, contentMode: .fit)
                        .overlay(alignment: .bottomLeading) {
                            if let status = item.processingLabel {
                                HStack(spacing: 7) {
                                    PixfunActivityIndicator(queued: status == "Queued…" || status == "Waiting to retry…", size: 18, tint: .pixfunGold)
                                    Text(LocalizedStringKey(status)).font(.pixfun(12, semibold: true))
                                }.foregroundStyle(Color.pixfunInk).padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(Color.pixfunBackground.opacity(0.85), in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.25)))
                                    .padding(8).allowsHitTesting(false).accessibilityLabel(status)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            let source = store.mediaSource(item)
                            let device = MediaCaptureIdentity(camera: item.metadata?.camera, source: source)
                            Label(LocalizedStringKey(device.name), systemImage: device.symbol).font(.pixfun(11, semibold: true))
                                .lineLimit(1).truncationMode(.middle).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(.black.opacity(0.65), in: Capsule())
                                .padding(.leading, 8).padding(.trailing, 48).padding(.top, 8)
                                .allowsHitTesting(false).help(device.name)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if item.kind == "video", let seconds = item.metadata?.duration, seconds > 0 {
                                Text(timestamp(seconds)).font(.caption.monospacedDigit()).padding(5).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 5)).padding(8)
                            }
                        }
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.name).font(.pixfun(14, semibold: true)).lineLimit(1).help(item.name)
                        if let cardDetail {
                            Text(verbatim: cardDetail).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).lineLimit(1)
                        }
                        if let time = store.visualMatchTime(item.id) {
                            Label("Visual match · \(timestamp(time))", systemImage: "play.circle")
                                .font(.pixfun(12)).foregroundStyle(Color.pixfunGold)
                        }
                    }.padding(13)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("\(store.selecting ? (isSelected ? "Deselect" : "Select") : "Open") \(item.name)\(item.isExample == true ? " · Sample" : "")\(item.processingLabel.map { " · \($0)" } ?? "")")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            let coreTags = store.coreMediaTags(for: item)
            if !coreTags.isEmpty {
                MediaTagFlow(spacing: 6) {
                    ForEach(coreTags) { tag in
                        MediaFacetChip(tag: tag) {
                            if store.selecting { store.toggleSelection(item.id) }
                            else { store.toggleMediaTag(tag) }
                        }
                    }
                }.padding(.horizontal, 13).padding(.bottom, 13)
            }
        }
        .background(hovered ? Color.pixfunRaised : .pixfunSurface).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(store.selecting && store.selection.contains(item.id) ? Color.pixfunGold : hovered ? .pixfunSubtle : .pixfunLine, lineWidth: store.selection.contains(item.id) && store.selecting ? 2 : 1))
        .onHover { hovered = $0 }
        .overlay(alignment: .topTrailing) {
            if store.selecting {
                MediaSelectionBadge(selected: isSelected).padding(10).allowsHitTesting(false).accessibilityHidden(true)
            } else {
                Button { store.favorite(item) } label: { Image(systemName: item.favorite == true ? "star.fill" : "star").font(.system(size: 15)).frame(width: 32, height: 32).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.2))) }
                    .buttonStyle(.plain).foregroundStyle(item.favorite == true ? Color.pixfunGold : .white).padding(7).accessibilityLabel(item.favorite == true ? "Remove favorite" : "Favorite")
            }
        }
        .contextMenu {
            if let usage = store.usedShots(item.id) {
                Menu("Used in current edit") {
                    ForEach(usage.shots.filter { $0.mediaId == item.id }) { shot in
                        Button("Cut \(StoryTimeline.timecode(StoryTimeline.offset(shot.id, in: usage.shots)))") {
                            store.openUsedShot(shot.id, projectID: usage.run.projectId)
                        }
                    }
                }
            }
            Button("Create rough cut · Beta") { store.attach([item.id]) }
            Button("Show in Finder") { store.reveal(item) }
            Button(LocalizedStringKey(item.favorite == true ? "Remove favorite" : "Favorite")) { store.favorite(item) }
            if item.missing == true { Button("Locate original…") { store.pick(locate: item.id) } }
            if item.analysisNeedsAttention { Button("Retry analysis") { store.retry(item) } }
            Divider()
            Button("Remove from Media", role: .destructive) { store.remove(item) }.disabled(store.removingMedia)
        }
    }
    private var cardDetail: String? {
        guard let date = item.metadata?.captureDate else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct MediaTagChip: View {
    @Environment(\.locale) private var locale
    let tag: MediaSearchTag
    var selected = false
    var tint: Color = MediaTagPalette.detail
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isFocused) private var focused
    private var displayText: String {
        tag.symbol == "video" ? CameraMotionLabel.display(tag.text, chinese: locale.identifier.hasPrefix("zh")) : tag.text
    }
    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(displayText)).font(.pixfun(11)).lineLimit(1).truncationMode(.tail)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(tint.opacity(selected ? 0.20 : hovered ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? Color.pixfunFocus : tint.opacity(selected ? 0.8 : 0.3)))
        }.buttonStyle(.plain).foregroundStyle(tint)
            .onHover { hovered = $0 }
            .help("Find media tagged: \(displayText)")
            .accessibilityLabel("Search tag: \(displayText)")
    }
}

struct MediaFacetChip: View {
    @EnvironmentObject var store: WorkspaceStore
    let tag: MediaFacetTag
    let action: () -> Void
    private var selected: Bool { store.mediaFacets.values[tag.facet]?.id == tag.id }
    var body: some View {
        MediaTagChip(tag: .init(text: tag.text, scope: .content, symbol: tag.facet.symbol), selected: selected, tint: MediaTagPalette.facet(tag.facet), action: action)
            .help("\(tag.facet.rawValue): \(tag.text)")
            .accessibilityLabel("Filter \(tag.facet.rawValue): \(tag.text)")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Normalize SF Symbols' different intrinsic widths without distorting them.
private struct MediaTagGroupLabel: View {
    let title: String
    let symbol: String
    let tint: Color
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).resizable().scaledToFit()
                .frame(width: 14, height: 14)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(title)).font(.pixfun(12)).lineLimit(1)
        }
        .foregroundStyle(tint).frame(width: 120, alignment: .leading).padding(.top, 4)
        .accessibilityElement(children: .combine)
    }
}

struct MediaDetailTags: View {
    @EnvironmentObject var store: WorkspaceStore
    let item: MediaItem
    var seek: ((Double) -> Void)? = nil
    @State private var editingTags = false
    private var tags: [MediaFacetTag] { store.mediaTags(for: item) }
    private var keywords: [MediaSearchTag] { MediaTagPresentation.visualDetails(item) }
    private var groups: [MediaDetailTagGroup] { MediaTagPresentation.detailGroups(item) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Tags").font(.pixfun(16, semibold: true))
                Spacer()
                if item.hasStructuredTags {
                    Button("Review tags") { editingTags = true }.buttonStyle(PixfunButtonStyle(kind: .quiet))
                } else {
                    Text("Filter your library by category").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                }
            }
            if tags.isEmpty {
                Text(LocalizedStringKey(item.processing ? "Category tags appear as analysis finishes." : "No matching category tags yet."))
                    .font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
            } else {
                ForEach(MediaFacet.allCases, id: \.self) { facet in
                    let categoryTags = tags.filter { $0.facet == facet }
                    if !categoryTags.isEmpty {
                        HStack(alignment: .top, spacing: 16) {
                            MediaTagGroupLabel(title: facet.rawValue, symbol: facet.symbol, tint: MediaTagPalette.facet(facet))
                            MediaTagFlow(spacing: 8) {
                                ForEach(categoryTags) { tag in MediaFacetChip(tag: tag) { store.filterMediaTag(tag) } }
                            }
                        }
                    }
                }
            }
            ForEach(groups) { group in
                let tint = MediaTagPalette.technique
                HStack(alignment: .top, spacing: 16) {
                    MediaTagGroupLabel(title: group.title, symbol: group.symbol, tint: tint)
                    MediaTagFlow(spacing: 8) {
                        ForEach(group.tags) { tag in MediaTagChip(tag: tag, tint: tint) { store.searchMediaTag(tag) } }
                    }
                }
            }
            if !keywords.isEmpty {
                HStack(alignment: .top, spacing: 16) {
                    MediaTagGroupLabel(title: "Visual details", symbol: "text.magnifyingglass", tint: MediaTagPalette.detail)
                    MediaTagFlow(spacing: 8) {
                        ForEach(keywords) { tag in
                            MediaTagChip(tag: tag) { store.searchMediaTag(tag) }
                        }
                    }
                }
            }
        }.padding(.vertical, 6)
            .sheet(isPresented: $editingTags) { MediaTagReview(item: item, seek: seek).environmentObject(store) }
    }
}

/// Corrections are library metadata, never a rewrite of the model's evidence.
struct MediaTagReview: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    var seek: ((Double) -> Void)? = nil
    @State private var hidden: Set<String> = []
    @State private var added: [EvidenceTag] = []
    @State private var category = "subject"
    @State private var label = ""
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Review tags").font(.pixfun(18, semibold: true))
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(saving)
                Button(LocalizedStringKey(saving ? "Saving…" : "Save")) {
                    saving = true; error = nil
                    Task {
                        do { try await store.saveMediaTags(item, hidden: hidden, added: added); dismiss() }
                        catch { self.error = error.localizedDescription; saving = false }
                    }
                }.buttonStyle(PixfunButtonStyle(kind: .primary)).disabled(saving)
            }
            Text("Uncheck incorrect tags or add your own. Corrections survive reanalysis; original observations stay intact.")
                .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(item.generatedTags) { tag in
                        VStack(alignment: .leading, spacing: 5) {
                            Toggle(isOn: Binding(get: { !hidden.contains(tag.id) }, set: { if $0 { hidden.remove(tag.id) } else { hidden.insert(tag.id) } })) {
                                HStack { Text(LocalizedStringKey(tag.label)); Text(LocalizedStringKey(tag.category.capitalized)).foregroundStyle(Color.pixfunMuted) }
                            }.toggleStyle(.checkbox).font(.pixfun(13))
                            Text(LocalizedStringKey(tag.source == "user" ? "Added by you" : "Observed in sampled frames · category normalized from saved tags"))
                                .font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
                            if item.kind == "video", !tag.evidence.isEmpty {
                                MediaTagFlow(spacing: 8) {
                                    ForEach(Array(tag.evidence.enumerated()), id: \.offset) { _, ref in
                                        Button("\(timestamp(ref.start))–\(timestamp(ref.end))") {
                                            if let seek { seek(ref.start) } else { store.openMedia(item, at: ref.start) }
                                            dismiss()
                                        }.buttonStyle(.plain).font(.pixfun(11)).monospacedDigit().foregroundStyle(Color.pixfunGold)
                                            .help("Observation window: \(ref.text). Review the original before treating this as a precise detection.")
                                    }
                                }
                            }
                        }.padding(.vertical, 3)
                    }
                    ForEach(added) { tag in
                        HStack {
                            Text(LocalizedStringKey(tag.label)).font(.pixfun(13))
                            Text("\(tag.category.capitalized) · Added by you").font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
                            Spacer()
                            Button { added.removeAll { $0.id == tag.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).accessibilityLabel("Remove custom tag \(tag.label)")
                        }
                    }
                }.padding(.trailing, 8)
            }
            HStack {
                Picker("Category", selection: $category) {
                    ForEach(["scene","subject","activity","detail"], id: \.self) { Text(LocalizedStringKey($0.capitalized)).tag($0) }
                }.labelsHidden().frame(width: 110)
                TextField("Add a tag", text: $label).textFieldStyle(.roundedBorder)
                Button("Add") {
                    let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = text.lowercased(), id = category+":"+key
                    if !added.contains(where: { $0.id == id }) {
                        added.append(.init(id:id, category:category, key:key, label:text, aliases:[], source:"user", evidence:[]))
                    }
                    label = ""
                }.disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || label.count > 48 || added.count >= 50)
            }.disabled(saving)
            if let error { Text(error).font(.pixfun(12)).foregroundStyle(Color.orange) }
        }.padding(24).frame(width: 600, height: 560).background(Color.pixfunBackground)
            .onAppear { hidden = Set(item.tagCorrections?.hidden ?? []); added = item.tagCorrections?.added ?? [] }
    }
}

/// Intrinsic-width chips wrap without adding a horizontal scrollbar to each card.
struct MediaTagFlow: Layout {
    var spacing: CGFloat = 6
    func positions(_ subviews: Subviews, width: CGFloat) -> ([CGPoint], CGSize) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + spacing; row = max(row, size.height)
        }
        return (points, CGSize(width: width, height: y + row))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        positions(subviews, width: max(1, proposal.width ?? 260)).1
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let points = positions(subviews, width: bounds.width).0
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + points[index].x, y: bounds.minY + points[index].y), proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

/// Opaque contrast backing keeps the selection control legible on every cover.
struct MediaSelectionBadge: View {
    let selected: Bool
    var body: some View {
        ZStack {
            Circle().fill(selected ? Color.pixfunGold : Color.pixfunBackground)
            Circle().strokeBorder(selected ? Color.pixfunGold : Color.white, lineWidth: 2)
            if selected {
                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.pixfunBackground)
            }
        }
        .frame(width: 30, height: 30)
        .background(Circle().fill(Color.pixfunBackground).padding(-2))
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }
}

struct MediaDetailView: View {
    @EnvironmentObject var store: WorkspaceStore
    let initialItem: MediaItem
    @StateObject private var playback = PlaybackController()
    @State private var playerError: String?
    @State private var selectedSegment: String?
    @State private var photo: NSImage?
    @State private var videoCover: NSImage?
    @State private var subtitleSearch = ""
    var item: MediaItem { store.items.first { $0.id == initialItem.id } ?? initialItem }
    var source: MediaLocation? { store.locations[item.id] }
    var matchingCues: [(offset: Int, element: Cue)] { Array(item.transcriptCues.enumerated()).filter { subtitleSearch.isEmpty || $0.element.text.localizedCaseInsensitiveContains(subtitleSearch) } }
    func seek(_ seconds: Double) { playback.seek(seconds) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button(action: store.backToMedia) { Label(LocalizedStringKey(store.mediaBackTitle), systemImage: "chevron.left") }.buttonStyle(PixfunButtonStyle(kind: .quiet)).keyboardShortcut("[", modifiers: .command).accessibilityLabel("Back to \(store.mediaBackTitle)")
                Text(item.name).font(.pixfun(17, semibold: true)).lineLimit(2).help(item.name)
                Spacer()
                Button { store.favorite(item) } label: { Image(systemName: item.favorite == true ? "star.fill" : "star") }.help("Favorite")
                Button("Add to brief") { store.attach([item.id]) }.buttonStyle(PixfunButtonStyle(kind: .primary))
            }.padding(.horizontal, PixfunLayout.pageInset).padding(.vertical, 16)
            Rectangle().fill(Color.pixfunLine).frame(height: 1)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            Group {
                                if item.kind == "image", let photo { Image(nsImage: photo).resizable().scaledToFit() }
                                else if let player = playback.player { NativeVideoPlayer(player: player, poster: playback.showsPoster ? playback.poster ?? videoCover : nil) }
                                else { ZStack { Color.black; if let playerError { Text(playerError).foregroundStyle(.secondary).padding() } else { ProgressView() } } }
                            }.frame(maxWidth: .infinity).frame(height: 420).background(.black).clipShape(RoundedRectangle(cornerRadius: 10))
                            if let error = playback.error {
                                HStack { Text(error).font(.caption).foregroundStyle(.orange); Button("Retry playback") { playback.retry() } }
                            }
                            if item.kind == "video", item.segments.count > 1 {
                                shotFilmstrip
                            }
                            if item.missing == true { Button("Locate original…") { store.pick(locate: item.id) } }
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Original").font(.pixfun(16, semibold: true))
                            originalMetadata
                            sourceFolderLink
                            if item.isExample == true {
                                Text("Built-in sample · Continuous excerpt").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                                if let credit = item.context?["credit"] {
                                    Text(credit).font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
                                }
                                if let link = item.context?["source"], let url = URL(string: link), url.scheme == "https" {
                                    Link("Source footage ↗", destination: url).font(.pixfun(12)).tint(.pixfunGold)
                                }
                            }
                            if let state = item.mediaAnalysis, state.status == "retrying" {
                                Text(store.language == .chinese
                                     ? "暂时中断，将自动重试（\(state.attempt ?? 1)/\(max(1, (state.maxAttempts ?? 3) - 1))）。已完成的结果已保留。"
                                     : "Temporarily interrupted. Automatic retry \(state.attempt ?? 1)/\(max(1, (state.maxAttempts ?? 3) - 1)); completed results are kept.")
                                    .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                            } else if let state = item.mediaAnalysis, state.status != "ready", let message = state.message, !message.isEmpty {
                                Text(LocalizedStringKey(message)).font(.pixfun(12)).foregroundStyle(item.analysisNeedsAttention ? Color.pixfunGold : Color.pixfunMuted)
                            }
                            if item.analysisNeedsAttention { Button("Retry analysis") { store.retry(item) } }
                        }.frame(width: 240, alignment: .leading)
                    }
                    if let error = item.error { Text(error).font(.callout).foregroundStyle(.orange) }
                    MediaDetailTags(item: item, seek: { seconds in
                        selectedSegment = item.segments.first { $0.start <= seconds && seconds < $0.end }?.id
                        seek(seconds)
                    })
                    editorialDescription
                    analysisDetails
                    if let location = item.recordedLocation {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Location").font(.pixfun(16, semibold: true))
                            Text(location).font(.pixfun(14)).foregroundStyle(Color.pixfunMuted).textSelection(.enabled)
                            if let coordinates = item.metadata?.location?.coordinates, coordinates != location {
                                Text(coordinates).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).textSelection(.enabled)
                            }
                            Text(LocalizedStringKey(item.locationAttribution))
                                .font(.pixfun(11)).foregroundStyle(Color.pixfunSubtle)
                            if !item.hasSavedPlaceName, item.metadata?.location?.coordinates != nil, item.metadata?.location?.resolvedName == nil {
                                Text(LocalizedStringKey(store.onlinePlaceNames ? "Place lookup uses Apple Maps; coordinates are kept when unavailable." : "Enable online place lookup in Settings to show area names."))
                                    .font(.pixfun(11)).foregroundStyle(Color.pixfunSubtle)
                            }
                        }
                    }
                    if !item.transcriptCues.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Subtitles & speech").font(.pixfun(16, semibold: true))
                            Text("\(item.transcriptCues.count) entries").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                            Spacer()
                            PixfunSearchField(placeholder: "Find in transcript", text: $subtitleSearch).frame(width: 230)
                        }
                        HStack(spacing: 8) {
                            Text(LocalizedStringKey(item.subtitleSourceLabel))
                            if let language = item.result?.analysis?.subtitleLanguage { Text(store.language.locale.localizedString(forLanguageCode: language) ?? language) }
                            if item.result?.analysis?.subtitleState == "sidecar", let filename = item.result?.analysis?.subtitleSource { Text(filename).lineLimit(1) }
                        }.font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
                        if let message = item.result?.analysis?.subtitleMessage, item.result?.analysis?.subtitleSource == "local-asr" {
                            Text(LocalizedStringKey(message)).font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
                        }
                        if matchingCues.isEmpty {
                            Text("No matching subtitles.").font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(matchingCues, id: \.offset) { _, cue in
                                    HStack(alignment: .top, spacing: 18) {
                                        Button(timestamp(cue.start)) { seek(cue.start) }.buttonStyle(.plain).foregroundStyle(Color.pixfunGold).monospacedDigit().frame(width: 55, alignment: .leading).accessibilityLabel("Jump to \(timestamp(cue.start))")
                                        Text(cue.text).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                                    }.padding(.vertical, 13)
                                    Divider()
                                }
                            }
                        }
                    }
                    }
                    if item.transcriptCues.isEmpty, let message = item.subtitleDisplayMessage, !message.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Text("Subtitles & speech").font(.pixfun(13, semibold: true))
                            Text(LocalizedStringKey(message)).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                        }
                    }
                    if let texts = item.analysisEvidence?.onScreenText, !texts.isEmpty {
                        DisclosureGroup("On-screen text") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Recognized in sampled frames. Includes signs and captions; timestamps are observation windows, not subtitle timing.")
                                    .font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
                                ForEach(Array(texts.enumerated()), id: \.offset) { _, entry in
                                    HStack(alignment: .top, spacing: 14) {
                                        if item.kind == "video" { Button(timestamp(entry.start)) { seek(entry.start) }.buttonStyle(.plain).foregroundStyle(Color.pixfunGold).monospacedDigit() }
                                        Text(entry.text).textSelection(.enabled)
                                    }.font(.pixfun(13))
                                }
                            }.padding(.top, 10)
                        }.font(.pixfun(13)).tint(.pixfunMuted)
                    }
                }.padding(24)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.pixfunBackground)
            .navigationTitle("Media")
            .task(id: "cover-\(item.id)-\(item.cover ?? "")") {
                videoCover = nil
                guard item.kind == "video", let path = item.cover else { return }
                let image = await store.service.image(path)
                guard !Task.isCancelled else { return }
                videoCover = image
            }
            .task(id: "\(item.id)-\(source?.path ?? "")-\(item.missing == true)") {
                playback.stop(); playerError = nil
                do {
                    let url = try await store.service.original(item.id)
                    guard FileManager.default.fileExists(atPath: url.path) else { throw ServiceError(message: "Original file is missing.") }
                    if item.kind == "image" {
                        photo = NSImage(contentsOf: url)
                        if photo == nil, let preview = item.url { photo = await store.service.image(preview) }
                        if photo == nil { throw ServiceError(message: "This image could not be previewed. Open the original in Finder.") }
                    }
                    else {
                        selectedSegment = item.segments.first { $0.start <= store.mediaSeekTime && store.mediaSeekTime < $0.end }?.id
                        playback.open(url, at: store.mediaSeekTime, withPoster: true)
                        store.mediaSeekTime = 0
                        // Opening a search result is navigation, not permission to start new model work.
                        if item.kind == "video" && item.mediaAnalysis == nil && !store.isSearchingMedia { store.describeVideo(item); store.analyzeShots(item) }
                    }
                } catch { playerError = error.localizedDescription }
            }.onDisappear { playback.stop() }
    }
    private var originalMetadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let date = item.metadata?.captureDate {
                info("Date captured", date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute().second().locale(store.language.locale)))
            } else { info("Date captured", store.language == .chinese ? "未读取到拍摄时间" : "Capture date not read") }
            if let camera = item.metadata?.camera?.trimmingCharacters(in: .whitespacesAndNewlines), !camera.isEmpty {
                info("Capture device", camera)
            }
            let fileType = (item.file.name as NSString).pathExtension.uppercased()
            if !fileType.isEmpty { info("File type", fileType) }
            if item.kind != "image", let duration = item.metadata?.duration, duration.isFinite, duration > 0 {
                info("Duration", duration.formatted(.number.precision(.fractionLength(0...2)).locale(store.language.locale)) + (store.language == .chinese ? " 秒" : " s"))
            }
            if let width = item.metadata?.width, let height = item.metadata?.height,
               width.isFinite, height.isFinite, width > 0, height > 0, width < 1_000_000, height < 1_000_000 {
                info("Resolution", "\(Int(width)) × \(Int(height))")
            }
            if item.kind == "video", let fps = item.metadata?.frameRateLabel { info("Frame rate", fps) }
            if let size = item.file.size, size >= 0 { info("Size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
            if item.kind == "video", let codec = Metadata.codecLabel(item.metadata?.videoCodec) { info("Video codec", codec) }
            if item.kind != "image", let hasAudio = item.metadata?.hasAudio {
                info("Audio", hasAudio ? (Metadata.codecLabel(item.metadata?.audioCodec) ?? (store.language == .chinese ? "有音轨" : "Audio track present"))
                     : (store.language == .chinese ? "无音轨" : "No audio track"))
            }
            if item.metadata?.location?.coordinates != nil || item.metadata?.mediaCreatedAt != nil || item.metadata?.dateSource != nil {
                DisclosureGroup("More file metadata") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let coordinates = item.metadata?.location?.coordinates {
                            info("GPS coordinates", coordinates)
                            if let altitude = item.metadata?.location?.altitude, altitude.isFinite {
                                info("GPS altitude", altitude.formatted(.number.precision(.fractionLength(0...1)).locale(store.language.locale)) + " m")
                            }
                        }
                        if let source = item.metadata?.dateSource, !source.isEmpty { info("Capture date source", source) }
                        if let created = item.metadata?.mediaCreatedAt, !created.isEmpty { info("Container creation time", created) }
                        Text("Read from the original file. Container creation time may reflect an export, not the capture time.")
                            .font(.pixfun(11)).foregroundStyle(Color.pixfunMuted).fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 10)
                }.font(.pixfun(12)).tint(.pixfunMuted)
            }
        }
    }
    func info(_ name: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(LocalizedStringKey(name)).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                .frame(width: 76, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Text(verbatim: value).font(.pixfun(13)).foregroundStyle(Color.pixfunInk)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }.accessibilityElement(children: .combine)
    }
    @ViewBuilder var analysisDetails: some View {
        if item.kind == "video" || item.displayVideoDescription != nil {
            DisclosureGroup("Analysis details") {
                VStack(alignment: .leading, spacing: 20) {
                    if item.kind == "video" {
                        shotAnalysisStatus
                        if let segment = item.segments.first(where: { $0.id == selectedSegment }) ?? item.segments.first,
                           let shot = segment.editorial {
                            analysisParameters(shot, segment: segment)
                        }
                    }
                    descriptionEvidence
                }
                .padding(.top, 14)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.pixfun(13)).tint(.pixfunMuted)
            .id(item.id + "-analysis-details")
            .accessibilityIdentifier("media.analysis.details")
        }
    }
    var shotFilmstrip: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(item.segments) { segment in
                    shotCard(segment).frame(width: 180)
                }
            }.padding(.bottom, 6)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("media.shots.below-player")
    }
    func shotCard(_ segment: Segment) -> some View {
        let selected = (item.segments.first(where: { $0.id == selectedSegment }) ?? item.segments.first)?.id == segment.id
        let highlighted = segment.editorial?.isHighlight == true
        return Button { selectedSegment = segment.id; seek(segment.start) } label: {
            VStack(alignment: .leading, spacing: 7) {
                ServiceImage(path: segment.thumbnailUrl, fit: .fill).aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(alignment: .topLeading) {
                        if highlighted {
                            Label("Highlight", systemImage: "sparkles")
                                .font(.pixfun(11, semibold: true))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .foregroundStyle(Color.pixfunBackground).background(Color.pixfunGold, in: Capsule())
                                .padding(8)
                                .help("AI editing pick: score 80+, recommended or must-keep, excluding likely duplicates and unusable shots.")
                        }
                    }
                Text(shotTitle(segment)).font(.pixfun(12, semibold: true)).padding(.horizontal, 8)
                Text("\(timestamp(segment.start))–\(timestamp(segment.end))").font(.pixfun(12)).monospacedDigit().foregroundStyle(Color.pixfunMuted).padding([.horizontal, .bottom], 8)
            }.background(Color.pixfunSurface).clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.pixfunGold : .pixfunLine, lineWidth: selected ? 2 : 1))
        }.buttonStyle(.plain)
            .accessibilityLabel("\(highlighted ? "Highlight · " : "")Jump to \(segment.label), \(timestamp(segment.start))")
            .accessibilityHint(segment.hoverDescription(analysisStatus: item.shotAnalysis?.status))
            .help(segment.hoverHelp(analysisStatus: item.shotAnalysis?.status))
    }
    var shotAnalysisStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Analysis results").font(.pixfun(13, semibold: true))
                Spacer()
                if item.shotAnalysis?.busy == true {
                    analysisActivity(queued: item.shotAnalysis?.status == "queued")
                    Button(LocalizedStringKey(item.shotAnalysis?.status == "queued" ? "Cancel" : "Stop")) { store.stopShots(item) }.buttonStyle(PixfunButtonStyle(kind: .quiet))
                } else {
                    Button(LocalizedStringKey(item.shotAnalysis?.segments == nil ? "Analyze" : "Reanalyze")) { store.analyzeShots(item, force: true) }
                        .buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(item.missing == true)
                }
            }
            if let state = item.shotAnalysis, let message = state.message, !message.isEmpty {
                Text(message).font(.pixfun(12)).foregroundStyle(state.status == "failed" ? Color.orange : Color.pixfunMuted)
            }
        }
    }
    func analysisParameters(_ shot: EditorialShot, segment: Segment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visual parameters").font(.pixfun(12, semibold: true))
            if item.segments.count > 1 {
                Text("Updates with the thumbnail selected above.")
                    .font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { shotQuickFacts(shot) }
                VStack(alignment: .leading, spacing: 6) { shotQuickFacts(shot) }
            }
            if shot.duplicate_candidate || shot.unusable_candidate {
                Text(LocalizedStringKey(shot.duplicate_candidate ? "Possible repeated content · review before removing" : "Potentially unusable · review original")).font(.pixfun(12)).foregroundStyle(Color.orange)
            }
            shotEvidence(shot, segment: segment)
        }
    }
    func shotTitle(_ segment: Segment) -> String {
        let index = (item.segments.firstIndex { $0.id == segment.id } ?? 0) + 1
        return store.language == .chinese ? "分镜 \(index)" : "Shot \(index)"
    }
    func shotEvidence(_ shot: EditorialShot, segment: Segment) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Divider().overlay(Color.pixfunLine)
                Text("Analysis & evidence").font(.pixfun(12, semibold: true))
                HStack(alignment: .firstTextBaseline) {
                    Text("Editing value").foregroundStyle(Color.pixfunMuted)
                    Spacer()
                    Text("\(Int(shot.importance_score))/100 · AI estimate").monospacedDigit()
                }
                Text(shot.edit_recommendation.reason).foregroundStyle(Color.pixfunMuted).lineSpacing(3)
                if let technical = segment.assessments?.technical, !technical.metrics.isEmpty {
                    Divider().overlay(Color.pixfunLine)
                    Text("Sampled-frame measurements").font(.pixfun(12, semibold: true))
                    ForEach(technical.metrics) { metric in
                        HStack {
                            Text(LocalizedStringKey(metricLabel(metric.key))).foregroundStyle(Color.pixfunMuted)
                            Spacer()
                            Text(metric.value, format: .number.precision(.fractionLength(2))).monospacedDigit()
                            Text("· \(metric.samples) frames").foregroundStyle(Color.pixfunMuted)
                        }
                    }
                    Text("Window averages, not quality scores. Sharpness depends on resolution and scene content.")
                        .font(.pixfun(11)).foregroundStyle(Color.pixfunMuted).lineSpacing(3)
                } else {
                    Text("Technical measurements · Not evaluated").foregroundStyle(Color.pixfunMuted)
                }
                Text("Aesthetic quality · Not evaluated\nProject relevance · Not evaluated without a project brief")
                    .foregroundStyle(Color.pixfunMuted).lineSpacing(5)
                if let hit = store.visualMatch(item.id), hit.shotId == segment.id {
                    Text("Search similarity \(hit.similarity, specifier: "%.3f") · “\(store.query)”")
                    Text("Query-specific similarity, not confidence or quality.").font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
                }
            }.font(.pixfun(12)).textSelection(.enabled)
    }
    func metricLabel(_ key: String) -> String {
        switch key {
        case "sharp_all": return "Sharpness · raw"
        case "mean_L": return "Luminance · raw"
        case "clip_hi": return "Bright-pixel fraction · 0–1"
        case "clip_lo": return "Dark-pixel fraction · 0–1"
        default: return key
        }
    }
    @ViewBuilder func shotQuickFacts(_ shot: EditorialShot) -> some View {
        if !shot.shot_size.isEmpty { Text(LocalizedStringKey(shot.shot_size)).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted) }
        if !shot.camera_motion.isEmpty { Text(LocalizedStringKey(CameraMotionLabel.display(shot.camera_motion, chinese: store.language == .chinese))).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted) }
        if shot.edit_recommendation.recommended_duration_sec.isFinite, shot.edit_recommendation.recommended_duration_sec > 0 {
            Text("Suggested cut \(shot.edit_recommendation.recommended_duration_sec, specifier: "%.1f")s")
                .font(.pixfun(12)).foregroundStyle(Color.pixfunGold)
        }
    }
    var fullShotDescriptions: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text("Visual changes").font(.pixfun(13, semibold: true))
                ForEach(item.descriptionShots) { segment in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Button("\(timestamp(segment.start))–\(timestamp(segment.end))") { selectedSegment = segment.id; seek(segment.start) }
                                    .buttonStyle(.plain).font(.pixfun(12)).monospacedDigit().foregroundStyle(Color.pixfunGold)
                                    .accessibilityLabel("Play \(shotTitle(segment)) from \(timestamp(segment.start))")
                            }
                            Text(ShotReadingText.summary(segment.editorial?.description ?? segment.hoverDescription(analysisStatus: item.shotAnalysis?.status)))
                                .font(.pixfun(14)).lineSpacing(5).foregroundStyle(Color.pixfunMuted)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                }
            }.padding(.top, 8)
            .frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
    }
    var descriptionChanges: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Visual changes").font(.pixfun(13, semibold: true))
            ForEach(Array(item.descriptionMoments.enumerated()), id: \.offset) { index, moment in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1).").font(.pixfun(12)).monospacedDigit()
                        .foregroundStyle(Color.pixfunMuted).frame(width: 20, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 5) {
                        if let label = moment.label, !label.isEmpty {
                            Text(label).font(.pixfun(13, semibold: true)).foregroundStyle(Color.pixfunInk)
                        }
                        Text(moment.text).font(.pixfun(14)).foregroundStyle(Color.pixfunMuted).lineSpacing(5)
                    }.fixedSize(horizontal: false, vertical: true)
                }
            }
        }.padding(.top, 4).textSelection(.enabled)
            .frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
    }
    var editorialDescription: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalizedStringKey(item.kind == "video" ? "Video description" : "Description")).font(.pixfun(16, semibold: true))
                Spacer()
                if item.videoDescription?.busy == true {
                    analysisActivity(queued: item.videoDescription?.status == "queued")
                    Button(LocalizedStringKey(item.videoDescription?.status == "queued" ? "Cancel" : "Stop")) { store.stopDescription(item) }.buttonStyle(PixfunButtonStyle(kind: .quiet))
                } else if item.kind == "video" {
                    Button(LocalizedStringKey(item.videoDescription?.status == "ready" ? "Regenerate" : "Generate")) { store.describeVideo(item, force: true) }
                        .buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(item.missing == true)
                }
            }
            if let title = item.displayVideoDescription?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty, title != item.name {
                Text(title).font(.pixfun(15, semibold: true)).foregroundStyle(Color.pixfunInk)
                    .lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 680, alignment: .leading)
                    .accessibilityIdentifier("media.description.title")
            }
            if !item.descriptionParagraphs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(item.descriptionParagraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph).font(.pixfun(14)).foregroundStyle(Color.pixfunInk)
                            .lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: 680, alignment: .leading)
            } else if item.videoDescription?.busy != true {
                Text(LocalizedStringKey(item.kind == "video" ? "Video overview is not available yet." : "No description yet.")).font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
            }
            if !item.descriptionMoments.isEmpty { descriptionChanges }
            else if !item.descriptionShots.isEmpty { fullShotDescriptions }
            if let state = item.videoDescription, let message = state.message, !message.isEmpty {
                Text(LocalizedStringKey(state.status == "failed" ? "Couldn’t update the video description. Existing analysis is kept. Try again." : message))
                    .font(.pixfun(12)).foregroundStyle(state.status == "failed" ? Color.pixfunGold : Color.pixfunMuted)
                    .textSelection(.enabled)
            }
        }
    }
    @ViewBuilder var descriptionEvidence: some View {
        if let description = item.displayVideoDescription,
           description.shotRevision != nil || !(description.coverage ?? "").isEmpty
            || description.contentBlocks.contains(where: { $0.kind == .note })
            || !description.editingNotes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if item.kind == "video" { Divider().overlay(Color.pixfunLine) }
                Text("Description notes").font(.pixfun(12, semibold: true))
                if let revision = description.shotRevision {
                    Text(LocalizedStringKey(revision == item.shotAnalysis?.revision ? "Based on the reviewed shot sequence" : "Shot analysis has changed · Regenerate to update this description"))
                        .font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
                }
                if let coverage = description.coverage, !coverage.isEmpty {
                    Text(coverage).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                }
                ForEach(Array(description.contentBlocks.filter { $0.kind == .note }.enumerated()), id: \.offset) { _, note in
                    Text(note.text).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).lineSpacing(4)
                }
                if !description.editingNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Editing suggestions").font(.pixfun(12, semibold: true))
                        ForEach(Array(description.editingNotes.enumerated()), id: \.offset) { _, note in
                            Text(note.text).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                                .lineSpacing(4).textSelection(.enabled)
                        }
                    }
                }
            }.textSelection(.enabled)
        }
    }
    func analysisActivity(queued: Bool) -> some View {
        HStack(spacing: 8) {
            PixfunActivityIndicator(queued: queued, size: 20)
            if queued {
                Text("Waiting for local analysis")
            } else {
                Text("Analyzing locally")
            }
        }.font(.pixfun(12, semibold: true)).foregroundStyle(Color.pixfunGold)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.pixfunGold.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
    }
    @ViewBuilder var sourceFolderLink: some View {
        if let source {
            Button { store.openSourceFolder(item) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text((source.folder as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.middle)
                }.font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .help("Open folder in Finder\n\(source.folder)")
                .accessibilityLabel("Open source folder")
                .accessibilityValue(source.folder)
                .contextMenu {
                    Button("Copy path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(source.path, forType: .string)
                    }
                }
        }
    }
}
