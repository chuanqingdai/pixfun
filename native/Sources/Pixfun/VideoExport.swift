import Foundation

struct VideoExportJob: Decodable {
    var id: String
    var runId: String
    var timelineVersion: Int
    var resolution: String
    var status: String
    var message: String
    var completed: Int
    var total: Int
    var width: Int
    var height: Int
    var path: String?
    var busy: Bool { status == "queued" || status == "running" }
    var qualityLabel: String { resolution == "4k" ? "4K" : "1080p" }
}

/// Stream a completed export to a sibling temporary file, then install atomically.
/// Existing destinations are replaced only if unchanged since save-panel approval.
enum VideoExportFiles {
    struct Identity: Equatable {
        let inode: UInt64
        let device: UInt64
        let size: UInt64
        let modified: Date
    }
    static func identity(_ url: URL) throws -> Identity? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw ServiceError(message: "Choose a regular file destination, not a symbolic link.")
            }
            return nil
        }
        let attributes = try fm.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw ServiceError(message: "Choose a regular file destination, not a folder or symbolic link.")
        }
        return Identity(inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                        device: (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
                        size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                        modified: attributes[.modificationDate] as? Date ?? .distantPast)
    }
    static func protect(_ destination: URL, originals: [URL]) throws {
        let target = destination.resolvingSymlinksInPath().standardizedFileURL.path
        let current = try identity(destination)
        for original in originals {
            let samePath = original.resolvingSymlinksInPath().standardizedFileURL.path == target
            let other = try? identity(original)
            let sameFile = current != nil && other != nil && current!.inode == other!.inode && current!.device == other!.device
            if samePath || sameFile { throw ServiceError(message: "Choose a different destination. Original media cannot be overwritten.") }
        }
    }
    static func install(source: URL, destination: URL, expected: Identity?, originals: [URL]) throws {
        try protect(destination, originals: originals + [source])
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".pixfun-export-\(UUID().uuidString).mp4")
        let fm = FileManager.default
        defer { try? fm.removeItem(at: temporary) }
        try fm.copyItem(at: source, to: temporary)
        try protect(destination, originals: originals + [source])
        guard try identity(destination) == expected else {
            throw ServiceError(message: "The destination changed during export. Export again or choose another filename; the existing file is kept.")
        }
        if expected == nil { try fm.moveItem(at: temporary, to: destination) }
        else { _ = try fm.replaceItemAt(destination, withItemAt: temporary) }
    }
}
