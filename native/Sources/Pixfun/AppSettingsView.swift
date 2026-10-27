import SwiftUI
import AppKit

/// Settings remain a draft. Appearance alone is previewed, then restored on cancel.
struct AppSettingsView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AppSettingsDraft()
    @State private var original = AppSettingsDraft()
    @State private var saving = false
    @State private var presentationLanguage = AppLanguage.saved
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
    private var changed: Bool { draft != original }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings").font(.pixfun(28, semibold: true))
                Text("Changes apply when you save. Appearance is previewed immediately.")
                    .font(.pixfun(14)).foregroundStyle(Color.pixfunMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            Rectangle().fill(Color.pixfunLine).frame(height: 1)
            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        generalSection
                        locationSection
                        processingSection
                        if let caps = store.agentCapabilities { localSection(caps) }
                    }.frame(width: min(920, max(0, viewport.size.width - 48))).padding(24).frame(maxWidth: .infinity)
                        .environment(\.pixfunSettingsWidth, min(920, max(0, viewport.size.width - 48)))
                }.scrollIndicators(.automatic)
            }.disabled(saving)
            Rectangle().fill(Color.pixfunLine).frame(height: 1)
            VStack(alignment: .leading, spacing: 12) {
                if let error {
                    Label { Text(LocalizedStringKey(error)).fixedSize(horizontal: false, vertical: true) } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }.font(.pixfun(14)).foregroundStyle(Color.pixfunDanger).textSelection(.enabled)
                        .accessibilityIdentifier("settings.error")
                }
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                            .frame(width: 16, height: 16).opacity(saving ? 1 : 0)
                            .accessibilityHidden(!saving)
                        Text(saving ? "Saving…" : "Unsaved changes")
                            .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                            .opacity(saving || changed ? 1 : 0)
                            .accessibilityHidden(!saving && !changed)
                    }.frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    Spacer(minLength: 16)
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                    Button("Save", action: confirm).keyboardShortcut(.defaultAction)
                        .buttonStyle(PixfunButtonStyle(kind: .primary)).disabled(saving || !changed)
                        .accessibilityIdentifier("settings.confirm")
                }
            }.padding(24)
        }
        .font(.pixfun(14)).foregroundStyle(Color.pixfunInk)
        .buttonStyle(PixfunButtonStyle()).tint(.pixfunGoldText)
        .frame(width: min(840, max(560, (NSScreen.main?.visibleFrame.width ?? 1280) - 80)),
               height: min(760, max(480, (NSScreen.main?.visibleFrame.height ?? 900) - 100)))
        .background(Color.pixfunBackground)
        .interactiveDismissDisabled(saving)
        // Keep the sheet language stable until dismissal; the workspace can update immediately.
        .environment(\.locale, presentationLanguage.locale)
        .onAppear {
            presentationLanguage = store.language
            draft = AppSettingsDraft(language: store.language, appearance: store.appearance,
                                     cloud: CloudSettings.read() ?? CloudSettings(), mode: store.agentMode,
                                     onlinePlaceNames: store.onlinePlaceNames, onlinePlaceBoundaries: store.onlinePlaceBoundaries,
                                     onlinePlaceFallback: store.onlinePlaceFallback)
            original = draft
            cloudExpanded = draft.mode != "local"
        }
        .onChange(of: draft.appearance) { store.previewAppearance($0) }
        .onChange(of: draft.mode) { if $0 != "local" { cloudExpanded = true } }
        .onDisappear { store.previewAppearance(nil) }
    }

    private var generalSection: some View {
        settingsSection("General") {
            settingRow("Appearance", hint: "Follow your Mac, or choose a light or dark interface. Photos and videos keep their original colors.") {
                PixfunSettingsMenu(title: "Appearance", selection: $draft.appearance,
                                   options: AppAppearance.allCases.map { ($0.title, $0) })
                    .accessibilityIdentifier("settings.appearance")
            }
            rowDivider
            settingRow("Language", hint: "Used for the interface, tags and new analysis.",
                       detail: "Existing descriptions keep their original language until regenerated. Original filenames never change.") {
                PixfunSettingsMenu(title: "Language", selection: $draft.language,
                                   options: [("简体中文", .chinese), ("English", .english)])
                    .accessibilityIdentifier("settings.language")
            }
        }
    }

    private var locationSection: some View {
        settingsSection("Place information") {
            settingRow("Look up place names", hint: "Send recorded coordinates to Apple Maps to show nearby areas. Photos and videos are not uploaded. Results are cached on this Mac; turning this off stops new lookups.", isToggle: true) {
                Toggle("Look up place names", isOn: $draft.onlinePlaceNames).labelsHidden().toggleStyle(.switch)
                    .accessibilityIdentifier("settings.placeNames")
            }
            rowDivider
            settingRow("Recognize campuses and scenic areas", hint: "Also send recorded coordinates to OpenStreetMap boundary services. No media or filenames are uploaded. Results are cached locally; missing boundaries keep the original address.",
                       detail: !draft.onlinePlaceNames ? "Enable place-name lookup first." : nil, isToggle: true) {
                Toggle("Recognize campuses and scenic areas", isOn: $draft.onlinePlaceBoundaries)
                    .labelsHidden().toggleStyle(.switch).disabled(!draft.onlinePlaceNames)
                    .accessibilityIdentifier("settings.placeBoundaries")
            }
            rowDivider
            settingRow("Verify places with a backup service", hint: "When boundary lookup is unavailable, send only recorded coordinates to Nominatim (OpenStreetMap). Names are used only after polygon containment is verified. Results are cached; originals are never uploaded.",
                       detail: !draft.onlinePlaceNames || !draft.onlinePlaceBoundaries ? "Enable place-name and area lookup first." : nil, isToggle: true) {
                Toggle("Verify places with a backup service", isOn: $draft.onlinePlaceFallback)
                    .labelsHidden().toggleStyle(.switch).disabled(!draft.onlinePlaceNames || !draft.onlinePlaceBoundaries)
                    .accessibilityIdentifier("settings.placeFallback")
            }
            rowDivider
            Link("© OpenStreetMap contributors · ODbL", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                .font(.pixfun(12)).foregroundStyle(Color.pixfunGoldText)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
    }

    private var processingSection: some View {
        settingsSection("Models & processing") {
            settingRow("Processing", hint: modeNote) {
                PixfunSettingsMenu(title: "Processing", selection: $draft.mode,
                                   options: [("On this Mac", "local"), ("Cloud + local", "hybrid"), ("Cloud", "cloud")])
            }
            rowDivider
            disclosureRow("Cloud connection", expanded: $cloudExpanded)
            if cloudExpanded {
                rowDivider
                settingRow("Provider") {
                    PixfunSettingsMenu(title: "Provider", selection: $draft.cloud.baseURL,
                                       options: providers + (providers.contains(where: { $0.1 == draft.cloud.baseURL }) ? [] : [(draft.cloud.baseURL, draft.cloud.baseURL)]))
                }
                rowDivider
                settingRow("Text model") {
                    TextField("Enter model ID", text: $draft.cloud.model, prompt: PixfunTypography.placeholder("Enter model ID"))
                        .accessibilityLabel("Text model ID").modifier(PixfunSettingsField())
                }
                rowDivider
                settingRow("Vision model", hint: "Only needed for cloud video analysis.") {
                    TextField("Enter vision model ID", text: $draft.cloud.visionModel, prompt: PixfunTypography.placeholder("Enter vision model ID"))
                        .accessibilityLabel("Vision model ID").modifier(PixfunSettingsField())
                }
                rowDivider
                settingRow("API key", hint: "Saved securely in macOS Keychain.") {
                    SecureField("Paste your API key", text: $draft.cloud.apiKey, prompt: PixfunTypography.placeholder("Paste your API key"))
                        .accessibilityLabel("API key").modifier(PixfunSettingsField())
                }
                Text("We ask before sending any content to the cloud.")
                    .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
        }
    }

    private func localSection(_ caps: AgentCapabilities) -> some View {
        settingsSection("Local models") {
            settingRow("Analysis engine") {
                Text(verbatim: "VisionFlow \(caps.engineVersion ?? "—")").foregroundStyle(Color.pixfunMuted)
            }
            rowDivider
            disclosureRow("Model status", expanded: $toolsExpanded)
            if toolsExpanded {
                Text(caps.localModel).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled).padding(16)
                ForEach(caps.tools ?? []) { tool in
                    rowDivider
                    settingRow(tool.name) {
                        Text(LocalizedStringKey(!tool.installed ? "Not installed" : tool.lastExecution == "verified" ? "Checked" : tool.lastExecution == "failed" ? "Needs attention" : "Not checked"))
                            .foregroundStyle(tool.lastExecution == "failed" ? Color.pixfunDanger : Color.pixfunMuted)
                    }
                }
                if let sample = Bundle.main.url(forResource: "sample", withExtension: "mp4", subdirectory: "HyperFrames/showcase") {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { sampleActions(sample) }
                        VStack(alignment: .leading, spacing: 8) { sampleActions(sample) }
                    }.frame(maxWidth: .infinity, alignment: .trailing).padding(16)
                }
            }
        }
    }

    @ViewBuilder private func sampleActions(_ sample: URL) -> some View {
        Button("Preview official templates") { NSWorkspace.shared.open(sample) }
        Button("Show example project") { NSWorkspace.shared.activateFileViewerSelecting([sample.deletingLastPathComponent()]) }
    }
    private var rowDivider: some View { Rectangle().fill(Color.pixfunLine).frame(height: 1).padding(.horizontal, 16) }
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringKey(title)).font(.pixfun(20, semibold: true)).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0, content: content).background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 8))
        }
    }
    private func disclosureRow(_ title: String, expanded: Binding<Bool>) -> some View {
        Button { expanded.wrappedValue.toggle() } label: {
            HStack(spacing: 12) {
                Text(LocalizedStringKey(title)).font(.pixfun(14, semibold: true))
                Spacer()
                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.pixfunMuted)
            }.padding(16).frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityValue(Text(expanded.wrappedValue ? "Expanded" : "Collapsed"))
    }
    private func settingRow<Control: View>(_ title: String, hint: String? = nil, detail: String? = nil,
                                          isToggle: Bool = false, @ViewBuilder control: () -> Control) -> some View {
        PixfunSettingsRow(title: title, hint: hint, detail: detail, isToggle: isToggle, control: control())
    }

    private func confirm() {
        guard !saving else { return }
        if draft.requiresCloudSave(comparedTo: original), let issue = draft.validationIssue { error = issue; return }
        guard changed else { return }
        saving = true; error = nil
        Task {
            do {
                if draft.requiresCloudSave(comparedTo: original) {
                    try await store.saveCloudSettings(draft.cloud, mode: draft.mode)
                    // A failed later save retries only the still-unsaved part.
                    original.cloud = draft.cloud; original.mode = draft.mode
                }
                if draft.language != original.language {
                    try await store.saveLanguage(draft.language)
                    original.language = draft.language
                }
                if draft.onlinePlaceBoundaries != original.onlinePlaceBoundaries || draft.onlinePlaceNames != original.onlinePlaceNames || draft.onlinePlaceFallback != original.onlinePlaceFallback {
                    store.savePlaceSettings(names: draft.onlinePlaceNames, boundaries: draft.onlinePlaceBoundaries, fallback: draft.onlinePlaceFallback)
                }
                store.saveAppearance(draft.appearance)
                dismiss()
                // Stay disabled during the closing animation. Re-enabling here causes
                // native controls to change appearance again before the sheet disappears.
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}

private struct PixfunSettingsWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 792 }
private extension EnvironmentValues {
    var pixfunSettingsWidth: CGFloat {
        get { self[PixfunSettingsWidthKey.self] }
        set { self[PixfunSettingsWidthKey.self] = newValue }
    }
}

/// Shared two-column row. Long descriptions grow; narrow containers stack.
private struct PixfunSettingsRow<Control: View>: View {
    let title: String
    var hint: String?
    var detail: String?
    var isToggle = false
    let control: Control
    @Environment(\.pixfunSettingsWidth) private var width
    private var stacked: Bool { width < 560 }
    private var copy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title)).font(.pixfun(14, semibold: true))
            if let hint { Text(LocalizedStringKey(hint)).foregroundStyle(Color.pixfunMuted).lineSpacing(4) }
            if let detail { Text(LocalizedStringKey(detail)).font(.pixfun(12)).foregroundStyle(Color.pixfunSubtle).lineSpacing(3) }
        }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }
    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 12) {
                    copy
                    control.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: hint == nil && detail == nil ? .center : .top, spacing: 24) {
                    copy
                    control.frame(width: isToggle ? 48 : 240, alignment: .trailing)
                }
            }
        }.padding(16).frame(maxWidth: .infinity, minHeight: hint == nil ? 72 : 78, alignment: .leading)
    }
}

struct PixfunSettingsMenu<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(String, Value)]
    @FocusState private var focused: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                Button { selection = options[index].1 } label: {
                    if options[index].1 == selection {
                        Label(LocalizedStringKey(options[index].0), systemImage: "checkmark")
                    } else {
                        Text(LocalizedStringKey(options[index].0))
                    }
                }
            }
        } label: {
            Text(LocalizedStringKey(options.first(where: { $0.1 == selection })?.0 ?? title))
                .font(.pixfun(14)).lineLimit(2)
        }
        // macOS flattens decoration inside a Menu label. Style the menu itself.
        .menuStyle(.borderlessButton).menuIndicator(.hidden).buttonStyle(.plain)
        .tint(.pixfunInk).foregroundStyle(Color.pixfunInk).focused($focused)
        .padding(.leading, 12).padding(.trailing, 32)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(hovered && enabled ? Color.pixfunHover : .pixfunInput, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovered = $0 }
        .opacity(enabled ? 1 : 0.5)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? Color.pixfunFocus : .pixfunControlBorder, lineWidth: focused ? 2 : 1))
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.pixfunMuted).padding(.trailing, 12)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text(LocalizedStringKey(options.first(where: { $0.1 == selection })?.0 ?? title)))
    }
}

struct PixfunSettingsField: ViewModifier {
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).font(.pixfun(14)).focused($focused)
            .padding(.horizontal, 12).frame(minHeight: 40)
            .background(Color.pixfunInput, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? Color.pixfunFocus : .pixfunControlBorder, lineWidth: focused ? 2 : 1))
    }
}
