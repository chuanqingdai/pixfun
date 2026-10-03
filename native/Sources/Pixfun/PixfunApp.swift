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
            CommandGroup(replacing: .newItem) {
                Button("New project") { store.newProject() }.keyboardShortcut("n").disabled(!store.ready)
                Button("Import files…") { store.pick(attach: store.page == .home || store.composerProjectID != nil) }.keyboardShortcut("o").disabled(!store.ready || store.importing)
                Button("Import folder…") { store.pick(folder: true, attach: store.page == .home || store.composerProjectID != nil) }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(!store.ready || store.importing)
            }
            CommandMenu("Workspace") {
                ForEach(Array(WorkspacePage.allCases.enumerated()), id: \.element.id) { index, page in
                    Button(page.rawValue) { store.navigate(page) }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
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
                } else { NavigationSplitView {
                    VStack(alignment: .leading, spacing: 0) {
                        PixfunLogo().padding(.horizontal, 6).padding(.top, 18).padding(.bottom, 30)
                        VStack(spacing: 6) {
                            ForEach(WorkspacePage.allCases) { page in
                                PixfunNavigationButton(page: page, selected: store.page == page) { store.navigate(page) }
                            }
                        }
                        Spacer()
                        Label("On this Mac", systemImage: "internaldrive").font(.pixfun(12)).foregroundStyle(Color.pixfunSubtle).padding(14)
                    }.padding(.horizontal, 16).padding(.bottom, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.pixfunSidebar)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 216, max: 240)
                } detail: {
                    Group {
                        switch store.page ?? .home {
                        case .home: HomeView()
                        case .media:
                            if let item = store.detail { MediaDetailView(initialItem: item).id(item.id) }
                            else { MediaView() }
                        case .skills: SkillsView()
                        case .project:
                            if let id = store.selectedProjectID { ProjectDetailView(projectID: id).id(id) }
                            else { ProjectsView() }
                        }
                    }.background(Color.pixfunBackground)
                }.toolbar(.hidden, for: .windowToolbar) }
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
    }
}

struct PageHeading: View {
    var title: String; var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.pixfun(28, semibold: true)).tracking(-0.6)
            if let subtitle { Text(subtitle).font(.pixfun(13)).foregroundStyle(Color.pixfunMuted) }
        }
    }
}

struct EmptyWorkspace: View {
    var symbol: String; var title: String; var detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 36, weight: .light)).foregroundStyle(Color.pixfunGold)
            Text(title).font(.title3.weight(.semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
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
        .task(id: path) { loaded = nil; if let path { loaded = await store.service.image(path) } }
    }
}
