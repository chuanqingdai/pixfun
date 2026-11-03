import Foundation

/// Optional OSM geocoding fallback. A reverse result is only a candidate:
/// the original coordinate must be strictly inside its unsimplified geometry.
enum PlacePolygon {
    struct Geometry: Codable {
        var polygons: [[[[Double]]]]
        enum Keys: String, CodingKey { case type, coordinates }
        init(polygons: [[[[Double]]]]) { self.polygons = polygons }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "Polygon": polygons = [try c.decode([[[Double]]].self, forKey: .coordinates)]
            case "MultiPolygon": polygons = try c.decode([[[[Double]]]].self, forKey: .coordinates)
            default: polygons = []
            }
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode("MultiPolygon", forKey: .type)
            try c.encode(polygons, forKey: .coordinates)
        }
        func contains(_ query: PlaceQuery) -> Bool {
            let vertices = polygons.flatMap { $0 }.reduce(0) { $0 + $1.count }
            guard vertices > 0, vertices <= 20_000 else { return false }
            func ring(_ points: [[Double]]) -> Bool? {
                guard points.count >= 4, points.first == points.last,
                      points.allSatisfy({ $0.count == 2 && $0[0].isFinite && $0[1].isFinite &&
                          abs($0[0]) <= 180 && abs($0[1]) <= 90 }) else { return nil }
                var inside = false
                for i in 1..<points.count {
                    let a = points[i-1], b = points[i], x = query.longitude, y = query.latitude
                    // Edge points are uncertain; never manufacture containment.
                    let cross = (x-a[0])*(b[1]-a[1]) - (y-a[1])*(b[0]-a[0])
                    if abs(cross) < 1e-12, x >= min(a[0],b[0]), x <= max(a[0],b[0]),
                       y >= min(a[1],b[1]), y <= max(a[1],b[1]) { return nil }
                    if (a[1] > y) != (b[1] > y),
                       x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0] { inside.toggle() }
                }
                return inside
            }
            for polygon in polygons {
                guard let outer = polygon.first, let contained = ring(outer) else { continue }
                if contained && polygon.dropFirst().allSatisfy({ ring($0) == false }) { return true }
            }
            return false
        }
    }
}

@MainActor final class PlaceFallbackLookup {
    static let consentKey = "onlinePlaceFallbackEnabled"
    private static let cacheKey = "placeBoundaryPolygons.v1"
    typealias Fetch = (URLRequest) async throws -> Data
    struct Result: Decodable {
        var osm_type: String?
        var osm_id: Int64?
        var category: String?
        var type: String?
        var name: String?
        var display_name: String?
        var boundingbox: [String]?
        var address: [String: String]?
        var namedetails: [String: String]?
        var extratags: [String: String]?
        var geojson: PlacePolygon.Geometry?
    }
    struct Cached: Codable {
        var match: PlaceBoundaryPolicy.Match
        var geometry: PlacePolygon.Geometry
        var language: String
        var savedAt: Date
    }
    private let defaults: UserDefaults
    private let fetch: Fetch
    private let interval: TimeInterval
    private var nextRequest = Date.distantPast
    private var cache: [Cached]
    init(defaults: UserDefaults = .standard, interval: TimeInterval = 1.1, fetch: Fetch? = nil) {
        self.defaults = defaults; self.interval = max(0, interval)
        self.cache = defaults.data(forKey: Self.cacheKey).flatMap { try? JSONDecoder().decode([Cached].self, from: $0) } ?? []
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        self.fetch = fetch ?? { request in
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 1_048_576 else { throw URLError(.dataLengthExceedsMaximum) }
                data.append(byte)
            }
            return data
        }
    }
    private func request(_ path: String, _ parameters: [String: String]) async throws -> Data {
        guard defaults.bool(forKey: Self.consentKey) else { throw URLError(.cancelled) }
        let wait = nextRequest.timeIntervalSinceNow
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        try Task.checkCancellation()
        guard defaults.bool(forKey: Self.consentKey) else { throw URLError(.cancelled) }
        let day = Int(Date().timeIntervalSince1970 / 86400)
        if defaults.integer(forKey: "placeFallbackRequestDay") != day {
            defaults.set(day, forKey: "placeFallbackRequestDay"); defaults.set(0, forKey: "placeFallbackRequestCount")
        }
        let count = defaults.integer(forKey: "placeFallbackRequestCount")
        guard count < 30 else { throw URLError(.resourceUnavailable) }
        let base = Bundle.main.object(forInfoDictionaryKey: "PixfunPlaceFallbackEndpoint") as? String
            ?? "https://nominatim.openstreetmap.org"
        guard let url = URL(string: base), url.scheme == "https", url.host != nil,
              var parts = URLComponents(url: url.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        parts.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let target = parts.url else { throw URLError(.badURL) }
        var request = URLRequest(url: target)
        request.setValue("Pixfun/0.2.0 (https://github.com/chuanqingdai/pixfun)", forHTTPHeaderField: "User-Agent")
        defaults.set(count + 1, forKey: "placeFallbackRequestCount")
        nextRequest = Date().addingTimeInterval(interval)
        do { return try await fetch(request) }
        catch { nextRequest = Date().addingTimeInterval(900); throw error }
    }
    private func candidate(_ value: Result, query: PlaceQuery) -> Cached? {
        guard let id = value.osm_id, id > 0, id <= Int64.max - 3_600_000_000,
              let type = value.osm_type, ["way", "relation"].contains(type),
              let category = value.category, let subtype = value.type,
              let geometry = value.geojson, geometry.contains(query) else { return nil }
        let tags = (value.extratags ?? [:]).merging([category: subtype]) { _, new in new }
        guard let (kind, _) = PlaceBoundaryPolicy.kind(tags) else { return nil }
        let names = value.namedetails ?? [:]
        guard let name = (names[query.language == "zh-Hans" ? "name:zh" : "name:en"] ?? names["name"] ?? value.name)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name.count <= 200 else { return nil }
        let address = value.address ?? [:]
        let region = address["state"]
        let declaredCity = address["city"] ?? address["municipality"]
        let city = declaredCity?.hasSuffix("区") == false && declaredCity?.hasSuffix("县") == false ? declaredCity :
            PlaceCaption.city(in: (value.display_name ?? "").components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " · "))
        let genericShort = names["short_name"]
        let localizedShort = names[query.language == "zh-Hans" ? "short_name:zh" : "short_name:en"]
        let short = (localizedShort ?? (query.language != "zh-Hans" || genericShort?.range(of: "\\p{Han}", options: .regularExpression) != nil ? genericShort : nil))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let match = PlaceBoundaryPolicy.Match(name: name, id: type == "relation" ? "area/\(id + 3_600_000_000)" : "way/\(id)",
                                             kind: kind, relation: "inside", city: city, region: region,
                                             shortName: short?.isEmpty == false && (short?.count ?? 201) <= 200 ? short : nil)
        return Cached(match: match, geometry: geometry, language: query.language, savedAt: Date())
    }
    private func select(_ values: [Cached]) -> Cached? {
        let priorities = ["campus":0, "lake":1, "scenic":2, "park":3, "attraction":4]
        guard let rank = values.compactMap({ priorities[$0.match.kind] }).min() else { return nil }
        let best = values.filter { priorities[$0.match.kind] == rank }
        guard Set(best.map { $0.match.name }).count == 1 else { return nil }
        return best.first
    }
    func cachedMatch(_ query: PlaceQuery) -> PlaceBoundaryPolicy.Match? {
        guard defaults.bool(forKey: Self.consentKey) else { return nil }
        cache.removeAll { Date().timeIntervalSince($0.savedAt) >= 30 * 86400 }
        return select(cache.filter { $0.language == query.language && $0.geometry.contains(query) })?.match
    }
    func lookup(_ query: PlaceQuery) async throws -> PlaceBoundaryPolicy.Match? {
        guard defaults.bool(forKey: Self.consentKey) else { return nil }
        if let found = cachedMatch(query) { return found }
        let options = ["format":"jsonv2", "polygon_geojson":"1", "namedetails":"1", "extratags":"1",
                       "addressdetails":"1", "accept-language":query.language]
        let data = try await request("reverse", options.merging(["lat":String(query.latitude), "lon":String(query.longitude), "layer":"poi"]) { _, new in new })
        let reverse = try JSONDecoder().decode(Result.self, from: data)
        var candidates = [candidate(reverse, query: query)].compactMap { $0 }
        var discovered = [reverse]
        if candidates.isEmpty {
            // A parent name only seeds a bounded search; its returned polygon
            // must contain this coordinate. Never adopt the nearest search hit.
            let address = reverse.address ?? [:]
            let parent = ["university", "college", "school"].compactMap { address[$0] }.first
            let city = address["city"] ?? address["state"] ?? ""
            let text = parent.map { $0 + " " + city } ?? "[university]"
            let viewbox = "\(max(-180,query.longitude-0.02)),\(min(90,query.latitude+0.02)),\(min(180,query.longitude+0.02)),\(max(-90,query.latitude-0.02))"
            let search = try await request("search", options.merging(["q":text, "viewbox":viewbox, "bounded":"1", "limit":"3"]) { _, new in new })
            discovered += try JSONDecoder().decode([Result].self, from: search)
            candidates = discovered.compactMap { candidate($0, query: query) }
        }
        if candidates.isEmpty {
            let ids = discovered.compactMap { value -> String? in
                guard value.geojson == nil, let id = value.osm_id, id > 0,
                      let type = value.osm_type, ["way","relation"].contains(type),
                      let category = value.category, let subtype = value.type,
                      PlaceBoundaryPolicy.kind((value.extratags ?? [:]).merging([category:subtype]) { _, new in new }) != nil else { return nil }
                if let raw = value.boundingbox {
                    let box = raw.compactMap(Double.init)
                    guard box.count == 4, box.allSatisfy({ $0.isFinite }), box[0] <= box[1], box[2] <= box[3],
                          (box[0]...box[1]).contains(query.latitude), (box[2]...box[3]).contains(query.longitude) else { return nil }
                }
                return (type == "relation" ? "R" : "W") + String(id)
            }
            if !ids.isEmpty {
                let geometry = try await request("lookup", options.merging(["osm_ids":Array(Set(ids)).sorted().prefix(3).joined(separator:",")]) { _, new in new })
                candidates = try JSONDecoder().decode([Result].self, from: geometry).compactMap { candidate($0, query: query) }
            }
        }
        guard let selected = select(candidates) else { return nil }
        cache.removeAll { $0.match.id == selected.match.id && $0.language == query.language }
        cache.append(selected); cache = Array(cache.suffix(30))
        if let saved = try? JSONEncoder().encode(cache), saved.count <= 2_000_000 { defaults.set(saved, forKey: Self.cacheKey) }
        return selected.match
    }
}
