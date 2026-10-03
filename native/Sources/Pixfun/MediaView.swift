import SwiftUI
import AVKit

struct MediaView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var knownMediaIDs: Set<String> = []
    func columns(_ count: Int) -> [[MediaSearchResult]] {
        var columns = Array(repeating: [MediaSearchResult](), count: count), heights = Array(repeating: 0.0, count: count)
        for result in store.mediaSearchResults {
            let shortest = heights.enumerated().min { $0.element < $1.element }!.offset
            columns[shortest].append(result); heights[shortest] += 1 / result.item.aspect + (result.hits.isEmpty ? 0.34 : 1.05) + (result.item.cardSummary == nil ? 0 : 0.16) + (result.item.searchTags.isEmpty ? 0 : 0.25)
        }
        return columns
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                PageHeading(title: "Media", subtitle: store.mediaResultSummary)
                Spacer()
                if store.importing {
                    ProgressView().controlSize(.small)
                    Text("Adding files…").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                }
                if store.selecting {
                    Button("Cancel", action: store.cancelSelection)
                    Button("Add \(store.selection.count) to brief", action: store.finishSelection).buttonStyle(PixfunButtonStyle(kind: .primary)).disabled(store.selection.isEmpty)
                } else {
                    Button("Select", action: store.beginSelection).buttonStyle(PixfunButtonStyle(kind: .quiet))
                    Button { store.pick(folder: true) } label: { Label("Add folder", systemImage: "folder.badge.plus") }
                    Button { store.pick() } label: { Label("Add files", systemImage: "plus") }.buttonStyle(PixfunButtonStyle(kind: .primary)).help("Reference local files without copying or uploading originals")
                }
            }.disabled(store.importing)
            HStack(spacing: 12) {
                HStack(spacing: 18) {
                    ForEach(MediaCategory.allCases, id: \.self) { category in
                        Button { store.category = category } label: {
                            Text(category.rawValue).font(.pixfun(13, semibold: store.category == category))
                                .foregroundStyle(store.category == category ? Color.pixfunGold : .pixfunMuted)
                                .frame(height: 36)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(store.category == category ? Color.pixfunGold : .clear).frame(height: 2)
                                }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityAddTraits(store.category == category ? [.isSelected] : [])
                    }
                }.fixedSize(horizontal: true, vertical: false).padding(.trailing, 8)
                Menu {
                    Button("All folders") { store.folder = "" }
                    Divider()
                    ForEach(store.folders) { folder in
                        Button { store.folder = folder.path } label: {
                            Text("\(folder.path) (\(folder.count))")
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                        Text(store.folder.isEmpty ? "All folders" : URL(fileURLWithPath: store.folder).lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium))
                    }.font(.pixfun(13)).foregroundStyle(Color.pixfunMuted).padding(.horizontal, 10).frame(height: 36)
                        .background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.pixfunLine))
                }.menuStyle(.borderlessButton).menuIndicator(.visible).tint(.pixfunMuted).frame(width: 152).accessibilityLabel("Filter by folder").help(store.folder.isEmpty ? "Filter by original folder, including subfolders" : store.folder)
                MediaSearchControls()
                Menu {
                    Picker("Sort by", selection: $store.sort) {
                        ForEach(MediaSort.allCases, id: \.self) { Text($0 == .original && store.isSearchingMedia ? "Best matches" : $0.rawValue).tag($0) }
                    }
                    if store.hasMediaFilters { Divider(); Button("Clear filters", action: store.resetMediaFilters) }
                    if store.items.contains(where: \.processing) {
                        Divider()
                        Button("Stop analysis") { store.perform { try await store.service.update("/api/desktop/stop", [:]); try await store.refresh() } }.disabled(store.importing)
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease").font(.system(size: 15)).foregroundStyle(Color.pixfunMuted)
                        .frame(width: 36, height: 36).background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.pixfunLine))
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).tint(.pixfunMuted).frame(width: 36).accessibilityLabel("Sort options").help("Sort results")
            }
            if let removed = store.removed {
                HStack { Text("Removed \(removed.name) from Media. Original kept.").font(.caption); Spacer(); Button("Undo", action: store.undoRemove) }
            }
            GeometryReader { proxy in
                let columns = columns(proxy.size.width > 1100 ? 4 : proxy.size.width > 730 ? 3 : 2)
                ScrollViewReader { scroll in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            if store.visibleItems.isEmpty {
                                EmptyWorkspace(symbol: "photo.on.rectangle.angled", title: store.items.isEmpty ? "Bring your footage" : "No matching footage", detail: store.items.isEmpty ? "Add local files or a folder. Originals stay in place; only the index and analysis cache are saved." : "Try fewer keywords or another search scope. Clips without saved analysis can still match their names and folders.")
                                    .frame(minHeight: 240)
                                if store.hasMediaFilters {
                                    HStack {
                                        if store.searchScope != .all { Button("Search everything") { store.searchScope = .all } }
                                        Button("Reset filters", action: store.resetMediaFilters)
                                    }.buttonStyle(PixfunButtonStyle()).frame(maxWidth: .infinity)
                                }
                            } else {
                                HStack(alignment: .top, spacing: 16) {
                                    ForEach(columns.indices, id: \.self) { index in
                                        LazyVStack(spacing: 16) { ForEach(columns[index]) { result in MediaCard(item: result.item, matches: result.hits).id(result.id) } }.frame(maxWidth: .infinity)
                                    }
                                }.padding(.bottom, 16)
                            }
                        }
                    }.onAppear {
                        knownMediaIDs = Set(store.items.map(\.id))
                        if let id = store.lastOpenedMediaID { scroll.scrollTo(id, anchor: .center) }
                    }.onChange(of: store.items.map(\.id)) { ids in
                        let current = Set(ids), added = current.subtracting(knownMediaIDs)
                        knownMediaIDs = current
                        // Surface imports without disturbing manual sorting or active searches.
                        if !added.isEmpty, store.sort == .original, !store.isSearchingMedia,
                           let first = store.mediaSearchResults.first, added.contains(first.id) {
                            scroll.scrollTo(first.id, anchor: .top)
                        }
                    }
                }
            }
        }.padding(32).navigationTitle("Media")

    }
}

struct MediaCard: View {
    @EnvironmentObject var store: WorkspaceStore
    let item: MediaItem
    var matches: [MediaSearchHit] = []
    @State private var hovered = false
    @State private var showTags = false
    @State private var showUsage = false
    var isSelected: Bool { store.selecting && store.selection.contains(item.id) }
    private var visibleTags: [MediaSearchTag] { Array(item.contentTags.prefix(3)) }
    private var additionalTagCount: Int { max(0, item.searchTags.count - visibleTags.count) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if store.selecting { store.toggleSelection(item.id) } else { store.openMedia(item) }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    ServiceImage(path: item.cover).aspectRatio(item.aspect, contentMode: .fit)
                        .overlay(alignment: .bottomLeading) {
                            if let status = item.processingLabel {
                                HStack(spacing: 7) {
                                    PixfunActivityIndicator(queued: status == "Queued…", size: 18, tint: .pixfunBackground)
                                    Text(status).font(.pixfun(12, semibold: true))
                                }.foregroundStyle(Color.pixfunBackground).padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(Color.pixfunGold, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.25)))
                                    .padding(8).allowsHitTesting(false).accessibilityLabel(status)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if item.isExample == true {
                                Text("Sample").font(.pixfun(11, semibold: true))
                                    .foregroundStyle(Color.pixfunBackground)
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(Color.pixfunGold, in: Capsule())
                                    .padding(10).allowsHitTesting(false)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if item.kind == "video", let seconds = item.metadata?.duration, seconds > 0 {
                                Text(timestamp(seconds)).font(.caption.monospacedDigit()).padding(5).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 5)).padding(8)
                            }
                        }
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.name).font(.pixfun(15, semibold: true)).lineLimit(2)
                        if matches.isEmpty, let summary = item.cardSummary {
                            Text(summary).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).lineLimit(2).help(summary)
                        }
                        if let location = item.context?["location"], !location.isEmpty { Label(location, systemImage: "mappin.and.ellipse").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).lineLimit(1) }
                        if let device = item.context?["device"], !device.isEmpty { Text(device).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).lineLimit(1) }
                        if item.status != "ready" && !item.processing { Text(item.missing == true ? "Original missing" : item.status.capitalized).font(.pixfun(12)).foregroundStyle(item.status == "error" ? Color.orange : .pixfunMuted) }
                        if !matches.isEmpty {
                            ForEach(Array(matches.prefix(2))) { hit in MediaSearchEvidence(hit: hit, query: store.query).padding(.top, 4) }
                            if matches.count > 2 { Text("+\(matches.count - 2) more matching entries").font(.pixfun(11)).foregroundStyle(Color.pixfunMuted) }
                        }
                    }.padding(13)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("\(store.selecting ? (isSelected ? "Deselect" : "Select") : "Open") \(item.name)\(item.isExample == true ? " · Sample" : "")\(item.processingLabel.map { " · \($0)" } ?? "")")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            if !item.searchTags.isEmpty {
                MediaTagFlow {
                    ForEach(visibleTags) { tag in tagButton(tag) }
                    if additionalTagCount > 0 {
                        Button(visibleTags.isEmpty ? "Tags" : "+\(additionalTagCount)") { showTags = true }
                            .font(.pixfun(11)).buttonStyle(.plain).padding(6)
                            .accessibilityLabel("Show all searchable tags")
                            .popover(isPresented: $showTags) {
                                MediaTagFlow { ForEach(item.searchTags) { tag in tagButton(tag) } }
                                    .padding(14).frame(width: 300)
                            }
                    }
                }.padding(.horizontal, 13).padding(.bottom, 12)
            }
            if !store.selecting, let usage = store.usedShots(item.id) {
                let used = usage.shots.filter { $0.mediaId == item.id }
                Button { showUsage = true } label: {
                    Label("\(usage.draft ? "Draft" : "Used") · \(used.count) clip\(used.count == 1 ? "" : "s")", systemImage: "scissors")
                        .font(.pixfun(11)).foregroundStyle(Color.pixfunGold)
                }.buttonStyle(.plain).padding(.horizontal, 13).padding(.bottom, 12)
                    .help("Used in the current project's edit")
                    .popover(isPresented: $showUsage) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(store.projects.first { $0.id == usage.run.projectId }?.title ?? "Current edit").font(.pixfun(13, semibold: true)).lineLimit(2)
                            ForEach(used) { shot in
                                Button {
                                    showUsage = false; store.openUsedShot(shot.id, projectID: usage.run.projectId)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        let position = StoryTimeline.offset(shot.id, in: usage.shots)
                                        Text("Cut \(StoryTimeline.timecode(position))–\(StoryTimeline.timecode(position + shot.end - shot.start))")
                                        Text(item.kind == "image" ? String(format: "Photo · %.2fs", shot.end) : "Source \(StoryTimeline.timecode(shot.start))–\(StoryTimeline.timecode(shot.end))")
                                            .foregroundStyle(Color.pixfunMuted)
                                    }.font(.pixfun(12)).monospacedDigit().padding(6)
                                }.buttonStyle(.plain).help("Locate this clip in the story")
                            }
                        }.padding(16).frame(width: 290)
                    }
            }
            if !store.selecting, let hit = matches.first(where: { $0.start != nil }), let seconds = hit.start {
                Button { store.openMedia(item, at: seconds) } label: {
                    Label("View match · \(timestamp(seconds))", systemImage: "play.circle")
                        .font(.pixfun(12)).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(PixfunButtonStyle(kind: .quiet)).foregroundStyle(Color.pixfunGold)
                    .padding(.horizontal, 5).padding(.bottom, 8)
                    .accessibilityLabel("Open matching moment at \(timestamp(seconds)) in \(item.name)")
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
            Button("Add to brief") { store.attach([item.id]) }
            Button("Show in Finder") { store.reveal(item) }
            Button(item.favorite == true ? "Remove favorite" : "Favorite") { store.favorite(item) }
            if item.missing == true { Button("Locate original…") { store.pick(locate: item.id) } }
            if item.status == "error" || item.status == "cancelled" { Button("Retry analysis") { store.retry(item) } }
            Divider()
            Button("Remove from Media", role: .destructive) { store.remove(item) }.disabled(item.processing)
        }
    }
    func tagButton(_ tag: MediaSearchTag) -> some View {
        Button {
            if store.selecting { store.toggleSelection(item.id) }
            else { showTags = false; store.searchScope = tag.scope; store.query = tag.text }
        } label: {
            Label(tag.text, systemImage: tag.symbol).font(.pixfun(11)).lineLimit(1)
                .padding(.horizontal, 7).padding(.vertical, 5)
                .background(Color.pixfunRaised, in: Capsule())
        }.buttonStyle(.plain).foregroundStyle(Color.pixfunMuted)
            .help(store.selecting ? "Select this material" : "Search \(tag.scope.rawValue): \(tag.text)")
            .accessibilityLabel(store.selecting ? "Select \(item.name)" : "Search for \(tag.text)")
    }
}

/// Intrinsic-width chips wrap without adding a horizontal scrollbar to each card.
struct MediaTagFlow: Layout {
    func positions(_ subviews: Subviews, width: CGFloat) -> ([CGPoint], CGSize) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += row + 6; row = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + 6; row = max(row, size.height)
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
    @State private var subtitleSearch = ""
    var item: MediaItem { store.items.first { $0.id == initialItem.id } ?? initialItem }
    var source: MediaLocation? { store.locations[item.id] }
    var matchingCues: [(offset: Int, element: Cue)] { Array(item.transcriptCues.enumerated()).filter { subtitleSearch.isEmpty || $0.element.text.localizedCaseInsensitiveContains(subtitleSearch) } }
    func seek(_ seconds: Double) { playback.player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button(action: store.backToMedia) { Label(store.mediaBackTitle, systemImage: "chevron.left") }.buttonStyle(PixfunButtonStyle(kind: .quiet)).keyboardShortcut("[", modifiers: .command).accessibilityLabel("Back to \(store.mediaBackTitle)")
                Text(item.name).font(.pixfun(20, semibold: true)).lineLimit(2).help(item.name)
                Spacer()
                Button { store.favorite(item) } label: { Image(systemName: item.favorite == true ? "star.fill" : "star") }.help("Favorite")
                Button("Add to brief") { store.attach([item.id]) }.buttonStyle(PixfunButtonStyle(kind: .primary))
            }.padding(22)
            Rectangle().fill(Color.pixfunLine).frame(height: 1)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            Group {
                                if item.kind == "image", let photo { Image(nsImage: photo).resizable().scaledToFit() }
                                else if let player = playback.player { NativeVideoPlayer(player: player) }
                                else { ZStack { Color.black; if let playerError { Text(playerError).foregroundStyle(.secondary).padding() } else { ProgressView() } } }
                            }.frame(maxWidth: .infinity).frame(height: 310).background(.black).clipShape(RoundedRectangle(cornerRadius: 10))
                            if let error = playback.error {
                                HStack { Text(error).font(.caption).foregroundStyle(.orange); Button("Retry playback") { playback.retry() } }
                            }
                            if item.missing == true { Button("Locate original…") { store.pick(locate: item.id) } }
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Original").font(.pixfun(16, semibold: true))
                            info("Duration", timestamp(item.metadata?.duration ?? 0))
                            if let width = item.metadata?.width, let height = item.metadata?.height { info("Resolution", "\(Int(width)) × \(Int(height))") }
                            if let size = item.file.size { info("Size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
                            info("Audio", item.metadata?.hasAudio == true ? "Included" : "None")
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
                            if item.status == "error" || item.status == "cancelled" { Button("Retry analysis") { store.retry(item) } }
                        }.frame(width: 190, alignment: .leading)
                    }
                    if let error = item.error { Text(error).font(.callout).foregroundStyle(.orange) }
                    MediaDetailSearchMatches(item: item) { seconds in
                        selectedSegment = item.segments.first { $0.start <= seconds && seconds < $0.end }?.id
                        seek(seconds)
                    }
                    if item.kind == "video" { shotBrowser }
                    editorialDescription
                    if let location = item.context?["location"], !location.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Location").font(.pixfun(16, semibold: true))
                            Text(location).font(.pixfun(14)).foregroundStyle(Color.pixfunMuted).textSelection(.enabled)
                        }
                    }
                    if !item.transcriptCues.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Transcript").font(.pixfun(16, semibold: true))
                            Text("\(item.transcriptCues.count) entries").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                            Spacer()
                            PixfunSearchField(placeholder: "Find in transcript", text: $subtitleSearch).frame(width: 230)
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
                }.padding(24)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.pixfunBackground)
            .navigationTitle("Media")
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
                        playback.open(url, at: store.mediaSeekTime)
                        store.mediaSeekTime = 0
                        // Opening a search result is navigation, not permission to start new model work.
                        if item.kind == "video" && !store.isSearchingMedia { store.describeVideo(item); store.analyzeShots(item) }
                    }
                } catch { playerError = error.localizedDescription }
            }.onDisappear { playback.stop() }
    }
    func info(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(name).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted); Text(value).font(.pixfun(14)) }
    }
    var shotBrowser: some View {
        VStack(alignment: .leading, spacing: 14) {
            shotAnalysisStatus
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
                ForEach(item.segments) { segment in
                    shotCard(segment)
                }
            }
            if let segment = item.segments.first(where: { $0.id == selectedSegment }) ?? item.segments.first {
                if let shot = segment.editorial { shotDetails(shot, segment: segment) }
                else { HStack { Text(segment.label).fontWeight(.medium); Text(segment.splitReason).foregroundStyle(.secondary) }.font(.callout) }
            }
        }
    }
    func shotCard(_ segment: Segment) -> some View {
        let selected = (item.segments.first(where: { $0.id == selectedSegment }) ?? item.segments.first)?.id == segment.id
        let highlighted = segment.editorial?.isHighlight == true
        return Button { selectedSegment = segment.id; seek(segment.start) } label: {
            VStack(alignment: .leading, spacing: 7) {
                ServiceImage(path: segment.thumbnailUrl, fit: .fit).aspectRatio(16 / 9, contentMode: .fit)
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
                Text(segment.label).font(.pixfun(13, semibold: true)).lineLimit(2).padding(.horizontal, 8)
                if let shot = segment.editorial {
                    Text("\(shot.edit_recommendation.level) · \(shot.edit_recommendation.recommended_duration_sec, specifier: "%.1f")s")
                        .font(.pixfun(12)).foregroundStyle(Color.pixfunGold).padding(.horizontal, 8)
                }
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
                Text(item.shotAnalysis?.segments == nil ? "Browse video" : "Editable shots").font(.pixfun(16, semibold: true))
                Text("\(item.segments.count)").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                Spacer()
                if item.shotAnalysis?.busy == true {
                    analysisActivity(queued: item.shotAnalysis?.status == "queued")
                    Button(item.shotAnalysis?.status == "queued" ? "Cancel" : "Stop") { store.stopShots(item) }.buttonStyle(PixfunButtonStyle(kind: .quiet))
                } else {
                    Button(item.shotAnalysis?.segments == nil ? "Analyze shots" : "Reanalyze") { store.analyzeShots(item, force: true) }
                        .buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(item.missing == true)
                }
            }
            if let state = item.shotAnalysis, let message = state.message, !message.isEmpty {
                Text(message).font(.pixfun(12)).foregroundStyle(state.status == "failed" ? Color.orange : Color.pixfunMuted)
            }
        }
    }
    func shotDetails(_ shot: EditorialShot, segment: Segment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shot.description).font(.pixfun(14)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Text((shot.story_role + [shot.shot_size, shot.capture_type, shot.camera_motion]).filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
            HStack {
                Text("\(shot.edit_recommendation.level) · \(shot.edit_recommendation.recommended_duration_sec, specifier: "%.1f")s suggested")
                Spacer()
                Text("Editing value \(Int(shot.importance_score))/100")
            }.font(.pixfun(13)).foregroundStyle(Color.pixfunGold)
            Text(shot.edit_recommendation.reason).font(.pixfun(13)).textSelection(.enabled)
            if !shot.reaction.isEmpty { info("Reaction", shot.reaction) }
            if !shot.dialogue.isEmpty { info("Dialogue · verify transcript", shot.dialogue) }
            if !shot.audio.isEmpty { info("Sound evidence", shot.audio.joined(separator: " · ")) }
            if shot.duplicate_candidate || shot.unusable_candidate {
                Text(shot.duplicate_candidate ? "Possible repeated content · review before removing" : "Potentially unusable · review original").font(.pixfun(12)).foregroundStyle(Color.orange)
            }
            Text(segment.note ?? segment.splitReason).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
            Text("Sampled visual analysis · environmental sounds not classified").font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
        }
    }
    var editorialDescription: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.kind == "video" ? "Video description" : "Description").font(.pixfun(16, semibold: true))
                Spacer()
                if item.videoDescription?.busy == true {
                    analysisActivity(queued: item.videoDescription?.status == "queued")
                    Button(item.videoDescription?.status == "queued" ? "Cancel" : "Stop") { store.stopDescription(item) }.buttonStyle(PixfunButtonStyle(kind: .quiet))
                } else if item.kind == "video" {
                    Button(item.videoDescription?.status == "ready" ? "Regenerate" : "Generate") { store.describeVideo(item, force: true) }
                        .buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(item.missing == true)
                }
            }
            if let description = item.displayVideoDescription?.full_description, !description.isEmpty {
                Text(description).font(.pixfun(14)).foregroundStyle(Color.pixfunInk).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(item.displayVideoDescription?.coverage ?? "Generated from local video evidence")
            } else if item.kind != "video", let description = item.description, !description.isEmpty {
                Text(description).foregroundStyle(Color.pixfunMuted).textSelection(.enabled)
            } else if item.videoDescription?.busy != true {
                Text("No full description yet.").font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
            }
            if let state = item.videoDescription, let message = state.message, !message.isEmpty {
                Text(message).font(.pixfun(12)).foregroundStyle(state.status == "failed" ? Color.orange : Color.pixfunMuted)
                    .textSelection(.enabled)
            }
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

@MainActor
final class PlaybackController: ObservableObject {
    @Published var player: AVPlayer?
    @Published var error: String?
    private var observation: NSKeyValueObservation?
    private var timeout: Task<Void, Never>?
    private var source: URL?
    func open(_ url: URL, at seconds: Double = 0) {
        stop(); source = url; error = nil
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let owner = self else { return }
            Task { @MainActor in
                guard owner.player?.currentItem === item else { return }
                if item.status == .readyToPlay {
                    owner.timeout?.cancel(); owner.error = nil
                    if seconds > 0 { owner.player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
                }
                if item.status == .failed {
                    owner.timeout?.cancel()
                    owner.error = "Cannot play this file with the system codecs. Open the original in Finder or convert to H.264 / HEVC."
                }
            }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            guard let self, self.player?.currentItem === item, item.status == .unknown else { return }
            self.error = "Playback is taking too long. Check that the original is available on this Mac."
        }
    }
    func retry() { if let source { open(source) } }
    func stop() { timeout?.cancel(); timeout = nil; observation = nil; player?.pause(); player = nil }
}

// Direct AVKit/AppKit integration also guarantees AVPlayerView is linked into
// the executable; no SwiftUI VideoPlayer runtime wrapper or web player is used.
struct NativeVideoPlayer: NSViewRepresentable {
    var player: AVPlayer
    var showsControls = true
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = showsControls ? .inline : .none
        view.allowsVideoFrameAnalysis = false
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
        view.controlsStyle = showsControls ? .inline : .none
    }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player?.pause(); view.player = nil }
}
