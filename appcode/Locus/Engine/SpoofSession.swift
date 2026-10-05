import CoreLocation
import Foundation
import MapKit
import UIKit
import UserNotifications

enum TravelMode: String, CaseIterable, Identifiable {
    case walk, run, cycle, drive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return "Walk"
        case .run: return "Run"
        case .cycle: return "Cycle"
        case .drive: return "Drive"
        }
    }

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .cycle: return "bicycle"
        case .drive: return "car"
        }
    }

    /// Base meters per second before natural variation.
    var baseSpeed: CLLocationSpeed {
        switch self {
        case .walk: return 1.4
        case .run: return 3.3
        case .cycle: return 6.5
        case .drive: return 13.4
        }
    }

    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .walk, .run: return .walking
        case .cycle, .drive: return .automobile
        }
    }
}

enum SpoofStatus: Equatable {
    case idle
    case connecting
    case active
    case reconnecting
    case dropped(String)

    /// The status word. State is always said in words, never by colour alone.
    var label: String {
        switch self {
        case .idle: return "Off"
        case .connecting: return "Connecting…"
        case .active: return "Live"
        case .reconnecting: return "Reconnecting…"
        case .dropped: return "Interrupted"
        }
    }

    var isDropped: Bool {
        if case .dropped = self { return true }
        return false
    }
}

@MainActor
final class SpoofSession: ObservableObject {
    @Published var status: SpoofStatus = .idle
    /// The candidate position: placed on the map but not sent yet. Equals `simulated` while live.
    @Published var pin: CLLocationCoordinate2D?
    @Published var pinName: String?
    @Published var simulated: CLLocationCoordinate2D?
    /// Name of the live position, when it came from search or Places.
    @Published var liveName: String?
    /// Degrees from north, unwrapped so the marker always turns the short way round.
    @Published private(set) var heading: Double = 0
    /// Where the live position has been during this session, for the trail on the map.
    @Published private(set) var trail: [CLLocationCoordinate2D] = []
    @Published private(set) var followingRoute = false
    /// The device's own position, captured while nothing is live.
    @Published private(set) var realLocation: CLLocationCoordinate2D?
    @Published var travelMode: TravelMode = .walk
    @Published var mapStyleIndex: Int = UserDefaults.standard.integer(forKey: Prefs.mapStyle) {
        didSet { UserDefaults.standard.set(mapStyleIndex, forKey: Prefs.mapStyle) }
    }
    @Published var lastError: String?
    @Published var isBusy = false
    @Published var joystickActive = false

    @Published var favorites: [SavedPlace] = []
    @Published var recents: [SavedPlace] = []
    @Published var savedRoutes: [SavedRoute] = []

    private var resendTimer: Timer?
    private var healthTimer: Timer?
    private var joystickTimer: Timer?
    private var routeTask: Task<Void, Never>?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var joystickVector: CGVector = .zero
    private let locationKeeper = BackgroundKeepAlive()

    private let favoritesKey = "locus.favorites"
    private let recentsKey = "locus.recents"
    private let routesKey = "trace.routes"

    init() {
        favorites = SavedPlace.load(key: favoritesKey)
        recents = SavedPlace.load(key: recentsKey)
        savedRoutes = SavedRoute.load(key: routesKey)
        locationKeeper.setPrecise(true)
        locationKeeper.onUpdate = { [weak self] coordinate in
            Task { @MainActor in
                self?.receiveDeviceLocation(coordinate)
            }
        }
    }

    var isSpoofing: Bool {
        if case .active = status { return true }
        if case .reconnecting = status { return true }
        return false
    }

    /// A placed position that isn't the live one yet.
    var candidate: CLLocationCoordinate2D? {
        guard let pin else { return nil }
        return Coord.same(pin, simulated) ? nil : pin
    }

    func placeCandidate(_ coordinate: CLLocationCoordinate2D, name: String?) {
        pin = coordinate
        pinName = name
    }

    func clearCandidate() {
        pin = simulated
        pinName = nil
    }

    func teleport(to coordinate: CLLocationCoordinate2D, name: String? = nil, pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "Pair this iPhone in Settings first."
            return
        }
        routeTask?.cancel()
        routeTask = nil
        followingRoute = false
        let placeName = name ?? (Coord.same(coordinate, pin) ? pinName : nil)
        pin = coordinate
        pinName = placeName
        liveName = placeName
        apply(coordinate, pairing: pairing, markRecent: true)
    }

    func stop(pairing: PairingStore) {
        routeTask?.cancel()
        routeTask = nil
        followingRoute = false
        stopJoystick()
        stopResend()
        stopHealth()
        isBusy = true
        let result = LocationEngine.clear()
        isBusy = false
        switch result {
        case .success:
            simulated = nil
            liveName = nil
            heading = 0
            trail = []
            status = .idle
            endBackground()
            // Keep location updates running so the map can return to the real fix.
            locationKeeper.setPrecise(true)
            locationKeeper.start()
        case .failure(let error):
            lastError = error.localizedDescription
            status = .dropped(error.localizedDescription)
            postDropNotification()
        }
    }

    /// Best-known real device coordinate (not the set position).
    var realCoordinate: CLLocationCoordinate2D? {
        realLocation ?? (simulated == nil ? locationKeeper.lastKnownCoordinate : nil)
    }

    /// Start lightweight GPS updates for the real-position marker and Locate.
    func startLocationUpdates() {
        locationKeeper.start()
    }

    func startJoystick(pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "Pair this iPhone in Settings first."
            return
        }
        let start = simulated ?? pin ?? realCoordinate
        guard let start else {
            lastError = "Place a position on the map first."
            return
        }
        routeTask?.cancel()
        routeTask = nil
        followingRoute = false
        if simulated == nil {
            liveName = pinName
            apply(start, pairing: pairing, markRecent: false)
        }
        joystickActive = true
        joystickTimer?.invalidate()
        joystickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickJoystick(pairing: pairing)
            }
        }
    }

    func updateJoystick(vector: CGVector) {
        joystickVector = vector
    }

    func stopJoystick() {
        joystickActive = false
        joystickVector = .zero
        joystickTimer?.invalidate()
        joystickTimer = nil
    }

    func followRoute(_ coordinates: [CLLocationCoordinate2D], name: String? = nil, pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "Pair this iPhone in Settings first."
            return
        }
        guard coordinates.count >= 2 else { return }
        routeTask?.cancel()
        stopJoystick()
        let mode = travelMode
        let varies = Prefs.bool(Prefs.speedVariation)
        liveName = name
        followingRoute = true
        routeTask = Task { [weak self] in
            guard let self else { return }
            var previous = coordinates[0]
            await MainActor.run {
                self.apply(previous, pairing: pairing, markRecent: true)
            }
            for next in coordinates.dropFirst() {
                if Task.isCancelled { break }
                let distance = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                    .distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude))
                var speed = mode.baseSpeed * (varies ? Double.random(in: 0.88...1.12) : 1)
                speed = max(0.8, speed)
                let stepMeters: CLLocationDistance = min(12, max(4, speed * 0.5))
                let steps = max(1, Int(ceil(distance / stepMeters)))
                for i in 1...steps {
                    if Task.isCancelled { break }
                    let t = Double(i) / Double(steps)
                    let coord = CLLocationCoordinate2D(
                        latitude: previous.latitude + (next.latitude - previous.latitude) * t,
                        longitude: previous.longitude + (next.longitude - previous.longitude) * t
                    )
                    let delay = stepMeters / speed
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    await MainActor.run {
                        self.apply(coord, pairing: pairing, markRecent: false)
                    }
                }
                previous = next
            }
            await MainActor.run {
                if !Task.isCancelled { self.followingRoute = false }
            }
        }
    }

    // MARK: - Favourites, recents, routes

    func isFavorite(_ coordinate: CLLocationCoordinate2D) -> Bool {
        favorites.contains { Coord.same($0.coordinate, coordinate) }
    }

    func toggleFavorite(_ coordinate: CLLocationCoordinate2D, name: String?) {
        if let existing = favorites.first(where: { Coord.same($0.coordinate, coordinate) }) {
            removeFavorite(existing)
        } else {
            addFavorite(name: name ?? suggestedFavoriteName(for: coordinate), coordinate: coordinate)
        }
    }

    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            coordinate: coordinate
        )
        // Don't let a generic star overwrite a named favorite for the same spot.
        if let existing = favorites.first(where: { $0.id == place.id }),
           Self.isGenericFavoriteName(place.name),
           !Self.isGenericFavoriteName(existing.name) {
            return
        }
        favorites.removeAll { $0.id == place.id }
        favorites.insert(place, at: 0)
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func renameFavorite(_ place: SavedPlace, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[index].name = trimmed
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeFavorite(_ place: SavedPlace) {
        favorites.removeAll { $0.id == place.id }
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeRecent(_ place: SavedPlace) {
        recents.removeAll { $0.id == place.id }
        SavedPlace.save(recents, key: recentsKey)
    }

    func saveRoute(name: String, coordinates: [CLLocationCoordinate2D]) {
        guard coordinates.count >= 2 else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let route = SavedRoute(
            name: trimmed.isEmpty ? "Route \(savedRoutes.count + 1)" : trimmed,
            coordinates: coordinates,
            mode: travelMode
        )
        savedRoutes.insert(route, at: 0)
        SavedRoute.save(savedRoutes, key: routesKey)
    }

    func renameRoute(_ route: SavedRoute, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = savedRoutes.firstIndex(where: { $0.id == route.id }) else { return }
        savedRoutes[index].name = trimmed
        SavedRoute.save(savedRoutes, key: routesKey)
    }

    func removeRoute(_ route: SavedRoute) {
        savedRoutes.removeAll { $0.id == route.id }
        SavedRoute.save(savedRoutes, key: routesKey)
    }

    /// Best display name for starring a position (search title, matching recent, etc.).
    func suggestedFavoriteName(for coordinate: CLLocationCoordinate2D, fallback: String? = nil) -> String {
        if let fallback, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let favorite = favorites.first(where: { Coord.same($0.coordinate, coordinate) }),
           !Self.isGenericFavoriteName(favorite.name) {
            return favorite.name
        }
        if let recent = recents.first(where: {
            abs($0.latitude - coordinate.latitude) < 0.00015 && abs($0.longitude - coordinate.longitude) < 0.00015
        }), !Self.isGenericFavoriteName(recent.name) {
            return recent.name
        }
        return Self.coordinateLabel(coordinate)
    }

    private static func coordinateLabel(_ coordinate: CLLocationCoordinate2D) -> String {
        Coord.format(coordinate)
    }

    private static func isGenericFavoriteName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Favorite" { return true }
        if trimmed.hasSuffix("° E") || trimmed.hasSuffix("° W") { return true }
        // Coordinate-looking labels from older builds.
        let parts = trimmed.split(separator: ",")
        if parts.count == 2,
           Double(parts[0].trimmingCharacters(in: .whitespaces)) != nil,
           Double(parts[1].trimmingCharacters(in: .whitespaces)) != nil {
            return true
        }
        return false
    }

    // MARK: - Engine

    private func receiveDeviceLocation(_ coordinate: CLLocationCoordinate2D) {
        // While a position is live the device reports that position, not where you are.
        guard simulated == nil, status == .idle else { return }
        realLocation = coordinate
    }

    private func apply(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore, markRecent: Bool) {
        if status == .idle || status.isDropped {
            status = .connecting
        }
        isBusy = true
        let result = LocationEngine.set(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            pairingPath: pairing.pairingPath,
            deviceIP: TunnelConfig.targetIP
        )
        isBusy = false
        switch result {
        case .success:
            track(from: simulated, to: coordinate, jumped: markRecent)
            simulated = coordinate
            pin = coordinate
            status = .active
            lastError = nil
            beginBackground()
            locationKeeper.setPrecise(false)
            locationKeeper.start()
            startResend(pairing: pairing)
            startHealth(pairing: pairing)
            if markRecent {
                pushNamedRecent(name: liveName ?? Self.coordinateLabel(coordinate), coordinate: coordinate)
            }
        case .failure(let error):
            lastError = error.localizedDescription
            if simulated != nil {
                status = .dropped(error.localizedDescription)
                postDropNotification()
            } else {
                status = .idle
            }
        }
    }

    /// Heading and trail for the live marker. A jump (Move here) resets both;
    /// the marker points north when still.
    private func track(from previous: CLLocationCoordinate2D?, to next: CLLocationCoordinate2D, jumped: Bool) {
        guard !jumped, let previous else {
            if jumped {
                heading = 0
                trail = []
            }
            return
        }
        guard Coord.distance(previous, next) > 0.3 else { return }
        var bearing = Self.bearing(from: previous, to: next)
        while bearing - heading > 180 { bearing -= 360 }
        while bearing - heading < -180 { bearing += 360 }
        heading = bearing
        if trail.isEmpty { trail.append(previous) }
        trail.append(next)
        if trail.count > 600 { trail.removeFirst(trail.count - 600) }
    }

    private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }

    private func tickJoystick(pairing: PairingStore) {
        guard joystickActive, let current = simulated else { return }
        let magnitude = hypot(joystickVector.dx, joystickVector.dy)
        guard magnitude > 0.08 else { return }
        let nx = joystickVector.dx / magnitude
        let ny = -joystickVector.dy / magnitude
        let variation = Prefs.bool(Prefs.speedVariation) ? Double.random(in: 0.9...1.1) : 1
        let speed = travelMode.baseSpeed * min(1.0, magnitude) * variation
        let dt = 0.25
        let meters = speed * dt
        let next = offset(coordinate: current, eastMeters: nx * meters, northMeters: ny * meters)
        apply(next, pairing: pairing, markRecent: false)
    }

    private func startResend(pairing: PairingStore) {
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let sim = self.simulated else { return }
                _ = LocationEngine.set(
                    latitude: sim.latitude,
                    longitude: sim.longitude,
                    pairingPath: pairing.pairingPath,
                    deviceIP: TunnelConfig.targetIP
                )
            }
        }
    }

    private func stopResend() {
        resendTimer?.invalidate()
        resendTimer = nil
    }

    private func startHealth(pairing: PairingStore) {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let sim = self.simulated else { return }
                if case .dropped = self.status {
                    self.status = .reconnecting
                    self.apply(sim, pairing: pairing, markRecent: false)
                } else if !LocationEngine.isSessionActive, self.isSpoofing {
                    self.status = .reconnecting
                    self.apply(sim, pairing: pairing, markRecent: false)
                }
            }
        }
    }

    private func stopHealth() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    func pushNamedRecent(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            coordinate: coordinate
        )
        recents.removeAll {
            abs($0.latitude - place.latitude) < 0.00015 && abs($0.longitude - place.longitude) < 0.00015
        }
        recents.insert(place, at: 0)
        if recents.count > 20 { recents = Array(recents.prefix(20)) }
        SavedPlace.save(recents, key: recentsKey)
    }

    private func beginBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackground()
        }
    }

    private func endBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func postDropNotification() {
        guard Prefs.bool(Prefs.interruptionAlerts) else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "Trace"
        content.body = "Interrupted. Reconnecting."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func offset(coordinate: CLLocationCoordinate2D, eastMeters: Double, northMeters: Double) -> CLLocationCoordinate2D {
        let earth = 6378137.0
        let dLat = northMeters / earth * (180 / .pi)
        let dLon = eastMeters / (earth * cos(coordinate.latitude * .pi / 180)) * (180 / .pi)
        return CLLocationCoordinate2D(latitude: coordinate.latitude + dLat, longitude: coordinate.longitude + dLon)
    }
}
