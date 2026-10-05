import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

/// Routes open as a sheet at the medium detent, with the map live above it.
/// Follow route is the one white action, at the bottom edge.
struct RoutesSheet: View {
    @Binding var route: RouteDraft
    var onBuild: () -> Void
    var onFollow: () -> Void
    var onDraw: () -> Void
    var onImport: (URL) -> Void
    var onSave: (String) -> Void

    @EnvironmentObject private var session: SpoofSession
    @State private var showImporter = false
    @State private var naming = false
    @State private var routeName = ""
    @State private var exportURL: URL?

    private var target: CLLocationCoordinate2D? { route.destination ?? session.candidate }
    private var targetName: String { route.destinationName ?? session.pinName ?? "the selected place" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Travel mode", selection: $session.travelMode) {
                        ForEach(TravelMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(summary)
                }

                Section {
                    Button(action: onBuild) {
                        Label("Route to \(targetName)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    .disabled(target == nil || route.building)
                    Button(action: onDraw) {
                        Label("Draw a path on the map", systemImage: "scribble")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import GPX", systemImage: "square.and.arrow.down")
                    }
                }

                if route.hasRoute {
                    Section {
                        if let exportURL {
                            ShareLink(item: exportURL) {
                                Label("Export GPX", systemImage: "square.and.arrow.up")
                            }
                        }
                        Button {
                            routeName = route.name ?? ""
                            naming = true
                        } label: {
                            Label("Save to Places", systemImage: "star")
                        }
                    }
                }
            }
            .navigationTitle("Routes")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton("Follow route", action: onFollow)
                    .disabled(!route.hasRoute)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.xml, .data]) { result in
            if case .success(let url) = result {
                onImport(url)
            }
        }
        .alert("Save route", isPresented: $naming) {
            TextField("Name", text: $routeName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { onSave(routeName) }
        } message: {
            Text("Saved routes appear in Places.")
        }
        .task(id: route.coordinates.count) {
            exportURL = route.hasRoute
                ? GPXCodec.temporaryFile(for: route.coordinates, name: route.name ?? "Trace Route")
                : nil
        }
    }

    private var summary: String {
        if route.building { return "Finding a route…" }
        if route.hasRoute {
            let time = Duration.seconds(route.distance / session.travelMode.baseSpeed)
                .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
            return "\(route.name ?? "Route") · \(Coord.distanceText(route.distance)) · \(time)"
        }
        if target != nil { return "To \(targetName). Pick a travel mode, then build the route." }
        return "Place a position on the map, draw a path, or import GPX."
    }
}
