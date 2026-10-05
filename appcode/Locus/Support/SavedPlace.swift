import CoreLocation
import Foundation

struct SavedPlace: Identifiable, Codable, Equatable {
    var id: String { "\(latitude),\(longitude)" }
    var name: String
    var latitude: Double
    var longitude: Double
    /// When this was saved or moved to. Missing on places saved by older builds.
    var date: Date? = nil

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(name: String, latitude: Double, longitude: Double, date: Date? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.date = date
    }

    init(name: String, coordinate: CLLocationCoordinate2D, date: Date? = .now) {
        self.init(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude, date: date)
    }

    static func load(key: String) -> [SavedPlace] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedPlace].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ places: [SavedPlace], key: String) {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// A route kept in Places › Routes.
struct SavedRoute: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var mode: String
    var latitudes: [Double]
    var longitudes: [Double]
    var created: Date

    init(name: String, coordinates: [CLLocationCoordinate2D], mode: TravelMode) {
        id = UUID()
        self.name = name
        self.mode = mode.rawValue
        latitudes = coordinates.map(\.latitude)
        longitudes = coordinates.map(\.longitude)
        created = .now
    }

    var coordinates: [CLLocationCoordinate2D] {
        zip(latitudes, longitudes).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
    }

    var travelMode: TravelMode { TravelMode(rawValue: mode) ?? .walk }

    var distance: CLLocationDistance {
        let points = coordinates
        return zip(points, points.dropFirst()).reduce(0) { $0 + Coord.distance($1.0, $1.1) }
    }

    /// "3.4 km · Walk · 42 min"
    var summary: String {
        let minutes = Duration.seconds(distance / travelMode.baseSpeed)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return "\(Coord.distanceText(distance)) · \(travelMode.title) · \(minutes)"
    }

    static func load(key: String) -> [SavedRoute] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedRoute].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ routes: [SavedRoute], key: String) {
        if let data = try? JSONEncoder().encode(routes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// UserDefaults keys for settings. The `locus.` keys predate the rename and are kept
/// so existing installs keep their data.
enum Prefs {
    static let setupComplete = "locus.setupComplete"
    static let speedVariation = "trace.speedVariation"
    static let interruptionAlerts = "trace.interruptionAlerts"
    static let showRealPosition = "trace.showRealPosition"
    static let mapStyle = "trace.mapStyle"

    static func bool(_ key: String, default value: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}
