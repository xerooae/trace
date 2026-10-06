import SwiftUI

/// Everything saved, in one native list: Favourites, Recents and Routes as
/// sections, like the Settings app. Long sections show a few rows and expand in
/// place with "Show all". Search lives in the search control.
struct PlacesView: View {
    enum Kind: Hashable {
        case favourites, recents, routes

        /// Rows shown before "Show all".
        var limit: Int {
            switch self {
            case .favourites: return 5
            case .recents, .routes: return 3
            }
        }
    }

    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var accounts: AccountStore

    @State private var expanded: Set<Kind> = []
    @State private var selected: SavedPlace?
    @State private var renamingPlace: SavedPlace?
    @State private var renamingRoute: SavedRoute?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if !session.favorites.isEmpty {
                    Section {
                        ForEach(visible(session.favorites, .favourites)) { place in
                            placeRow(place, systemImage: "star.fill", detail: Coord.format(place.coordinate), mono: true)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        session.removeFavorite(place)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                    Button {
                                        startRename(place)
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                }
                        }
                    } header: {
                        sectionHeader("Favourites", kind: .favourites, count: session.favorites.count)
                    }
                }

                if !session.recents.isEmpty {
                    Section {
                        ForEach(visible(session.recents, .recents)) { place in
                            placeRow(place, systemImage: "clock", detail: recentDetail(place), mono: place.date == nil)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        session.removeRecent(place)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                    Button {
                                        session.addFavorite(name: place.name, coordinate: place.coordinate)
                                    } label: {
                                        Label("Favourite", systemImage: "star")
                                    }
                                }
                        }
                    } header: {
                        sectionHeader("Recents", kind: .recents, count: session.recents.count)
                    }
                }

                if !session.savedRoutes.isEmpty {
                    Section {
                        ForEach(visible(session.savedRoutes, .routes)) { saved in
                            routeRow(saved)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        session.removeRoute(saved)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                    Button {
                                        newName = saved.name
                                        renamingRoute = saved
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                }
                        }
                    } header: {
                        sectionHeader("Routes", kind: .routes, count: session.savedRoutes.count)
                    }
                }

                if !isEmpty {
                    Section {
                    } footer: {
                        Text(accounts.syncEnabled ? "Sync is on." : "Saved on this iPhone.")
                    }
                }
            }
            .navigationTitle("Places")
            // Less space above the content: the large title sits in the bar, and the
            // list starts right under it with compact section gaps.
            .toolbarTitleDisplayMode(.inlineLarge)
            .contentMargins(.top, 8, for: .scrollContent)
            .listSectionSpacing(.compact)
            .animation(TraceTheme.motion, value: expanded)
            .overlay {
                if isEmpty {
                    ContentUnavailableView(
                        "No places yet",
                        systemImage: "star",
                        description: Text("Tap the star on any place to keep it here. Places you spoof to, and routes you save, appear here too.")
                    )
                }
            }
            .sheet(item: $selected) { place in
                PlaceSheet(place: place, onRename: { startRename(place) })
                    .presentationDetents([.medium, .large])
            }
            .alert("Rename favourite", isPresented: Binding(
                get: { renamingPlace != nil },
                set: { if !$0 { renamingPlace = nil } }
            )) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { renamingPlace = nil }
                Button("Save") {
                    if let place = renamingPlace { session.renameFavorite(place, to: newName) }
                    renamingPlace = nil
                }
            } message: {
                Text("Choose a name you'll recognise later.")
            }
            .alert("Rename route", isPresented: Binding(
                get: { renamingRoute != nil },
                set: { if !$0 { renamingRoute = nil } }
            )) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { renamingRoute = nil }
                Button("Save") {
                    if let saved = renamingRoute { session.renameRoute(saved, to: newName) }
                    renamingRoute = nil
                }
            }
        }
    }

    // MARK: - Sections

    /// A prominent section title with "Show all" / "Show less" when the section is long.
    private func sectionHeader(_ title: String, kind: Kind, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(TraceTheme.ink)
            Spacer()
            if count > kind.limit {
                Button(expanded.contains(kind) ? "Show less" : "Show all") {
                    Haptics.select()
                    if expanded.contains(kind) {
                        expanded.remove(kind)
                    } else {
                        expanded.insert(kind)
                    }
                }
                .font(.subheadline)
                .tint(TraceTheme.accent)
                .buttonStyle(.borderless)
            }
        }
        .textCase(nil)
        .padding(.horizontal, -4)
    }

    private func visible<T>(_ items: [T], _ kind: Kind) -> [T] {
        expanded.contains(kind) ? items : Array(items.prefix(kind.limit))
    }

    // MARK: - Rows

    private func placeRow(_ place: SavedPlace, systemImage: String, detail: String, mono: Bool) -> some View {
        Button {
            Haptics.tap()
            selected = place
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .foregroundStyle(TraceTheme.ink)
                        .lineLimit(2)
                    Text(detail)
                        .font(mono ? .footnote.monospaced() : .footnote)
                        .foregroundStyle(TraceTheme.ink2)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(TraceTheme.ink)
            }
        }
    }

    private func routeRow(_ saved: SavedRoute) -> some View {
        Button {
            Haptics.tap()
            router.routeToLoad = saved
            router.tab = .map
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(saved.name)
                        .foregroundStyle(TraceTheme.ink)
                        .lineLimit(2)
                    Text(saved.summary)
                        .font(.footnote)
                        .foregroundStyle(TraceTheme.ink2)
                }
            } icon: {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundStyle(TraceTheme.ink)
            }
        }
    }

    // MARK: - Data

    private func recentDetail(_ place: SavedPlace) -> String {
        guard let date = place.date else { return Coord.format(place.coordinate) }
        return date.formatted(.relative(presentation: .named))
    }

    private var isEmpty: Bool {
        session.favorites.isEmpty && session.recents.isEmpty && session.savedRoutes.isEmpty
    }

    private func startRename(_ place: SavedPlace) {
        newName = place.name
        guard selected != nil else {
            renamingPlace = place
            return
        }
        // Let the place sheet finish closing before the alert presents.
        selected = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            renamingPlace = place
        }
    }
}

/// A place opens at the medium detent as a native list, with Spoof here pinned at
/// the bottom as the one blue action.
struct PlaceSheet: View {
    let place: SavedPlace
    var onRename: () -> Void

    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    private var isFavourite: Bool { session.isFavorite(place.coordinate) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Coordinates") {
                        Text(Coord.format(place.coordinate, decimals: 5))
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                    if let real = session.realCoordinate {
                        LabeledContent("From your real position", value: Coord.distanceText(Coord.distance(real, place.coordinate)))
                    }
                    if let date = place.date {
                        LabeledContent(isFavourite ? "Saved" : "Spoofed here",
                                       value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                Section {
                    Button {
                        Haptics.tap()
                        router.routeDestination = place
                        router.tab = .map
                        dismiss()
                    } label: {
                        RowLabel("Route here", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    if isFavourite {
                        Button(action: onRename) {
                            RowLabel("Rename", systemImage: "pencil")
                        }
                    } else {
                        Button {
                            Haptics.select()
                            session.addFavorite(name: place.name, coordinate: place.coordinate)
                        } label: {
                            RowLabel("Add to Favourites", systemImage: "star")
                        }
                    }
                    ShareLink(item: "\(place.name) · \(Coord.format(place.coordinate, decimals: 5))") {
                        RowLabel("Share", systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        if isFavourite {
                            session.removeFavorite(place)
                        } else {
                            session.removeRecent(place)
                        }
                        dismiss()
                    } label: {
                        Label(isFavourite ? "Remove from Favourites" : "Remove from Recents", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton("Spoof here") {
                    session.teleport(to: place.coordinate, name: place.name, pairing: pairing)
                    router.cameraTarget = place
                    router.tab = .map
                    dismiss()
                }
                .disabled(session.isBusy)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
    }
}
