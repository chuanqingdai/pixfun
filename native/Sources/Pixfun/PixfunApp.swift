import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: WorkspaceStore?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { store?.stop() }
}

#if !PIXFUN_LAYOUT_TEST
@main
#endif
struct PixfunApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = WorkspaceStore()
    init() { PixfunTypography.register() }
    var body: some Scene {
        Window("Pixfun", id: "workspace") {
            WorkspaceView().environmentObject(store)
                .environment(\.locale, store.language.locale)
                .frame(minWidth: 960, minHeight: 650)
                .preferredColorScheme(.dark).tint(.pixfunGold)
                .font(.pixfun()).foregroundStyle(Color.pixfunInk)
                .buttonStyle(PixfunButtonStyle())
                .scrollIndicators(.never)
                .background(PixfunWindowAppearance())
                .task { delegate.store = store; await store.start() }
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { store.settingsPresented = true }
                    .keyboardShortcut(",").disabled(!store.ready)
            }
            CommandGroup(replacing: .newItem) {
                Button("New project") { store.newProject() }.keyboardShortcut("n").disabled(!store.ready)
                Button("Import files…") { store.pick(attach: store.page == .home || store.composerProjectID != nil) }.keyboardShortcut("o").disabled(!store.ready || store.importing)
                Button("Import folder…") { store.pick(folder: true, attach: store.page == .home || store.composerProjectID != nil) }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(!store.ready || store.importing)
            }
            CommandMenu("Workspace") {
                ForEach(Array(WorkspacePage.primaryPages.enumerated()), id: \.element.id) { index, page in
                    Button(page.navigationTitle) { store.navigate(page) }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
            }
        }
    }
}

struct WorkspaceView: View {
    @EnvironmentObject var store: WorkspaceStore
    var body: some View {
        Group {
            if store.ready {
                if let projectID = store.editorProjectID, store.page == .project, store.selectedProjectID == projectID {
                    StoryEditorWorkspace(projectID: projectID)
                } else { GeometryReader { viewport in
                    // Imported grids must never raise the window's minimum
                    // height and push persistent navigation off screen.
                    HSplitView {
                    PixfunSidebar()
                        .frame(minWidth: 200, idealWidth: 216, maxWidth: 240)
                        .frame(height: viewport.size.height)
                    Group {
                        switch store.page ?? .media {
                        case .media:
                            if let item = store.detail { MediaDetailView(initialItem: item).id(item.id) }
                            else { MediaView() }
                        case .mediaSync: MediaSyncView(service: store.service, showMedia: { store.openSyncedMedia($0, name: $1) })
                        case .home, .skills, .project: CreationWorkspaceView()
                        }
                    }.frame(minWidth: 0, maxWidth: .infinity)
                        .frame(height: viewport.size.height)
                        .background(Color.pixfunBackground)
                    }
                    .frame(width: viewport.size.width, height: viewport.size.height)
                    .toolbar(.hidden, for: .windowToolbar)
                } }
            } else {
                VStack(spacing: 22) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 88, height: 88)
                    Text("Pixfun").font(.largeTitle.weight(.semibold))
                    if let error = store.startupError {
                        Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 430)
                        Button("Retry") { Task { await store.start() } }.buttonStyle(PixfunButtonStyle(kind: .primary))
                        Button("Show library folder") { NSWorkspace.shared.open(store.service.dataDirectory) }
                    } else {
                        ProgressView().controlSize(.small)
                        Text("Opening your local workspace…").foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.pixfunBackground)
            }
        }
        .alert("Pixfun", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .sheet(isPresented: $store.settingsPresented) { AppSettingsView() }
    }
}

struct PixfunSidebar: View {
    @EnvironmentObject var store: WorkspaceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PixfunLogo()
                .padding(.horizontal, PixfunSidebarMetrics.contentInset)
                .padding(.top, 18).padding(.bottom, 20)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    navigationGroup("Media", pages: WorkspacePage.mediaPages)
                    navigationGroup("Create", pages: WorkspacePage.creationPages, beta: true)
                }
            }
            Spacer()
            Divider().padding(.bottom, 8)
            Button { store.settingsPresented = true } label: {
                Label("Settings", systemImage: "gearshape").font(.pixfun(13))
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(PixfunButtonStyle(kind: .quiet)).help("Settings…")
            Label("On this Mac", systemImage: "internaldrive")
                .font(.pixfun(12)).foregroundStyle(Color.pixfunSubtle)
                .padding(PixfunSidebarMetrics.contentInset)
        }.padding(.horizontal, 12).padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.pixfunSidebar)
    }

    private func navigationGroup(_ title: String, pages: [WorkspacePage], beta: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(title)).font(.pixfun(12, semibold: true)).foregroundStyle(Color.pixfunMuted)
                    .accessibilityAddTraits(.isHeader)
                if beta {
                    Text("Beta").font(.pixfun(10)).foregroundStyle(Color.pixfunSubtle)
                }
            }.padding(.horizontal, PixfunSidebarMetrics.contentInset)
            VStack(spacing: 4) {
                ForEach(pages) { page in
                    PixfunNavigationButton(page: page, selected: store.page == page) { store.navigate(page) }
                }
            }
        }
    }
}

struct CreationWorkspaceView: View {
    @EnvironmentObject var store: WorkspaceStore
    var body: some View {
        Group {
                switch store.page {
                case .skills: SkillsView()
                case .project:
                    if let id = store.selectedProjectID { ProjectDetailView(projectID: id).id(id) }
                    else { ProjectsView() }
                default: HomeView()
                }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PageHeading: View {
    var title: String; var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(LocalizedStringKey(title)).font(.pixfun(22, semibold: true))
            if let subtitle { Text(LocalizedStringKey(subtitle)).font(.pixfun(13)).foregroundStyle(Color.pixfunMuted) }
        }
    }
}

struct EmptyWorkspace: View {
    var symbol: String; var title: String; var detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 36, weight: .light)).foregroundStyle(Color.pixfunGold)
            Text(LocalizedStringKey(title)).font(.title3.weight(.semibold))
            Text(LocalizedStringKey(detail)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
    }
}

struct ServiceImage: View {
    @EnvironmentObject var store: WorkspaceStore
    var path: String?; var fit: ContentMode = .fill
    @State private var loaded: NSImage?
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white.opacity(0.045)
                if let loaded {
                    Image(nsImage: loaded).resizable().aspectRatio(contentMode: fit).frame(width: proxy.size.width, height: proxy.size.height).clipped()
                } else { Image(systemName: "photo").foregroundStyle(.tertiary) }
            }
        }
        .task(id: path) {
            loaded = nil
#if PIXFUN_LAYOUT_TEST
            if let path, path.hasPrefix("/") { loaded = NSImage(contentsOfFile: path); return }
#endif
            if let path { loaded = await store.service.image(path) }
        }
    }
}
