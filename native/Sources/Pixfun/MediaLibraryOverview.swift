import SwiftUI

/// Only current work and actionable problems appear here; no persistent run history.
struct MediaLibraryActivityView: View {
    @EnvironmentObject var store: WorkspaceStore
    private var materials: [MediaItem] { store.libraryItems }
    private var analyzing: Int { materials.filter { $0.processingLabel != nil }.count }
    private var attention: Int { materials.filter { MediaWorkFilter.attention.includes($0) }.count }
    private var attentionSummaries: [String] {
        MediaAttentionReason.allCases.compactMap { reason in
            let count = materials.filter { $0.attentionReason == reason }.count
            return count > 0 ? reason.summary(count: count, chinese: store.language == .chinese) : nil
        }
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
            HStack(alignment: .center, spacing: 10) {
                if !transfers.isEmpty || analyzing > 0 || store.syncSnapshot?.archiving == true {
                    ProgressView().controlSize(.small).tint(Color.pixfunGold).frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }
                Text(statusLine).font(.pixfun(14, semibold: true)).foregroundStyle(Color.pixfunInk)
                    .lineLimit(1).truncationMode(.tail).help(detail)
                if materials.contains(where: { $0.mediaAnalysis?.status == "failed" && $0.missing != true && !$0.processing }) {
                    Button("Retry failed analyses") { store.retryFailedAnalysis() }
                        .buttonStyle(.borderless).font(.pixfun(12)).tint(.pixfunGold)
                }
            }.frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .accessibilityElement(children: .contain)
        }
    }
    private var statusLine: String {
        if store.language == .chinese {
            var parts: [String] = []
            if let first = transfers.first { parts.append("同步中 · \(first.name) · \(first.processed)/\(first.total)") }
            let running = max(0, analyzing - waiting - retrying)
            if running > 0 { parts.append("正在分析 \(running) 个素材") }
            if waiting > 0 { parts.append("\(waiting) 个排队中") }
            if retrying > 0 { parts.append("\(retrying) 个等待重试") }
            parts.append(contentsOf: attentionSummaries)
            if syncIssue { parts.append("同步异常") }
            if store.syncSnapshot?.archiving == true { parts.append("正在备份") }
            return parts.joined(separator: " · ")
        }
        var parts = [headline]
        if waiting > 0 { parts.append("\(waiting) queued") }
        if retrying > 0 { parts.append("\(retrying) waiting to retry") }
        if !transfers.isEmpty, let first = transfers.first, first.total > 0 {
            parts.append("\(first.processed)/\(first.total) ready")
        }
        if !transfers.isEmpty, analyzing > 0 { parts.append("\(analyzing) analyzing") }
        if attention > 0, !transfers.isEmpty || analyzing > 0 || syncIssue { parts.append(contentsOf: attentionSummaries) }
        return parts.joined(separator: " · ")
    }
    private var headline: String {
        if let first = transfers.first {
            let extra = transfers.count > 1 ? " + \(transfers.count - 1) sources" : ""
            return "\(first.phaseTitle) · \(first.name)\(extra)"
        }
        if analyzing > 0 { return "Analyzing \(analyzing) \(analyzing == 1 ? "file" : "files")" }
        if syncIssue { return store.syncStatusUnavailable ? "Sync status unavailable" : "Sync needs attention" }
        if attention > 0 { return attentionSummaries.joined(separator: " · ") }
        return "Backing up verified copies"
    }
    private var detail: String {
        if attention > 0 {
            let files = materials.compactMap { item in
                item.attentionReason.map { item.name + " · " + $0.summary(count: 1, chinese: store.language == .chinese) }
            }.joined(separator: "\n")
            let note = store.language == .chinese
                ? "已完成的标签和描述仍可查看，可重试未完成的分析。"
                : "Completed tags and descriptions remain available. You can retry incomplete analysis."
            return note + "\n" + files
        }
        if store.language == .chinese {
            if analyzing > 0 { return "可以先浏览素材，分析完成后将更新标签和内容搜索。" }
            return "已导入的素材可正常使用，详情请查看同步任务。"
        }
        if let first = transfers.first {
            let saved = first.total > 0 ? "\(first.processed)/\(first.total) ready. " : ""
            return saved + (analyzing > 0 ? "\(analyzing) files being analyzed. Ready files are already available." : "Verified files appear here as they arrive.")
        }
        if analyzing > 0 { return "Browse now. Content search and filters update as analysis finishes." + (attention > 0 ? " \(attention) files need attention." : "") }
        if syncIssue { return "Open Media Sync for the current issue. Existing library items remain available." }
        return "Your working copies are available while the backup continues."
    }
}

struct MediaLibraryWelcomeView: View {
    @EnvironmentObject var store: WorkspaceStore
    private var source: SyncDevice? { store.syncSnapshot?.devices.first { $0.busy || $0.checking || $0.needsAttention } ?? store.syncSnapshot?.devices.first }
    private var isFirstVisit: Bool { source == nil && !store.importing && !store.syncStatusUnavailable }
    var body: some View {
        VStack(spacing: 28) {
            if isFirstVisit {
                VStack(spacing: 16) {
                    Text("Turn your photos and videos\ninto searchable memories.")
                        .font(.pixfun(38, semibold: true)).lineSpacing(2)
                    Text("Bring your media together. Let local AI help you\nfind the moments you remember.")
                        .font(.pixfun(16)).lineSpacing(5).foregroundStyle(Color.pixfunMuted)
                }.fixedSize(horizontal: false, vertical: true)
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
                }.padding(.vertical, 20)
            }
            VStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { manualImportButton; syncButton }
                    VStack(spacing: 12) { manualImportButton; syncButton }
                }
                if !isFirstVisit {
                    Text("Imported files appear here as they arrive.")
                        .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                }
                Label("Your storage. Your originals, untouched.", systemImage: "checkmark.shield")
                    .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
            }
            if isFirstVisit { LibraryWelcomeWorkflow().padding(.top, 16) }
        }.multilineTextAlignment(.center).padding(.horizontal, 24).padding(.vertical, 28)
            .padding(.top, isFirstVisit ? 48 : 0)
            .frame(maxWidth: 880).frame(maxWidth: .infinity, alignment: .center)
    }
    private var manualImportButton: some View {
        Button { store.pick() } label: {
            Text("Import photos & videos")
                .font(.pixfun(16, semibold: true))
                .padding(.horizontal, 24).frame(minHeight: 56)
                .fixedSize(horizontal: true, vertical: false)
        }.buttonStyle(PixfunButtonStyle(kind: .primary))
            .disabled(store.importing)
            .help("Choose local photos and videos to add to your library")
            .accessibilityHint("Manually select local files. Your originals stay in place.")
    }
    private var syncButton: some View {
        Button { store.navigate(.mediaSync) } label: {
            Text(LocalizedStringKey(isFirstVisit ? "Set up sync" : "View Media Sync"))
                .font(.pixfun(16, semibold: true))
                .padding(.horizontal, 16).frame(minHeight: 56)
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

/// A static explanation, not fake media or a second set of navigation controls.
private struct LibraryWelcomeWorkflow: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 40) {
                step(0).frame(width: 220)
                step(1).frame(width: 220)
                step(2).frame(width: 220)
            }
            HStack(alignment: .top, spacing: 24) {
                step(0).frame(width: 180)
                step(1).frame(width: 180)
                step(2).frame(width: 180)
            }
            VStack(spacing: 32) {
                step(0)
                step(1)
                step(2)
            }.frame(maxWidth: .infinity)
        }
        .padding(.vertical, 28).frame(maxWidth: .infinity)
        .overlay(alignment: .top) { Rectangle().fill(Color.pixfunLine).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    private func step(_ index: Int) -> some View {
        VStack(spacing: 14) {
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
            VStack(spacing: 8) {
                Text(["Bring your media", "Auto-sync new files", "Find the moment"][index])
                    .font(.pixfun(15, semibold: true)).foregroundStyle(Color.pixfunInk)
                Text(["Scan with your phone\nor connect a card or drive.", "From connected cards\nand folders you set up.", "AI makes scenes and\nspoken words searchable."][index])
                    .font(.pixfun(13)).lineSpacing(4).foregroundStyle(Color.pixfunMuted)
            }
        }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }
}
