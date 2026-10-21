import SwiftUI

/// Isolated rendering of the actual page. Does not start a service or import files.
@main struct MediaSyncLayoutTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/pixfun-sync-banner-review", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let working = SyncStorage(id: "working", name: "Samsung T9", path: "/Volumes/Test/Working", connected: true, enabled: true, availableBytes: 2_100_000_000_000)
        let archive = SyncStorage(id: "archive", name: "WD Elements", path: "/Volumes/Test/Archive", connected: false, enabled: true, availableBytes: nil)
        let importing = SyncDevice(id: "card", name: "Canon EOS R5 Mark II", kind: "camera", status: "Importing", message: "DSC_0282.MOV", automatic: true, photos: true, videos: true, connected: true, busy: true, lastSync: nil, completed: 82, total: 136, failed: 0, skipped: 0, bytes: 84_000_000_000, totalBytes: 146_000_000_000)
        let paused = SyncDevice(id: "folder", name: "Travel footage", kind: "external", status: "Paused", message: "Paused. Completed files are kept.", automatic: false, photos: true, videos: true, connected: true, busy: false, lastSync: 1_791_120_000, completed: 8, total: 12, failed: 0, skipped: 2, bytes: 4_000_000_000, totalBytes: 5_000_000_000)
        for (state, width) in [("01-empty", 700.0), ("02-setup", 560.0), ("03-importing", 1040.0), ("04-paused-narrow", 700.0), ("05-archive-error", 700.0), ("06-completed", 700.0), ("07-empty-wide", 1680.0), ("08-verifying", 700.0), ("09-offline", 700.0), ("10-first-setup", 560.0), ("11-discovered", 560.0), ("12-first-discovered", 1040.0), ("13-phone-pairing", 560.0), ("14-phone-offline", 700.0), ("15-phone-copying", 1040.0), ("16-new-sync-inline", 1040.0)] {
            let empty = ["01-empty", "07-empty-wide", "10-first-setup", "12-first-discovered"].contains(state)
            var completed = paused; completed.status = "Completed"; completed.completed = 10; completed.skipped = 2; completed.bytes = completed.totalBytes
            var devices = state == "06-completed" || state == "05-archive-error" ? [completed] : [importing, paused]
            if state == "08-verifying" { var verifying = importing; verifying.status = "Verifying"; verifying.bytes = verifying.totalBytes; devices = [verifying] }
            if state == "09-offline" { var offline = paused; offline.status = "Offline"; offline.connected = false; devices = [offline] }
            if state == "16-new-sync-inline" { devices = [completed] }
            var snapshot = MediaSyncSnapshot(devices: empty ? [] : devices, storage: empty ? [SyncStorage(id: "working", name: "Not configured", connected: false, enabled: false), SyncStorage(id: "archive", name: "Not configured", connected: false, enabled: false)] : [working, archive], available: [], archivePending: empty ? 0 : 10, archiving: false, phoneAvailable: false)
            if state == "05-archive-error" { snapshot.storage[1].connected = true; snapshot.archiveError = "Not Enough Storage. Free some space and retry." }
            if ["11-discovered", "12-first-discovered"].contains(state) { snapshot.available = [SyncDiscoveredSource(id: "card", name: "EOS_CARD", path: "/Volumes/EOS_CARD", kind: "camera"), SyncDiscoveredSource(id: "drive", name: "Travel SSD", path: "/Volumes/Travel SSD", kind: "external")] }
            if state.hasPrefix("13-") || state.hasPrefix("14-") || state.hasPrefix("15-") {
                snapshot.phoneAvailable = true
                snapshot.wifi = SyncWiFi(enabled: true, pairing: state == "13-phone-pairing" ? SyncPhonePairing(payload: #"{"version":1,"endpoint":"https://test-mac.local:12345","fingerprint":"fixture-not-a-real-certificate","secret":"fixture-only"}"#, expiresAt: Date().timeIntervalSince1970 + 300) : nil)
                if state == "13-phone-pairing" {
                    snapshot.phoneImport = BrowserPhoneImport(phase: "waiting", url: "https://import.example.invalid/import#layout-fixture-not-a-live-code", expiresAt: Date().timeIntervalSince1970 + 300)
                }
                var phone = importing; phone.kind = "phone"; phone.name = "My Android phone"
                if state == "14-phone-offline" { phone.status = "Offline"; phone.connected = false; phone.busy = false }
                snapshot.devices = [phone]
            }
            let model = MediaSyncStore(service: LocalService()); model.snapshot = snapshot
            let content: AnyView = state == "13-phone-pairing" ? AnyView(SyncPhoneSetupView(model: model).padding(28)) : state == "02-setup" ? AnyView(SyncSettingsView(model: model, device: nil, discovered: SyncDiscoveredSource(id: "card", name: "EOS_CARD", path: "/Volumes/EOS_CARD", kind: "camera"))) : ["10-first-setup", "11-discovered"].contains(state) ? AnyView(SyncSettingsView(model: model, device: nil, discovered: nil)) : AnyView(MediaSyncView(snapshot: snapshot, creatingSync: state == "16-new-sync-inline"))
            let view = content.font(.pixfun()).foregroundStyle(Color.pixfunInk).tint(.pixfunGold)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .buttonStyle(PixfunButtonStyle()).environment(\.colorScheme, .dark).background(Color.pixfunBackground)
            let host = NSHostingView(rootView: view)
            let rect = NSRect(x: 0, y: 0, width: width, height: state == "16-new-sync-inline" ? 1260 : 900)
            let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host; host.frame = rect; host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(state + ".png"))
            print("Rendered Media Sync \(state)")
        }
    }
}
