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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Routes")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(TraceTheme.ink)
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(TraceTheme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    TraceSegmented(options: TravelMode.allCases, selection: $session.travelMode) { $0.title }

                    VStack(spacing: 0) {
                        row("Route to \(targetName)",
                            icon: "point.topleft.down.to.point.bottomright.curvepath",
                            disabled: target == nil || route.building,
                            action: onBuild)
                        divider
                        row("Draw a path on the map", icon: "scribble", action: onDraw)
                        divider
                        row("Import GPX", icon: "square.and.arrow.down") { showImporter = true }
                        if route.hasRoute {
                            if let exportURL {
                                divider
                                ShareLink(item: exportURL) {
                                    rowLabel("Export GPX", icon: "square.and.arrow.up")
                                }
                                .buttonStyle(.plain)
                            }
                            divider
                            row("Save to Places", icon: "star") {
                                routeName = route.name ?? ""
                                naming = true
                            }
                        }
                    }
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button("Follow route", action: onFollow)
                .buttonStyle(TracePrimaryButtonStyle())
                .disabled(!route.hasRoute)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
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

    private func row(_ title: String, icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(title, icon: icon)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    private func rowLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(TraceTheme.ink2)
                .frame(width: 28)
            Text(title)
                .foregroundStyle(TraceTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TraceTheme.ink3)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private var divider: some View {
        Rectangle()
            .fill(TraceTheme.rule)
            .frame(height: 1)
            .padding(.leading, 58)
    }
}
