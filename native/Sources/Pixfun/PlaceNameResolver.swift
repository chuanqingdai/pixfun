import Foundation
import CoreLocation

/// Only the coordinate and preferred language cross the network boundary.
struct PlaceQuery: Hashable {
    let latitude: Double
    let longitude: Double
    let language: String
    init?(_ location: CaptureLocation, language: String) {
        guard location.coordinates != nil, let latitude = location.latitude, let longitude = location.longitude else { return nil }
        self.latitude = latitude; self.longitude = longitude; self.language = language
    }
    // Exact coordinates, not rounded tiles: adjacent streets must not share a name.
    var key: String { "\(latitude.bitPattern):\(longitude.bitPattern):\(language)" }
}

struct PlaceAddress: Codable {
    var country: String? = nil
    var region: String? = nil
    var city: String? = nil
    var district: String? = nil
    var street: String? = nil
    var area: String? = nil
    // A reverse-geocoder name is a nearby reference, not proof of a filmed building.
    var nearbyName: String? = nil
    var displayName: String? = nil
    var boundaryID: String? = nil
    var areaRelation: String? = nil
    var placeKind: String? = nil
    var boundaryRetry: Bool? = nil
    var shortName: String? = nil
    var shortNameSource: String? = nil
    var label: String? {
        var parts: [String] = []
        let areaLabel = areaRelation == "nearby" ? displayName : area
        for value in [country, region, city, district, areaLabel, street] {
            guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, !parts.contains(text) else { continue }
            parts.append(text)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

@MainActor final class PlaceNameResolver {
    static let consentKey = "onlinePlaceNamesEnabled"
    static let aliasesKey = "placeDisplayAliases.v1"
    private static let cacheKey = "placeNamesCache.v3"
    struct Entry: Codable { let address: PlaceAddress; let savedAt: Date }
    typealias Lookup = (PlaceQuery) async throws -> PlaceAddress?
    typealias BoundaryLookup = (PlaceQuery) async throws -> PlaceBoundaryPolicy.Match?
    private let defaults: UserDefaults
    private let lookup: Lookup
    private let interval: TimeInterval
    private let retryDelay: TimeInterval
    private let now: () -> Date
    private let canRequest: () -> Bool
    private let useBoundaries: () -> Bool
    private let boundaryLookup: BoundaryLookup
    private let cachedBoundary: (PlaceQuery) -> PlaceBoundaryPolicy.Match?
    private var cache: [String: Entry]
    private var failures: [String: Date] = [:]
    private var pending: [PlaceQuery] = []
    private var worker: Task<Void, Never>?
    private var enabled = false
    private var generation = 0
    private var nextRequest = Date.distantPast
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard, interval: TimeInterval = 5, retryDelay: TimeInterval = 300,
         now: @escaping () -> Date = Date.init, canRequest: @escaping () -> Bool = { true },
         useBoundaries: (() -> Bool)? = nil, lookup: Lookup? = nil, boundaryLookup: BoundaryLookup? = nil,
         cachedBoundary: ((PlaceQuery) -> PlaceBoundaryPolicy.Match?)? = nil) {
        self.defaults = defaults; self.interval = interval; self.retryDelay = retryDelay; self.now = now
        self.lookup = lookup ?? Self.appleLookup; self.canRequest = canRequest
        self.useBoundaries = useBoundaries ?? { defaults.bool(forKey: PlaceBoundaryLookup.consentKey) }
        let boundaries = PlaceBoundaryLookup(defaults: defaults)
        self.boundaryLookup = boundaryLookup ?? { try await boundaries.lookup($0) }
        self.cachedBoundary = cachedBoundary ?? { boundaries.cachedMatch($0) }
        self.cache = defaults.data(forKey: Self.cacheKey).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    static func appleLookup(_ query: PlaceQuery) async throws -> PlaceAddress? {
        // macOS 13+ / SDK 14 compatible. No CLLocationManager or current-location permission.
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: query.latitude, longitude: query.longitude)
        let timeout = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 20_000_000_000); geocoder.cancelGeocode() }
            catch { /* Completed or cancelled by the caller. */ }
        }
        defer { timeout.cancel() }
        return try await withTaskCancellationHandler {
            let marks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: query.language))
            try Task.checkCancellation()
            guard let mark = marks.first else { return nil }
            // Use the area attached to this coordinate, never nearest-POI guessing.
            let area = mark.areasOfInterest?.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return PlaceAddress(country: mark.country, region: mark.administrativeArea, city: mark.locality,
                                district: mark.subLocality, street: mark.thoroughfare,
                                area: area, nearbyName: mark.name)
        } onCancel: {
            Task { @MainActor in geocoder.cancelGeocode() }
        }
    }

    private func key(_ query: PlaceQuery) -> String {
        query.key + (useBoundaries() ? (defaults.bool(forKey: PlaceFallbackLookup.consentKey) ? ":boundaries:fallback" : ":boundaries") : ":apple")
    }

    func cached(_ query: PlaceQuery) -> String? {
        guard let entry = cache[key(query)], now().timeIntervalSince(entry.savedAt) <
                (entry.address.boundaryRetry == true ? 900 : entry.address.boundaryID == nil ? 86400 : 30 * 86400) else { return nil }
        return entry.address.label
    }

    func resolved(_ query: PlaceQuery) -> ResolvedPlace? {
        guard let entry = cache[key(query)], let label = cached(query) else { return nil }
        let enriched = entry.address.boundaryID != nil
        return formatted(ResolvedPlace(version: enriched ? 3 : 2, label: label, area: entry.address.area,
                             nearbyName: entry.address.nearbyName, latitude: query.latitude,
                             longitude: query.longitude, language: query.language,
                             provider: enriched ? "apple-osm" : "apple-geocoder", resolvedAt: entry.savedAt.timeIntervalSince1970,
                             displayName: entry.address.displayName, boundaryID: entry.address.boundaryID,
                             areaRelation: entry.address.areaRelation, placeKind: entry.address.placeKind,
                             city: entry.address.city, region: entry.address.region,
                             shortName: entry.address.shortName, shortNameSource: entry.address.shortNameSource))
    }

    private func formatted(_ original: ResolvedPlace) -> ResolvedPlace {
        var place = original
        place.city = place.city ?? PlaceCaption.city(in: place.label)
        if let area = place.area {
            let city = PlaceCaption.context(place.city, chinese: place.language == "zh-Hans")
            let aliases = defaults.dictionary(forKey: Self.aliasesKey) as? [String: String] ?? [:]
            // Explicit naming preferences are scoped to city AND canonical area.
            if let alias = aliases[city + "|" + area]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !city.isEmpty, !alias.isEmpty, alias.count <= 200 {
                place.shortName = alias
                place.shortNameSource = "user-alias"
            }
        }
        place.displayName = PlaceCaption.make(city: place.city, region: place.region, area: place.area,
                                            shortName: place.shortName, relation: place.areaRelation,
                                            kind: place.placeKind, chinese: place.language == "zh-Hans")
        return place
    }

    func applyingCache(to items: [MediaItem], language: String) -> [MediaItem] {
        var changed = false
        let mapped: [MediaItem] = items.map { original -> MediaItem in
            var item = original
            item.metadata?.location?.resolvedName = nil
            if let query = item.placeQuery(language: language) {
                // Local geometry is cheap and independent of the online queue.
                // New imports must not delay already-verified areas behind
                // dozens of unrelated network lookups.
                if useBoundaries(), resolved(query)?.version != 3, let match = cachedBoundary(query) {
                    let old = item.validResolvedPlace
                    let address = cache[key(query)]?.address ?? cache[query.key + ":boundaries"]?.address ??
                        cache[query.key + ":apple"]?.address ??
                        PlaceAddress(region: old?.region, city: old?.city ?? old.flatMap { PlaceCaption.city(in: $0.label) })
                    cache[key(query)] = Entry(address: PlaceBoundaryPolicy.applying(match, to: address, language: language), savedAt: now())
                    changed = true
                }
                if let place = resolved(query),
                   place.version == 3 || item.validResolvedPlace?.version != 3 || item.validResolvedPlace?.language != language {
                    item.resolvedPlace = place
                }
                if item.resolvedPlace?.language != language { item.resolvedPlace = nil }
                if item.resolvedPlace?.language == language, let place = item.validResolvedPlace {
                    item.resolvedPlace = formatted(place)
                    item.metadata?.location?.resolvedName = place.label
                }
            }
            return item
        }
        if changed, let saved = try? JSONEncoder().encode(cache) { defaults.set(saved,forKey:Self.cacheKey) }
        return mapped
    }

    func schedule(_ queries: [PlaceQuery], enabled: Bool, foreground: Bool) {
        self.enabled = enabled
        guard enabled, foreground else { cancel(); return }
        // Refresh replaces pending work, so deleted media never stays queued.
        var seen: Set<PlaceQuery> = []
        pending = queries.filter { seen.insert($0).inserted && cached($0) == nil && (failures[key($0)] ?? .distantPast) <= now() }
        guard worker == nil, !pending.isEmpty else { return }
        generation += 1
        let current = generation
        worker = Task { [weak self] in
            guard let self else { return }
            defer { if generation == current { worker = nil } }
            while enabled, !Task.isCancelled, generation == current, !pending.isEmpty {
                let wait = nextRequest.timeIntervalSince(now())
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                guard !Task.isCancelled, generation == current, !pending.isEmpty, canRequest() else { return }
                let query = pending.removeFirst()
                let cacheID = key(query)
                guard cached(query) == nil, (failures[cacheID] ?? .distantPast) <= now() else { continue }
                nextRequest = now().addingTimeInterval(interval)
                do {
                    var address: PlaceAddress?
                    do { address = try await lookup(query) }
                    catch { if !useBoundaries() { throw error } }
                    try Task.checkCancellation()
                    if useBoundaries(), canRequest(), generation == current {
                        do {
                            if let match = try await boundaryLookup(query) {
                                address = PlaceBoundaryPolicy.applying(match, to: address, language: query.language)
                            }
                        } catch {
                            try Task.checkCancellation()
                            // Keep Apple's address usable, but retry enrichment after cooldown.
                            address?.boundaryRetry = true
                        }
                    }
                    guard !Task.isCancelled, generation == current else { return }
                    if let address, address.label?.isEmpty == false {
                        cache[cacheID] = Entry(address: address, savedAt: now())
                        failures.removeValue(forKey: cacheID)
                        let retained = cache.sorted { $0.value.savedAt > $1.value.savedAt }.prefix(1000)
                        cache = Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
                        if let data = try? JSONEncoder().encode(cache) { defaults.set(data, forKey: Self.cacheKey) }
                        onChange?()
                    } else { failures[cacheID] = now().addingTimeInterval(retryDelay) }
                } catch {
                    guard !Task.isCancelled, generation == current else { return }
                    failures[cacheID] = now().addingTimeInterval(retryDelay)
                    // Network / service throttling: cool down the entire queue, not just one coordinate.
                    nextRequest = now().addingTimeInterval(max(60, interval))
                }
            }
        }
    }

    func cancel() {
        generation += 1; worker?.cancel(); worker = nil; pending = []
    }
}

extension MediaItem {
    func placeQuery(language: String) -> PlaceQuery? {
        guard !hasSavedPlaceName, let location = metadata?.location else { return nil }
        return PlaceQuery(location, language: language)
    }
}
