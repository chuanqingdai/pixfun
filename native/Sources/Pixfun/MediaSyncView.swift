import SwiftUI
import AppKit

@MainActor
final class MediaSyncStore: ObservableObject {
    @Published var snapshot: MediaSyncSnapshot?
    @Published var error: String?
    @Published var saving = false
    @Published var discovering = false
    private let service: LocalService
    private var revision = 0
    private var refreshFailed = false
    init(service: LocalService) { self.service = service }

    func refresh() async {
        guard !saving, !discovering else { return }
        let current = revision
        do {
            let result: MediaSyncSnapshot = try await service.get("/api/desktop/sync", native: true)
            guard current == revision, !saving else { return }
            snapshot = result
            if refreshFailed { self.error = nil; refreshFailed = false }
        } catch { if !Task.isCancelled && current == revision { self.error = error.localizedDescription; refreshFailed = true } }
    }

    @discardableResult func perform(_ payload: [String: Any]) async -> Bool {
        guard !saving else { return false }
        revision += 1; saving = true; error = nil; refreshFailed = false
        defer { saving = false }
        do {
            snapshot = try await service.post("/api/desktop/sync", payload, native: true)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func discoverSources() async {
        guard !saving, !discovering else { return }
        revision += 1
        let current = revision
        discovering = true
        defer { discovering = false }
        do {
            let result: MediaSyncSnapshot = try await service.post("/api/desktop/sync", ["action": "discover"], native: true)
            guard current == revision, !saving else { return }
            snapshot = result
            error = nil
        } catch {
            if current == revision, !saving, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    static func chooseFolder(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        let bundle = Bundle.main.path(forResource: AppLanguage.saved.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        panel.prompt = bundle.localizedString(forKey: "Choose", value: nil, table: nil)
        panel.message = bundle.localizedString(forKey: message, value: nil, table: nil)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private struct SyncSetup: Identifiable {
    var id = UUID()
    var device: SyncDevice?
    var discovered: SyncDiscoveredSource?
}

struct MediaSyncView: View {
    @StateObject private var model: MediaSyncStore
    @State private var setup: SyncSetup?
    @State private var storageExpanded = false
    @State private var creatingSync = false
    private var polling = true
    private var showMedia: ((String, String) -> Void)?
    init(service: LocalService, showMedia: ((String, String) -> Void)? = nil) {
        _model = StateObject(wrappedValue: MediaSyncStore(service: service)); self.showMedia = showMedia
    }
#if PIXFUN_LAYOUT_TEST
    init(snapshot: MediaSyncSnapshot, creatingSync: Bool = false) {
        let model = MediaSyncStore(service: LocalService())
        model.snapshot = snapshot
        _model = StateObject(wrappedValue: model)
        _creatingSync = State(initialValue: creatingSync)
        polling = false
        showMedia = { _, _ in }
    }
#endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 20) {
                    PageHeading(title: "Media Sync", subtitle: "Import new photos and videos. Keep your originals.")
                    Spacer(minLength: 0)
                }
                if model.snapshot?.devices.isEmpty != false { SyncFlowOverview() }
                if let error = model.error, setup == nil, !creatingSync, model.snapshot == nil || model.snapshot?.devices.isEmpty == false {
                    HStack(alignment: .top) {
                        Label(error, systemImage: "exclamationmark.circle").font(.pixfun(13))
                        Spacer()
                        Button("Dismiss") { model.error = nil }.buttonStyle(PixfunButtonStyle(kind: .quiet))
                    }.foregroundStyle(Color.pixfunGold)
                }
                if let snapshot = model.snapshot {
                    if snapshot.devices.isEmpty {
                        SyncSettingsView(model: model, device: nil, discovered: nil, embedded: true)
                    } else {
                        devices(snapshot)
                        if creatingSync {
                            SyncSettingsView(model: model, device: nil, discovered: nil, embedded: true,
                                onClose: { creatingSync = false }, onSaved: { creatingSync = false })
                        } else {
                            Button { creatingSync = true } label: {
                                Label("New Sync", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(model.saving)
                        }
                        storage(snapshot)
                    }
                } else {
                    if model.error == nil { ProgressView("Loading Media Sync…") }
                    else { Button("Retry") { Task { model.error = nil; await model.refresh() } } }
                }
            }.frame(maxWidth: 800, alignment: .leading).padding(PixfunLayout.pageInset)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color.pixfunBackground)
        .task {
            guard polling else { return }
            while !Task.isCancelled {
                await model.refresh()
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { break }
            }
        }
        .sheet(item: $setup) { value in
            SyncSettingsView(model: model, device: value.device, discovered: value.discovered)
        }
    }

    private func devices(_ snapshot: MediaSyncSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !snapshot.devices.isEmpty { Text("Your syncs").font(.pixfun(17, semibold: true)) }
            ForEach(snapshot.devices) { device in deviceCard(device, snapshot: snapshot) }
        }
    }

    private func deviceCard(_ device: SyncDevice, snapshot: MediaSyncSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: device.kind == "phone" ? "iphone" : device.kind == "camera" ? "sdcard" : "externaldrive")
                    .font(.system(size: 20)).foregroundStyle(Color.pixfunGold).frame(width: 28, height: 32)
                VStack(alignment: .leading, spacing: 5) {
                    Text(device.name).font(.pixfun(15, semibold: true))
                        .help(device.sourcePath ?? device.name)
                    Text(device.method + (device.kind == "phone" ? (device.automatic ? " · Automatic" : " · Paused") : device.automatic ? " · Auto-import on connection" : " · Manual import"))
                        .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                }
                Spacer()
                Text(device.cardTitle(snapshot.working)).font(.pixfun(12, semibold: true))
                    .foregroundStyle(device.needsAttention || device.busy || device.destinationNeedsAttention(snapshot.working) ? Color.pixfunGold : .pixfunMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.turn.down.right").foregroundStyle(Color.pixfunGold)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Save new imports to · " + (snapshot.working?.name ?? "Not configured"))
                        .font(.pixfun(12, semibold: true)).foregroundStyle(Color.pixfunMuted)
                    if let path = snapshot.working?.path {
                        Text(path).font(.pixfun(11)).foregroundStyle(Color.pixfunSubtle)
                            .lineLimit(1).truncationMode(.middle).help(path).textSelection(.enabled)
                    }
                }
            }.accessibilityElement(children: .combine)
            if device.checking || device.status == "Verifying" || device.status == "Paused" && device.busy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(device.phaseMessage).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                }.accessibilityElement(children: .combine)
            } else if device.showsProgress && device.total > 0 {
                HStack {
                    Text("\(device.processed) / \(device.total) files ready")
                    Spacer()
                    if device.totalBytes > 0 { Text("\(Int(device.fraction * 100))% copied") }
                }.font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).monospacedDigit()
                if device.totalBytes > 0 {
                    ProgressView(value: device.fraction).accessibilityLabel("Import progress for \(device.name)")
                }
            } else if !device.summary.isEmpty {
                Text(device.summary).font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
            }
            if !device.busy && !device.checking && (device.status != "Completed" || device.completed == 0 || device.destinationNeedsAttention(snapshot.working)) {
                Text(device.cardMessage(snapshot.working)).font(.pixfun(12)).foregroundStyle(device.needsAttention || device.destinationNeedsAttention(snapshot.working) ? Color.pixfunGold : .pixfunMuted).fixedSize(horizontal: false, vertical: true)
            }
            if device.total > 0 && device.status != "Completed" {
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(SyncFormat.bytes(device.bytes)) / \(SyncFormat.bytes(device.totalBytes)) copied")
                        Text(device.summary)
                        if let path = device.sourcePath { Text("Source · " + path).textSelection(.enabled) }
                        if device.status == "Importing" { Text(device.message).lineLimit(2) }
                    }.font(.pixfun(12)).foregroundStyle(Color.pixfunSubtle).padding(.top, 6)
                }.font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
            }
            HStack {
                if !device.busy, let time = device.lastSync {
                    Text("Last import: \(SyncFormat.date(time))")
                        .font(.pixfun(12)).foregroundStyle(Color.pixfunSubtle)
                }
                Spacer(minLength: 6)
                if device.hasMedia, let showMedia {
                    Button("View Media") { showMedia(device.id, device.name) }
                        .buttonStyle(PixfunButtonStyle(kind: device.status == "Completed" ? .primary : .quiet))
                }
                if device.destinationNeedsAttention(snapshot.working) {
                    Button("Choose Save Location") { chooseStorage("working") }.disabled(model.saving || snapshot.storageBusy)
                } else if device.kind == "phone" {
                    Button(LocalizedStringKey(device.automatic ? "Pause" : "Resume")) { action(device.automatic ? "phonePause" : "phoneResume", device.id) }
                        .disabled(model.saving)
                } else if device.busy {
                    Button(LocalizedStringKey(device.status == "Paused" ? "Pausing…" : "Pause")) { action("pause", device.id) }
                        .disabled(model.saving || device.status == "Paused")
                } else if device.connected && snapshot.working?.connected == true {
                    Button(device.actionLabel) { action(device.action == "Import" ? "start" : device.action.lowercased(), device.id) }
                        .buttonStyle(PixfunButtonStyle(kind: device.status == "Completed" ? .quiet : .primary)).disabled(model.saving)
                        .help("Checks the source; verified files are skipped, not copied again")
                }
                if !device.busy {
                    Menu {
                        if device.kind == "phone" {
                            Button("Unpair Phone") { action("phoneRemove", device.id) }
                        } else {
                            Button("Source Settings…") { setup = SyncSetup(device: device) }
                        }
                    } label: { Image(systemName: "ellipsis").frame(width: 22, height: 28) }
                        .menuStyle(.borderlessButton).fixedSize().disabled(model.saving)
                        .accessibilityLabel("Options for \(device.name)")
                }
            }
        }.syncCard()
    }

    private func storage(_ snapshot: MediaSyncSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let wifi = snapshot.wifi, wifi.enabled || snapshot.devices.contains(where: { $0.kind == "phone" }) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Receive from paired phones over Wi-Fi", isOn: Binding(get: { wifi.enabled }, set: { enabled in
                        Task { await model.perform(["action": enabled ? "phoneEnable" : "phoneDisable"]) }
                    })).toggleStyle(.switch).font(.pixfun(13)).disabled(model.saving)
                    if let error = wifi.error { Text(error).font(.pixfun(12)).foregroundStyle(Color.pixfunGold) }
                }
            }
            DisclosureGroup(isExpanded: $storageExpanded) {
              VStack(spacing: 0) {
                ForEach(snapshot.storage) { location in
                    if location.id == "archive" { Divider().overlay(Color.pixfunLine).padding(.vertical, 18) }
                    HStack(alignment: .center, spacing: 16) {
                        Image(systemName: location.id == "working" ? "externaldrive" : "archivebox")
                            .font(.system(size: 20)).foregroundStyle(Color.pixfunSubtle).frame(width: 28)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(location.title).font(.pixfun(14, semibold: true))
                            Text(storageDetail(location)).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                                .help(location.path ?? "")
                            if location.id == "archive", location.path != nil {
                                Toggle("Back up automatically", isOn: Binding(get: { location.enabled }, set: { enabled in
                                    Task { await model.perform(["action": "archiveEnabled", "enabled": enabled]) }
                                })).toggleStyle(.switch).controlSize(.small).font(.pixfun(12)).disabled(model.saving)
                            }
                        }
                        Spacer()
                        Button(LocalizedStringKey(location.path == nil ? "Choose" : "Change")) { chooseStorage(location.id) }
                            .accessibilityLabel(location.id == "working" ? "Choose save location" : "Choose backup location")
                            .disabled(model.saving || snapshot.storageBusy)
                            .help(snapshot.storageBusy ? "Pause imports and wait for the current archive copy before changing storage" : "Choose a folder")
                    }
                }
                if let archive = snapshot.storage.first(where: { $0.id == "archive" }), archive.path != nil, snapshot.archivePending > 0 {
                    if snapshot.archiveWaiting == true, archive.enabled {
                        Text("Waiting for your drives. Backup continues automatically when they reconnect.")
                            .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                    } else if let message = snapshot.archiveError, archive.enabled {
                        Text(message + " Working copies are still available in Media.")
                            .font(.pixfun(12)).foregroundStyle(Color.pixfunGold).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
                    }
                    HStack {
                        Text(LocalizedStringKey(snapshot.archiving ? "Archiving in the background…" : "\(snapshot.archivePending) files awaiting archive" ))
                            .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                        Spacer()
                        if !snapshot.archiving && archive.connected && archive.enabled {
                            Button("Retry") { Task { await model.perform(["action": "archive"]) } }.disabled(model.saving)
                        }
                    }.padding(.top, 16)
                }
              }.syncCard().padding(.top, 10)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Storage & backup").font(.pixfun(17, semibold: true))
                    Text("Changes apply to future imports. Existing files stay where they are.")
                        .font(.pixfun(12)).foregroundStyle(Color.pixfunSubtle)
                }
            }
            if let working = snapshot.working {
                Text("Save to · " + storageDetail(working)).font(.pixfun(12))
                    .foregroundStyle(working.connected ? Color.pixfunMuted : .pixfunGold)
            }
            if !storageExpanded, let backup = snapshot.storage.first(where: { $0.id == "archive" }), backup.path != nil, backup.enabled, snapshot.archivePending > 0 {
                HStack {
                    Text(LocalizedStringKey(snapshot.archiveWaiting == true ? "Waiting for drives. Backup resumes when connected." : snapshot.archiveError != nil ? "Backup needs attention. Imported media is available." : snapshot.archiving ? "Backing up in the background…" : "\(snapshot.archivePending) files awaiting backup. Imported media is available."))
                        .font(.pixfun(12)).foregroundStyle(snapshot.archiveError != nil ? Color.pixfunGold : .pixfunMuted)
                    Spacer()
                    Button("Details") { storageExpanded = true }.buttonStyle(PixfunButtonStyle(kind: .quiet))
                }
            }
        }
    }

    private func storageDetail(_ storage: SyncStorage) -> String {
        guard storage.path != nil else { return storage.id == "working" ? "Choose where imported media is saved" : "Optional · Keep a second copy" }
        guard storage.connected else { return storage.name + " · Offline" }
        return storage.name + (storage.availableBytes.map { " · \(SyncFormat.bytes($0)) available" } ?? "")
    }
    private func chooseStorage(_ kind: String) {
        guard let url = MediaSyncStore.chooseFolder(message: kind == "working" ? "Choose where Pixfun saves imported media." : "Choose a separate folder for your archive copies.") else { return }
        Task { await model.perform(["action": "storage", "kind": kind, "path": url.path]) }
    }
    private func action(_ name: String, _ id: String) { Task { await model.perform(["action": name, "id": id]) } }
}

struct SyncSettingsView: View {
    @ObservedObject var model: MediaSyncStore
    let device: SyncDevice?
    let discovered: SyncDiscoveredSource?
    var embedded = false
    var onClose: (() -> Void)? = nil
    var onSaved: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var path: String?
    @State private var kind = "camera"
    @State private var automatic = true
    @State private var photos = true
    @State private var videos = true
    @State private var workingPath: String?
    @State private var optionsExpanded = false
    @State private var choosingSource = false
    @State private var initialPhoneIDs: Set<String> = []
    private var sources: [SyncDiscoveredSource] { model.snapshot?.available ?? [] }
    private var resolvedName: String {
        let custom = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? String((path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? device?.name ?? "").prefix(80)) : custom
    }
    private var destination: String? { workingPath ?? model.snapshot?.working?.path }
    private var destinationAvailable: Bool { workingPath != nil || model.snapshot?.working?.connected == true }
    private var validation: String? {
        if device == nil && path == nil { return "Choose a card or folder to import from." }
        if resolvedName.isEmpty { return "Choose a card or folder to import from." }
        if name.count > 80 { return "Use a name up to 80 characters." }
        if !photos && !videos { return "Select photos, videos, or both." }
        if device == nil && !destinationAvailable { return "Choose a connected save location before importing." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(device != nil ? "Sync Settings" : model.snapshot?.devices.isEmpty == true ? "Create your first sync" : "Create a new sync"))
                    .font(.system(size: embedded ? 15 : 20, weight: .semibold))
                if embedded {
                    Text("Choose a source and save location. Pixfun remembers them for future imports.")
                        .font(.pixfun(13)).foregroundStyle(Color.pixfunMuted)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                if device == nil {
                    sourceSection
                } else if let device {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Import from").font(.pixfun(13, semibold: true))
                        Label(device.name, systemImage: device.kind == "camera" ? "sdcard" : "externaldrive")
                            .font(.pixfun(14, semibold: true))
                    }
                }
                if kind == "phone" {
                    SyncPhoneSetupView(model: model)
                } else {
                    destinationSection
                    importOptionsSection
                }
            }
            if kind != "phone" {
            if let error = model.error { Text(error).font(.pixfun(12)).foregroundStyle(Color.pixfunGold).fixedSize(horizontal: false, vertical: true) }
            else if let validation, path != nil || device != nil { Text(LocalizedStringKey(validation)).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if let device {
                    Button("Remove Source") {
                        Task { if await model.perform(["action": "remove", "id": device.id]) { dismiss() } }
                    }.help("Remove this configuration only. Originals and imported files are kept.")
                }
                Spacer()
                if !embedded || onClose != nil {
                    Button("Cancel") { if let onClose { onClose() } else { dismiss() } }.keyboardShortcut(.cancelAction)
                }
                Button { save() } label: {
                    HStack(spacing: 10) {
                        if model.saving { ProgressView().controlSize(.small) }
                        else { Image(systemName: device == nil ? "arrow.triangle.2.circlepath" : "checkmark").font(.system(size: 15, weight: .semibold)).accessibilityHidden(true) }
                        Text(LocalizedStringKey(model.saving ? "Saving…" : device == nil ? "Create Sync & Import" : "Save Changes"))
                    }
                }
                    .buttonStyle(.borderedProminent).controlSize(.regular).keyboardShortcut(.defaultAction)
                    .disabled(validation != nil)
                    .help(validation ?? "Save this sync and import new media. Originals stay untouched.")
                    .accessibilityHint(validation ?? "Saves this sync configuration.")
            }
            } else if !embedded || onClose != nil {
                HStack { Spacer(); Button("Done") { if let onClose { onClose() } else { dismiss() } } }
            }
        }.padding(embedded ? 0 : 24).frame(width: embedded ? nil : 520)
            .frame(maxWidth: embedded ? .infinity : nil, alignment: .leading)
            .buttonStyle(.bordered)
            .disabled(model.saving).interactiveDismissDisabled(model.saving)
            .onAppear {
                model.error = nil
                name = device?.name ?? discovered?.name ?? ""; path = discovered?.path
                kind = device?.kind ?? discovered?.kind ?? "external"; automatic = device?.automatic ?? true
                photos = device?.photos ?? true; videos = device?.videos ?? true
                initialPhoneIDs = Set(model.snapshot?.devices.filter { $0.kind == "phone" }.map(\.id) ?? [])
            }
            .onChange(of: model.snapshot?.devices.filter { $0.kind == "phone" }.map(\.id)) { ids in
                // Pairing finishes asynchronously; collapse the same creation form on success.
                if kind == "phone", let ids, ids.contains(where: { !initialPhoneIDs.contains($0) }) {
                    onSaved?()
                    if !embedded { dismiss() }
                }
            }
            .task {
#if !PIXFUN_LAYOUT_TEST
                if device == nil { await model.discoverSources() }
#endif
            }
    }
    private var sourceSection: some View {
                  VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center) {
                            Text("Media source").font(.pixfun(13, semibold: true))
                            Spacer(minLength: 16)
                            Button { Task { await model.discoverSources() } } label: {
                                Label(LocalizedStringKey(model.discovering ? "Checking…" : "Refresh"), systemImage: "arrow.clockwise")
                            }.buttonStyle(.bordered).controlSize(.small).disabled(model.discovering || model.saving)
                                .accessibilityLabel("Refresh connected devices")
                        }
                        if path == nil && kind != "phone" {
                            Text(LocalizedStringKey(model.discovering ? "Looking for connected cards and drives…" : sources.isEmpty ? "No connected cards or drives found. Connect one and refresh, or choose a local folder." : "Choose a connected card or drive below. Its name is filled in automatically."))
                                .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button { choosingSource.toggle() } label: {
                        SyncSelectionLabel(title: kind == "phone" ? "Import from phone" : path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Select a device or folder",
                                           symbol: kind == "phone" ? "iphone" : kind == "camera" ? "sdcard" : "externaldrive",
                                           accessory: choosingSource ? "chevron.up" : "chevron.down", prominent: true)
                    }.buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Select connected device or local folder")
                        .accessibilityValue(kind == "phone" ? "Import from phone" : path ?? "No source selected")
                        .accessibilityHint("Opens source choices. Select a connected device, a folder, or an available phone connection.")
                        .help(path ?? "Choose where to import photos and videos from")
                        .popover(isPresented: $choosingSource, arrowEdge: .bottom) { sourceChoices }
                  }.syncFormGroup()
    }

    private var destinationSection: some View {
                VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Save location").font(.pixfun(13, semibold: true))
                    Text("Save verified copies to your Mac or external drive. Shared by all sources; originals stay on your devices.")
                        .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).fixedSize(horizontal: false, vertical: true)
                    if workingPath != nil && model.snapshot?.working?.path != nil {
                        Text("This updates the save location for future imports from all sources. Existing files stay in place.")
                            .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                SyncSaveLocationCard(destination: destination, available: destinationAvailable,
                                     choosingDisabled: model.snapshot?.storageBusy == true) {
                    guard let url = MediaSyncStore.chooseFolder(message: "Choose where Pixfun saves verified copies. Shared by all sources; originals stay unchanged.") else { return }
                    workingPath = url.path
                }
                }.syncFormGroup()
    }

    private var importOptionsSection: some View {
                VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Import new media when connected").font(.system(size: 13, weight: .medium))
                        Text("Keep Pixfun running and your Mac awake. Completed files are skipped; originals stay on your device.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Toggle("Import new media when connected", isOn: $automatic)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .accessibilityIdentifier("sync.automatic")
                }
                Divider()
                DisclosureGroup("Advanced options", isExpanded: $optionsExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("RAW import is not supported.")
                            .font(.pixfun(12)).foregroundStyle(Color.pixfunSubtle)
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                            if device != nil || path != nil {
                                GridRow {
                                    Text("Display name").foregroundStyle(Color.pixfunMuted).frame(width: 88, alignment: .leading)
                                    TextField("Display name", text: $name).textFieldStyle(.roundedBorder)
                                        .controlSize(.large).frame(width: 240)
                                        .accessibilityLabel("Optional display name")
                                }
                            }
                            GridRow {
                                Text("Source type").foregroundStyle(Color.pixfunMuted).frame(width: 88, alignment: .leading)
                                Picker("Source type", selection: $kind) {
                                    Text("Card / camera").tag("camera")
                                    Text("Drive / folder").tag("external")
                                }.labelsHidden().pickerStyle(.menu)
                                    .frame(width: 240).accessibilityLabel("Source type")
                                    .accessibilityValue(kind == "camera" ? "Card / camera" : "Drive / folder")
                            }
                            GridRow {
                                Text("Media types").foregroundStyle(Color.pixfunMuted).frame(width: 88, alignment: .leading)
                                HStack(spacing: 24) {
                                    Toggle("Photos", isOn: $photos)
                                    Toggle("Videos", isOn: $videos)
                                }.toggleStyle(.checkbox).frame(minHeight: 30, alignment: .leading)
                                    .accessibilityElement(children: .contain).accessibilityLabel("Media types to import")
                            }
                        }.font(.pixfun(12)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.font(.system(size: 13))
                }.syncFormGroup()
    }

    private var sourceChoices: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !sources.isEmpty {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(sources) { source in
                            sourceChoice(source.name, symbol: source.kind == "camera" ? "sdcard" : "externaldrive",
                                         selected: path == source.path) {
                                choosingSource = false
                                selectSource(source.path, name: source.name, kind: source.kind ?? "external")
                            }.help(source.path)
                        }
                    }
                }.frame(height: min(CGFloat(sources.count) * 50 - 6, 244))
                Divider()
            }
            sourceChoice("Choose a folder…", symbol: "folder", selected: false, detail: "Cards, drives or local folders") {
                choosingSource = false
                // Let the popover dismiss before presenting the system folder picker.
                Task { @MainActor in
                    await Task.yield()
                    chooseSourceFolder()
                }
            }
            if model.snapshot?.phoneAvailable == true {
                sourceChoice("Import from phone", symbol: "iphone", selected: kind == "phone", detail: "Scan to choose files. No app needed.") {
                    choosingSource = false
                    kind = "phone"; path = nil
                }
            }
        }.padding(8).frame(width: 376)
            .background(Color.pixfunSidebar, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.pixfunLine, lineWidth: 1))
    }
    private func sourceChoice(_ title: String, symbol: String, selected: Bool, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol).font(.system(size: 19, weight: .regular)).frame(width: 28)
                    .foregroundStyle(selected ? Color.pixfunGold : .pixfunMuted).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(LocalizedStringKey(title)).font(.pixfun(13, semibold: true)).foregroundStyle(Color.pixfunInk)
                        .lineLimit(1).truncationMode(.middle)
                    if let detail {
                        Text(LocalizedStringKey(detail)).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.pixfunGold)
                    .frame(width: 18).opacity(selected ? 1 : 0).accessibilityHidden(true)
            }.padding(.horizontal, 12).padding(.vertical, detail == nil ? 8 : 12)
                .frame(maxWidth: .infinity, minHeight: detail == nil ? 44 : 68, alignment: .leading)
        }.buttonStyle(SyncSourceChoiceStyle(selected: selected))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private func selectSource(_ sourcePath: String, name sourceName: String, kind sourceKind: String) {
        path = sourcePath
        name = String(sourceName.prefix(80))
        kind = sourceKind
    }
    private func chooseSourceFolder() {
        guard let url = MediaSyncStore.chooseFolder(message: "Choose a folder containing your media. Originals will be kept.") else { return }
        selectSource(url.path, name: url.lastPathComponent, kind: "external")
    }
    private func save() {
        guard validation == nil else { return }
        var payload: [String: Any] = ["action": "configure", "name": resolvedName, "kind": kind, "automatic": automatic, "photos": photos, "videos": videos, "importNow": device == nil]
        if let device { payload["id"] = device.id } else { payload["path"] = path }
        if let workingPath { payload["workingPath"] = workingPath }
        Task {
            if await model.perform(payload) {
                onSaved?()
                if !embedded { dismiss() }
            }
        }
    }
}

/// Source rows are choices, not competing primary actions.
private struct SyncSourceChoiceStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, selected: selected)
    }
    private struct Row: View {
        let configuration: ButtonStyle.Configuration
        let selected: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        @State private var hovered = false
        var body: some View {
            configuration.label
                .background(enabled && (hovered || configuration.isPressed) ? Color.pixfunHover : selected ? .pixfunRaised : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.pixfunFocus : .clear, lineWidth: 2))
                .opacity(enabled ? 1 : 0.5)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onHover { hovered = $0 }
        }
    }
}

/// The path is information; only the explicitly labelled button opens the picker.
struct SyncSaveLocationCard: View {
    let destination: String?
    let available: Bool
    let choosingDisabled: Bool
    let choose: () -> Void

    private var storageDescription: String {
        guard let destination else { return "Mac or external drive" }
        let url = URL(fileURLWithPath: destination)
        let volume = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeIsInternalKey, .volumeIsLocalKey])
        if volume?.volumeIsInternal == true { return "Stored on this Mac" }
        if volume?.volumeIsInternal == false, volume?.volumeIsLocal == true {
            return "External drive" + (volume?.volumeName.map { " · " + $0 } ?? "")
        }
        let components = url.pathComponents
        return components.count > 2 && components[1] == "Volumes" ? "Storage · " + components[2] : "Selected storage"
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) { location; changeButton }
            VStack(alignment: .leading, spacing: 14) { location; changeButton }
        }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var location: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "folder").font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.pixfunGold).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(LocalizedStringKey(destination.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No save folder selected"))
                    .font(.pixfun(14, semibold: true)).lineLimit(1).truncationMode(.middle)
                Text(LocalizedStringKey(storageDescription)).font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                if let destination {
                    Text(destination).font(.pixfun(11)).foregroundStyle(Color.pixfunSubtle)
                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(destination)
                    if !available {
                        Text("Disconnected — reconnect this storage or choose another folder.")
                            .font(.pixfun(12)).foregroundStyle(Color.pixfunGold)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var changeButton: some View {
        Button(LocalizedStringKey(destination == nil ? "Choose Save Folder…" : "Change Folder…"), action: choose)
            .buttonStyle(.bordered).controlSize(.regular).fixedSize()
            .disabled(choosingDisabled)
            .help("Choose where Pixfun saves new imports. Existing files stay in place.")
    }
}

private struct SyncFlowOverview: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .syncFlowIcon, spacing: 12) {
                sourceGroup.frame(minWidth: 190, maxWidth: .infinity)
                flowArrow("arrow.right")
                process.frame(minWidth: 190, maxWidth: .infinity)
                flowArrow("arrow.right")
                destinations.frame(minWidth: 190, maxWidth: .infinity)
            }
            VStack(spacing: 16) {
                sourceGroup
                flowArrow("arrow.down")
                process
                flowArrow("arrow.down")
                destinations
            }.frame(maxWidth: .infinity)
        }.padding(.horizontal, 20).padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Import from your devices. Scan a QR code for a one-time phone import, or connect a camera or drone memory card. Auto-sync new files from connected cards and folders you set up. Save copies to your Mac or an external drive. Originals stay untouched.")
    }

    private var sourceGroup: some View {
        stage("Import from your devices", detail: "Phone via QR\nCamera & drone via card") {
            HStack(spacing: 18) {
                Image(systemName: "iphone").frame(width: 28)
                Image(systemName: "camera").frame(width: 32)
                SyncDroneIcon().frame(width: 30, height: 30)
            }
        }
    }

    private var process: some View {
        stage("Auto-sync new files", detail: "From connected cards\nand folders you set up") {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 28, weight: .light))
                .frame(width: 52, height: 52)
                .background(Color.pixfunBrandSoft, in: Circle())
        }
    }

    private var destinations: some View {
        stage("Save to your storage", detail: "Your Mac or external drive\nOriginals stay untouched") {
            HStack(spacing: 22) {
                Image(systemName: "laptopcomputer")
                Image(systemName: "externaldrive")
            }
        }
    }

    private func stage<Icon: View>(_ title: String, detail: String, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 8) {
            icon().font(.system(size: 27, weight: .light))
                .foregroundStyle(Color.pixfunGold).frame(height: 52)
            VStack(spacing: 6) {
                Text(LocalizedStringKey(title)).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.pixfunInk)
                Text(LocalizedStringKey(detail)).font(.system(size: 12)).lineSpacing(2).foregroundStyle(Color.pixfunMuted)
            }.fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).multilineTextAlignment(.center)
            .alignmentGuide(.syncFlowIcon) { $0[VerticalAlignment.top] + 26 }
    }

    private func flowArrow(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 14, weight: .light))
            .foregroundStyle(Color.pixfunSubtle).frame(width: 20, height: 20)
            .alignmentGuide(.syncFlowIcon) { $0[VerticalAlignment.center] }
            .accessibilityHidden(true)
    }
}

private extension VerticalAlignment {
    struct SyncFlowIconAlignment: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[VerticalAlignment.center] }
    }
    static let syncFlowIcon = VerticalAlignment(SyncFlowIconAlignment.self)
}

/// Repo-native line icon; does not require a new bitmap asset or SF Symbols version.
/// Shared simplified outline used by Media Sync and the Library welcome flow.
struct SyncDroneIcon: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Path { path in
                    let arms: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(5, 5, 9, 9), (19, 5, 15, 9), (5, 19, 9, 15), (19, 19, 15, 15)]
                    for (x, y, endX, endY) in arms {
                        path.move(to: CGPoint(x: side * x / 24, y: side * y / 24))
                        path.addLine(to: CGPoint(x: side * endX / 24, y: side * endY / 24))
                    }
                }.stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                Path { path in
                    let rotors: [(CGFloat, CGFloat)] = [(2, 5), (16, 5), (2, 19), (16, 19)]
                    for (x, y) in rotors {
                        path.move(to: CGPoint(x: side * x / 24, y: side * y / 24))
                        path.addLine(to: CGPoint(x: side * (x + 6) / 24, y: side * y / 24))
                    }
                }.stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                RoundedRectangle(cornerRadius: side / 24).stroke(lineWidth: 1.3)
                    .frame(width: side * 0.25, height: side * 0.25)
            }
        }
    }
}

private extension View {
    func syncFormGroup() -> some View {
        self.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 10))
    }
    func syncCard() -> some View {
        self.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.pixfunLine))
    }
}
