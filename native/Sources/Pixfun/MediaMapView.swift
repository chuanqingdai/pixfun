import SwiftUI
import MapKit

/// Full-width workspace destination; shares the library's records and Agent composer.
struct MediaMapView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var day = ""
    @State private var showOrder = false
    @State private var selectedIDs: Set<String> = []
    @State private var fitRequest = 0
    @State private var mapError = false
    @State private var loadMap = UserDefaults.standard.bool(forKey: PlaceNameResolver.consentKey)
    @State private var originalMetadata: [String: Metadata] = [:]
    @State private var reading = false
    @State private var readMessage: String?
    @State private var readTask: Task<Void, Never>?
    @State private var allPoints: [MediaMapPoint] = []
    @State private var visibleIDs: Set<String> = []
    @State private var confirmCreation = false
    @State private var creationError: String?
    // Preview injection uses isolated fixtures; production defaults remain unchanged.
    init(initialDay: String = "", initialOrder: Bool = false, initialSelection: Set<String> = [], mapEnabled: Bool? = nil) {
        _day = State(initialValue: initialDay); _showOrder = State(initialValue: initialOrder)
        _selectedIDs = State(initialValue: initialSelection)
        _loadMap = State(initialValue: mapEnabled ?? UserDefaults.standard.bool(forKey: PlaceNameResolver.consentKey))
    }
    private var chinese: Bool { store.language == .chinese }
    private var mapItems: [MediaItem] {
        store.mediaMapItems.map { source in
            var item = source
            if let metadata = originalMetadata[item.id] { item.metadata = metadata }
            return item
        }
    }
    // Do not reparse every timestamp on selection, panning, or map-loading callbacks.
    private var inputKey: [String] {
        mapItems.map { item in
            let m = item.metadata, l = m?.location
            var parts: [String] = [item.id, item.name, item.cover ?? "", String(item.isExample == true)]
            parts += [item.kind, item.status, String(item.missing == true)]
            parts += [m?.capturedAt ?? "", m?.camera ?? "", m?.captureDeviceID ?? "", item.syncSourceId ?? ""]
            parts += [l?.source ?? "", l?.datum ?? ""]
            parts += [String(l?.latitude ?? Double.nan), String(l?.longitude ?? Double.nan), String(l?.horizontalAccuracy ?? -1)]
            let review = item.locationReview
            parts += [review?.source ?? "", review?.place ?? "", String(review?.latitude ?? Double.nan), String(review?.longitude ?? Double.nan)]
            return parts.joined(separator: "\u{1F}")
        }
    }
    private var days: [String] { Array(Set(allPoints.compactMap(\.day))).sorted(by: >) }
    private var points: [MediaMapPoint] { allPoints.filter { day.isEmpty || $0.day == day } }
    private var selected: [MediaMapPoint] { MediaMapData.ordered(points.filter { selectedIDs.contains($0.id) }) }
    private var orderPoints: [MediaMapPoint] { selected.isEmpty ? points.filter { visibleIDs.contains($0.id) } : selected }
    private var numbers: [String: Int] { showOrder ? MediaMapData.sequenceNumbers(orderPoints) : [:] }
    private var routes: [MediaMapRoute] {
        guard showOrder else { return [] }
        return Set(orderPoints.compactMap(\.day)).sorted().flatMap { MediaMapData.routes(orderPoints, day: $0) }
    }
    private var canCreate: Bool { !selected.isEmpty && selected.allSatisfy { MediaMapCreation.eligible($0.item) } && !store.saving && !store.importing }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Media map").font(.pixfun(20, semibold: true))
                    Text(chinese ? "素材库 · \(points.count) 个素材有可展示坐标" : "Library · \(points.count) mapped items")
                        .font(.pixfun(12)).foregroundStyle(Color.pixfunMuted)
                }
                Spacer()
                Button { readOriginals() } label: { Label(reading ? "Reading locations" : "Read original locations", systemImage: "arrow.clockwise") }
                    .buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(reading)
                    .help("Read capture metadata locally without rerunning analysis or changing files.")
            }.padding(20)
            if !allPoints.isEmpty {
                HStack(spacing: 14) {
                    Picker("Capture date", selection: $day) {
                        Text("All dates").tag("")
                        ForEach(days, id: \.self) { Text(verbatim: $0).tag($0) }
                    }.frame(width: 220)
                    Toggle("Capture order", isOn: $showOrder).toggleStyle(.checkbox).disabled(days.isEmpty)
                        .help("Number recorded capture times. Connect points only when location evidence is sufficient.")
                    Spacer()
                    Button {
                        selectedIDs = visibleIDs.intersection(Set(points.map(\.id)))
                        showOrder = true
                    } label: { Label("Select this area", systemImage: "viewfinder") }
                        .buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(!loadMap || visibleIDs.isEmpty)
                    Button { fitRequest += 1 } label: { Label("Show all points", systemImage: "arrow.up.left.and.arrow.down.right") }
                        .buttonStyle(PixfunButtonStyle(kind: .quiet)).disabled(!loadMap || points.isEmpty)
                }.font(.pixfun(12)).padding(.horizontal, 20).padding(.bottom, 12)
            }
            ZStack(alignment: .topLeading) {
                if allPoints.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "mappin.slash").font(.system(size: 32)).foregroundStyle(Color.pixfunMuted)
                        Text("No recorded coordinates to display").font(.pixfun(17, semibold: true))
                        Text("Place names alone cannot position media on a map. Read original locations or import photos and videos with GPS metadata.")
                            .font(.pixfun(13)).foregroundStyle(Color.pixfunMuted).multilineTextAlignment(.center).frame(maxWidth: 430)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !loadMap {
                    VStack(spacing: 16) {
                        Image(systemName: "map").font(.system(size: 32)).foregroundStyle(Color.pixfunGold)
                        Text("Load Apple Maps?").font(.pixfun(17, semibold: true))
                        Text("Apple receives map-area requests. Thumbnails and files stay on this Mac. This does not enable place-name lookups.")
                            .font(.pixfun(13)).foregroundStyle(Color.pixfunMuted).multilineTextAlignment(.center).frame(maxWidth: 440)
                        Button("Load map") { loadMap = true }.buttonStyle(PixfunButtonStyle(kind: .primary))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    MediaMapCanvas(points: points, routes: routes, numbers: numbers, store: store, chinese: chinese, selectedIDs: selectedIDs, fitRequest: fitRequest,
                                   onSelect: { selectedIDs = Set($0); showOrder = true }, onVisible: { visibleIDs = Set($0) }, onError: { mapError = $0 })
                    if mapError {
                        Text("Map background unavailable. Recorded points remain; check your connection.")
                            .font(.pixfun(12)).padding(10).background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 8)).padding(12)
                    } else if showOrder && routes.isEmpty {
                        Text(numbers.isEmpty ? "Capture times are insufficient for numbering." : "Numbers show capture order. Location evidence is insufficient for connecting these points.")
                            .font(.pixfun(12)).padding(10).background(Color.pixfunSurface, in: RoundedRectangle(cornerRadius: 8)).padding(12)
                    }
                    if !selected.isEmpty {
                        VStack(spacing: 0) {
                            Divider()
                            selectionStrip.padding(.bottom, 12)
                                .background(Color.pixfunSurface.opacity(0.96))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transaction { $0.animation = nil }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                if let readMessage { Text(verbatim: readMessage).foregroundStyle(Color.pixfunGold) }
                if let creationError { Text(verbatim: creationError).foregroundStyle(Color.pixfunGold) }
                Text(showOrder ? "Dashed lines show capture order, not a verified route. Gaps, date changes and large jumps are not connected." : "Zoom to separate thumbnails. Click a thumbnail or a group to browse its media.")
                HStack(alignment: .top) {
                    Text("Original GPS is retained; user-confirmed corrections apply only inside Pixfun. Apple Maps loads online; media stays local.")
                    Spacer(minLength: 12)
                    let excluded = store.mediaMapItems.count - allPoints.count
                    if excluded > 0 { Text(chinese ? "\(excluded) 个素材无可用坐标" : "\(excluded) without usable coordinates").fixedSize() }
                }
            }.font(.pixfun(11)).foregroundStyle(Color.pixfunMuted).frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    if store.draft.hasContent { confirmCreation = true } else { createFromSelection(replace: false) }
                } label: { Label("Create", systemImage: "sparkles").frame(minWidth: 76) }
                    .buttonStyle(PixfunButtonStyle(kind: .primary)).disabled(!canCreate)
                    .accessibilityLabel("Create with selected media")
                    .help(canCreate ? "Add selected media and an editable request to Agent. Nothing is sent yet." : "Select available photos or videos first. Remove unavailable items to continue.")
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(minWidth: 700, maxWidth: .infinity, minHeight: 540, maxHeight: .infinity)
        .navigationTitle("Media map")
        .background(Color.pixfunBackground).foregroundStyle(Color.pixfunInk)
        .task(id: inputKey) { allPoints = mapItems.compactMap(MediaMapPoint.init) }
        .onChange(of: day) { _ in selectedIDs = []; visibleIDs = []; fitRequest += 1 }
        .onChange(of: days) { values in if !day.isEmpty && !values.contains(day) { day = "" } }
        .onDisappear { readTask?.cancel() }
        .alert("Existing creation draft", isPresented: $confirmCreation) {
            Button("Keep draft and add media") { createFromSelection(replace: false) }
            Button("Use selection and default request") { createFromSelection(replace: true) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Keep your existing text and attachments, or replace only the unsent draft with this selection. Saved projects are unchanged. Nothing is sent automatically.") }
    }

    private func createFromSelection(replace: Bool) {
        guard canCreate, store.prepareMapCreation(selected.map(\.id), replaceDraft: replace) else {
            creationError = chinese ? "素材状态已变化，请重新选择可用素材。" : "Media changed. Select available items again."
            return
        }
    }

    private func readOriginals() {
        let candidates = store.mediaMapItems
        reading = true
        readTask = Task { @MainActor in
            defer { reading = false }
            var failures = 0
            for (index, item) in candidates.enumerated() {
                guard !Task.isCancelled else { return }
                readMessage = chinese ? "读取原始定位 \(index + 1)/\(candidates.count)" : "Reading locations \(index + 1)/\(candidates.count)"
                do {
                    struct Response: Decodable { let metadata: Metadata }
                    let result: Response = try await store.service.post("/api/desktop/analysis/map-metadata", ["id": item.id], native: true)
                    guard !Task.isCancelled else { return }
                    var metadata = item.metadata ?? Metadata()
                    metadata.location = result.metadata.location
                    metadata.capturedAt = result.metadata.capturedAt
                    metadata.camera = result.metadata.camera
                    metadata.dateSource = result.metadata.dateSource
                    metadata.captureDeviceID = result.metadata.captureDeviceID
                    originalMetadata[item.id] = metadata
                } catch {
                    if Task.isCancelled { return }
                    failures += 1
                }
            }
            readMessage = chinese ? "已读取 \(candidates.count - failures) 个素材\(failures > 0 ? "，\(failures) 个暂无法读取（不代表没有定位）" : "，未修改原文件")" : "Read \(candidates.count - failures) items; \(failures) unavailable. Source files unchanged."
            fitRequest += 1
        }
    }

    private var selectionStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(chinese ? "所选位置 · \(selected.count) 个素材" : "Selected points · \(selected.count) items").font(.pixfun(12, semibold: true))
                Text("Capture numbers; equal times share a number").font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
                if selected.count == 1, let point = selected.first {
                    Text(verbatim: point.accuracyLabel(chinese: chinese)).font(.pixfun(11)).foregroundStyle(Color.pixfunMuted)
                }
                Spacer()
                Button { selectedIDs = [] } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Clear map selection")
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(selected) { point in
                        Button {
                            store.openMedia(point.item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                ServiceImage(path: point.item.cover).frame(width: 112, height: 64).clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(alignment: .bottomLeading) {
                                        if let number = numbers[point.id] {
                                            Text(verbatim: "#\(number)").font(.pixfun(11, semibold: true)).padding(4)
                                                .background(Color.pixfunBackground.opacity(0.85), in: RoundedRectangle(cornerRadius: 4)).padding(3)
                                        }
                                    }
                                Text(verbatim: point.item.name).lineLimit(1)
                                Text(point.day.map { "\($0) \(point.clock ?? "")" } ?? (chinese ? "拍摄时间未知" : "Capture time unknown"))
                                    .foregroundStyle(Color.pixfunMuted).lineLimit(1)
                            }.font(.pixfun(11)).frame(width: 112, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).help(chinese ? "打开 \(point.item.name)" : "Open \(point.item.name)")
                            .overlay(alignment: .topTrailing) {
                                Button { selectedIDs.remove(point.id) } label: {
                                    Image(systemName: "minus.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.8)).padding(3)
                                }.buttonStyle(.plain).accessibilityLabel(chinese ? "取消选择 \(point.item.name)" : "Deselect \(point.item.name)")
                            }
                    }
                }
            }.frame(height: 122)
        }.padding(.horizontal, 20).padding(.top, 12)
    }
}

private final class MediaMapAnnotation: NSObject, MKAnnotation {
    let point: MediaMapPoint
    let coordinate: CLLocationCoordinate2D
    var title: String? { point.item.name }
    init(_ point: MediaMapPoint) {
        self.point = point
        coordinate = .init(latitude: point.latitude, longitude: point.longitude)
    }
}

private struct MediaMapThumbnail: View {
    let point: MediaMapPoint
    let count: Int
    let sequence: Int?
    var body: some View {
        ServiceImage(path: point.item.cover).frame(width: 68, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.pixfunGold,
                style: StrokeStyle(lineWidth: 2, dash: point.datumKnown && point.accuracy.map { $0 <= MediaMapData.maximumAccuracy } == true ? [] : [3, 2])))
            .overlay(alignment: .bottomTrailing) {
                if count > 1 || sequence != nil {
                    Text(verbatim: count > 1 ? "\(count)" : "#\(sequence!)").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.pixfunBackground).padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.pixfunGold, in: RoundedRectangle(cornerRadius: 4)).padding(3)
                }
            }.shadow(color: .black.opacity(0.35), radius: 3, y: 2).padding(4)
    }
}

/// Let MapKit own pointer/selection events instead of the embedded image view.
private final class MapThumbnailHost: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Keep the hosting view alive while MapKit reuses or reclusters annotations. Replacing
/// the entire annotation view restarts image loading and makes thumbnails flash.
private final class MediaMapAnnotationView: MKAnnotationView {
    let host = MapThumbnailHost(rootView: AnyView(EmptyView()))
    var presentationKey = ""

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = NSRect(x: 0, y: 0, width: 76, height: 56)
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    required init?(coder: NSCoder) { nil }
}

private struct MediaMapCanvas: NSViewRepresentable {
    let points: [MediaMapPoint]
    let routes: [MediaMapRoute]
    let numbers: [String: Int]
    let store: WorkspaceStore
    let chinese: Bool
    let selectedIDs: Set<String>
    let fitRequest: Int
    let onSelect: ([String]) -> Void
    let onVisible: ([String]) -> Void
    let onError: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.mapType = .standard
        map.showsZoomControls = true; map.showsCompass = true; map.showsScale = true
        map.isRotateEnabled = false; map.isPitchEnabled = false; map.showsUserLocation = false
        map.pointOfInterestFilter = .excludingAll
        map.setAccessibilityLabel(chinese ? "素材地图，可缩放并选择缩略图" : "Media map. Zoom and select thumbnails.")
        return map
    }
    func updateNSView(_ map: MKMapView, context: Context) {
        context.coordinator.update(self, map: map)
    }
    static func dismantleNSView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.visibleWorkItem?.cancel()
        map.delegate = nil
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MediaMapCanvas
        var pointKeys: [String: String] = [:]
        var annotations: [String: MediaMapAnnotation] = [:]
        var routeKeys: [[String]] = []
        var routeOverlays: [MKPolyline] = []
        var accuracyOverlay: MKCircle?
        var fitted = -1
        var sequence: [String: Int] = [:]
        var selectedIDs: Set<String> = []
        var reportedVisible: Set<String> = []
        var pendingVisible: Set<String> = []
        var visibleWorkItem: DispatchWorkItem?
        init(_ parent: MediaMapCanvas) { self.parent = parent }
        func update(_ value: MediaMapCanvas, map: MKMapView) {
            parent = value
            let keys = Dictionary(uniqueKeysWithValues: value.points.map {
                ($0.id, "\($0.latitude)|\($0.longitude)|\($0.accuracy ?? -1)|\($0.datumKnown)|\($0.item.cover ?? "")|\($0.item.name)")
            })
            let nextRoutes = value.routes.map { route in
                route.points.map { "\($0.id)|\($0.latitude)|\($0.longitude)" }
            }
            let pointsChanged = keys != pointKeys, routesChanged = nextRoutes != routeKeys
            let numbersChanged = sequence != value.numbers
            sequence = value.numbers
            if pointsChanged {
                let changed = Set(pointKeys.keys.filter { keys[$0] != pointKeys[$0] })
                let removed = changed.compactMap { annotations.removeValue(forKey: $0) }
                if !removed.isEmpty { map.removeAnnotations(removed) }
                pointKeys = keys
                let added = value.points.filter { annotations[$0.id] == nil }.map(MediaMapAnnotation.init)
                for annotation in added { annotations[annotation.point.id] = annotation }
                if !added.isEmpty { map.addAnnotations(added) }
            }
            if routesChanged {
                routeKeys = nextRoutes
                if !routeOverlays.isEmpty { map.removeOverlays(routeOverlays) }
                routeOverlays = value.routes.map { route in
                    let coordinates = route.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    return MKPolyline(coordinates: coordinates, count: coordinates.count)
                }
                if !routeOverlays.isEmpty { map.addOverlays(routeOverlays) }
            }
            if pointsChanged || routesChanged || numbersChanged || selectedIDs != value.selectedIDs {
                selectedIDs = value.selectedIDs
                if let accuracyOverlay { map.removeOverlay(accuracyOverlay); self.accuracyOverlay = nil }
                // One selected point only: a cluster is not a measured position or accuracy estimate.
                if selectedIDs.count == 1, let point = value.points.first(where: { selectedIDs.contains($0.id) }),
                   let radius = point.accuracy, radius > 0 {
                    let circle = MKCircle(center: .init(latitude: point.latitude, longitude: point.longitude), radius: radius)
                    accuracyOverlay = circle
                    map.addOverlay(circle)
                }
            }
            if numbersChanged { refreshVisibleAnnotations(map) }
            if fitted != value.fitRequest || (fitted == -1 && !value.points.isEmpty) {
                fitted = value.fitRequest
                DispatchQueue.main.async { [weak map, weak self] in
                    guard let map, let self else { return }
                    map.layoutSubtreeIfNeeded()
                    self.fit(map, annotations: value.points.compactMap { self.annotations[$0.id] })
                }
            }
            if pointsChanged { reportVisible(map) }
        }
        func reportVisible(_ map: MKMapView) {
            let rect = map.visibleMapRect
            let worldWidth = MKMapRect.world.size.width
            let ids = Set(parent.points.filter { point in
                let projected = MKMapPoint(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                return [projected.x, projected.x - worldWidth, projected.x + worldWidth].contains {
                    rect.contains(MKMapPoint(x: $0, y: projected.y))
                }
            }.map(\.id))
            guard ids != reportedVisible || ids != pendingVisible else { return }
            pendingVisible = ids
            visibleWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.pendingVisible == ids, self.reportedVisible != ids else { return }
                self.reportedVisible = ids
                self.parent.onVisible(Array(ids))
            }
            visibleWorkItem = work
            // Region callbacks can arrive in short bursts while MapKit settles its
            // viewport. Coalesce them so SwiftUI does not redraw route badges mid-pan.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { reportVisible(mapView) }
        func fit(_ map: MKMapView, annotations: [MKAnnotation]) {
            guard let first = annotations.first else { return }
            if annotations.count == 1 {
                map.setRegion(.init(center: first.coordinate, latitudinalMeters: 1600, longitudinalMeters: 1600), animated: false)
            } else {
                map.showAnnotations(annotations, animated: false)
            }
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let identifier = annotation is MKClusterAnnotation ? "media-cluster" : "media-point"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MediaMapAnnotationView)
                ?? MediaMapAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            configure(view, for: annotation)
            return view
        }
        func refreshVisibleAnnotations(_ mapView: MKMapView) {
            for annotation in mapView.annotations {
                guard let view = mapView.view(for: annotation) as? MediaMapAnnotationView else { continue }
                configure(view, for: annotation)
            }
        }
        func configure(_ view: MediaMapAnnotationView, for annotation: MKAnnotation) {
            let members: [MediaMapAnnotation]
            if let cluster = annotation as? MKClusterAnnotation { members = cluster.memberAnnotations.compactMap { $0 as? MediaMapAnnotation } }
            else if let single = annotation as? MediaMapAnnotation { members = [single] }
            else { return }
            guard let point = MediaMapData.ordered(members.map(\.point)).first else { return }
            view.annotation = annotation
            // Cluster annotations are aggregates, never members of another cluster.
            view.clusteringIdentifier = annotation is MKClusterAnnotation ? nil : "media"
            view.canShowCallout = false
            view.collisionMode = .rectangle; view.displayPriority = annotation is MKClusterAnnotation ? .defaultHigh : .defaultLow
            let key = "\(members.map { $0.point.id }.sorted().joined(separator: ","))|\(point.item.cover ?? "")|\(sequence[point.id] ?? -1)"
            if view.presentationKey != key {
                view.presentationKey = key
                view.host.rootView = AnyView(MediaMapThumbnail(point: point, count: members.count, sequence: sequence[point.id])
                    .environmentObject(parent.store).transaction { $0.animation = nil })
            }
            view.setAccessibilityLabel(members.count > 1 ? (parent.chinese ? "\(members.count) 个素材，点击展开" : "\(members.count) items, click to browse") : point.item.name + ", " + point.accuracyLabel(chinese: parent.chinese))
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                let members = cluster.memberAnnotations.compactMap { $0 as? MediaMapAnnotation }
                parent.onSelect(members.map { $0.point.id })
                // Coincident coordinates remain browsable in the strip even at maximum zoom.
                if let first = members.first, members.contains(where: { $0.point.distance(to: first.point) > 40 }) {
                    fit(mapView, annotations: members)
                }
            } else if let point = view.annotation as? MediaMapAnnotation { parent.onSelect([point.point.id]) }
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = NSColor(Color.pixfunGold).withAlphaComponent(0.12)
                renderer.strokeColor = NSColor(Color.pixfunGold).withAlphaComponent(0.7)
                renderer.lineWidth = 1; renderer.lineDashPattern = [4, 4]
                return renderer
            }
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = NSColor(Color.pixfunGold); renderer.lineWidth = 3; renderer.lineDashPattern = [6, 5]
            return renderer
        }
        func mapViewDidFinishLoadingMap(_ mapView: MKMapView) { DispatchQueue.main.async { self.parent.onError(false) } }
        func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) { DispatchQueue.main.async { self.parent.onError(true) } }
    }
}
