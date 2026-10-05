import MapKit
import NetworkExtension
import SwiftUI

/// A route being built, drawn or imported on the Map tab.
struct RouteDraft {
    var destination: CLLocationCoordinate2D?
    var destinationName: String?
    var coordinates: [CLLocationCoordinate2D] = []
    var drawn: [CLLocationCoordinate2D] = []
    var drawing = false
    var building = false
    var name: String?

    var hasRoute: Bool { coordinates.count >= 2 }

    var distance: CLLocationDistance {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { $0 + Coord.distance($1.0, $1.1) }
    }
}

/// Home. Read high, act low: the status pill sits at the top, and every control
/// is in the tray or floats just above it. Search lives in its own tab control.
struct MapHomeView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Prefs.showRealPosition) private var showReal = true

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showRoutes = false
    @State private var route = RouteDraft()
    @State private var tunnelConnected = LocalDevVPN.isConnected

    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                mapContent
            }
            .mapStyle(mapStyle)
            .mapControlVisibility(.hidden)
            // Global coordinates keep the tap and the conversion in the same space.
            .onTapGesture(coordinateSpace: .global) { point in
                handleTap(point, proxy: proxy)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            statusPill
                .frame(maxWidth: isRegular ? 420 : .infinity)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TraceTheme.gutter)
                .padding(.top, 4)
        }
        .overlay(alignment: .bottom) {
            bottomStack
        }
        .sheet(isPresented: $showRoutes) {
            RoutesSheet(
                route: $route,
                onBuild: buildRoute,
                onFollow: followRoute,
                onDraw: startDrawing,
                onImport: importGPX,
                onSave: { session.saveRoute(name: $0, coordinates: route.coordinates) }
            )
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .onAppear {
            session.startLocationUpdates()
            refreshTunnel()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshTunnel() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)) { _ in
            refreshTunnel()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                refreshTunnel()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .traceImportGPX)) { note in
            if let url = note.object as? URL { importGPX(url) }
        }
        .onChange(of: router.cameraTarget) { _, place in
            guard let place else { return }
            focus(place.coordinate)
            router.cameraTarget = nil
        }
        .onChange(of: router.routeDestination) { _, place in
            guard let place else { return }
            route = RouteDraft()
            route.destination = place.coordinate
            route.destinationName = place.name
            focus(place.coordinate)
            showRoutes = true
            router.routeDestination = nil
        }
        .onChange(of: router.routeToLoad) { _, saved in
            guard let saved else { return }
            route = RouteDraft()
            route.coordinates = saved.coordinates
            route.name = saved.name
            session.travelMode = saved.travelMode
            if let first = saved.coordinates.first { focus(first, meters: 3000) }
            showRoutes = true
            router.routeToLoad = nil
        }
    }

    // MARK: - Map

    @MapContentBuilder private var mapContent: some MapContent {
        if showReal, session.simulated == nil, let real = session.realLocation {
            Annotation("", coordinate: real, anchor: .center) {
                RealPositionMarker()
            }
            .annotationTitles(.hidden)
        }
        if route.coordinates.count > 1 {
            MapPolyline(coordinates: route.coordinates)
                .stroke(Color.white.opacity(0.8), lineWidth: 3)
        }
        if route.drawn.count > 1 {
            MapPolyline(coordinates: route.drawn)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [4, 6]))
        }
        if session.trail.count > 1 {
            MapPolyline(coordinates: session.trail)
                .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
        }
        if let candidate = session.candidate {
            Annotation("", coordinate: candidate, anchor: .center) {
                PositionMarker(state: .candidate)
            }
            .annotationTitles(.hidden)
        }
        if let live = session.simulated {
            Annotation("", coordinate: live, anchor: .center) {
                PositionMarker(state: markerState, heading: .degrees(session.heading))
            }
            .annotationTitles(.hidden)
        }
    }

    private var mapStyle: MapStyle {
        if session.mapStyleIndex == 1 {
            return .hybrid(elevation: .realistic)
        }
        return .standard(elevation: .realistic, emphasis: .muted)
    }

    private var markerState: PositionState {
        switch session.status {
        case .idle: return .candidate
        case .connecting, .reconnecting: return .connecting
        case .active: return .live
        case .dropped: return .interrupted
        }
    }

    // MARK: - Status pill (reading only)

    private var statusPill: some View {
        switch session.status {
        case .idle:
            return StatusPill(
                state: session.candidate == nil ? .off : .candidate,
                title: "Off",
                subtitle: session.candidate == nil ? "Tap the map or search" : "Position placed, not sent",
                coordinate: nil
            )
        case .connecting:
            return StatusPill(state: .connecting, title: "Connecting…", subtitle: "Opening the tunnel", coordinate: nil)
        case .active:
            return StatusPill(state: .live, title: "Live", subtitle: liveSubtitle, coordinate: session.simulated)
        case .reconnecting:
            return StatusPill(state: .connecting, title: "Reconnecting…", subtitle: liveSubtitle, coordinate: session.simulated)
        case .dropped:
            return StatusPill(state: .interrupted, title: "Interrupted", subtitle: "Reconnecting…", coordinate: session.simulated)
        }
    }

    private var liveSubtitle: String {
        if session.joystickActive { return "Joystick · \(session.travelMode.title)" }
        if session.followingRoute { return "Following a route · \(session.travelMode.title)" }
        return session.liveName ?? "Position set"
    }

    // MARK: - Bottom stack (thumb zone)

    private var bottomStack: some View {
        VStack(spacing: TraceTheme.rowGap) {
            floatingRow
            tray
                .frame(maxWidth: isRegular ? 400 : .infinity)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, TraceTheme.gutter)
        .padding(.bottom, 10)
        .animation(TraceTheme.motion, value: trayKey)
    }

    /// Changes whenever the tray's rows change, so rows grow upward smoothly.
    private var trayKey: String {
        "\(session.joystickActive)|\(session.followingRoute)|\(session.candidate != nil)|\(session.status.label)|\(route.drawing)|\(tunnelConnected)"
    }

    private var floatingRow: some View {
        HStack(alignment: .bottom, spacing: TraceTheme.rowGap) {
            if session.joystickActive {
                mapButtons
                Spacer(minLength: 0)
                JoystickPad { session.updateJoystick(vector: $0) }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                Spacer(minLength: 0)
                mapButtons
            }
        }
    }

    private var mapButtons: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: cycleMapStyle) {
                    Image(systemName: "square.3.layers.3d")
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel(session.mapStyleIndex == 1 ? "Map style: satellite" : "Map style: muted")
                Button(action: showMyPosition) {
                    Image(systemName: "location")
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel("Show my position")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .tint(.white)
        }
    }

    private var tray: some View {
        VStack(spacing: TraceTheme.rowGap) {
            if route.drawing {
                drawingRow
            } else {
                contextRow
            }
            if session.joystickActive || session.followingRoute {
                Picker("Travel mode", selection: $session.travelMode) {
                    ForEach(TravelMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: session.travelMode)
            }
            actionRow
        }
        .padding(TraceTheme.trayPadding)
        .traceGlass(.regular, in: RoundedRectangle(cornerRadius: TraceTheme.trayRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Controls")
    }

    @ViewBuilder private var contextRow: some View {
        if session.status.isDropped {
            note("Interrupted", "The tunnel dropped. Trace is reconnecting and will go live again on its own.")
        } else if let candidate = session.candidate {
            placeRow(session.pinName ?? "Selected position", candidate, favoriteName: session.pinName, clearable: true)
        } else if session.isSpoofing, let live = session.simulated {
            placeRow(session.liveName ?? "Position set", live, favoriteName: session.liveName, clearable: false)
        } else if !tunnelConnected {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LocalDevVPN isn't connected")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TraceTheme.ink)
                    Text("Connect it before you move.")
                        .font(.footnote)
                        .foregroundStyle(TraceTheme.ink2)
                }
                .padding(.leading, 6)
                Spacer(minLength: 8)
                SecondaryButton("Connect", size: .regular, expand: false) {
                    LocalDevVPN.openOrInstall()
                }
            }
        }
    }

    private func placeRow(_ title: String, _ coordinate: CLLocationCoordinate2D, favoriteName: String?, clearable: Bool) -> some View {
        let saved = session.isFavorite(coordinate)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TraceTheme.ink)
                    .lineLimit(1)
                Text(Coord.format(coordinate))
                    .font(.caption.monospaced())
                    .foregroundStyle(TraceTheme.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.leading, 6)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            CircleButton(systemImage: saved ? "star.fill" : "star",
                         label: saved ? "Remove from Favourites" : "Save to Favourites") {
                session.toggleFavorite(coordinate, name: favoriteName)
            }
            .sensoryFeedback(.selection, trigger: saved)
            if clearable {
                CircleButton(systemImage: "xmark", label: "Clear place") {
                    session.clearCandidate()
                }
            }
        }
    }

    private func note(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TraceTheme.ink)
            Text(body)
                .font(.footnote)
                .foregroundStyle(TraceTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private var drawingRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Drawing a path")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TraceTheme.ink)
                Text(route.drawn.count < 2 ? "Tap the map to add points." : "\(route.drawn.count) points")
                    .font(.footnote)
                    .foregroundStyle(TraceTheme.ink2)
            }
            .padding(.leading, 6)
            Spacer(minLength: 8)
            CircleButton(systemImage: "arrow.uturn.backward", label: "Undo last point") {
                _ = route.drawn.popLast()
            }
            .disabled(route.drawn.isEmpty)
            SecondaryButton("Done", size: .regular, expand: false, action: finishDrawing)
        }
    }

    private var actionRow: some View {
        HStack(spacing: TraceTheme.rowGap) {
            CircleButton(systemImage: "point.topleft.down.to.point.bottomright.curvepath", label: "Routes") {
                showRoutes = true
            }
            CircleButton(systemImage: "dot.circle.and.hand.point.up.left.fill",
                         label: "Joystick",
                         selected: session.joystickActive,
                         action: toggleJoystick)
            primaryAction
        }
    }

    /// One white action, closest to the thumb. Stop and Cancel are bordered, not red.
    @ViewBuilder private var primaryAction: some View {
        if let candidate = session.candidate {
            if session.isSpoofing {
                SecondaryButton("Stop", expand: false) { session.stop(pairing: pairing) }
            }
            PrimaryButton("Move here") { session.teleport(to: candidate, pairing: pairing) }
                .disabled(session.isBusy)
        } else if session.status == .connecting {
            SecondaryButton("Cancel") { session.stop(pairing: pairing) }
        } else if session.isSpoofing || session.status.isDropped {
            SecondaryButton("Stop") { session.stop(pairing: pairing) }
        } else {
            PrimaryButton("Move here") {}
                .disabled(true)
        }
    }

    // MARK: - Actions

    private func handleTap(_ point: CGPoint, proxy: MapProxy) {
        guard let coordinate = proxy.convert(point, from: .global) else { return }
        if route.drawing {
            route.drawn.append(coordinate)
            return
        }
        session.placeCandidate(coordinate, name: nil)
        lookUpName(for: coordinate)
    }

    private func lookUpName(for coordinate: CLLocationCoordinate2D) {
        Task {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first,
                  Coord.same(session.pin, coordinate),
                  session.pinName == nil else { return }
            session.pinName = placemark.name ?? placemark.locality
        }
    }

    private func focus(_ coordinate: CLLocationCoordinate2D, meters: CLLocationDistance = 1200) {
        withAnimation(TraceTheme.camera) {
            position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters))
        }
    }

    /// The live position while live, otherwise your real one.
    private func showMyPosition() {
        if let target = session.simulated ?? session.realCoordinate {
            focus(target, meters: 900)
        } else {
            withAnimation(TraceTheme.camera) { position = .userLocation(fallback: .automatic) }
        }
    }

    private func cycleMapStyle() {
        session.mapStyleIndex = session.mapStyleIndex == 1 ? 0 : 1
    }

    private func toggleJoystick() {
        if session.joystickActive {
            session.stopJoystick()
        } else {
            session.startJoystick(pairing: pairing)
        }
    }

    private func refreshTunnel() {
        tunnelConnected = LocalDevVPN.isConnected
    }

    // MARK: - Routes

    private func buildRoute() {
        guard let end = route.destination ?? session.candidate else { return }
        guard let start = session.simulated ?? session.realCoordinate else {
            session.lastError = "Trace doesn't know where to start. Allow location access, or move somewhere first."
            return
        }
        let mode = session.travelMode
        let name = route.destinationName ?? session.pinName
        route.building = true
        Task {
            do {
                route.coordinates = try await RouteBuilder.roadRoute(from: start, to: end, mode: mode)
                route.name = name.map { "To \($0)" }
            } catch {
                session.lastError = error.localizedDescription
            }
            route.building = false
        }
    }

    private func followRoute() {
        guard route.hasRoute else { return }
        showRoutes = false
        session.followRoute(route.coordinates, name: route.name, pairing: pairing)
    }

    private func startDrawing() {
        showRoutes = false
        route = RouteDraft()
        route.drawing = true
    }

    private func finishDrawing() {
        route.drawing = false
        if route.drawn.count >= 2 {
            route.coordinates = RouteBuilder.sample(coordinates: route.drawn, every: 10)
            route.name = "Drawn path"
        }
        route.drawn = []
        showRoutes = route.hasRoute
    }

    private func importGPX(_ url: URL) {
        do {
            let coordinates = try GPXCodec.parse(url)
            route = RouteDraft()
            route.coordinates = RouteBuilder.sample(coordinates: coordinates, every: 10)
            route.name = url.deletingPathExtension().lastPathComponent
            if let first = coordinates.first { focus(first, meters: 3000) }
            showRoutes = true
        } catch {
            session.lastError = error.localizedDescription
        }
    }
}

/// The marker in its state, the word, then coordinates in SF Mono. Reading only.
struct StatusPill: View {
    let state: PositionState
    let title: String
    let subtitle: String?
    let coordinate: CLLocationCoordinate2D?

    var body: some View {
        HStack(spacing: 12) {
            PositionMarker(state: state, width: 11)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TraceTheme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(TraceTheme.ink2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let coordinate {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Coord.parts(coordinate).0)
                    Text(Coord.parts(coordinate).1)
                }
                .font(.caption.monospaced())
                .foregroundStyle(TraceTheme.ink2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(minHeight: 54)
        .traceGlass(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
