import MapKit
import SwiftUI

/// Search. The search control beside the tab bar turns into a glass field above
/// the keyboard, which comes up straight away. Results drop down from the top in
/// Liquid Glass, like the Dynamic Island expanding. Choosing a result places it
/// on the map, ready for Move here.
struct SearchOverlay: View {
    @Binding var isActive: Bool

    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var router: AppRouter
    @StateObject private var completer = PlaceSearchCompleter()
    @State private var query = ""
    @FocusState private var focused: Bool

    private let morph = Animation.spring(duration: 0.38, bounce: 0.12)
    private let panelShape = RoundedRectangle(cornerRadius: 32, style: .continuous)

    private enum Action {
        case place(CLLocationCoordinate2D, String?)
        case completion(MKLocalSearchCompletion)
    }

    private struct Row: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let systemImage: String
        let mono: Bool
        let action: Action
    }

    private struct ResultSection: Identifiable {
        let id: String
        let title: String
        let rows: [Row]
    }

    var body: some View {
        let sections = self.sections
        ZStack {
            if isActive {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                    .transition(.opacity)
            }
            VStack(spacing: 10) {
                if isActive {
                    // Results follow the field: they drop from the top 120 ms later,
                    // always at full size, whatever the number of results.
                    resultsPanel(sections)
                        .frame(maxHeight: .infinity)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.2, anchor: .top).combined(with: .opacity)
                                .animation(morph.delay(0.12)),
                            removal: .scale(scale: 0.2, anchor: .top).combined(with: .opacity)
                        ))
                } else {
                    Spacer(minLength: 0)
                }
                bottomField
            }
        }
        .animation(morph, value: isActive)
        .animation(morph, value: sections.map { "\($0.id)\($0.rows.count)" }.joined())
        .onChange(of: isActive) { _, active in
            focused = active
            // Focus again once the field has its full width.
            if active { DispatchQueue.main.async { focused = true } }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused && isActive && query.isEmpty { close() }
        }
        .onChange(of: query) { _, value in
            // Coordinates go straight to the map; MapKit has nothing useful to add.
            completer.query = Coord.parse(value) == nil ? value.trimmingCharacters(in: .whitespaces) : ""
        }
    }

    // MARK: - Field (the search control, grown into a bar)

    private var bottomField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TraceTheme.ink2)
                TextField("Places or coordinates", text: $query)
                    .focused($focused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onSubmit(submit)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(TraceTheme.ink3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(width: isActive ? nil : 44, height: 44)
            .frame(maxWidth: isActive ? .infinity : 44)
            .glassEffect(.regular.interactive(), in: Capsule())

            if isActive {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TraceTheme.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("Close search")
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        // Collapsed, it sits under the system's search control and stays invisible.
        .opacity(isActive ? 1 : 0)
        .allowsHitTesting(isActive)
        .accessibilityHidden(!isActive)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, TraceTheme.gutter)
        .padding(.bottom, 8)
    }

    // MARK: - Results (Liquid Glass, dropping from the top)

    private func resultsPanel(_ sections: [ResultSection]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if sections.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(TraceTheme.ink3)
                        Text(trimmedQuery.isEmpty ? "Search for a place" : "No results for “\(trimmedQuery)”")
                            .font(.headline)
                            .foregroundStyle(TraceTheme.ink)
                        Text(trimmedQuery.isEmpty
                             ? "Type an address or a landmark, or paste coordinates like 47.1456, 27.6069."
                             : "Check the spelling, or try coordinates.")
                            .font(.subheadline)
                            .foregroundStyle(TraceTheme.ink2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 48)
                }
                ForEach(sections) { section in
                    Text(section.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(TraceTheme.ink2)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 2)
                    ForEach(section.rows) { row in
                        Button {
                            perform(row.action)
                        } label: {
                            rowView(row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.automatic)
        .scrollDismissesKeyboard(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(panelShape)
        .glassEffect(.regular, in: panelShape)
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 14) {
            Image(systemName: row.systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(TraceTheme.ink)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .foregroundStyle(TraceTheme.ink)
                    .lineLimit(1)
                if !row.subtitle.isEmpty {
                    Text(row.subtitle)
                        .font(row.mono ? .footnote.monospaced() : .footnote)
                        .foregroundStyle(TraceTheme.ink2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    // MARK: - Data

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var sections: [ResultSection] {
        let q = trimmedQuery
        var result: [ResultSection] = []
        if q.isEmpty {
            let favourites = session.favorites.prefix(8).map { savedRow($0, systemImage: "star.fill") }
            if !favourites.isEmpty {
                result.append(ResultSection(id: "favourites", title: "Favourites", rows: Array(favourites)))
            }
            let recents = session.recents
                .filter { recent in !session.favorites.contains { $0.id == recent.id } }
                .prefix(8)
                .map { savedRow($0, systemImage: "clock") }
            if !recents.isEmpty {
                result.append(ResultSection(id: "recents", title: "Recents", rows: Array(recents)))
            }
            return result
        }
        if let coordinate = Coord.parse(q) {
            result.append(ResultSection(id: "coordinates", title: "Coordinates", rows: [Row(
                id: "coordinate",
                title: Coord.format(coordinate, decimals: 5),
                subtitle: "Set this position on the map",
                systemImage: "scope",
                mono: false,
                action: .place(coordinate, nil)
            )]))
        }
        let saved = matchingSaved(q).map {
            savedRow($0, systemImage: session.isFavorite($0.coordinate) ? "star.fill" : "clock")
        }
        if !saved.isEmpty {
            result.append(ResultSection(id: "saved", title: "Saved", rows: saved))
        }
        let places = completer.results.map { completion in
            Row(
                id: "place-\(completion.title)-\(completion.subtitle)",
                title: completion.title,
                subtitle: completion.subtitle,
                systemImage: "mappin.and.ellipse",
                mono: false,
                action: .completion(completion)
            )
        }
        if !places.isEmpty {
            result.append(ResultSection(id: "results", title: "Results", rows: places))
        }
        return result
    }

    /// Favourites first, then recents that aren't already favourites.
    private func matchingSaved(_ q: String) -> [SavedPlace] {
        let favourites = session.favorites.filter { $0.name.localizedCaseInsensitiveContains(q) }
        let recents = session.recents.filter { recent in
            recent.name.localizedCaseInsensitiveContains(q) && !favourites.contains { $0.id == recent.id }
        }
        return Array((favourites + recents).prefix(4))
    }

    private func savedRow(_ place: SavedPlace, systemImage: String) -> Row {
        Row(
            id: "saved-\(place.id)",
            title: place.name,
            subtitle: Coord.format(place.coordinate),
            systemImage: systemImage,
            mono: true,
            action: .place(place.coordinate, place.name)
        )
    }

    // MARK: - Actions

    private func submit() {
        if let coordinate = Coord.parse(trimmedQuery) {
            choose(coordinate, name: nil)
        } else if let first = sections.first?.rows.first {
            perform(first.action)
        }
    }

    private func perform(_ action: Action) {
        switch action {
        case .place(let coordinate, let name):
            choose(coordinate, name: name)
        case .completion(let completion):
            Task {
                let request = MKLocalSearch.Request(completion: completion)
                guard let response = try? await MKLocalSearch(request: request).start(),
                      let item = response.mapItems.first else { return }
                choose(item.placemark.coordinate, name: item.name ?? completion.title)
            }
        }
    }

    /// Places the result on the map as the candidate and switches to the Map tab.
    /// Typed coordinates have no name, so Trace looks one up.
    private func choose(_ coordinate: CLLocationCoordinate2D, name: String?) {
        session.placeCandidate(coordinate, name: name)
        if name == nil { session.nameCandidate(coordinate) }
        router.cameraTarget = SavedPlace(name: name ?? Coord.format(coordinate), coordinate: coordinate)
        router.tab = .map
        close()
    }

    private func close() {
        focused = false
        query = ""
        isActive = false
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
