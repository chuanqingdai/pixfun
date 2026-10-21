import SwiftUI
import AppKit

/// All controls edit a private draft. Nothing observes the draft outside this sheet.
struct AppSettingsView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AppSettingsDraft()
    @State private var original = AppSettingsDraft()
    @State private var saving = false
    @State private var error: String?
    @State private var cloudExpanded = false
    @State private var toolsExpanded = false

    private let providers = [
        ("OpenAI", "https://api.openai.com/v1"),
        ("DeepSeek", "https://api.deepseek.com/v1"),
        ("Qwen · China", "https://dashscope.aliyuncs.com/compatible-mode/v1"),
        ("Qwen · International", "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")
    ]
    private var modeNote: String {
        switch draft.mode {
        case "hybrid": return "Cloud plans the edit. Your clips are analyzed on this Mac."
        case "cloud": return "Cloud helps plan the edit and review selected frames."
        default: return "Your clips are processed on this Mac."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 17, weight: .semibold))
                Spacer()
            }.padding(.horizontal, 24).padding(.vertical, 18)
            Divider()
            Form {
                Section("General") {
                    settingRow("Language", hint: "Used for the interface, tags and new analysis.",
                               detail: "Existing descriptions keep their original language until regenerated. Original filenames never change.") {
                        Picker("Language", selection: $draft.language) {
                            Text(verbatim: "简体中文").tag(AppLanguage.chinese)
                            Text(verbatim: "English").tag(AppLanguage.english)
                        }.labelsHidden().pickerStyle(.menu).fixedSize()
                            .accessibilityIdentifier("settings.language")
                    }
                    settingRow("Look up place names", hint: "Send recorded coordinates to Apple Maps to show nearby areas. Photos and videos are not uploaded. Results are cached on this Mac; turning this off stops new lookups.") {
                        Toggle("Look up place names", isOn: $draft.onlinePlaceNames)
                            .labelsHidden().toggleStyle(.switch)
                            .accessibilityIdentifier("settings.placeNames")
                    }
                    settingRow("Recognize campuses and scenic areas", hint: "Also send recorded coordinates to OpenStreetMap boundary services. No media or filenames are uploaded. Results are cached locally; missing boundaries keep the original address.") {
                        Toggle("Recognize campuses and scenic areas", isOn: $draft.onlinePlaceBoundaries)
                            .labelsHidden().toggleStyle(.switch).disabled(!draft.onlinePlaceNames)
                            .accessibilityIdentifier("settings.placeBoundaries")
                    }
                    settingRow("Verify places with a backup service", hint: "When boundary lookup is unavailable, send only recorded coordinates to Nominatim (OpenStreetMap). Names are used only after polygon containment is verified. Results are cached; originals are never uploaded.") {
                        Toggle("Verify places with a backup service", isOn: $draft.onlinePlaceFallback)
                            .labelsHidden().toggleStyle(.switch).disabled(!draft.onlinePlaceNames || !draft.onlinePlaceBoundaries)
                            .accessibilityIdentifier("settings.placeFallback")
                    }
                    Link("© OpenStreetMap contributors · ODbL", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                        .font(.system(size: 11))
                }
                Section("Models & processing") {
                    settingRow("Processing", hint: modeNote) {
                        Picker("Processing", selection: $draft.mode) {
                            Text("On this Mac").tag("local")
                            Text("Cloud + local").tag("hybrid")
                            Text("Cloud").tag("cloud")
                        }.labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    DisclosureGroup("Cloud connection", isExpanded: $cloudExpanded) {
                        settingRow("Provider") {
                            Picker("Provider", selection: $draft.cloud.baseURL) {
                                ForEach(providers, id: \.1) { provider in
                                    Text(LocalizedStringKey(provider.0)).tag(provider.1)
                                }
                                if !providers.contains(where: { $0.1 == draft.cloud.baseURL }) {
                                    Text(verbatim: draft.cloud.baseURL).tag(draft.cloud.baseURL)
                                }
                            }.labelsHidden().pickerStyle(.menu).frame(width: 220, alignment: .trailing)
                        }
                        settingRow("Text model") {
                            TextField("Enter model ID", text: $draft.cloud.model)
                                .labelsHidden().accessibilityLabel("Text model ID").frame(width: 220)
                        }
                        settingRow("Vision model", hint: "Only needed for cloud video analysis.") {
                            TextField("Enter vision model ID", text: $draft.cloud.visionModel)
                                .labelsHidden().accessibilityLabel("Vision model ID").frame(width: 220)
                        }
                        settingRow("API key", hint: "Saved securely in macOS Keychain.") {
                            SecureField("Paste your API key", text: $draft.cloud.apiKey)
                                .labelsHidden().accessibilityLabel("API key").frame(width: 220)
                        }
                        Text("We ask before sending any content to the cloud.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let caps = store.agentCapabilities {
                    Section("Local models") {
                        settingRow("Analysis engine") {
                            Text(verbatim: "VisionFlow \(caps.engineVersion ?? "—")").foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Model status", isExpanded: $toolsExpanded) {
                            Text(caps.localModel).font(.system(size: 12)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            ForEach(caps.tools ?? []) { tool in
                                LabeledContent {
                                    Text(LocalizedStringKey(!tool.installed ? "Not installed" : tool.lastExecution == "verified" ? "Checked" : tool.lastExecution == "failed" ? "Needs attention" : "Not checked"))
                                        .foregroundStyle(.secondary)
                                } label: { Text(tool.name).lineLimit(2) }
                            }
                            if let sample = Bundle.main.url(forResource: "sample", withExtension: "mp4", subdirectory: "HyperFrames/showcase") {
                                HStack {
                                    Spacer()
                                    Button("Preview official templates") { NSWorkspace.shared.open(sample) }
                                    Button("Show example project") { NSWorkspace.shared.activateFileViewerSelecting([sample.deletingLastPathComponent()]) }
                                }.controlSize(.small)
                            }
                        }
                    }
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
                .textFieldStyle(.roundedBorder).scrollIndicators(.automatic)
                // Grouped Form already supplies 20pt outer insets on macOS.
                .padding(.horizontal, 4)
                .disabled(saving)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if let error {
                    Label { Text(LocalizedStringKey(error)).fixedSize(horizontal: false, vertical: true) } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }.font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    if saving { ProgressView().controlSize(.small); Text("Saving…").foregroundStyle(.secondary) }
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                    Button("OK", action: confirm).keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent).disabled(saving)
                        .accessibilityIdentifier("settings.confirm")
                }
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }
        .font(.system(size: 13)).foregroundStyle(.primary)
        .buttonStyle(.bordered).controlSize(.regular).tint(Color.accentColor)
        .frame(width: 620, height: min(680, max(440, (NSScreen.main?.visibleFrame.height ?? 900) - 100)))
        .background(Color(nsColor: .windowBackgroundColor))
        .interactiveDismissDisabled(saving)
        // Use the saved locale, never the tentative language selection.
        .environment(\.locale, store.language.locale)
        .onAppear {
            draft = AppSettingsDraft(language: store.language, cloud: CloudSettings.read() ?? CloudSettings(), mode: store.agentMode, onlinePlaceNames: store.onlinePlaceNames, onlinePlaceBoundaries: store.onlinePlaceBoundaries, onlinePlaceFallback: store.onlinePlaceFallback)
            original = draft
            cloudExpanded = draft.mode != "local"
        }
        .onChange(of: draft.mode) { if $0 != "local" { cloudExpanded = true } }
    }

    private func settingRow<Control: View>(_ title: String, hint: String? = nil, detail: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // A single full-width header keeps every control on the same trailing
            // edge. Supporting text must not participate in control alignment.
            HStack(alignment: .center, spacing: 16) {
                Text(LocalizedStringKey(title))
                Spacer(minLength: 16)
                control()
            }.frame(minHeight: 24)
            if hint != nil || detail != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let hint {
                        Text(LocalizedStringKey(hint)).font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let detail {
                        Text(LocalizedStringKey(detail)).font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
    }

    private func confirm() {
        guard !saving else { return }
        if let issue = draft.validationIssue { error = issue; return }
        if draft == original { dismiss(); return }
        saving = true; error = nil
        Task {
            do {
                if draft.requiresCloudSave(comparedTo: original) {
                    try await store.saveCloudSettings(draft.cloud, mode: draft.mode)
                    // If the later language save fails, retry only the unsaved part.
                    original.cloud = draft.cloud; original.mode = draft.mode
                }
                if draft.language != original.language { try await store.saveLanguage(draft.language) }
                if draft.onlinePlaceBoundaries != original.onlinePlaceBoundaries || draft.onlinePlaceNames != original.onlinePlaceNames || draft.onlinePlaceFallback != original.onlinePlaceFallback {
                    store.savePlaceSettings(names: draft.onlinePlaceNames, boundaries: draft.onlinePlaceBoundaries, fallback: draft.onlinePlaceFallback)
                }
                dismiss()
            } catch { self.error = error.localizedDescription }
            saving = false
        }
    }
}
