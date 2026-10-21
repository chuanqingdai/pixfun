import SwiftUI

/// Only current work and actionable problems appear here; no persistent run history.
struct MediaLibraryActivityView: View {
    @EnvironmentObject var store: WorkspaceStore
    private var materials: [MediaItem] { store.libraryItems }
    private var analyzing: Int { materials.filter { $0.processingLabel != nil }.count }
    private var attention: Int { materials.filter { MediaWorkFilter.attention.includes($0) }.count }
    private var failed: Int {
        materials.filter { item in
            item.attentionReason != nil && item.missing != true && !item.processing &&
                [item.status, item.mediaAnalysis?.status, item.shotAnalysis?.status, item.videoDescription?.status]
                    .contains { ["failed", "error"].contains($0 ?? "") }
        }.count
    }
    private var waiting: Int { materials.filter { $0.processingLabel == "Queued…" }.count }
    private var retrying: Int { materials.filter { $0.processingLabel == "Waiting to retry…" }.count }
    private var transfers: [SyncDevice] { store.syncSnapshot?.devices.filter { $0.busy || $0.checking } ?? [] }
    private var syncIssue: Bool {
        store.syncStatusUnavailable || store.syncSnapshot?.archiveError != nil ||
        store.syncSnapshot?.devices.contains { $0.status == "Needs Attention" || $0.status == "Offline" && $0.pending > 0 } == true
    }
    var body: some View {
        if !transfers.isEmpty || analyzing > 0 || attention > 0 || syncIssue || store.syncSnapshot?.archiving == true {
            HStack(alignment: .center, spacing: 12) {
                Group {
                    if !transfers.isEmpty || analyzing > 0 || store.syncSnapshot?.archiving == true {
                        ProgressView().controlSize(.small).tint(Color.pixfunGold).frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.pixfunGold)
                    }
                }.frame(width: 24, height: 24)
                    .background(Color.pixfunGold.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                Text(statusLine).font(.pixfun(15, semibold: true)).foregroundStyle(Color.pixfunInk)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).help(detail)
                Spacer(minLength: 8)
                if materials.contains(where: { $0.mediaAnalysis?.status == "failed" && $0.missing != true && !$0.processing }) {
                    Button { store.retryFailedAnalysis() } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }.buttonStyle(PixfunButtonStyle(kind: .primary)).fixedSize()
                        .accessibilityLabel("Retry failed analyses")
                        .help("Retry incomplete analysis only. Completed results are kept.")
                }
            }.padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(Color.pixfunBrandSoft.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.pixfunGold.opacity(0.24)))
                .accessibilityElement(children: .contain)
        }
    }
    private var statusLine: String {
        let chinese = store.language == .chinese
        var parts: [String] = []
        if let first = transfers.first {
            let extra = transfers.count > 1 ? " +\(transfers.count - 1)" : ""
            parts.append(chinese ? "同步中 \(first.name)\(extra) \(first.processed)/\(first.total)"
                         : "\(first.phaseTitle) \(first.name)\(extra) \(first.processed)/\(first.total)")
        }
        // Processing includes running, queued and automatic-retry work; it is
        // not a count of simultaneous model processes.
        if analyzing > 0 { parts.append(chinese ? "处理中 \(analyzing)" : "Processing \(analyzing)") }
        if failed > 0 { parts.append(chinese ? "失败 \(failed)" : "Failed \(failed)") }
        let otherAttention = max(0, attention - failed)
        if otherAttention > 0 { parts.append(chinese ? "需检查 \(otherAttention)" : "Needs attention \(otherAttention)") }
        if syncIssue {
            parts.append(chinese ? "同步异常" : store.syncStatusUnavailable ? "Sync unavailable" : "Sync needs attention")
        }
        if store.syncSnapshot?.archiving == true { parts.append(chinese ? "备份中" : "Backing up") }
        return parts.joined(separator: " · ")
    }
    private var detail: String {
        let running = max(0, analyzing - waiting - retrying)
        let progress = analyzing > 0
            ? (store.language == .chinese
               ? "正在分析 \(running) 个，排队 \(waiting) 个，等待自动重试 \(retrying) 个。\n"
               : "\(running) running, \(waiting) queued, \(retrying) waiting for automatic retry.\n")
            : ""
        if attention > 0 {
            let files = materials.compactMap { item in
                item.attentionReason.map { item.name + " · " + $0.summary(count: 1, chinese: store.language == .chinese) }
            }.joined(separator: "\n")
            let note = store.language == .chinese
                ? "已完成的标签和描述仍可查看，可重试未完成的分析。"
                : "Completed tags and descriptions remain available. You can retry incomplete analysis."
            return progress + note + "\n" + files
        }
        if store.language == .chinese {
            if analyzing > 0 { return progress + "可以先浏览素材，分析完成后将更新标签和内容搜索。" }
            return "已导入的素材可正常使用，详情请查看同步任务。"
        }
        if let first = transfers.first {
            let saved = first.total > 0 ? "\(first.processed)/\(first.total) ready. " : ""
            return saved + (analyzing > 0 ? "\(analyzing) files being analyzed. Ready files are already available." : "Verified files appear here as they arrive.")
        }
        if analyzing > 0 { return progress + "Browse now. Content search and filters update as analysis finishes." }
        if syncIssue { return "Open Media Sync for the current issue. Existing library items remain available." }
        return "Your working copies are available while the backup continues."
    }
}

struct MediaLibraryWelcomeView: View {
    @EnvironmentObject var store: WorkspaceStore
    private var source: SyncDevice? { store.syncSnapshot?.devices.first { $0.busy || $0.checking || $0.needsAttention } ?? store.syncSnapshot?.devices.first }
    private var isFirstVisit: Bool { source == nil && !store.importing && !store.syncStatusUnavailable }
    var body: some View {
        VStack(spacing: 0) {
            if isFirstVisit {
                LibraryWelcomeArtwork()
                    .frame(maxWidth: 1080)
                    .padding(.bottom, 20)
                Text("Turn your photos and videos\ninto searchable memories.")
                    .font(.pixfun(34, semibold: true)).lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 720)
                    .padding(.bottom, 22)
            } else {
                VStack(spacing: 16) {
                    if source?.busy == true || source?.checking == true || store.importing {
                        ProgressView().controlSize(.regular)
                    } else {
                        Image(systemName: "photo.stack").font(.system(size: 32, weight: .light)).foregroundStyle(Color.pixfunGold)
                    }
                    Text(LocalizedStringKey(title)).font(.pixfun(28, semibold: true))
                    Text(detail).font(.pixfun(14)).foregroundStyle(Color.pixfunMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 20).padding(.bottom, 4)
            }
            VStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { manualImportButton; syncButton }
                    VStack(spacing: 12) { manualImportButton; syncButton }
                }
                if !isFirstVisit {
                    Text("Imported files appear here as they arrive.")
                        .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                }
            }
            .frame(maxWidth: 720)
            if isFirstVisit { LibraryWelcomeWorkflow().padding(.top, 28) }
        }.multilineTextAlignment(.center).padding(.horizontal, 24).padding(.vertical, 30)
            .padding(.top, isFirstVisit ? 4 : 0)
            .frame(maxWidth: 1120).frame(maxWidth: .infinity, alignment: .center)
    }
    private var manualImportButton: some View {
        Button { store.pick() } label: {
            Text("Import photos & videos")
                .font(.pixfun(15, semibold: true))
                .padding(.horizontal, 20).frame(minHeight: 48)
                .fixedSize(horizontal: true, vertical: false)
        }.buttonStyle(PixfunButtonStyle(kind: .primary))
            .disabled(store.importing)
            .help("Choose local photos and videos to add to your library")
            .accessibilityHint("Manually select local files. Your originals stay in place.")
    }
    private var syncButton: some View {
        Button { store.navigate(.mediaSync) } label: {
            Text(LocalizedStringKey(isFirstVisit ? "Set up sync" : "View Media Sync"))
                .font(.pixfun(14))
                .padding(.horizontal, 16).frame(minHeight: 48)
                .fixedSize(horizontal: true, vertical: false)
        }.buttonStyle(PixfunButtonStyle(kind: .secondary))
            .accessibilityHint("Go to Media Sync to connect a device or set up folder sync")
    }
    private var title: String {
        if store.syncStatusUnavailable { return "Your library is empty" }
        if store.importing { return "Adding your first files" }
        if let source { return source.busy || source.checking ? "Your first import is on its way" : source.needsAttention ? "Your source needs attention" : "Waiting for your first import" }
        return "Start with your first sync"
    }
    private var detail: String {
        if store.syncStatusUnavailable { return "Sync status is unavailable. Open Media Sync to check your connection." }
        if store.importing { return "Files will appear as soon as they are added. You can browse while analysis continues." }
        if let source { return source.name + " · " + source.phaseMessage }
        return "Choose a phone, card or folder in Media Sync, then choose where to save its copies."
    }
}

/// The approved promotional artwork is decorative. Copy and actions remain
/// native below it so they stay localized, selectable and accessible.
struct LibraryWelcomeArtwork: View {
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "welcome-reference", withExtension: "png", subdirectory: "Welcome"),
              let original = NSImage(contentsOf: url),
              let bitmap = original.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let illustration = bitmap.cropping(to: CGRect(x: 0, y: 0, width: bitmap.width,
                  height: Int(Double(bitmap.height) * 450.0 / 1058.0))) else { return nil }
        return NSImage(cgImage: illustration, size: NSSize(width: illustration.width, height: illustration.height))
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                .accessibilityHidden(true)
        }
    }
}

/// A static explanation, not fake media or a second set of navigation controls.
private struct LibraryWelcomeWorkflow: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 48) {
                step(0).frame(width: 248)
                step(1).frame(width: 248)
                step(2).frame(width: 248)
            }
            HStack(alignment: .top, spacing: 28) {
                step(0).frame(width: 190)
                step(1).frame(width: 190)
                step(2).frame(width: 190)
            }
            VStack(spacing: 30) {
                step(0).frame(maxWidth: 320, alignment: .leading)
                step(1).frame(maxWidth: 320, alignment: .leading)
                step(2).frame(maxWidth: 320, alignment: .leading)
            }.frame(maxWidth: .infinity)
        }
        .padding(.top, 28).padding(.bottom, 20).frame(maxWidth: 940)
        .overlay(alignment: .top) { Rectangle().fill(Color.pixfunLine).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    private func step(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if index == 0 {
                    HStack(spacing: 7) {
                        Image(systemName: "iphone").frame(width: 26, height: 28)
                        Image(systemName: "camera").frame(width: 26, height: 28)
                        SyncDroneIcon().frame(width: 26, height: 26)
                        Image(systemName: "sdcard").frame(width: 26, height: 28)
                        Image(systemName: "externaldrive").frame(width: 26, height: 28)
                    }.font(.system(size: 24, weight: .light))
                } else if index == 1 {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 32, weight: .light))
                } else {
                    Image(systemName: "magnifyingglass").font(.system(size: 32, weight: .light))
                }
            }.foregroundStyle(Color.pixfunGold).frame(height: 52).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 9) {
                Text(["Bring your media", "Auto-sync new files", "Find the moment"][index])
                    .font(.pixfun(15, semibold: true)).foregroundStyle(Color.pixfunInk)
                Text(["Scan with your phone, or connect a memory card or drive.", "Automatically import new media from cards and folders you set up.", "Describe a scene or enter dialogue to find matching media and moments."][index])
                    .font(.pixfun(13)).fontWeight(.regular).lineSpacing(5).foregroundStyle(Color.pixfunMuted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }
}
