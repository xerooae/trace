import SwiftUI

/// Everything saved, in one tab. The switch and search sit at the bottom, where the thumb is.
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
    @State private var query = ""
    @State private var searching = false
    @FocusState private var queryFocused: Bool
    @State private var selected: SavedPlace?
    @State private var renamingPlace: SavedPlace?
    @State private var renamingRoute: SavedRoute?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    switch scope {
                    case .favourites:
                        ForEach(filtered(session.favorites)) { place in
                            placeRow(place, icon: "star.fill", detail: Coord.format(place.coordinate), mono: true)
                                .swipeActions(edge: .trailing) {
                                    Button { session.removeFavorite(place) } label: { Label("Remove", systemImage: "trash") }
                                        .tint(Color(white: 0.24))
                                    Button { startRename(place) } label: { Label("Rename", systemImage: "pencil") }
                                        .tint(Color(white: 0.14))
                                }
                        }
                    case .recents:
                        ForEach(filtered(session.recents)) { place in
                            placeRow(place, icon: "clock", detail: recentDetail(place), mono: place.date == nil)
                                .swipeActions(edge: .trailing) {
                                    Button { session.removeRecent(place) } label: { Label("Remove", systemImage: "trash") }
                                        .tint(Color(white: 0.24))
                                    Button {
                                        session.addFavorite(name: place.name, coordinate: place.coordinate)
                                    } label: {
                                        Label("Favourite", systemImage: "star")
                                    }
                                    .tint(Color(white: 0.14))
                                }
                        }
                    case .routes:
                        ForEach(filteredRoutes) { saved in
                            routeRow(saved)
                                .swipeActions(edge: .trailing) {
                                    Button { session.removeRoute(saved) } label: { Label("Remove", systemImage: "trash") }
                                        .tint(Color(white: 0.24))
                                    Button {
                                        newName = saved.name
                                        renamingRoute = saved
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    .tint(Color(white: 0.14))
                                }
                        }
                    }
                } header: {
                    Label(syncLine, systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(TraceTheme.ink3)
                        .labelStyle(.titleAndIcon)
                }
            }
            .listStyle(.plain)
            .traceList()
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.large)
            .overlay {
                if isEmpty { emptyState }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
            .sheet(item: $selected) { place in
                PlaceSheet(place: place, onRename: { startRename(place) })
                    .presentationDetents([.medium, .large])
                    .presentationBackground(TraceTheme.graphite)
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

    // MARK: - Rows (content on black, never on glass)

    private func placeRow(_ place: SavedPlace, icon: String, detail: String, mono: Bool) -> some View {
        Button {
            selected = place
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(TraceTheme.ink2)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .foregroundStyle(TraceTheme.ink)
                        .lineLimit(2)
                    Text(detail)
                        .font(mono ? .footnote.monospaced() : .footnote)
                        .foregroundStyle(TraceTheme.ink2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(TraceTheme.ink3)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.black)
        .listRowSeparatorTint(TraceTheme.rule)
    }

    private func routeRow(_ saved: SavedRoute) -> some View {
        Button {
            router.routeToLoad = saved
            router.tab = .map
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.body.weight(.medium))
                    .foregroundStyle(TraceTheme.ink2)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(saved.name)
                        .foregroundStyle(TraceTheme.ink)
                        .lineLimit(2)
                    Text(saved.summary)
                        .font(.footnote)
                        .foregroundStyle(TraceTheme.ink2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(TraceTheme.ink3)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.black)
        .listRowSeparatorTint(TraceTheme.rule)
    }

    // MARK: - Bottom bar (thumb zone)

    private var bottomBar: some View {
        HStack(spacing: 6) {
            if searching {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(TraceTheme.ink3)
                    TextField("Search \(scope.title.lowercased())", text: $query)
                        .focused($queryFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onAppear { queryFocused = true }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(TraceTheme.fill, in: Capsule())
                Button("Cancel") {
                    query = ""
                    queryFocused = false
                    withAnimation(TraceTheme.motion) { searching = false }
                }
                .font(.body)
                .foregroundStyle(TraceTheme.ink)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .padding(.horizontal, 8)
            } else {
                TraceSegmented(options: Scope.allCases, selection: $scope) { $0.title }
                Button {
                    withAnimation(TraceTheme.motion) { searching = true }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(TraceIconButtonStyle(size: 44, filled: false))
                .accessibilityLabel("Search places")
            }
        }
        .padding(3)
        .traceGlass(.regular, in: Capsule())
        .frame(maxWidth: 520)
        .padding(.horizontal, TraceTheme.gutter)
        .padding(.bottom, 10)
    }

    // MARK: - Data

    private var syncLine: String {
        let count: String
        switch scope {
        case .favourites: count = "\(session.favorites.count) \(session.favorites.count == 1 ? "favourite" : "favourites")"
        case .recents: count = "Your last \(session.recents.count) moves"
        case .routes: count = "\(session.savedRoutes.count) \(session.savedRoutes.count == 1 ? "route" : "routes")"
        }
        return accounts.syncEnabled ? "\(count) · sync on" : "\(count) · on this iPhone"
    }

    private func filtered(_ places: [SavedPlace]) -> [SavedPlace] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return places }
        return places.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var filteredRoutes: [SavedRoute] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return session.savedRoutes }
        return session.savedRoutes.filter { $0.name.localizedCaseInsensitiveContains(q) }
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
            EmptyState(title: "No favourites yet", message: "Tap the star on any place to keep it here.")
        case .recents:
            EmptyState(title: "No moves yet", message: "Places you move to appear here.")
        case .routes:
            EmptyState(title: "No saved routes", message: "Build or draw a route on the map, then save it.")
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

/// A place opens at the medium detent: details on top, actions at the bottom edge,
/// Move here lowest of all.
struct PlaceSheet: View {
    let place: SavedPlace
    var onRename: () -> Void

    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    private var isFavourite: Bool { session.isFavorite(place.coordinate) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(TraceTheme.ink)
                    .lineLimit(2)
                Text(Coord.format(place.coordinate, decimals: 5))
                    .font(.footnote.monospaced())
                    .foregroundStyle(TraceTheme.ink2)
                    .textSelection(.enabled)
                    .padding(.top, 8)
                if let real = session.realCoordinate {
                    Text("\(Coord.distanceText(Coord.distance(real, place.coordinate))) from your real position")
                        .font(.footnote)
                        .foregroundStyle(TraceTheme.ink3)
                }
            }
            .padding(.top, 28)

            if let date = place.date {
                HStack {
                    Text(isFavourite ? "Saved" : "Moved here")
                        .foregroundStyle(TraceTheme.ink)
                    Spacer()
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(TraceTheme.ink2)
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 16)
            }

            Spacer(minLength: 16)

            VStack(spacing: TraceTheme.rowGap) {
                HStack(spacing: TraceTheme.rowGap) {
                    Button {
                        router.routeDestination = place
                        router.tab = .map
                        dismiss()
                    } label: {
                        Label("Route here", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    .buttonStyle(TraceGlassButtonStyle())

                    if isFavourite {
                        Button(action: onRename) {
                            Label("Rename", systemImage: "pencil")
                        }
                        .buttonStyle(TraceGlassButtonStyle())
                    } else {
                        Button {
                            session.addFavorite(name: place.name, coordinate: place.coordinate)
                        } label: {
                            Label("Save", systemImage: "star")
                        }
                        .buttonStyle(TraceGlassButtonStyle())
                    }

                    Menu {
                        ShareLink(item: "\(place.name) · \(Coord.format(place.coordinate, decimals: 5))") {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        if isFavourite {
                            Button(role: .destructive) {
                                session.removeFavorite(place)
                                dismiss()
                            } label: {
                                Label("Remove from Favourites", systemImage: "trash")
                            }
                        } else {
                            Button(role: .destructive) {
                                session.removeRecent(place)
                                dismiss()
                            } label: {
                                Label("Remove from Recents", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.medium))
                            .foregroundStyle(TraceTheme.ink)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.08), in: Circle())
                            .contentShape(Circle())
                    }
                    .accessibilityLabel("More")
                }

                Button("Move here") {
                    session.teleport(to: place.coordinate, name: place.name, pairing: pairing)
                    router.cameraTarget = place
                    router.tab = .map
                    dismiss()
                }
                .buttonStyle(TracePrimaryButtonStyle())
                .disabled(session.isBusy)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
    }
}
