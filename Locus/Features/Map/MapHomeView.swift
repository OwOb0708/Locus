import MapKit
import SwiftUI

/// What to do once a speed has been picked — carries whatever coordinates
/// that action needs so the confirm step doesn't have to re-derive state.
private enum SpeedPickerContext: Identifiable {
    case navigate(CLLocationCoordinate2D)
    case multiStop([CLLocationCoordinate2D])
    case importedGPX([CLLocationCoordinate2D])

    var id: String {
        switch self {
        case .navigate(let c): return "navigate-\(c.latitude)-\(c.longitude)"
        case .multiStop(let pts): return "multiStop-\(pts.count)-\(pts.last?.latitude ?? 0)-\(pts.last?.longitude ?? 0)"
        case .importedGPX(let pts): return "gpx-\(pts.count)"
        }
    }

    var title: String {
        switch self {
        case .navigate: return "導航到這個地點"
        case .multiStop: return "依序走訪多個地點"
        case .importedGPX: return "播放匯入的 GPX 路線"
        }
    }
}

/// Identifiable wrapper so a plain coordinate can drive `.sheet(item:)`.
private struct PendingPin: Identifiable {
    let coordinate: CLLocationCoordinate2D
    var id: String { "\(coordinate.latitude)-\(coordinate.longitude)" }
}

struct MapHomeView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore

    @StateObject private var search = PlaceSearchCompleter()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var isRouting = false
    @State private var showGPXImporter = false
    @State private var pinSelected = false
    @State private var isDraggingPin = false
    @State private var suppressNextMapTap = false
    /// Set when the pin comes from search / a named place so starring keeps the title.
    @State private var pinPlaceName: String?

    /// Drives the "傳送／導航／多點模式／遙控" bottom sheet after a plain map tap.
    @State private var pendingPin: PendingPin?
    @State private var multiStopActive = false
    @State private var multiStopWaypoints: [CLLocationCoordinate2D] = []
    @State private var speedPickerPayload: SpeedPickerContextWrapper?
    @State private var pickedMode: TravelMode = .walk
    @State private var pickedSpeed: CLLocationSpeed = TravelMode.walk.baseSpeed
    @State private var pickedIsCustom = false
    @State private var showSettings = false
    @State private var showPlaces = false

    /// Plain standard map, no satellite/hybrid imagery and no 3D elevation —
    /// keeps rendering cheap and avoids MapKit's realistic-elevation glitches.
    private let mapStyle: MapStyle = .standard(elevation: .flat)

    var body: some View {
        ZStack(alignment: .top) {
            // Keep Map inside the safe layout bounds so MapProxy.convert matches
            // finger position. Ignoring the safe area makes the tiles full-bleed but
            // shifts convert() upward by ~status-bar height.
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()

                    if let pin = session.pin {
                        Annotation("", coordinate: pin, anchor: .bottom) {
                            MapDropPin(
                                selected: pinSelected,
                                isDragging: isDraggingPin,
                                onSelect: {
                                    searchFocused = false
                                    suppressNextMapTap = true
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                        pinSelected.toggle()
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        suppressNextMapTap = false
                                    }
                                },
                                onRemove: {
                                    suppressNextMapTap = true
                                    withAnimation {
                                        session.pin = nil
                                        pinSelected = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        suppressNextMapTap = false
                                    }
                                },
                                onDragBegan: {
                                    searchFocused = false
                                    suppressNextMapTap = true
                                    pinSelected = false
                                    isDraggingPin = true
                                },
                                onDragMoved: { globalPoint in
                                    if let coord = proxy.convert(globalPoint, from: .global) {
                                        session.pin = coord
                                    }
                                },
                                onDragEnded: {
                                    isDraggingPin = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        suppressNextMapTap = false
                                    }
                                }
                            )
                        }
                    }
                    if let sim = session.simulated {
                        Annotation("模擬位置", coordinate: sim) {
                            ZStack {
                                Circle().fill(LocusTheme.accent.opacity(0.25)).frame(width: 44, height: 44)
                                Circle().fill(LocusTheme.accent).frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        }
                    }
                    ForEach(Array(multiStopWaypoints.enumerated()), id: \.offset) { index, coord in
                        Annotation("", coordinate: coord) {
                            WaypointMarker(number: index + 1)
                        }
                    }
                    if routeCoords.count > 1 {
                        MapPolyline(coordinates: routeCoords)
                            .stroke(LocusTheme.accent, lineWidth: 5)
                    }
                    if multiStopWaypoints.count > 1 {
                        MapPolyline(coordinates: multiStopWaypoints)
                            .stroke(LocusTheme.accentSecondary, style: StrokeStyle(lineWidth: 3, dash: [4, 5]))
                    }
                }
                .mapStyle(mapStyle)
                .mapControlVisibility(.hidden)
                .onTapGesture { point in
                    searchFocused = false
                    guard !suppressNextMapTap, !isDraggingPin else { return }
                    pinSelected = false
                    placePin(at: point, proxy: proxy)
                }
            }
            .background(Color.black.ignoresSafeArea())

            topChrome

            if isRouting {
                VStack {
                    Spacer()
                    Text("正在規劃路線…")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .locusGlass(.regular, in: Capsule())
                        .padding(.bottom, 160)
                }
            }
        }
        .onAppear {
            session.startLocationUpdates()
        }
        .onChange(of: session.pin?.latitude) { _, newValue in
            if newValue == nil { pinSelected = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .locusImportGPX)) { note in
            guard let url = note.object as? URL else { return }
            importGPX(url)
        }
        .fileImporter(isPresented: $showGPXImporter, allowedContentTypes: [.xml, .data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                importGPX(url)
            }
        }
        .sheet(item: $pendingPin) { pending in
            PinActionSheet(
                onTeleport: {
                    session.teleport(to: pending.coordinate, pairing: pairing)
                },
                onNavigate: {
                    presentSpeedPicker(.navigate(pending.coordinate))
                },
                onMultiStop: {
                    multiStopActive = true
                    multiStopWaypoints = [pending.coordinate]
                },
                onJoystick: {
                    session.startJoystick(pairing: pairing, at: pending.coordinate)
                }
            )
            .presentationDetents([.height(330)])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $speedPickerPayload) { payload in
            SpeedPickerSheet(
                title: payload.context.title,
                mode: $pickedMode,
                speedMPS: $pickedSpeed,
                isCustom: $pickedIsCustom,
                onConfirm: { startFollowing(payload.context) },
                onCancel: {}
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showPlaces) {
            PlacesView()
        }
    }

    private func presentSpeedPicker(_ context: SpeedPickerContext) {
        pickedMode = session.travelMode
        pickedSpeed = session.effectiveSpeed
        pickedIsCustom = session.customSpeed != nil
        speedPickerPayload = SpeedPickerContextWrapper(context: context)
    }

    private func startFollowing(_ context: SpeedPickerContext) {
        switch context {
        case .navigate(let destination):
            guard let start = session.currentRealOrSimulated else {
                session.lastError = "目前抓不到你的位置，請稍後再試。"
                return
            }
            runRoute { try await RouteBuilder.roadRoute(from: start, to: destination, mode: pickedMode) }
        case .multiStop(let waypoints):
            // The start is wherever you actually are right now — the pin
            // that opened the "多點模式" sheet is already the *first stop*
            // to walk to, not the start itself. Every leg (including the
            // one from your current position to that first pin) is a real
            // road route, so you walk the whole way instead of teleporting
            // to the first pin and only then starting to walk.
            guard let start = session.currentRealOrSimulated else {
                session.lastError = "目前抓不到你的位置，請稍後再試。"
                return
            }
            runRoute {
                var full: [CLLocationCoordinate2D] = []
                var previous = start
                for point in waypoints {
                    let leg = try await RouteBuilder.roadRoute(from: previous, to: point, mode: pickedMode)
                    full.append(contentsOf: full.isEmpty ? leg : Array(leg.dropFirst()))
                    previous = point
                }
                return full
            }
        case .importedGPX(let coords):
            beginFollowing(coords)
        }
    }

    private func runRoute(_ build: @escaping () async throws -> [CLLocationCoordinate2D]) {
        isRouting = true
        Task {
            do {
                let coords = try await build()
                await MainActor.run {
                    isRouting = false
                    beginFollowing(coords)
                }
            } catch {
                await MainActor.run {
                    isRouting = false
                    session.lastError = error.localizedDescription
                }
            }
        }
    }

    private func beginFollowing(_ coords: [CLLocationCoordinate2D]) {
        guard coords.count >= 2 else {
            session.lastError = "路線點數不足，無法開始移動。"
            return
        }
        routeCoords = coords
        session.travelMode = pickedMode
        session.customSpeed = pickedIsCustom ? pickedSpeed : nil
        session.followRoute(coords, pairing: pairing)
    }

    private func placePin(at point: CGPoint, proxy: MapProxy) {
        guard let coord = proxy.convert(point, from: .local) else { return }
        if multiStopActive {
            multiStopWaypoints.append(coord)
        } else {
            session.pin = coord
            pinPlaceName = nil
            pinSelected = false
            // Center the pin on screen so it's clearly visible while the
            // action sheet (anchored at the bottom) covers the lower half.
            withAnimation(.easeInOut(duration: 0.3)) {
                position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 800, longitudinalMeters: 800))
            }
            pendingPin = PendingPin(coordinate: coord)
        }
    }

    private var topChrome: some View {
        VStack(spacing: 10) {
            StatusBarView()

            searchBar

            if !searchText.isEmpty && !search.results.isEmpty {
                searchResults
            }

            if multiStopActive {
                multiStopBar
            }

            HStack(alignment: .center, spacing: 10) {
                mapChromeButtons
                Spacer(minLength: 0)
                locateButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
        .safeAreaPadding(.top, 8)
    }

    private var multiStopBar: some View {
        HStack(spacing: 12) {
            // Start is your current location, not one of these — these are
            // only the stops to walk to after that.
            Text("多點模式：已加入 \(multiStopWaypoints.count) 個停靠點")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("取消") {
                multiStopActive = false
                multiStopWaypoints.removeAll()
            }
            .foregroundStyle(LocusTheme.danger)

            Button("完成") {
                let points = multiStopWaypoints
                multiStopActive = false
                multiStopWaypoints.removeAll()
                presentSpeedPicker(.multiStop(points))
            }
            .fontWeight(.bold)
            .foregroundStyle(multiStopWaypoints.isEmpty ? .secondary : LocusTheme.accent)
            .disabled(multiStopWaypoints.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜尋地點", text: $searchText)
                .textInputAutocapitalization(.words)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    searchFocused = false
                }
                .onChange(of: searchText) { _, value in
                    search.query = value
                }
            if searchFocused || !searchText.isEmpty {
                Button {
                    searchText = ""
                    search.query = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除並關閉鍵盤")
            }
            if searchFocused {
                Button("完成") {
                    searchFocused = false
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(LocusTheme.accent)
            }
        }
        .padding(12)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(search.results.prefix(5), id: \.self) { item in
                Button {
                    select(completion: item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
            }
        }
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var mapChromeButtons: some View {
        HStack(spacing: 4) {
            chromeIconButton("gearshape.fill") {
                showSettings = true
            }

            chromeIconButton("star.fill") {
                showPlaces = true
            }

            Menu {
                Button {
                    showGPXImporter = true
                } label: {
                    Label("匯入 GPX", systemImage: "square.and.arrow.down")
                }
                Button {
                    exportGPX()
                } label: {
                    Label("匯出目前路線", systemImage: "square.and.arrow.up")
                }
                .disabled(routeCoords.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)

            if session.pin != nil {
                chromeIconButton("star.circle") {
                    if let pin = session.pin {
                        let name = session.suggestedFavoriteName(for: pin, fallback: pinPlaceName)
                        session.addFavorite(name: name, coordinate: pin)
                    }
                }
            }
        }
        .padding(6)
        .locusGlass(.clear, in: Capsule())
        .contentShape(Capsule())
    }

    private var locateButton: some View {
        Button {
            searchFocused = false
            goToCurrentLocation()
        } label: {
            Image(systemName: "location.fill")
                .font(.body.weight(.semibold))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .locusGlass(.interactive, in: Circle())
        .foregroundStyle(.primary)
        .contentShape(Circle())
        .accessibilityLabel("目前位置")
    }

    /// Centers on the spoofed fix while spoofing, otherwise the real GPS —
    /// never the leftover teleport pin (`.automatic` would frame that marker).
    private func goToCurrentLocation() {
        let meters: CLLocationDistance = 900
        withAnimation(.easeInOut(duration: 0.35)) {
            if session.isSpoofing, let sim = session.simulated {
                position = .region(MKCoordinateRegion(
                    center: sim,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else if let real = session.realCoordinate {
                position = .region(MKCoordinateRegion(
                    center: real,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else {
                position = .userLocation(
                    followsHeading: false,
                    fallback: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                        latitudinalMeters: 2000,
                        longitudinalMeters: 2000
                    ))
                )
            }
        }
    }

    private func chromeIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func select(completion: MKLocalSearchCompletion) {
        Task {
            let request = MKLocalSearch.Request(completion: completion)
            if let response = try? await MKLocalSearch(request: request).start(),
               let item = response.mapItems.first {
                let coord = item.placemark.coordinate
                let title = item.name ?? completion.title
                await MainActor.run {
                    session.pin = coord
                    pinPlaceName = title
                    position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1200, longitudinalMeters: 1200))
                    searchText = ""
                    search.query = ""
                    searchFocused = false
                    session.addFavorite(name: title, coordinate: coord)
                    session.pushNamedRecent(name: title, coordinate: coord)
                }
            }
        }
    }

    private func importGPX(_ url: URL) {
        do {
            let coords = try GPXCodec.parse(url)
            let sampled = RouteBuilder.sample(coordinates: coords, every: 10)
            if let first = coords.first {
                session.pin = first
                position = .region(MKCoordinateRegion(center: first, latitudinalMeters: 2000, longitudinalMeters: 2000))
            }
            presentSpeedPicker(.importedGPX(sampled))
        } catch {
            session.lastError = error.localizedDescription
        }
    }

    private func exportGPX() {
        guard !routeCoords.isEmpty else {
            session.lastError = "沒有可以匯出的內容。"
            return
        }
        let gpx = GPXCodec.export(routeCoords)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Locus-Route.gpx")
        do {
            try gpx.data(using: .utf8)?.write(to: url)
            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.keyWindow?.rootViewController {
                root.present(av, animated: true)
            }
        } catch {
            session.lastError = error.localizedDescription
        }
    }
}

/// Bottom sheet shown after dropping a pin — matches the "change your
/// location" style reference: plain list of modes anchored to the bottom,
/// map stays visible (and centered on the pin) above it.
private struct PinActionSheet: View {
    var onTeleport: () -> Void
    var onNavigate: () -> Void
    var onMultiStop: () -> Void
    var onJoystick: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("更改你的位置")
                .font(.headline)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()
            row(icon: "bolt.fill", title: "傳送模式") {
                dismiss()
                onTeleport()
            }
            Divider().padding(.leading, 56)
            row(icon: "arrow.triangle.turn.up.right.diamond.fill", title: "導航模式") {
                dismiss()
                onNavigate()
            }
            Divider().padding(.leading, 56)
            row(icon: "mappin.and.ellipse", title: "多點模式") {
                dismiss()
                onMultiStop()
            }
            Divider().padding(.leading, 56)
            row(icon: "dot.circle.and.hand.point.up.left.fill", title: "搖桿模式") {
                dismiss()
                onJoystick()
            }

            Spacer(minLength: 0)
        }
    }

    private func row(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LocusTheme.accent)
                    .frame(width: 24)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Small numbered marker for multi-stop waypoints, in visit order.
private struct WaypointMarker: View {
    let number: Int

    var body: some View {
        ZStack {
            Circle().fill(LocusTheme.accentSecondary).frame(width: 26, height: 26)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }
}

/// `SpeedPickerContext` isn't `Identifiable`-friendly to store directly in a
/// `@State` across view updates without a stable box; this wrapper gives the
/// `.sheet(item:)` modifier a stable identity per presentation.
private struct SpeedPickerContextWrapper: Identifiable {
    let context: SpeedPickerContext
    var id: String { context.id }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}

@MainActor
final class PlaceSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    var query: String = "" {
        didSet {
            completer.queryFragment = query
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results
        Task { @MainActor in self.results = items }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
