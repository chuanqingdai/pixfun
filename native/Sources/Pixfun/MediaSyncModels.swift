import Foundation

struct MediaSyncSnapshot: Decodable {
    var devices: [SyncDevice]
    var storage: [SyncStorage]
    var available: [SyncDiscoveredSource]
    var archivePending: Int
    var archiving: Bool
    var phoneAvailable: Bool
    var archiveError: String? = nil
    var archiveWaiting: Bool? = nil
    var wifi: SyncWiFi? = nil
    var phoneImport: BrowserPhoneImport? = nil
    var working: SyncStorage? { storage.first { $0.id == "working" } }
    var storageBusy: Bool { archiving || devices.contains { $0.busy } || phoneImport?.phase == "uploading" }
}

struct BrowserPhoneImport: Decodable {
    var phase: String
    var url: String? = nil
    var expiresAt: Double? = nil
    var completed: Int? = nil
    var skipped: Int? = nil
    var total: Int? = nil
    var bytes: Int64? = nil
    var totalBytes: Int64? = nil
    var error: String? = nil
    var processed: Int { (completed ?? 0) + (skipped ?? 0) }
}

struct SyncDevice: Decodable, Identifiable {
    var id, name, kind, status, message: String
    var automatic, photos, videos, connected, busy: Bool
    var lastSync: Double?
    var completed, total, failed, skipped: Int
    var bytes, totalBytes: Int64
    var sourcePath: String? = nil
    var readyCount: Int? = nil
    var hasMedia: Bool { (readyCount ?? processed) > 0 }
    var processed: Int { min(total, completed + skipped) }
    var pending: Int { max(0, total - processed - failed) }
    var fraction: Double { totalBytes > 0 ? min(1, max(0, Double(bytes) / Double(totalBytes))) : 0 }
    var method: String { kind == "phone" ? "Wi-Fi sync" : kind == "camera" ? "Card import" : "Folder import" }
    var checking: Bool { status == "Scanning" || status == "Waiting" }
    var showsProgress: Bool { status == "Importing" || status == "Paused" && !busy }
    var needsAttention: Bool { status == "Needs Attention" || status == "Source changed" || status == "Offline" && pending > 0 && !automatic }
    func destinationNeedsAttention(_ storage: SyncStorage?) -> Bool {
        connected && !busy && storage?.connected != true
    }
    func cardTitle(_ storage: SyncStorage?) -> String {
        if destinationNeedsAttention(storage) { return storage?.path == nil ? "Choose save location" : "Save location disconnected" }
        return phaseTitle
    }
    func cardMessage(_ storage: SyncStorage?) -> String {
        if destinationNeedsAttention(storage) {
            return storage?.path == nil ? "Choose where new imports will be saved." : automatic && status != "Paused" ? "Reconnect your save location. New imports will continue automatically." : "Reconnect your save location or choose another folder. Existing files stay where they are."
        }
        return phaseMessage
    }
    var phaseTitle: String {
        switch status {
        case "Connected": return automatic ? "Ready to sync" : "Ready to import"
        case "Waiting": return "Queued"
        case "Waiting for storage": return "Waiting for save location"
        case "Waiting for source": return "Waiting for your card"
        case "Waiting to import": return "Ready to continue automatically"
        case "Scanning": return "Checking for new media"
        case "Importing": return "Importing"
        case "Verifying": return "Verifying copies"
        case "Paused": return busy ? "Pausing…" : "Paused"
        case "Completed": return completed == 0 && failed == 0 ? "Up to date" : "Import complete"
        case "Offline": return kind == "phone" ? "Waiting for phone" : automatic ? "Waiting for your device" : "Disconnected"
        default: return status
        }
    }
    var phaseMessage: String {
        switch status {
        case "Connected": return kind == "phone" ? "Waiting for new media from your phone." : automatic ? "New media imports automatically when this source reconnects." : "Start an import when you’re ready."
        case "Waiting": return "Waiting for the current import to finish."
        case "Waiting for storage": return "Reconnect your save location. Import will continue automatically."
        case "Waiting for source": return "Reconnect this card. Verified files will be skipped."
        case "Waiting to import": return "Import continues when both devices are available. Keep Pixfun running."
        case "Scanning": return "Checking for new files and previously imported copies."
        case "Verifying": return "Checking copied files before adding them to Media."
        case "Paused": return busy ? "Finishing the current step safely…" : "Completed files are kept. Continue when you’re ready."
        case "Offline": return kind == "phone" ? "Connect both devices to the same Wi-Fi and open Pixfun Sync on your phone. Background timing is managed by your phone." : automatic ? "Plug it in to import new files automatically. Saved media stays in your library." : "Reconnect this source to continue. Imported files are kept."
        case "Completed": return total == 0 ? "No supported photos or videos found. Check the source folder and file types." : completed == 0 && failed == 0 ? "No new media to import." : "Verified copies are available in Media."
        default: return message
        }
    }
    var actionLabel: String { status == "Completed" ? "Check for new" : status == "Paused" ? "Continue import" : action }
    var summary: String {
        var parts: [String] = []
        if completed > 0 { parts.append("\(completed) new") }
        if skipped > 0 { parts.append("\(skipped) already imported") }
        if failed > 0 { parts.append("\(failed) failed") }
        if pending > 0 { parts.append("\(pending) pending") }
        return parts.joined(separator: " · ")
    }
    var action: String { status == "Paused" ? "Resume" : status == "Needs Attention" ? "Retry" : "Import" }
}

struct SyncWiFi: Decodable {
    var enabled: Bool
    var error: String?
    var pairing: SyncPhonePairing?
}

struct SyncPhonePairing: Decodable {
    var payload: String
    var expiresAt: Double
}

struct SyncStorage: Decodable, Identifiable {
    var id, name: String
    var path: String?
    var connected, enabled: Bool
    var availableBytes: Int64?
    var title: String { id == "working" ? "Save location" : "Backup location" }
}

struct SyncDiscoveredSource: Decodable, Identifiable {
    var id, name, path: String
    var kind: String? = nil
}

enum SyncFormat {
    static func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
    static func date(_ timestamp: Double) -> String {
        Date(timeIntervalSince1970: timestamp).formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(Locale(identifier: "en")))
    }
}
