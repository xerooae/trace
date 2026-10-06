import SwiftUI

@main
struct TraceApp: App {
    @StateObject private var session = SpoofSession()
    @StateObject private var pairing = PairingStore()
    @StateObject private var accounts = AccountStore()
    @StateObject private var router = AppRouter()
    @AppStorage(Prefs.setupComplete) private var setupComplete = false

    var body: some Scene {
        WindowGroup {
            Group {
                // Gates replace the tab view entirely: first run, then plan access.
                if accounts.account == nil || !setupComplete {
                    OnboardingView(startsSignedIn: accounts.account != nil)
                } else if !accounts.hasFullAccess {
                    PlanView(mode: .ended)
                } else {
                    AppTabs()
                }
            }
            .environmentObject(session)
            .environmentObject(pairing)
            .environmentObject(accounts)
            .environmentObject(router)
            .preferredColorScheme(.dark)
            .tint(TraceTheme.accent)
            .onOpenURL(perform: handleIncoming)
        }
    }

    private func handleIncoming(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ["plist", "mobiledevicepairing", "mobiledevicepair"].contains(ext) {
            do {
                try pairing.importPairing(from: url)
            } catch {
                session.lastError = error.localizedDescription
            }
        } else if ext == "gpx" {
            router.tab = .map
            NotificationCenter.default.post(name: .traceImportGPX, object: url)
        }
    }
}

extension Notification.Name {
    static let traceImportGPX = Notification.Name("traceImportGPX")
}

enum AppTab: Hashable {
    case map, places, settings, search
}

/// Cross-tab requests: Places asks the Map to show a place or open a route.
@MainActor
final class AppRouter: ObservableObject {
    @Published var tab: AppTab = .map
    /// The map moves its camera here, then clears it.
    @Published var cameraTarget: SavedPlace?
    /// The map opens Routes toward this place, then clears it.
    @Published var routeDestination: SavedPlace?
    /// The map loads this saved route into Routes, then clears it.
    @Published var routeToLoad: SavedRoute?
}

/// Three tabs: Map · Places · Settings, plus search as its own control beside the
/// tab bar. The account is the first row of Settings.
struct AppTabs: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SpoofSession
    @State private var searching = false

    /// The search control never becomes the selected tab, so the tab bar never
    /// collapses (and never changes height). It turns into the search overlay.
    private var selection: Binding<AppTab> {
        Binding(
            get: { router.tab },
            set: { tab in
                if tab == .search {
                    searching = true
                    // Re-publish the current tab so the tab bar snaps back to it.
                    let current = router.tab
                    router.tab = current
                } else {
                    router.tab = tab
                }
            }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            Tab("Map", systemImage: "map", value: AppTab.map) {
                MapHomeView()
            }
            Tab("Places", systemImage: "star", value: AppTab.places) {
                PlacesView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
            Tab(value: AppTab.search, role: .search) {
                // Never shown: selecting search opens the overlay below instead.
                Color.clear
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.never)
        .overlay {
            SearchOverlay(isActive: $searching)
        }
        .sensoryFeedback(trigger: session.status) { old, new in
            if new == .active && old != .active { return .success }
            if new.isDropped && !old.isDropped { return .warning }
            return nil
        }
        .alert("Trace", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }
}
