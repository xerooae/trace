#if targetEnvironment(simulator)
import Foundation

/// Simulator builds are for design previews (Appetize). Each session is a fresh
/// install, so start on the map, paired and signed in. Launch with
/// `-showOnboarding YES` to go through first run instead.
enum SimulatorPreview {
    @MainActor
    static func prepare() {
        PairingStore().installSimulatorPlaceholder()

        guard !UserDefaults.standard.bool(forKey: "showOnboarding") else { return }
        let accounts = AccountStore()
        if accounts.account == nil {
            try? accounts.signIn(email: "preview@trace.app")
        }
        UserDefaults.standard.set(true, forKey: Prefs.setupComplete)
    }
}
#endif
