import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: WorkspaceStore
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                Text("What will you create?").font(.pixfun(40, semibold: true)).tracking(-1.2)
                    .frame(maxWidth: .infinity).padding(.bottom, 14)
                BriefComposer()
            }.padding(.horizontal, 36).padding(.top, 88).padding(.bottom, 36)
                .frame(maxWidth: 880).frame(maxWidth: .infinity)
        }.navigationTitle("Home")
    }
}

/// Shared visual style; Home and each project own separate draft values.
struct BriefComposer: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var writing = false
    @State private var editorHeight: CGFloat = 120
    @State private var modelSettings = false
    @State private var pendingExample: AgentExample?
    @State private var confirmReplacement = false
    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
                VStack(alignment: .leading, spacing: 16) {
                    if !store.composerDraft.attachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(store.composerDraft.attachments) { attachment in
                                    AttachmentView(attachment: attachment) { store.composerDraft.attachments.removeAll { $0.id == attachment.id } }
                                }
                            }.padding(2)
                        }.frame(height: 92)
                    }
                    if let skill = store.composerDraft.skill {
                        HStack(spacing: 7) {
                            Image(systemName: "wand.and.stars")
                            Text(skill.title)
                            Button { store.composerDraft.skill = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Remove skill")
                        }.font(.callout).foregroundStyle(Color.pixfunGold)
                    }
                    PromptEditor(text: $store.composerDraft.prompt, height: $editorHeight, requestFocus: $writing,
                                 placeholder: "Add videos, then ask me to analyze or edit…").frame(height: editorHeight)
                    HStack(spacing: 4) {
                        Button { store.pick(folder: true, attach: true) } label: { ComposerToolLabel(title: "Folder", symbol: "folder") }
                        Button { store.pick(attach: true) } label: { ComposerToolLabel(title: "Files & audio", symbol: "paperclip") }
                            .modifier(ComposerAttachmentHint(active: store.needsComposerMaterials && !store.importing && !store.saving))
                        Button(action: store.beginSelection) { ComposerToolLabel(title: "From Media", symbol: "photo.on.rectangle") }
                        Spacer(minLength: 8)
                        Button { modelSettings = true } label: { ComposerToolLabel(title: "Models", symbol: "slider.horizontal.3") }
                            .help("Model settings")
                        if store.importing || store.saving { ProgressView().controlSize(.small) }
                        Button(action: store.submitAgent) { Image(systemName: "arrow.up").font(.system(size: 20, weight: .medium)).frame(width: 16, height: 40) }.buttonStyle(PixfunButtonStyle(kind: .primary)).accessibilityLabel("Send to Agent").help(store.needsComposerMaterials ? "Add files or choose From Media first" : "Send to Agent")
                            .disabled(!store.canSubmitAgent)
                            .keyboardShortcut(.return, modifiers: .command)
                    }.buttonStyle(PixfunButtonStyle(kind: .quiet)).padding(.horizontal, -10).disabled(store.importing)
                }.padding(22).background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.pixfunLine))

            ComposerNotice()
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AgentExample.starters) { example in
                    Button {
                        if example.requiresReplacementConfirmation(for: store.composerDraft.prompt) {
                            pendingExample = example
                            confirmReplacement = true
                        } else {
                            store.composerDraft.prompt = example.applying(to: store.composerDraft.prompt)
                            writing = true
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: example.symbol)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Color.pixfunGold)
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            Text(example.outcome).font(.pixfun(13))
                                .lineLimit(1).minimumScaleFactor(0.9)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 11, weight: .medium))
                                .accessibilityHidden(true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(PixfunButtonStyle(kind: .quiet))
                        .help("Insert an editable example; nothing is sent yet.")
                        .accessibilityLabel("\(example.outcome) Insert example request.")
                        .disabled(store.saving)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
        }.onChange(of: store.composerDraft.skill) { _ in writing = true }
            .sheet(isPresented: $modelSettings) { AgentSettingsView() }
            .alert("Replace your draft?", isPresented: $confirmReplacement) {
                Button("Cancel", role: .cancel) { pendingExample = nil }
                Button("Use example") {
                    if let example = pendingExample { store.composerDraft.prompt = example.prompt; writing = true }
                    pendingExample = nil
                }
            } message: { Text("This example will replace your text. Your attached files will stay.") }
    }
}

/// Identical icon footprint and spacing for every composer toolbar entry.
struct ComposerToolLabel: View {
    let title: String
    let symbol: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 14, weight: .regular)).frame(width: 16, height: 16)
            Text(title).lineLimit(1)
        }.fixedSize(horizontal: true, vertical: false)
    }
}

/// Draw attention to the existing entry point, without adding another prompt or button.
struct ComposerAttachmentHint: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .background(active ? Color.pixfunGold.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(active ? Color.pixfunGold.opacity(0.55) : .clear))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: active)
            .help(active ? "Add your material to continue. Your message will stay here." : "Attach files or audio")
            .accessibilityHint(active ? "Add material before sending. Your message is kept." : "Attach files or audio")
    }
}

struct ComposerNotice: View {
    @EnvironmentObject var store: WorkspaceStore
    var body: some View {
        if let issue = store.composerIssue {
            HStack {
                Text(issue).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                Spacer()
                if let run = store.blockingAgentRun, let project = store.projects.first(where: { $0.id == run.projectId }) {
                    Button("Open project") { store.open(project) }.buttonStyle(PixfunButtonStyle(kind: .quiet))
                }
            }.accessibilityElement(children: .contain)
        }
    }
}

struct AttachmentView: View {
    @EnvironmentObject var store: WorkspaceStore
    var attachment: Attachment; var remove: () -> Void
    @State private var hovering = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                if attachment.kind == "audio" {
                    Image(systemName: "waveform").frame(width: 108, height: 58).background(.white.opacity(0.06))
                } else { ServiceImage(path: store.items.first { $0.id == attachment.id }?.cover).frame(width: 108, height: 58) }
                Button(action: remove) { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.7)) }
                    .buttonStyle(.plain).padding(3).opacity(hovering ? 1 : 0.25).help("Remove from brief").accessibilityLabel("Remove \(attachment.name)")
            }.overlay(alignment: .bottomLeading) {
                if let status = store.items.first(where: { $0.id == attachment.id })?.processingLabel {
                    ProgressView().controlSize(.mini).padding(6)
                        .background(.black.opacity(0.75), in: Circle()).padding(4)
                        .help(status).accessibilityLabel(status).allowsHitTesting(false)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 6))
            Text(attachment.name).font(.caption).lineLimit(1).frame(width: 108, alignment: .leading)
        }.onHover { hovering = $0 }
    }
}
