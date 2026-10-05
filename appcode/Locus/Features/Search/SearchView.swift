import MapKit
import SwiftUI

/// Search opens as a sheet from the search control beside the tab bar, with the
/// keyboard up. Choosing a result closes the sheet and places it on the map,
/// ready for Move here.
struct SearchView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var completer = PlaceSearchCompleter()
    @State private var query = ""
    @State private var searchActive = true

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    if !session.favorites.isEmpty {
                        Section("Favourites") {
                            ForEach(session.favorites.prefix(6)) { place in
                                savedRow(place, systemImage: "star.fill")
                            }
                        }
                    }
                    if !session.recents.isEmpty {
                        Section("Recents") {
                            ForEach(session.recents.prefix(6)) { place in
                                savedRow(place, systemImage: "clock")
                            }
                        }
                    }
                } else {
                    if let coordinate = typedCoordinate {
                        Section("Coordinates") {
                            Button {
                                choose(coordinate, name: nil)
                            } label: {
                                row(title: Coord.format(coordinate, decimals: 5),
                                    subtitle: "Set this position on the map",
                                    systemImage: "scope",
                                    mono: false)
                            }
                        }
                    }
                    let saved = matchingSaved
                    if !saved.isEmpty {
                        Section("Saved") {
                            ForEach(saved) { place in
                                savedRow(place, systemImage: session.isFavorite(place.coordinate) ? "star.fill" : "clock")
                            }
                        }
                    }
                    if !completer.results.isEmpty {
                        Section("Places") {
                            ForEach(completer.results, id: \.self) { completion in
                                Button {
                                    resolve(completion)
                                } label: {
                                    row(title: completion.title, subtitle: completion.subtitle, systemImage: "mappin.and.ellipse", mono: false)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, isPresented: $searchActive, prompt: "Places or coordinates")
            .autocorrectionDisabled()
            .onSubmit(of: .search) {
                if let coordinate = typedCoordinate { choose(coordinate, name: nil) }
            }
            .onChange(of: query) { _, value in
                // Coordinates go straight to the map; MapKit has nothing useful to add.
                completer.query = Coord.parse(value) == nil ? value.trimmingCharacters(in: .whitespaces) : ""
            }
            .overlay {
                if trimmedQuery.isEmpty && session.favorites.isEmpty && session.recents.isEmpty {
                    ContentUnavailableView(
                        "Search for a place",
                        systemImage: "magnifyingglass",
                        description: Text("Find an address or a landmark, then move there.")
                    )
                } else if !trimmedQuery.isEmpty && typedCoordinate == nil && matchingSaved.isEmpty && completer.results.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var typedCoordinate: CLLocationCoordinate2D? {
        Coord.parse(trimmedQuery)
    }

    /// Favourites first, then recents that aren't already favourites.
    private var matchingSaved: [SavedPlace] {
        let q = trimmedQuery
        let favourites = session.favorites.filter { $0.name.localizedCaseInsensitiveContains(q) }
        let recents = session.recents.filter { recent in
            recent.name.localizedCaseInsensitiveContains(q) && !favourites.contains { $0.id == recent.id }
        }
        return Array((favourites + recents).prefix(4))
    }

    private func savedRow(_ place: SavedPlace, systemImage: String) -> some View {
        Button {
            choose(place.coordinate, name: place.name)
        } label: {
            row(title: place.name, subtitle: Coord.format(place.coordinate), systemImage: systemImage, mono: true)
        }
    }

    private func row(title: String, subtitle: String, systemImage: String, mono: Bool) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(TraceTheme.ink)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(mono ? .footnote.monospaced() : .footnote)
                        .foregroundStyle(TraceTheme.ink2)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(TraceTheme.ink2)
        }
    }

    private func resolve(_ completion: MKLocalSearchCompletion) {
        Task {
            let request = MKLocalSearch.Request(completion: completion)
            guard let response = try? await MKLocalSearch(request: request).start(),
                  let item = response.mapItems.first else { return }
            choose(item.placemark.coordinate, name: item.name ?? completion.title)
        }
    }

    /// Places the result on the map as the candidate and switches to the Map tab.
    /// Typed coordinates have no name, so Trace looks one up.
    private func choose(_ coordinate: CLLocationCoordinate2D, name: String?) {
        session.placeCandidate(coordinate, name: name)
        if name == nil { session.nameCandidate(coordinate) }
        router.cameraTarget = SavedPlace(name: name ?? Coord.format(coordinate), coordinate: coordinate)
        router.tab = .map
        query = ""
        dismiss()
    }
}

@MainActor
final class PlaceSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    var query: String = "" {
        didSet {
            if query.isEmpty {
                results = []
            } else {
                completer.queryFragment = query
            }
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
