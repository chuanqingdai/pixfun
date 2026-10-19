import Foundation

enum MediaSearchMerge {
    /// Keep exact/text matches first, then add visual-only matches once per file.
    static func combine(text: [MediaSearchResult], visual: [CatalogHit], allowed: [MediaSearchResult]) -> [MediaSearchResult] {
        let items = Dictionary(uniqueKeysWithValues: allowed.map { ($0.id, $0.item) })
        var seen = Set(text.map(\.id))
        return text + visual.compactMap { hit in
            guard let item = items[hit.mediaId], seen.insert(hit.mediaId).inserted else { return nil }
            return MediaSearchResult(item: item, hits: [.init(id: 0, label: "Visual match", text: "Review this moment in the original video", start: hit.start, segmentID: hit.shotId, priority: 100)])
        }
    }
}
// Model types live with Media search so non-UI test targets can use the same contract.
struct CatalogHit: Decodable {
    var mediaId: String
    var shotId: String
    var start: Double
    var end: Double
    var similarity: Double
    var label: String
    var shotStart: Double? = nil
    var boundarySource: String? = nil
}
struct CatalogJob: Decodable {
    var id: String
    var action: String
    var status: String
    var done: Int
    var total: Int
    var message: String
    var hits: [CatalogHit]
    var failures: [String]
}
struct CatalogStatus: Decodable {
    var indexed: Int
    var total: Int
    var stale: Int
    var job: CatalogJob?
}
