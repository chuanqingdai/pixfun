import Foundation

/// OSM's is_in query tests actual mapped areas (including multipolygon holes).
/// No radius, POI centre, filename or visual-model guess can prove containment.
enum PlaceBoundaryPolicy {
    struct Response: Decodable { var elements: [Element]; var remark: String? }
    struct Element: Decodable {
        var type: String
        var id: Int64
        var tags: [String: String]?
    }
    struct Match: Equatable {
        var name: String
        var id: String
        var kind: String
        var relation: String
        var city: String? = nil
        var region: String? = nil
    }
    static func query(_ query: PlaceQuery) -> String {
        let point = "\(query.latitude),\(query.longitude)"
        return """
        [out:json][timeout:15][maxsize:16777216];
        is_in(\(point))->.a;
        (area.a["amenity"~"^(university|college|school)$"];
         area.a["leisure"="park"];area.a["boundary"="national_park"];
         area.a["natural"="water"]["water"~"^(lake|reservoir)$"];
         area.a["tourism"="attraction"];
         area.a["boundary"="administrative"]["admin_level"="4"];way.a;)->.inside;
        .inside convert contained ::=::,::id=id(),_osm_type=type();
        out tags;
        (way(around:100,\(point))["natural"="water"]["water"~"^(lake|reservoir)$"];
         rel(around:100,\(point))["natural"="water"]["water"~"^(lake|reservoir)$"];);
        out tags;
        """
    }
    static func kind(_ tags: [String: String]) -> (String, Int)? {
        if ["university", "college", "school"].contains(tags["amenity"] ?? "") { return ("campus", 0) }
        if tags["natural"] == "water", ["lake", "reservoir"].contains(tags["water"] ?? "") { return ("lake", 1) }
        if tags["boundary"] == "national_park" { return ("scenic", 2) }
        if tags["leisure"] == "park" { return ("park", 3) }
        if tags["tourism"] == "attraction" { return ("attraction", 4) }
        return nil
    }
    static func match(_ response: Response, language: String) -> Match? {
        // Timeout responses can contain partial data; partial agreement is not evidence.
        guard response.remark == nil else { return nil }
        let regions = Set(response.elements.compactMap { element -> String? in
            guard element.type == "contained", element.tags?["boundary"] == "administrative",
                  element.tags?["admin_level"] == "4" else { return nil }
            return element.tags?[language == "zh-Hans" ? "name:zh" : "name:en"] ?? element.tags?["name"]
        })
        let candidates: [(Match, Int)] = response.elements.compactMap { element in
            guard element.id > 0, let tags = element.tags, let (kind, priority) = kind(tags),
                  let name = (tags[language == "zh-Hans" ? "name:zh" : "name:en"] ?? tags["name"])?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name.count <= 200 else { return nil }
            let originalType = tags["_osm_type"] ?? element.type
            let inside = element.type == "contained" && ["area", "way"].contains(originalType)
            guard inside || (["way", "relation"].contains(element.type) && kind == "lake") else { return nil }
            return (Match(name: name, id: "\(originalType)/\(element.id)", kind: kind,
                          relation: inside ? "inside" : "nearby", city: tags["addr:city"],
                          region: regions.count == 1 ? regions.first : nil), (inside ? 0 : 100) + priority)
        }
        guard let rank = candidates.map(\.1).min() else { return nil }
        let best = candidates.filter { $0.1 == rank }.map(\.0)
        // Two distinct named campuses/lakes at this point: abstain, never pick first.
        guard Set(best.map(\.name)).count == 1 else { return nil }
        return best.sorted { $0.id < $1.id }.first
    }
    static func applying(_ match: Match, to original: PlaceAddress?, language: String) -> PlaceAddress {
        var address = original ?? PlaceAddress()
        if address.city == nil { address.city = match.city }
        if address.region == nil { address.region = match.region }
        address.area = match.name
        address.boundaryID = match.id
        address.areaRelation = match.relation
        address.placeKind = match.kind
        let chinese = language == "zh-Hans"
        var context = (match.kind == "lake" ? address.region : address.city) ?? address.region ?? ""
        if chinese, context.hasSuffix("市") || context.hasSuffix("省") { context.removeLast() }
        let name = match.name + (match.relation == "nearby" ? (chinese ? "附近" : " vicinity") : "")
        address.displayName = [context, name].filter { !$0.isEmpty }.joined(separator: " ")
        return address
    }
}

/// Serial, bounded pilot access. Production builds must set PixfunBoundaryEndpoint
/// to an operated/contracted Overpass endpoint, not depend on community capacity.
@MainActor final class PlaceBoundaryLookup {
    static let consentKey = "onlinePlaceBoundariesEnabled"
    private let defaults: UserDefaults
    private let session: URLSession
    private var nextRequest = Date.distantPast
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 30
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
    }
    func lookup(_ query: PlaceQuery) async throws -> PlaceBoundaryPolicy.Match? {
        try Task.checkCancellation()
        let now = Date()
        guard now >= nextRequest else { throw URLError(.resourceUnavailable) }
        let day = Int(now.timeIntervalSince1970 / 86400)
        if defaults.integer(forKey: "placeBoundaryRequestDay") != day {
            defaults.set(day, forKey: "placeBoundaryRequestDay")
            defaults.set(0, forKey: "placeBoundaryRequestCount")
        }
        let count = defaults.integer(forKey: "placeBoundaryRequestCount")
        guard count < 100 else { throw URLError(.resourceUnavailable) }
        defaults.set(count + 1, forKey: "placeBoundaryRequestCount")
        nextRequest = now.addingTimeInterval(5)
        let endpoint = Bundle.main.object(forInfoDictionaryKey: "PixfunBoundaryEndpoint") as? String
            ?? "https://overpass-api.de/api/interpreter"
        guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Pixfun/0.7 PlaceBoundaryPilot", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "data", value: PlaceBoundaryPolicy.query(query))]
        request.httpBody = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 1_048_576 else { throw URLError(.dataLengthExceedsMaximum) }
                data.append(byte)
            }
            try Task.checkCancellation()
            let result = try JSONDecoder().decode(PlaceBoundaryPolicy.Response.self, from: data)
            guard result.remark == nil else { throw URLError(.cannotParseResponse) }
            return PlaceBoundaryPolicy.match(result, language: query.language)
        } catch {
            nextRequest = Date().addingTimeInterval(15 * 60)
            throw error
        }
    }
}
