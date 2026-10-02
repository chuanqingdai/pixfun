import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct AgentWorkspaceView: View {
    @EnvironmentObject var store: WorkspaceStore
    let run: AgentRun
    var compact = false
    @State private var height: CGFloat = 36
    @State private var focused = false
    @State private var modelSettings = false
    @State private var followingLatest = true
    @State private var showAttachments = false
    @State private var changeFiles = false
    @State private var confirmReplacement = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !compact {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.currentProject?.title ?? "Project").font(.pixfun(18, semibold: true)).lineLimit(1)
                    if !run.busy { Text(run.statusLabel).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            conversation
        }.padding(.horizontal, compact ? 16 : 28).padding(.top, 16).padding(.bottom, 18)
            .sheet(isPresented: $modelSettings) { AgentSettingsView() }.navigationTitle("Project")
            .sheet(isPresented: $changeFiles) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Files for this task").font(.pixfun(18, semibold: true))
                    Text("Changes apply to your next message. Sent messages keep their original attachments.")
                        .font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108))], spacing: 12) {
                            ForEach(store.composerDraft.attachments) { attachment in
                                AttachmentView(attachment: attachment) { store.composerDraft.attachments.removeAll { $0.id == attachment.id } }
                            }
                        }
                    }.frame(height: 220)
                    HStack {
                        Button("Add files…") { store.pick(attach: true) }
                        Spacer()
                        Button("Done") { changeFiles = false; focused = true }.buttonStyle(PixfunButtonStyle(kind: .primary))
                    }
                }.padding(24).frame(width: 480).background(Color.pixfunBackground)
            }
            .onChange(of: run.id) { _ in confirmReplacement = false }
            .onChange(of: run.busy) { busy in if !busy { confirmReplacement = false } }
    }
    var results: some View {
                    VStack(alignment: .leading, spacing: 18) {
                        AgentResultHeading(run: run)
                        if let report = run.displayAnalysisReport {
                            AgentAnalysisResults(run: run, report: report)
                        } else if run.showsDirectEvidence {
                            AgentEvidenceResults(run: run)
                        } else {
                        if let preview = run.preview { AgentVideoMessage(artifact: preview, aspect: run.aspect) }
                        if !run.timeline.isEmpty {
                            Button("Open editor") { store.openEditor(run.projectId) }.buttonStyle(PixfunButtonStyle(kind: .primary))
                        }
                        if !run.resultText.isEmpty && run.preview == nil {
                            Text(run.resultText).font(.pixfun(15)).lineSpacing(5).textSelection(.enabled)
                        }
                        ForEach(run.artifacts.filter { $0.type == "finishing" || $0.type == "credits" }) { artifact in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(artifact.title).font(.pixfun(14, semibold: true))
                                Text(artifact.text).font(.pixfun(13)).foregroundStyle(Color.pixfunMuted).textSelection(.enabled)
                                if artifact.path != nil { Button("Export credits…") { store.exportArtifact(artifact) }.buttonStyle(PixfunButtonStyle(kind: .quiet)) }
                            }
                        }
                        if !run.timeline.isEmpty { AgentTimelineResult(run: run).id(run.id) }
                        if !run.resultText.isEmpty && run.preview != nil {
                            DisclosureGroup("Editing notes") {
                                Text(run.resultText).font(.pixfun(14)).lineSpacing(5).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                            }.font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                        }
                        ForEach(run.artifacts.filter { $0.type == "skill" }) { artifact in
                            DisclosureGroup(artifact.title) {
                                Text(artifact.text).font(.pixfun(13)).textSelection(.enabled)
                            }
                        }
                        if run.artifacts.contains(where: { ["analysis", "observation", "subtitle", "match", "notice"].contains($0.type) }) {
                          if run.status == "failed" {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Saved results").font(.pixfun(14, semibold: true))
                                AgentSourceResults(artifacts: run.artifacts.filter { !["finishing", "credits", "skill"].contains($0.type) })
                            }
                          } else {
                          DisclosureGroup("Source results") {
                            AgentSourceResults(artifacts: run.artifacts.filter { !["finishing", "credits", "skill"].contains($0.type) })
                          }.font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                          }
                        }
                        }
                    }
    }
    var conversation: some View {
                VStack(alignment: .leading, spacing: 16) {
                  GeometryReader { viewport in
                    ScrollViewReader { proxy in
                      ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            ForEach(store.agentRuns.filter { $0.projectId == run.projectId }.sorted { ($0.createdAt ?? $0.updatedAt) < ($1.createdAt ?? $1.updatedAt) }) { entry in
                              VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 12) {
                                    let files = entry.sentAttachments(in: store.items)
                                    if !files.isEmpty { AgentMessageAttachments(attachments: files) }
                                    Text(entry.prompt).font(.pixfun(15)).lineSpacing(4).textSelection(.enabled)
                                }
                                    .padding(16).background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 14))
                                    .frame(maxWidth: 620, alignment: .trailing)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                if let scope = entry.editScope {
                                    Text("Referenced \(scope.shotIds.count) shot(s) · v\(scope.version)").font(.pixfun(12)).foregroundStyle(Color.pixfunGold)
                                }
                                Label("Pixfun", systemImage: "sparkles").font(.pixfun(14, semibold: true)).foregroundStyle(Color.pixfunGold)
                                if let notice = entry.skillNotice {
                                    Label(notice, systemImage: "wand.and.stars").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                                }
                                ForEach((entry.conversationHistory ?? []).filter { $0.state != "pending" || entry.id != run.id }) { decision in
                                    AgentDecisionHistory(decision: decision)
                                }
                                if entry.status == "failed" {
                                    AgentFailureCard(run: entry, canRetry: entry.id == run.id,
                                                     editingBlocked: compact && store.editorHasPendingChanges)
                                } else if entry.id == run.id { AgentActivityView(run: entry) }
                                if entry.busy { AgentPartialFindings(run: entry) }
                                if !entry.question.isEmpty && (entry.id == run.id || entry.conversationHistory?.isEmpty != false) {
                                    Text(entry.displayQuestion).font(.pixfun(15)).lineSpacing(5).textSelection(.enabled)
                                        .padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(Color.pixfunGold).frame(width: 2) }
                                }
                                if compact && !entry.busy {
                                    if !entry.resultText.isEmpty {
                                        DisclosureGroup("Editing summary") { Text(entry.resultText).font(.pixfun(13)).lineSpacing(4).textSelection(.enabled) }
                                    }
                                    if entry.id == run.id && entry.status == "completed" {
                                        Text("Review the preview, then select a shot to request another change.").font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                                    }
                                } else if entry.id == run.id && !entry.busy {
                                    results
                                    if entry.status == "completed" { followUp }
                                }
                                else if !entry.busy { AgentPreviousResults(run: entry) }
                                // Decisions belong to the message that requested them, not
                                // the fixed composer. Past turns never retain live actions.
                                if entry.id == run.id {
                                    if run.hasConversationActions && run.status != "failed" { conversationActions }
                                    if confirmReplacement {
                                        VStack(alignment: .leading, spacing: 12) {
                                            Text("Stop the current task and send your changes?").font(.pixfun(15, semibold: true))
                                            Text("Completed analysis is kept. Your changes will start a new turn.")
                                                .font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                                            HStack {
                                                Button("Stop & send") { confirmReplacement = false; store.submitAgent(); focused = true }
                                                    .buttonStyle(PixfunButtonStyle(kind: .primary))
                                                Button("Keep working") { confirmReplacement = false }
                                                    .buttonStyle(PixfunButtonStyle(kind: .quiet))
                                            }.disabled(store.saving || store.agentActionPending)
                                        }.padding(16).background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                              }
                            }
                            Color.clear.frame(height: 1).id("conversation-bottom")
                              .background(GeometryReader { marker in
                                  Color.clear.preference(key: AgentBottomPreference.self, value: marker.frame(in: .named("agent-conversation")).maxY)
                              })
                        }.frame(maxWidth: 800).frame(maxWidth: .infinity).padding(.vertical, 16)
                      }.coordinateSpace(name: "agent-conversation")
                        .onPreferenceChange(AgentBottomPreference.self) { y in followingLatest = y <= viewport.size.height + 70 }
                        .onAppear { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
                        .onChange(of: run.id) { _ in proxy.scrollTo("conversation-bottom", anchor: .bottom) }
                        .onChange(of: run.updatedAt) { _ in
                            if followingLatest { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
                        }
                        .onChange(of: confirmReplacement) { visible in
                            if visible { followingLatest = true; proxy.scrollTo("conversation-bottom", anchor: .bottom) }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if !followingLatest {
                                Button("Latest ↓") { followingLatest = true; proxy.scrollTo("conversation-bottom", anchor: .bottom) }
                                    .buttonStyle(PixfunButtonStyle(kind: .quiet)).padding(8)
                            }
                        }
                    }
                  }
                    composer.frame(maxWidth: 800).frame(maxWidth: .infinity)
                }
    }
    var conversationActions: some View {
            HStack {
                if run.status == "consent" {
                    Button("Allow this task") { store.agentAction("approve", run: run) }.buttonStyle(PixfunButtonStyle(kind: .primary))
                    Button("Decline") { store.agentAction("stop", run: run) }
                } else if run.canResumePhotoEdit {
                    Button("Create video") { store.agentAction("retry", run: run) }.buttonStyle(PixfunButtonStyle(kind: .primary))
                } else if run.canUseVideosOnly {
                    Button(run.clarificationKind == "visual_only" ? "Use photos & videos" : "Use videos only") { store.agentAction(run.clarificationKind == "visual_only" ? "use_visuals" : "use_videos", run: run) }.buttonStyle(PixfunButtonStyle(kind: .primary))
                    Button("Change files") { store.agentAction("change_files", run: run); changeFiles = true }.buttonStyle(PixfunButtonStyle(kind: .quiet))
                } else if run.status == "clarify", let choices = run.choices, !choices.isEmpty {
                    ForEach(choices) { choice in
                        Button(choice.label) { store.submitAgent(prompt: choice.prompt) }
                            .buttonStyle(PixfunButtonStyle(kind: .quiet))
                            .disabled(!store.canApplyAgentOption)
                            .help("Apply this choice now")
                    }
                } else if run.status == "review" || (run.status == "completed" && run.intent == "plan" && !run.timeline.isEmpty && run.preview == nil) {
                    Button("Build preview") { store.agentAction("approve", run: run) }.buttonStyle(PixfunButtonStyle(kind: .primary))
                    if !compact { Text("Or describe changes below").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted) }
                } else if ["failed", "cancelled", "interrupted"].contains(run.status) {
                    Button("Retry") { store.agentAction("retry", run: run) }
                    if !compact { Text("Your draft and completed results are kept.").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted) }
                }
                if store.agentActionPending { ProgressView().controlSize(.small) }
                Spacer()
            }.disabled(store.agentActionPending || store.saving || (compact && store.editorHasPendingChanges))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Response options")
    }
    var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                if compact, let scope = store.editorSelection {
                    HStack {
                        Label("\(scope.shotIds.count) selected · v\(scope.version)", systemImage: "film").font(.pixfun(12)).foregroundStyle(Color.pixfunGold)
                        Spacer()
                        Button { store.editorSelection = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Clear editing selection")
                    }.padding(.bottom, 4)
                }
                if !store.composerPendingAttachments.isEmpty || store.composerDraft.skill != nil {
                    HStack(spacing: 10) {
                        if !store.composerPendingAttachments.isEmpty {
                            Button { showAttachments.toggle() } label: {
                                Label("\(store.composerPendingAttachments.count) new files", systemImage: "photo.on.rectangle")
                            }.buttonStyle(PixfunButtonStyle(kind: .quiet))
                                .popover(isPresented: $showAttachments) {
                                    VStack(alignment: .leading, spacing: 14) {
                                        Text("For your next message").font(.pixfun(14, semibold: true))
                                        ScrollView {
                                            LazyVGrid(columns: [GridItem(.fixed(108)), GridItem(.fixed(108)), GridItem(.fixed(108))], spacing: 12) {
                                                ForEach(store.composerPendingAttachments) { attachment in
                                                    AttachmentView(attachment: attachment) { store.composerDraft.attachments.removeAll { $0.id == attachment.id } }
                                                }
                                            }
                                        }.frame(width: 350, height: 190)
                                    }.padding(16).background(Color.pixfunSurface)
                                }
                        }
                        if let skill = store.composerDraft.skill {
                            HStack(spacing: 6) {
                                Image(systemName: "wand.and.stars"); Text(skill.title).lineLimit(1)
                                Button { store.composerDraft.skill = nil } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain).accessibilityLabel("Remove skill from next message")
                            }.font(.pixfun(12)).foregroundStyle(Color.pixfunGold)
                        }
                        Spacer()
                    }
                }
                PromptEditor(text: $store.composerDraft.prompt, height: $height, requestFocus: $focused,
                             minimumHeight: 36, maximumHeight: 128, placeholder: run.status == "clarify" ? "Tell me your preference…" : "Describe what to create or change…", onSubmit: send)
                    .frame(height: height)
                HStack(spacing: 8) {
                    Menu {
                        Button("Add files…") { store.pick(attach: true) }
                        Button("Add folder…") { store.pick(folder: true, attach: true) }
                        Button("From Media", action: store.beginSelection)
                    } label: { Image(systemName: "plus").font(.system(size: 17)).frame(width: 24, height: 24) }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Add material").disabled(store.importing || store.saving)
                        .modifier(ComposerAttachmentHint(active: store.needsComposerMaterials && !store.importing && !store.saving))
                    Spacer()
                    Button { modelSettings = true } label: { ComposerToolLabel(title: "Models", symbol: "slider.horizontal.3") }
                        .buttonStyle(PixfunButtonStyle(kind: .quiet)).help("Model settings")
                    if run.busy {
                        Button { store.agentAction("stop", run: run) } label: {
                            Group {
                                if store.agentActionPending || store.saving { ProgressView().controlSize(.mini) }
                                else { Image(systemName: "stop.fill") }
                            }.frame(width: 16, height: 20)
                        }
                            .accessibilityLabel("Stop task").help("Stop task; keep completed results").disabled(store.agentActionPending || store.saving)
                    } else {
                        Button(action: send) {
                            Group {
                                if store.importing || store.saving || store.agentActionPending { ProgressView().controlSize(.mini) }
                                else { Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)) }
                            }.frame(width: 16, height: 20)
                        }
                            .buttonStyle(PixfunButtonStyle(kind: .primary)).disabled(!store.canSubmitAgent)
                            .accessibilityLabel(store.canResumeWithMaterials && store.composerDraft.prompt.isEmpty ? "Continue" : "Send")
                            .help("Enter to send · Shift–Enter for a new line").keyboardShortcut(.return, modifiers: .command)
                    }
                }
            }.padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.pixfunLine))
            ComposerNotice()
        }
    }
    func send() {
        guard store.canSubmitAgent else { return }
        if run.busy { confirmReplacement = true }
        else { store.submitAgent(); focused = true }
    }
    var followUp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(run.preview != nil ? "What would you like to change?" : "Where would you like to go next?")
                .font(.pixfun(15, semibold: true))
            Text(run.preview != nil ? "Tell me which moment to change, or adjust the pacing, shot order, and length." : "Ask a follow-up, explore a specific moment, or ask me to turn these findings into a story.")
                .font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
            HStack(spacing: 8) {
                ForEach(run.preview != nil ? ["Tighter pacing", "Stronger opening", "Shorten by 20%"] : ["Find highlights", "Plan a story", "Create a video"], id: \.self) { suggestion in
                    Button(suggestion) {
                        let seconds = max(1, run.timeline.reduce(0) { $0 + $1.end - $1.start } * 0.8)
                        let prompts = ["Tighter pacing": "Make the pacing tighter while keeping the key story moments. Render the updated preview directly.", "Stronger opening": "Replace the opening with a stronger moment from my footage. Keep the rest of the story and render the updated preview.", "Shorten by 20%": "Shorten the total duration to \(String(format: "%.1f", seconds)) seconds while keeping the key moments. Render the updated preview.", "Find highlights": "Find the strongest moments in this footage and explain why they work.", "Plan a story": "Suggest a story structure with shot order and timing. Give me a plan only; do not render a video.", "Create a video": "Create a travel video from this footage using the story discussed so far. Keep original sound and render the preview directly."]
                        let value = prompts[suggestion] ?? suggestion
                        store.submitAgent(prompt: value)
                    }.buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(!store.canApplyAgentOption)
                        .help("Run this request now")
                }
            }
        }.padding(.top, 8)
    }
}

struct AgentMessageAttachments: View {
    @EnvironmentObject var store: WorkspaceStore
    let attachments: [Attachment]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 130), alignment: .leading)], alignment: .leading, spacing: 10) {
            ForEach(attachments) { attachment in
                let item = store.items.first { $0.id == attachment.id }
                Button { if let item { store.openMedia(item) } } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        if attachment.kind == "audio" {
                            Image(systemName: "waveform").frame(height: 62).frame(maxWidth: .infinity)
                                .background(.white.opacity(0.06))
                        } else {
                            ServiceImage(path: item?.cover).frame(height: 62).clipped().cornerRadius(5)
                        }
                        Text(attachment.name).font(.pixfun(11)).lineLimit(1).foregroundStyle(Color.pixfunMuted)
                    }
                }.buttonStyle(.plain).disabled(item == nil)
                    .help(attachment.name).accessibilityLabel("Sent file: \(attachment.name)")
            }
        }
    }
}

struct AgentDecisionHistory: View {
    let decision: AgentDecision
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if decision.options.count == 1 && decision.options.first?.id == "retry" {
                Label(decision.selected == "retry" ? "Retry requested" : "Earlier attempt stopped",
                      systemImage: "arrow.counterclockwise").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                DisclosureGroup("Previous attempt details") {
                    Text(decision.question).font(.pixfun(12)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }.font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
            } else {
            Text(decision.question).font(.pixfun(14)).lineSpacing(4).textSelection(.enabled)
            if let text = decision.resultText, !text.isEmpty {
                DisclosureGroup("Plan at this point") { Text(text).font(.pixfun(13)).textSelection(.enabled) }
            }
            // Text chips, deliberately not buttons: history cannot re-authorize work.
            ForEach(decision.options) { option in
                HStack(spacing: 8) {
                    Image(systemName: decision.selected == option.id ? "checkmark.circle.fill" : "circle")
                    Text(option.label)
                }.font(.pixfun(13)).foregroundStyle(decision.selected == option.id ? Color.pixfunGold : Color.pixfunMuted)
            }
            if let response = decision.response {
                Text("You chose: \(response)").font(.pixfun(13)).foregroundStyle(Color.pixfunMuted).textSelection(.enabled)
            } else {
                Text("Earlier options").font(.pixfun(12)).foregroundStyle(Color.pixfunSubtle)
            }
            }
        }.padding(.leading, 12)
            .overlay(alignment: .leading) { Rectangle().fill(Color.pixfunLine).frame(width: 2) }
    }
}

struct AgentPartialFindings: View {
    @EnvironmentObject var store: WorkspaceStore
    let run: AgentRun
    var findings: [AgentArtifact] { run.artifacts.filter { ["analysis", "observation", "subtitle"].contains($0.type) && !$0.text.isEmpty } }
    var body: some View {
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Findings so far").font(.pixfun(15, semibold: true))
                Text("Still analyzing. These findings may be refined.").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                ForEach(AgentSourceGroup.groups(findings)) { group in
                    AgentMaterialSummaryCard(title: group.title, summary: group.summary, mediaID: group.findings.first?.mediaId)
                }
            }
        }
    }
}

private struct AgentBottomPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct AgentActivityView: View {
    let run: AgentRun
    var body: some View {
        if run.busy {
            HStack(spacing: 12) {
                PixfunActivityIndicator(queued: run.status == "queued")
                Text(run.stageLabel).font(.pixfun(14, semibold: true)).foregroundStyle(Color.pixfunGold)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 16).padding(.vertical, 13)
                .background(Color.pixfunGold.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.pixfunGold.opacity(0.35)))
                .accessibilityElement(children: .combine)
        } else if let notice = run.activityNotice {
            Text(notice).font(.pixfun(13))
                .foregroundStyle(run.status == "failed" ? .orange : Color.pixfunMuted)
                .textSelection(.enabled)
        }
    }
}

struct AgentFailureCard: View {
    @EnvironmentObject var store: WorkspaceStore
    let run: AgentRun
    var canRetry = false
    var editingBlocked = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(run.failureTitle, systemImage: "exclamationmark.circle")
                .font(.pixfun(15, semibold: true)).foregroundStyle(Color.pixfunInk)
            Text(run.activityNotice ?? "Try again to continue.")
                .font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Text("Your files and saved results are kept.")
                .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
            if canRetry {
                HStack(spacing: 10) {
                    Button { store.agentAction("retry", run: run) } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }.buttonStyle(PixfunButtonStyle(kind: .primary))
                        .disabled(store.agentActionPending || store.saving || editingBlocked)
                    if store.agentActionPending { ProgressView().controlSize(.small) }
                }
            }
            if !run.message.isEmpty && run.message != run.activityNotice {
                DisclosureGroup("Technical details") {
                    Text(run.message).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }.font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.pixfunLine))
    }
}

struct AgentVideoMessage: View {
    @EnvironmentObject var store: WorkspaceStore
    let artifact: AgentArtifact
    let aspect: String
    @StateObject private var playback = AgentPlayback()
    var ratio: CGFloat { aspect == "9:16" ? 9/16 : aspect == "1:1" ? 1 : 16/9 }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(artifact.title).font(.pixfun(16, semibold: true))
            Group {
                if let issue = playback.issue {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                        Text(issue).font(.pixfun(13))
                        Button("Reload preview") { playback.load(artifact.path) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.pixfunSurface)
                }
                else if let player = playback.player {
                    NativeVideoPlayer(player: player).overlay {
                        if !playback.hasStarted, let poster = playback.poster {
                            Image(nsImage: poster).resizable().scaledToFit().allowsHitTesting(false)
                        }
                    }
                }
                else { Color.black }
            }.aspectRatio(ratio, contentMode: .fit).frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Generated rough-cut video")
            HStack {
                Button { playback.toggle() } label: {
                    Label(playback.playing ? "Pause" : "Play", systemImage: playback.playing ? "pause.fill" : "play.fill")
                }.buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(!playback.ready || playback.issue != nil)
                Text(playback.durationLabel + " · " + aspect).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).help(artifact.text)
                Spacer()
                Button { store.exportArtifact(artifact) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(playback.issue != nil)
            }
        }.onAppear { if playback.player == nil { playback.load(artifact.path) } }
            .onChange(of: artifact.path) { _ in playback.load(artifact.path) }
            .onDisappear { playback.player?.pause() }
    }
}

@MainActor
final class AgentPlayback: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var issue: String?
    @Published private(set) var playing = false
    @Published private(set) var ready = false
    @Published private(set) var poster: NSImage?
    @Published private(set) var hasStarted = false
    private var posterGenerator: AVAssetImageGenerator?
    var durationLabel: String {
        guard ready, let seconds = player?.currentItem?.duration.seconds, seconds.isFinite else { return "Preview" }
        return timestamp(seconds)
    }
    private var observation: NSKeyValueObservation?
    private var playbackObservation: NSKeyValueObservation?
    func load(_ path: String?) {
        player?.pause()
        posterGenerator?.cancelAllCGImageGeneration(); posterGenerator = nil; poster = nil; hasStarted = false
        observation = nil; playbackObservation = nil; player = nil; issue = nil; ready = false; playing = false
        guard let path, FileManager.default.isReadableFile(atPath: path) else {
            issue = "Preview file is unavailable. Rebuild the preview to continue."
            return
        }
        let item = AVPlayerItem(url: URL(fileURLWithPath: path))
        player = AVPlayer(playerItem: item)
        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 720)
        posterGenerator = generator
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { [weak self] _, image, _, _, _ in
            guard let image else { return }
            Task { @MainActor [weak self] in
                guard let self, self.player?.currentItem === item else { return }
                self.poster = NSImage(cgImage: image, size: .zero)
            }
        }
        playbackObservation = player?.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player === player else { return }
                self.playing = player.timeControlStatus != .paused
                if self.playing { self.hasStarted = true }
            }
        }
        observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player?.currentItem === item else { return }
                if item.status == .failed {
                    self.issue = "This preview could not be played. Reload it or rebuild the preview."
                } else if item.status == .readyToPlay {
                    self.ready = true
                    self.player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        }
    }
    func toggle() {
        guard let player, ready, issue == nil else { return }
        if playing { player.pause() }
        else {
            if let end = player.currentItem?.duration.seconds, end.isFinite, player.currentTime().seconds >= end - 0.05 {
                player.seek(to: .zero)
            }
            player.play()
        }
    }
}

struct AgentPreviousResults: View {
    @EnvironmentObject var store: WorkspaceStore
    let run: AgentRun
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AgentResultHeading(run: run)
            if let report = run.displayAnalysisReport {
                AgentAnalysisResults(run: run, report: report)
            } else if run.showsDirectEvidence {
                AgentEvidenceResults(run: run)
            } else {
            if let preview = run.preview { AgentVideoMessage(artifact: preview, aspect: run.aspect) }
            if !run.resultText.isEmpty { Text(run.resultText).font(.pixfun(14)).textSelection(.enabled) }
            if !run.timeline.isEmpty {
                DisclosureGroup("Earlier story · \(run.timeline.count) shots") {
                    ForEach(run.timeline) { shot in
                        Text("\(shot.label) · \(timestamp(shot.start))–\(timestamp(shot.end))\n\(shot.reason)")
                            .font(.pixfun(12)).textSelection(.enabled).padding(.vertical, 4)
                    }
                }
            }
            if run.artifacts.contains(where: { ["analysis", "observation", "subtitle", "match", "notice", "finishing", "credits", "skill"].contains($0.type) }) {
                DisclosureGroup("Source results") {
                    AgentSourceResults(artifacts: run.artifacts)
                }
            }
            }
        }
    }
}

struct AgentResultHeading: View {
    let run: AgentRun
    var body: some View {
        if let title = run.resultHeading {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.pixfun(17, semibold: true)).foregroundStyle(Color.pixfunInk)
                if let detail = run.resultDetail {
                    Text(detail).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AgentTimelineResult: View {
    @EnvironmentObject var store: WorkspaceStore
    let run: AgentRun
    @State private var expanded: Bool
    init(run: AgentRun) {
        self.run = run
        _expanded = State(initialValue: run.intent == "plan" && run.preview == nil)
    }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(run.timeline.enumerated()), id: \.element.id) { index, shot in
                    HStack(alignment: .top, spacing: 12) {
                        ServiceImage(path: store.items.first { $0.id == shot.mediaId }?.cover)
                            .frame(width: 88, height: 50).clipped().cornerRadius(5)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(index + 1). \(shot.label)").font(.pixfun(14, semibold: true))
                            Text("\(String(format: "%.1f", shot.end - shot.start))s · \(store.items.first { $0.id == shot.mediaId }?.file.name ?? "Source")")
                                .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                            Text(shot.reason).font(.pixfun(13)).lineSpacing(3).foregroundStyle(Color.pixfunMuted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if shot.locked { Image(systemName: "lock.fill").accessibilityLabel("Locked shot") }
                    }.padding(.vertical, 4)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        } label: {
            Text(run.intent == "plan" && run.preview == nil ? "Shot order & timing" : "Timeline · \(run.timeline.count) shots")
                .font(.pixfun(14, semibold: true))
        }
    }
}

/// One layout for current and historical evidence, without report downloads.
struct AgentSourceResults: View {
    let artifacts: [AgentArtifact]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(AgentSourceGroup.groups(artifacts)) { group in
                AgentMaterialSummaryCard(title: group.title, summary: group.summary, mediaID: group.findings.first?.mediaId)
            }
            ForEach(artifacts.filter { $0.type == "notice" }) { artifact in
                Text(artifact.text).font(.pixfun(13)).lineSpacing(4).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            let details = artifacts.filter { ["finishing", "credits", "skill"].contains($0.type) }
            if !details.isEmpty {
                DisclosureGroup("Editing details") {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(details) { artifact in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(artifact.title).font(.pixfun(13, semibold: true)).foregroundStyle(Color.pixfunInk)
                                Text(artifact.text).font(.pixfun(13)).lineSpacing(4).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                }.font(.pixfun(13))
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
    }
}

struct AgentMaterialSummaryCard: View {
    @EnvironmentObject var store: WorkspaceStore
    let title: String
    let summary: String
    let mediaID: String?
    @State private var hovering = false
    var item: MediaItem? { store.items.first { $0.id == mediaID } }
    var body: some View {
        Button { if let item { store.openMedia(item) } } label: {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if item?.kind == "audio" {
                        ZStack {
                            Color.white.opacity(0.045)
                            Image(systemName: "waveform").foregroundStyle(Color.pixfunMuted)
                        }
                    } else {
                        ServiceImage(path: item?.cover, fit: .fit)
                    }
                }
                .frame(width: 96, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 12) {
                        Text(title).font(.pixfun(14, semibold: true)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium))
                            .foregroundStyle(hovering ? Color.pixfunGold : Color.pixfunMuted)
                    }.foregroundStyle(Color.pixfunInk)
                    Text(summary).font(.pixfun(14)).lineSpacing(4).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true).foregroundStyle(Color.pixfunMuted)
                        .multilineTextAlignment(.leading)
                    if item == nil { Text("Source unavailable").font(.pixfun(11)).foregroundStyle(Color.pixfunSubtle) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(hovering ? Color.pixfunRaised : Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hovering ? Color.pixfunGold : Color.pixfunLine))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled(item == nil)
            .onHover { hovering = $0 && item != nil }
            .help(item == nil ? "The original material is unavailable" : "Open material details")
            .accessibilityLabel("\(title). \(summary)")
            .accessibilityHint(item == nil ? "Original material unavailable" : "Open material details")
    }
}

/// The answer is visible; additional evidence is folded and transcripts can be exported.
struct AgentEvidenceResults: View {
    @EnvironmentObject var store: WorkspaceStore
    let run: AgentRun
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(run.intent == "search"
                 ? (run.directEvidence.isEmpty ? "No matching moments found." : "\(run.directEvidence.count) matching moments")
                 : (run.directEvidence.isEmpty ? "No usable speech was found." : "Transcript · \(run.directEvidence.count) entries"))
                .font(.pixfun(15, semibold: true))
            ForEach(Array(run.directEvidence.prefix(8))) { item in evidence(item) }
            if run.directEvidence.count > 8 {
                DisclosureGroup("Show all \(run.directEvidence.count) results") {
                    ForEach(Array(run.directEvidence.dropFirst(8))) { item in evidence(item) }
                }.font(.pixfun(13))
            }
            ForEach(run.artifacts.filter { $0.type == "notice" }) { item in
                Text(item.text).font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
            }
            ForEach(run.artifacts.filter { $0.type == "file" && $0.path?.lowercased().hasSuffix(".srt") == true }) { item in
                Button("Export \(item.title)…") { store.exportArtifact(item) }
                    .buttonStyle(PixfunButtonStyle(kind: .secondary))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    func evidence(_ artifact: AgentArtifact) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(artifact.title).font(.pixfun(13, semibold: true))
                Spacer()
                if let id = artifact.mediaId, let item = store.items.first(where: { $0.id == id }) {
                    Button("\(timestamp(artifact.start ?? 0))–\(timestamp(artifact.end ?? 0)) ↗") {
                        store.openMedia(item, at: artifact.start ?? 0)
                    }.buttonStyle(PixfunButtonStyle(kind: .quiet)).help("Open this moment")
                } else { Text("\(timestamp(artifact.start ?? 0))–\(timestamp(artifact.end ?? 0))").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted) }
            }
            Text(artifact.text).font(.pixfun(14)).lineSpacing(4).textSelection(.enabled)
        }.padding(.vertical, 4)
    }
}

struct AgentAnalysisResults: View {
    @EnvironmentObject var store: WorkspaceStore
    let run: AgentRun
    let report: AgentAnalysisReport
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(report.overview).font(.pixfun(15)).lineSpacing(5).textSelection(.enabled)
            ForEach(report.materials) { material in
                AgentMaterialSummaryCard(title: material.title, summary: material.content, mediaID: material.mediaId)
            }
            ForEach(run.artifacts.filter { $0.type == "notice" }) { notice in
                Text("\(notice.title): \(notice.text)").font(.pixfun(13)).foregroundStyle(Color.pixfunMuted).textSelection(.enabled)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AgentSettingsView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    @State private var config = CloudSettings()
    @State private var mode = "local"
    @State private var savingSettings = false
    @State private var settingsError: String?
    @FocusState private var focusedField: SettingsField?
    private enum SettingsField: Hashable { case textModel, visionModel, apiKey }
    private let providers = [
        ("OpenAI", "https://api.openai.com/v1"),
        ("DeepSeek", "https://api.deepseek.com/v1"),
        ("Qwen · China", "https://dashscope.aliyuncs.com/compatible-mode/v1"),
        ("Qwen · International", "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")
    ]
    private let processingModes = [
        ("On this Mac", "local"), ("Cloud + local", "hybrid"), ("Cloud", "cloud")
    ]
    private var modeNote: String {
        switch mode {
        case "hybrid": return "Cloud plans the edit. Your clips are analyzed on this Mac."
        case "cloud": return "Cloud helps plan the edit and review selected frames."
        default: return "Your clips are processed on this Mac."
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Agent models").font(.pixfun(22, semibold: true))
                .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        settingsMenu("Processing", selection: $mode, choices: processingModes)
                        Text(modeNote).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("Cloud connection").font(.pixfun(16, semibold: true))
                            if mode == "local" { Text("Optional").font(.pixfun(12)).foregroundStyle(Color.pixfunMuted) }
                        }
                        settingsMenu("Provider", selection: $config.baseURL, choices: providers)
                        settingsField("Text model") {
                            TextField("Enter model ID", text: $config.model)
                                .focused($focusedField, equals: .textModel)
                                .accessibilityLabel("Text model ID")
                        }
                        settingsField("Vision model", hint: mode == "cloud" ? nil : "Only needed for cloud video analysis.") {
                            TextField("Enter vision model ID", text: $config.visionModel)
                                .focused($focusedField, equals: .visionModel)
                                .accessibilityLabel("Vision model ID")
                        }
                        settingsField("API key", hint: "Saved securely in macOS Keychain.") {
                            SecureField("Paste your API key", text: $config.apiKey)
                                .focused($focusedField, equals: .apiKey)
                                .accessibilityLabel("API key")
                        }
                        Text("We ask before sending any content to the cloud.")
                            .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                    }
                    if let caps = store.agentCapabilities {
                        DisclosureGroup("Local models") {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(caps.localModel).font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                                ForEach(caps.tools ?? []) { tool in
                                    HStack(alignment: .top, spacing: 20) {
                                        Text(tool.name).fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 8)
                                        Text(!tool.installed ? "Not installed" : tool.lastExecution == "verified" ? "Checked" : tool.lastExecution == "failed" ? "Needs attention" : "Not checked")
                                            .foregroundStyle(tool.lastExecution == "verified" ? Color.pixfunGold : Color.pixfunMuted)
                                            .fixedSize()
                                    }.font(.pixfun(12))
                                }
                            }.padding(.top, 12)
                        }.font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                    }
                }.padding(.horizontal, 28).padding(.bottom, 24)
            }
            Rectangle().fill(Color.pixfunLine).frame(height: 1)
            VStack(alignment: .leading, spacing: 12) {
                if let settingsError {
                    Text(settingsError).font(.pixfun(12)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                HStack {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    if savingSettings { ProgressView().controlSize(.small) }
                    Button("Save") {
                        savingSettings = true; settingsError = nil
                        Task {
                            do { try await store.saveCloudSettings(config, mode: mode); dismiss() }
                            catch { settingsError = error.localizedDescription }
                            savingSettings = false
                        }
                    }.buttonStyle(PixfunButtonStyle(kind: .primary))
                }
            }.padding(.horizontal, 28).padding(.vertical, 18)
        }.disabled(savingSettings)
            .frame(width: 600, height: min(740, max(460, (NSScreen.main?.visibleFrame.height ?? 900) - 100)))
            .background(Color.pixfunSurface)
            .interactiveDismissDisabled(savingSettings)
            .onAppear { config = CloudSettings.read() ?? CloudSettings(); mode = store.agentMode }
    }
    private func settingsField<Content: View>(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.pixfun(13, semibold: true))
            content().textFieldStyle(.plain).font(.pixfun(14))
                .padding(.horizontal, 14).frame(height: 46)
                .background(Color.pixfunBackground, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.pixfunLine))
            if let hint { Text(hint).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted) }
        }
    }
    private func settingsMenu(_ title: String, selection: Binding<String>, choices: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.pixfun(13, semibold: true))
            Menu {
                ForEach(choices, id: \.1) { choice in
                    Button { selection.wrappedValue = choice.1 } label: {
                        if selection.wrappedValue == choice.1 { Label(choice.0, systemImage: "checkmark") }
                        else { Text(choice.0) }
                    }
                }
            } label: {
                HStack {
                    Text(choices.first { $0.1 == selection.wrappedValue }?.0 ?? selection.wrappedValue).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.pixfunMuted)
                }.font(.pixfun(14)).foregroundStyle(Color.pixfunInk)
                    .padding(.horizontal, 14).frame(height: 46)
                    .background(Color.pixfunBackground, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.pixfunLine))
            }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                .accessibilityLabel(title)
                .accessibilityValue(choices.first { $0.1 == selection.wrappedValue }?.0 ?? selection.wrappedValue)
        }
    }
}
