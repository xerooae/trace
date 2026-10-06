import SwiftUI
import UniformTypeIdentifiers

/// Native grouped list, like the Settings app: account first, then the setup
/// that keeps Trace working.
struct SettingsView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(Prefs.speedVariation) private var speedVariation = true
    @AppStorage(Prefs.interruptionAlerts) private var interruptionAlerts = true
    @AppStorage(Prefs.showRealPosition) private var showRealPosition = true
    @AppStorage(Prefs.mapLook) private var mapLook: MapLook = .satellite
    @State private var tunnelConnected = LocalDevVPN.isConnected

    var body: some View {
        NavigationStack {
            List {
                if let account = accounts.account {
                    Section {
                        NavigationLink {
                            AccountView()
                        } label: {
                            HStack(spacing: 14) {
                                Avatar(initials: account.initials, size: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.displayName)
                                        .font(.title3.weight(.semibold))
                                    Text(accounts.hasFullAccess ? "Full access · included" : "Plan ended")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Connection") {
                    NavigationLink {
                        PairingSettingsView()
                    } label: {
                        LabeledContent {
                            Text(pairing.hasPairingFile ? "Paired" : "Not paired")
                        } label: {
                            RowLabel("Pairing", systemImage: "iphone")
                        }
                    }
                    NavigationLink {
                        TunnelSettingsView()
                    } label: {
                        LabeledContent {
                            Text(tunnelConnected ? "Connected" : "Not connected")
                        } label: {
                            RowLabel("Tunnel", systemImage: "lock.shield")
                        }
                    }
                }

                Section("Movement") {
                    Picker(selection: $session.travelMode) {
                        ForEach(TravelMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    } label: {
                        RowLabel("Travel mode", systemImage: "figure.walk")
                    }
                    Toggle(isOn: $speedVariation) {
                        RowLabel("Natural speed variation", systemImage: "waveform.path")
                    }
                    .traceToggle()
                }

                Section("Map") {
                    Picker(selection: $mapLook) {
                        ForEach(MapLook.allCases) { look in
                            Text(look.title).tag(look)
                        }
                    } label: {
                        RowLabel("Map style", systemImage: "map")
                    }
                    Toggle(isOn: $showRealPosition) {
                        RowLabel("Show real position", systemImage: "location")
                    }
                    .traceToggle()
                }

                Section {
                    Toggle(isOn: $interruptionAlerts) {
                        RowLabel("Interruption alerts", systemImage: "bell")
                    }
                    .traceToggle()
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("A notification when a live position drops while Trace is in the background.")
                }

                Section {
                    LabeledContent {
                        Text(AppInfo.version)
                    } label: {
                        RowLabel("Version", systemImage: "info.circle")
                    }
                    NavigationLink {
                        LicencesView()
                    } label: {
                        RowLabel("Licences", systemImage: "doc.text")
                    }
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        RowLabel("Privacy", systemImage: "hand.raised")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Trace's location engine is based on Locus (MIT).")
                }
            }
            .navigationTitle("Settings")
            .sensoryFeedback(.selection, trigger: speedVariation)
            .sensoryFeedback(.selection, trigger: showRealPosition)
            .sensoryFeedback(.selection, trigger: interruptionAlerts)
            .sensoryFeedback(.selection, trigger: mapLook)
            .sensoryFeedback(.selection, trigger: session.travelMode)
            // Less space above the content: the large title sits in the bar, and the
            // list starts right under it with compact section gaps.
            .toolbarTitleDisplayMode(.inlineLarge)
            .contentMargins(.top, 8, for: .scrollContent)
            .listSectionSpacing(.compact)
            .onAppear(perform: refresh)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
            }
        }
    }

    private func refresh() {
        tunnelConnected = LocalDevVPN.isConnected
        pairing.refresh()
    }
}

struct Avatar: View {
    let initials: String
    var size: CGFloat = 48

    var body: some View {
        Text(initials)
            .font(size > 60 ? Font.title.weight(.semibold) : Font.headline)
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(Color(uiColor: .systemGray3), in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Account

/// Plan, sync and sign-in, with Sign out and Delete account at the end.
struct AccountView: View {
    @EnvironmentObject private var accounts: AccountStore
    @State private var confirmSignOut = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            if let account = accounts.account {
                Section {
                    VStack(spacing: 6) {
                        Avatar(initials: account.initials, size: 80)
                        Text(account.displayName)
                            .font(.title2.weight(.semibold))
                            .padding(.top, 6)
                        if !account.email.isEmpty {
                            Text(account.email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)

                Section {
                    LabeledContent("Full access", value: accounts.hasFullAccess ? "Included" : "Ended")
                } header: {
                    Text("Plan")
                } footer: {
                    Text("Every account has full access for now. When plans arrive, nothing you've saved changes.")
                }

                Section {
                    Toggle("Sync places and routes", isOn: $accounts.syncEnabled)
                        .traceToggle()
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Sync starts once the Trace account server is connected. Your pairing file and live position never leave this iPhone.")
                }

                Section("Sign-in") {
                    LabeledContent("Signed in with", value: account.method.title)
                    LabeledContent("Member since", value: account.created.formatted(date: .abbreviated, time: .omitted))
                }

                Section {
                    Button("Sign out") {
                        confirmSignOut = true
                    }
                    .frame(maxWidth: .infinity)
                }

                Section {
                    Button("Delete account", role: .destructive) {
                        confirmDelete = true
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("Deleting your account removes it from this iPhone. Your places and pairing stay on the device.")
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Sign out of Trace?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out") { accounts.signOut() }
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { accounts.deleteAccount() }
        } message: {
            Text("This can't be undone.")
        }
    }
}

// MARK: - Pairing

struct PairingSettingsView: View {
    @EnvironmentObject private var pairing: PairingStore
    @State private var showImporter = false
    @State private var confirmRemove = false
    @State private var message: String?

    private var supportsOnDevicePairing: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: pairing.hasPairingFile ? "Paired" : "Not paired")
            }

            Section {
                if supportsOnDevicePairing {
                    NavigationLink {
                        PairOnDeviceView(mode: .pushed)
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        RowLabel("Pair on this iPhone", systemImage: "iphone.radiowaves.left.and.right")
                    }
                }
                Button {
                    showImporter = true
                } label: {
                    RowLabel("Import a pairing file", systemImage: "square.and.arrow.down")
                }
                Button {
                    do {
                        try pairing.importPairingFromClipboard()
                        message = "Pairing file installed."
                    } catch {
                        message = error.localizedDescription
                    }
                } label: {
                    RowLabel("Paste from clipboard", systemImage: "doc.on.clipboard")
                }
            } footer: {
                Text(supportsOnDevicePairing
                     ? "On iOS 27, pair on this iPhone with no computer: confirm the six-digit code under Settings › Privacy & Security › Developer Mode › Pair with Host. On iOS 26, import an RPPairing file made with idevice_pair. In LiveContainer, use Paste if the file picker doesn't work."
                     : "Import an RPPairing file made with idevice_pair (not a SideStore .mobiledevicepairing file). In LiveContainer, use Paste if the file picker doesn't work.")
            }

            if pairing.hasPairingFile {
                Section {
                    Button("Remove pairing", role: .destructive) {
                        confirmRemove = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Pairing")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                    } catch {
                        message = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
        .confirmationDialog("Remove the pairing?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove pairing", role: .destructive) {
                try? pairing.removePairing()
            }
        } message: {
            Text("Trace can't set your position until this iPhone is paired again.")
        }
        .alert("Trace", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
}

// MARK: - Tunnel

struct TunnelSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var address = TunnelConfig.targetIP
    @State private var connected = LocalDevVPN.isConnected
    @State private var installed = LocalDevVPN.isInstalled

    var body: some View {
        List {
            Section {
                LabeledContent("LocalDevVPN", value: connected ? "Connected" : installed ? "Not connected" : "Not installed")
                Button {
                    LocalDevVPN.openOrInstall()
                } label: {
                    RowLabel(installed ? "Open LocalDevVPN" : "Get LocalDevVPN", systemImage: "lock.shield")
                }
            } footer: {
                Text("LocalDevVPN opens a private tunnel on this iPhone. Start your first spoof on Wi‑Fi; after that it keeps working on cellular.")
            }

            Section {
                TextField(TunnelConfig.defaultIP, text: $address)
                    .font(.body.monospaced())
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { TunnelConfig.setTargetIP(address) }
            } header: {
                Text("Tunnel address")
            } footer: {
                Text("Leave this at \(TunnelConfig.defaultIP) unless you changed it in LocalDevVPN.")
            }
        }
        .navigationTitle("Tunnel")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { TunnelConfig.setTargetIP(address) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                connected = LocalDevVPN.isConnected
                installed = LocalDevVPN.isInstalled
            }
        }
    }
}

// MARK: - About

struct LicencesView: View {
    var body: some View {
        List {
            Section {
                Text("Trace's location engine is based on Locus by ChrisMack32, released under the MIT licence.")
            } header: {
                Text("Locus")
            }
            Section {
                Text("Location simulation uses the idevice FFI by jkcoxson, released under the MIT licence.")
            } header: {
                Text("idevice")
            } footer: {
                Text("MIT licence: permission is granted, free of charge, to any person obtaining a copy of this software to deal in it without restriction, provided the copyright notice and this permission notice are included. The software is provided \"as is\", without warranty of any kind.")
            }
        }
        .navigationTitle("Licences")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("On this iPhone") {
                Text("Your pairing file, live position, favourites, recents and routes are stored on this iPhone.")
            }
            Section("Your account") {
                Text("Your account is stored on this iPhone until the Trace account server is connected.")
            }
            Section("Sync") {
                Text("When sync arrives, it covers favourites, recents and routes. Your pairing file and live position never leave this iPhone.")
            }
            Section("No tracking") {
                Text("No analytics and no advertising.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
