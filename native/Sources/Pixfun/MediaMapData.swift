import Foundation

/// Read-only map projections. Never use place names, search anchors or group centroids as GPS.
struct MediaMapPoint: Identifiable {
    let item: MediaItem
    let latitude: Double
    let longitude: Double
    let captured: Date?
    let day: String?
    let clock: String?
    let timeBasis: String?
    let datumKnown: Bool
    let accuracy: Double?
    let corrected: Bool
    var id: String { item.id }
    var canConnect: Bool {
        datumKnown && (corrected || accuracy.map { $0 <= MediaMapData.maximumAccuracy } == true) &&
        item.metadata?.captureDeviceID?.hasPrefix("camera-sha256:") == true && captured != nil && timeBasis != nil
    }
    func accuracyLabel(chinese: Bool) -> String {
        if corrected { return chinese ? "应用内人工确认位置" : "User-confirmed app location" }
        let value = accuracy.map { chinese ? "定位误差约 \(Int(min($0.rounded(.up), 99_999_999))) 米" : "Reported accuracy: \(Int(min($0.rounded(.up), 99_999_999))) m" }
            ?? (chinese ? "定位精度未知" : "Accuracy unknown")
        return datumKnown ? value : value + (chinese ? " · 坐标系未声明" : " · Datum unspecified")
    }

    init?(_ item: MediaItem) { self.init(item, pendingLocation: nil) }
    init?(_ item: MediaItem, pendingLocation: AgentTripLocation?) {
        guard item.isExample != true else { return nil }
        let location = item.metadata?.location
        let reviewed = item.locationReview?.validCoordinates
        let override = pendingLocation.map { ($0.latitude, $0.longitude) } ?? reviewed
        guard let lat = override?.0 ?? location?.latitude, let lon = override?.1 ?? location?.longitude,
              lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180,
              override != nil || (location?.source == "file-metadata" && !(lat == 0 && lon == 0)) else { return nil }
        let datum = (location?.datum ?? "").uppercased().filter { $0.isLetter || $0.isNumber }
        guard ["", "WGS84", "WGS1984"].contains(datum) else { return nil }
        corrected = override != nil
        datumKnown = corrected || !datum.isEmpty
        accuracy = corrected ? nil : location?.horizontalAccuracy.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.item = item; latitude = lat; longitude = lon
        captured = item.metadata?.captureDate
        let raw = item.metadata?.capturedAt ?? ""
        // Preserve the recorded calendar day, not the Mac's current time zone.
        if raw.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$"#, options: .regularExpression) != nil,
           Self.validWallClock(String(raw.prefix(19))) {
            day = String(raw.prefix(10)); clock = String(raw.dropFirst(11).prefix(5))
            if captured != nil {
                let offset = raw.hasSuffix("Z") ? "+0000" : String(raw.suffix(raw.suffix(3).contains(":") ? 6 : 5)).replacingOccurrences(of: ":", with: "")
                timeBasis = offset == "-0000" ? nil : offset
            } else { timeBasis = nil }
        } else { day = nil; clock = nil; timeBasis = nil }
    }

    private static func validWallClock(_ raw: String) -> Bool {
        // Validate calendar fields only. UTC here is NOT assigned to the captured timestamp.
        let validator = DateFormatter()
        validator.locale = Locale(identifier: "en_US_POSIX")
        validator.calendar = Calendar(identifier: .gregorian)
        validator.timeZone = TimeZone(secondsFromGMT: 0)
        validator.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; validator.isLenient = false
        guard let date = validator.date(from: raw) else { return false }
        return validator.string(from: date) == raw
    }

    func distance(to other: Self) -> Double {
        let r = Double.pi / 180
        let a = pow(sin((other.latitude - latitude) * r / 2), 2) + cos(latitude * r) * cos(other.latitude * r) * pow(sin((other.longitude - longitude) * r / 2), 2)
        return 6_371_008.8 * 2 * asin(sqrt(min(1, max(0, a))))
    }
}

struct MediaMapRoute {
    let points: [MediaMapPoint]
}

enum MediaMapData {
    // Conservative local-sequence policy v1. Limits split sketches; they do not declare GPS invalid.
    static let maximumAccuracy = 100.0
    static let maximumGap = 7200.0
    static let maximumStep = 2000.0
    static let maximumExtent = 5000.0
    static let maximumSpeed = 50.0
    static func ordered(_ points: [MediaMapPoint]) -> [MediaMapPoint] {
        points.sorted {
            let a = $0.captured ?? .distantFuture, b = $1.captured ?? .distantFuture
            return a == b ? $0.id < $1.id : a < b
        }
    }

    /// Ordinal rank of known instants, independent of GPS precision/device identity.
    /// Ties share a rank; missing/ambiguous timestamps get no invented position.
    static func sequenceNumbers(_ points: [MediaMapPoint]) -> [String: Int] {
        let timed = ordered(points.filter { $0.captured != nil && $0.timeBasis != nil && $0.day != nil })
        var numbers: [String: Int] = [:], rank = 0
        var previous: Date?
        for (index, point) in timed.enumerated() {
            if previous != point.captured { rank = index + 1; previous = point.captured }
            numbers[point.id] = rank
        }
        return numbers
    }

    /// Capture-order sketches only, never route planning, motion tracking or place confirmation.
    /// Split at dates, source/model changes, clock-zone changes, long gaps and spatial jumps.
    static func routes(_ points: [MediaMapPoint], day: String) -> [MediaMapRoute] {
        guard !day.isEmpty else { return [] }
        var result: [MediaMapRoute] = [], run: [MediaMapPoint] = []
        func flush() { if run.count >= 2 { result.append(.init(points: run)) }; run = [] }
        for point in ordered(points.filter { $0.day == day }) {
            guard point.canConnect,
                  let camera = point.item.metadata?.camera, !camera.isEmpty else { flush(); continue }
            if let last = run.last, let anchor = run.first {
                let seconds = point.captured!.timeIntervalSince(last.captured!)
                let meters = last.distance(to: point)
                if point.timeBasis != last.timeBasis || point.item.metadata?.captureDeviceID != last.item.metadata?.captureDeviceID ||
                    point.item.syncSourceId != last.item.syncSourceId || camera != last.item.metadata?.camera ||
                    seconds <= 0 || seconds > maximumGap || meters > maximumStep || anchor.distance(to: point) > maximumExtent ||
                    meters / seconds > maximumSpeed || meters <= (point.accuracy ?? 0) + (last.accuracy ?? 0) {
                    flush()
                }
            }
            run.append(point)
        }
        flush()
        return result
    }
}

enum MediaMapCreation {
    static func eligible(_ item: MediaItem) -> Bool {
        item.isExample != true && item.missing != true && item.status == "ready" && ["video", "image"].contains(item.kind)
    }
    static func prompt(chinese: Bool) -> String {
        if chinese {
            return "请根据这些素材的拍摄时间、地点和精彩内容，创作一段有故事感的旅行视频。"
        }
        return "Create a story-led travel video from these materials using their capture times, locations, and strongest moments."
    }
}
