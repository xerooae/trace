import SwiftUI

/// Everything saved, in one tab: a native grouped list, with the switch in the
/// bottom toolbar where the thumb is. Search lives in the search tab.
struct PlacesView: View {
    enum Scope: String, CaseIterable, Hashable {
        case favourites, recents, routes

        var title: String {
            switch self {
            case .favourites: return "Favourites"
            case .recents: return "Recents"
            case .routes: return "Routes"
            }
        }
    }

    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var accounts: AccountStore

    @State private var scope: Scope = .favourites
    @State private var selected: SavedPlace?
    @State private var renamingPlace: SavedPlace?
    @State private var renamingRoute: SavedRoute?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if !isEmpty {
                    Section {
                        switch scope {
                        case .favourites:
                            ForEach(session.favorites) { place in
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
                        case .recents:
                            ForEach(session.recents) { place in
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
                        case .routes:
                            ForEach(session.savedRoutes) { saved in
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
                        }
                    } footer: {
                        Text(syncLine)
                    }
                }
            }
            .navigationTitle("Places")
            .overlay {
                if isEmpty { emptyState }
            }
            // Above the tab bar, not in a bottom toolbar: inside a TabView on iOS 26
            // a bottom toolbar renders behind the tab bar.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Picker("Show", selection: $scope) {
                    ForEach(Scope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(4)
                .glassEffect(.regular, in: Capsule())
                .frame(maxWidth: 420)
                .padding(.horizontal, TraceTheme.gutter)
                .padding(.bottom, 8)
            }
            .sensoryFeedback(.selection, trigger: scope)
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

    // MARK: - Rows

    private func placeRow(_ place: SavedPlace, systemImage: String, detail: String, mono: Bool) -> some View {
        Button {
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
                    .foregroundStyle(TraceTheme.ink2)
            }
        }
    }

    private func routeRow(_ saved: SavedRoute) -> some View {
        Button {
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
                    .foregroundStyle(TraceTheme.ink2)
            }
        }
    }

    // MARK: - Data

    private var syncLine: String {
        let count: String
        switch scope {
        case .favourites: count = "\(session.favorites.count) \(session.favorites.count == 1 ? "favourite" : "favourites")"
        case .recents: count = "Your last \(session.recents.count) moves"
        case .routes: count = "\(session.savedRoutes.count) \(session.savedRoutes.count == 1 ? "route" : "routes")"
        }
        return accounts.syncEnabled ? "\(count). Sync is on." : "\(count), on this iPhone."
    }

    private func recentDetail(_ place: SavedPlace) -> String {
        guard let date = place.date else { return Coord.format(place.coordinate) }
        return date.formatted(.relative(presentation: .named))
    }

    private var isEmpty: Bool {
        switch scope {
        case .favourites: return session.favorites.isEmpty
        case .recents: return session.recents.isEmpty
        case .routes: return session.savedRoutes.isEmpty
        }
    }

    @ViewBuilder private var emptyState: some View {
        switch scope {
        case .favourites:
            ContentUnavailableView("No favourites yet", systemImage: "star",
                                   description: Text("Tap the star on any place to keep it here."))
        case .recents:
            ContentUnavailableView("No moves yet", systemImage: "clock",
                                   description: Text("Places you move to appear here."))
        case .routes:
            ContentUnavailableView("No saved routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                   description: Text("Build or draw a route on the map, then save it."))
        }
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

/// A place opens at the medium detent as a native list, with Move here pinned at
/// the bottom as the one white action.
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
                        LabeledContent(isFavourite ? "Saved" : "Moved here",
                                       value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                Section {
                    Button {
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
                PrimaryButton("Move here") {
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
