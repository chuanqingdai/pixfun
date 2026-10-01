import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var store: WorkspaceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                PageHeading(title: "Project")
                Spacer()
                Button("New project", action: store.newProject).buttonStyle(PixfunButtonStyle(kind: .primary))
            }
            if store.projects.isEmpty {
                EmptyWorkspace(symbol: "folder", title: "Your stories start here", detail: "Describe your video in Home to start a project.")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 20, alignment: .top)], alignment: .leading, spacing: 24) {
                        ForEach(store.sortedProjects) { project in
                            ProjectCard(project: project)
                        }
                    }.padding(2).padding(.bottom, 24)
                }
            }
        }.padding(32).navigationTitle("Project")
    }
}

struct ProjectCard: View {
    @EnvironmentObject var store: WorkspaceStore
    let project: Project
    @State private var hovering = false
    var edited: Date { Date(timeIntervalSince1970: store.projectEditedAt(project) / 1000) }
    var body: some View {
        Button { store.open(project) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if let cover = store.projectCover(project) { ServiceImage(path: cover) }
                    else {
                        Rectangle().fill(Color.pixfunRaised)
                            .overlay(Image(systemName: "film").font(.system(size: 28, weight: .light)).foregroundStyle(Color.pixfunSubtle))
                    }
                }.aspectRatio(16 / 9, contentMode: .fit).clipped().accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(project.title).font(.pixfun(16, semibold: true)).foregroundStyle(Color.pixfunInk)
                        .lineLimit(2).frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
                    Text("Edited \(edited.formatted(date: .abbreviated, time: .shortened))")
                        .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).lineLimit(1)
                }.padding(16)
            }.background(hovering ? Color.pixfunRaised : Color.pixfunSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hovering ? Color.pixfunGold : Color.pixfunLine))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .help(project.title).accessibilityLabel("Open \(project.title), edited \(edited.formatted())")
    }
}

struct ProjectDetailView: View {
    @EnvironmentObject var store: WorkspaceStore
    let projectID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { store.navigate(.project) } label: { Label("Back to Project", systemImage: "arrow.left") }
                .buttonStyle(PixfunButtonStyle(kind: .quiet)).padding(.horizontal, 28).padding(.top, 20)
            if let run = store.activeAgentRun {
                AgentWorkspaceView(run: run).id(run.id)
            } else if let project = store.projects.first(where: { $0.id == projectID }) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        PageHeading(title: project.title)
                        ForEach(Array(project.messages.enumerated()), id: \.offset) { _, message in
                            Text(message.text).font(.pixfun(14)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                            Divider()
                        }
                        BriefComposer()
                    }.padding(32).frame(maxWidth: 880).frame(maxWidth: .infinity)
                }
            } else {
                EmptyWorkspace(symbol: "folder", title: "Project unavailable", detail: "Return to Project to choose another story.")
            }
        }.navigationTitle(store.currentProject?.title ?? "Project")
    }
}
