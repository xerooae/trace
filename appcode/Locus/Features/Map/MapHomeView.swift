import MapKit
import NetworkExtension
import SwiftUI
import UIKit

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

    // MARK: - Bottom stack (thumb zone): tools float above, the tray is one line

    private var bottomStack: some View {
        VStack(spacing: TraceTheme.rowGap) {
            floatingRow
            if session.joystickActive || session.followingRoute {
                travelModePicker
            }
            lineCapsule
                .frame(maxWidth: isRegular ? 420 : .infinity)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, TraceTheme.gutter)
        .padding(.bottom, 10)
        .animation(TraceTheme.motion, value: trayKey)
    }

    /// Changes whenever the bottom stack changes shape, so it animates smoothly.
    private var trayKey: String {
        "\(session.joystickActive)|\(session.followingRoute)|\(session.candidate != nil)|\(session.status.label)|\(route.drawing)|\(tunnelConnected)"
    }

    /// Routes and Joystick float on the left; map controls, or the joystick pad, on the right.
    private var floatingRow: some View {
        HStack(alignment: .bottom, spacing: TraceTheme.rowGap) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    glassButton("point.topleft.down.to.point.bottomright.curvepath", label: "Routes") {
                        showRoutes = true
                    }
                    glassButton("dot.circle.and.hand.point.up.left.fill", label: "Joystick",
                                selected: session.joystickActive, action: toggleJoystick)
                }
            }
            Spacer(minLength: 0)
            if session.joystickActive {
                JoystickPad { session.updateJoystick(vector: $0) }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        glassButton("square.3.layers.3d",
                                    label: session.mapStyleIndex == 1 ? "Map style: satellite" : "Map style: muted",
                                    action: cycleMapStyle)
                        glassButton("location", label: "Show my position", action: showMyPosition)
                    }
                }
            }
        }
    }

    /// A floating glass circle. Selected (Joystick on) is Trace Blue glass.
    @ViewBuilder private func glassButton(_ systemImage: String, label: String, selected: Bool = false,
                                          action: @escaping () -> Void) -> some View {
        if selected {
            Button(action: action) {
                Image(systemName: systemImage)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .tint(TraceTheme.accent)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isSelected)
        } else {
            Button(action: action) {
                Image(systemName: systemImage)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .tint(.white)
            .accessibilityLabel(label)
        }
    }

    private var travelModePicker: some View {
        Picker("Travel mode", selection: $session.travelMode) {
            ForEach(TravelMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(6)
        .traceGlass(.regular, in: Capsule())
        .frame(maxWidth: isRegular ? 420 : .infinity)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sensoryFeedback(.selection, trigger: session.travelMode)
    }

    // MARK: - The one line

    /// What the line says: the marker's state, a title, then the coordinates
    /// (or a short detail when there are none). Live says so in the title.
    private struct Line {
        var state: PositionState
        var title: String
        var coordinate: CLLocationCoordinate2D? = nil
        var detail: String? = nil
    }

    private var currentLine: Line {
        if route.drawing {
            return Line(state: .off, title: "Drawing a path",
                        detail: route.drawn.count < 2 ? "Tap the map to add points" : "\(route.drawn.count) points")
        }
        if session.status.isDropped {
            return Line(state: .interrupted, title: "Interrupted", detail: "Reconnecting…")
        }
        if session.status == .connecting || session.status == .reconnecting {
            return Line(state: .connecting, title: session.status.label, detail: session.liveName ?? "Opening the tunnel")
        }
        if let candidate = session.candidate {
            // The grey marker and the blue Move already say it isn't sent.
            return Line(state: .candidate, title: session.pinName ?? "Selected position", coordinate: candidate)
        }
        if session.isSpoofing, let live = session.simulated {
            return Line(state: .live, title: liveTitle, coordinate: live)
        }
        if !tunnelConnected {
            return Line(state: .off, title: "LocalDevVPN isn't connected", detail: "Connect it before you move")
        }
        return Line(state: .off, title: "Off", detail: "Tap the map or search")
    }

    /// "Live · Shibuya Crossing", "Live · Joystick", "Live · Route".
    private var liveTitle: String {
        if session.joystickActive { return "Live · Joystick" }
        if session.followingRoute { return "Live · Route" }
        return "Live · \(session.liveName ?? "Position set")"
    }

    /// The tray is one glass capsule: the marker, what's happening and where, then the
    /// action at the thumb. Long-press it for Save, Copy coordinates and Clear.
    private var lineCapsule: some View {
        let line = currentLine
        return HStack(spacing: 12) {
            PositionMarker(state: line.state, width: 14)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(line.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TraceTheme.ink)
                    .lineLimit(1)
                Group {
                    if let coordinate = line.coordinate {
                        Text(Coord.format(coordinate))
                            .font(.caption.monospaced())
                    } else if let detail = line.detail {
                        Text(detail)
                            .font(.caption)
                    }
                }
                .foregroundStyle(TraceTheme.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 4)
            lineActions
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(minHeight: 64)
        .traceGlass(.regular, in: Capsule())
        .contextMenu { lineMenu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Controls")
    }

    /// One action at the thumb: blue Move, or a neutral Stop, Cancel, Connect or Done.
    @ViewBuilder private var lineActions: some View {
        if route.drawing {
            Button {
                _ = route.drawn.popLast()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.body.weight(.medium))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(TraceTheme.ink)
            .disabled(route.drawn.isEmpty)
            .accessibilityLabel("Undo last point")
            lineButton("Done", primary: false, action: finishDrawing)
        } else if session.status.isDropped || session.status == .reconnecting {
            lineButton("Stop", primary: false) { session.stop(pairing: pairing) }
        } else if session.status == .connecting {
            lineButton("Cancel", primary: false) { session.stop(pairing: pairing) }
        } else if let candidate = session.candidate {
            if session.isSpoofing {
                lineButton("Stop", primary: false) { session.stop(pairing: pairing) }
            } else {
                starButton(candidate, name: session.pinName)
            }
            lineButton("Move", primary: true) { session.teleport(to: candidate, pairing: pairing) }
                .disabled(session.isBusy)
        } else if session.isSpoofing, let live = session.simulated {
            starButton(live, name: session.liveName)
            lineButton("Stop", primary: false) { session.stop(pairing: pairing) }
        } else if !tunnelConnected {
            lineButton("Connect", primary: false) { LocalDevVPN.openOrInstall() }
        } else {
            lineButton("Move", primary: true) {}
                .disabled(true)
        }
    }

    private func starButton(_ coordinate: CLLocationCoordinate2D, name: String?) -> some View {
        let saved = session.isFavorite(coordinate)
        return Button {
            session.toggleFavorite(coordinate, name: name)
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.body.weight(.medium))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(TraceTheme.ink)
        .accessibilityLabel(saved ? "Remove from Favourites" : "Save to Favourites")
        .sensoryFeedback(.selection, trigger: saved)
    }

    /// A compact capsule inside the line: Trace Blue for Move, neutral for the rest.
    @ViewBuilder private func lineButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        if primary {
            Button(action: action) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(TraceTheme.accent)
        } else {
            Button(action: action) {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.white)
        }
    }

    /// Long-press menu on the line.
    @ViewBuilder private var lineMenu: some View {
        if let coordinate = session.candidate ?? session.simulated {
            let name = session.candidate != nil ? session.pinName : session.liveName
            Button {
                session.toggleFavorite(coordinate, name: name)
            } label: {
                Label(session.isFavorite(coordinate) ? "Remove from Favourites" : "Save to Favourites", systemImage: "star")
            }
            Button {
                UIPasteboard.general.string = Coord.format(coordinate, decimals: 5)
            } label: {
                Label("Copy coordinates", systemImage: "doc.on.doc")
            }
            if session.candidate != nil {
                Button(role: .destructive) {
                    session.clearCandidate()
                } label: {
                    Label("Clear place", systemImage: "xmark")
                }
            }
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
        session.nameCandidate(coordinate)
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
