import SwiftUI
import UniformTypeIdentifiers

/// Account first, then the setup that keeps Trace working.
struct SettingsView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(Prefs.speedVariation) private var speedVariation = true
    @AppStorage(Prefs.interruptionAlerts) private var interruptionAlerts = true
    @AppStorage(Prefs.showRealPosition) private var showRealPosition = true
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
                                Avatar(initials: account.initials, size: 48)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.displayName)
                                        .font(.headline)
                                        .foregroundStyle(TraceTheme.ink)
                                    Text(accounts.hasFullAccess ? "Full access · included" : "Plan ended")
                                        .font(.footnote)
                                        .foregroundStyle(TraceTheme.ink2)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .listRowBackground(TraceTheme.graphite)
                }

                Section("Connection") {
                    NavigationLink {
                        PairingSettingsView()
                    } label: {
                        SettingsRow(title: "Pairing", icon: "iphone", value: pairing.hasPairingFile ? "Paired" : "Not paired")
                    }
                    NavigationLink {
                        TunnelSettingsView()
                    } label: {
                        SettingsRow(title: "Tunnel", icon: "lock.shield", value: tunnelConnected ? "Connected" : "Not connected")
                    }
                }
                .listRowBackground(TraceTheme.graphite)

                Section("Movement") {
                    Picker(selection: $session.travelMode) {
                        ForEach(TravelMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    } label: {
                        SettingsRow(title: "Travel mode", icon: "figure.walk")
                    }
                    Toggle(isOn: $speedVariation) {
                        SettingsRow(title: "Natural speed variation", icon: "waveform.path")
                    }
                    .toggleStyle(TraceToggleStyle())
                }
                .listRowBackground(TraceTheme.graphite)

                Section("Map") {
                    Picker(selection: $session.mapStyleIndex) {
                        Text("Muted").tag(0)
                        Text("Satellite").tag(1)
                    } label: {
                        SettingsRow(title: "Map style", icon: "square.3.layers.3d")
                    }
                    Toggle(isOn: $showRealPosition) {
                        SettingsRow(title: "Show real position", icon: "location")
                    }
                    .toggleStyle(TraceToggleStyle())
                }
                .listRowBackground(TraceTheme.graphite)

                Section {
                    Toggle(isOn: $interruptionAlerts) {
                        SettingsRow(title: "Interruption alerts", icon: "bell")
                    }
                    .toggleStyle(TraceToggleStyle())
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("A notification when a live position drops while Trace is in the background.")
                }
                .listRowBackground(TraceTheme.graphite)

                Section {
                    LabeledContent {
                        Text(AppInfo.version)
                    } label: {
                        SettingsRow(title: "Version", icon: "info.circle")
                    }
                    NavigationLink {
                        LicencesView()
                    } label: {
                        SettingsRow(title: "Licences", icon: "doc.text")
                    }
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        SettingsRow(title: "Privacy", icon: "hand.raised")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Trace's location engine is based on Locus (MIT).")
                }
                .listRowBackground(TraceTheme.graphite)
            }
            .traceList()
            .navigationTitle("Settings")
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

struct SettingsRow: View {
    let title: String
    let icon: String
    var value: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(TraceTheme.ink2)
                .frame(width: 26)
            Text(title)
                .foregroundStyle(TraceTheme.ink)
            if let value {
                Spacer(minLength: 8)
                Text(value)
                    .foregroundStyle(TraceTheme.ink2)
            }
        }
    }
}

struct Avatar: View {
    let initials: String
    var size: CGFloat = 48

    var body: some View {
        Text(initials)
            .font(size > 60 ? Font.title.weight(.semibold) : Font.headline)
            .foregroundStyle(TraceTheme.ink)
            .frame(width: size, height: size)
            .background(Color(white: 0.1), in: Circle())
            .overlay(Circle().stroke(TraceTheme.hairline, lineWidth: 1))
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
                        Avatar(initials: account.initials, size: 72)
                        Text(account.displayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(TraceTheme.ink)
                            .padding(.top, 6)
                        if !account.email.isEmpty {
                            Text(account.email)
                                .font(.subheadline)
                                .foregroundStyle(TraceTheme.ink2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section {
                    LabeledContent("Full access", value: accounts.hasFullAccess ? "Included" : "Ended")
                } header: {
                    Text("Plan")
                } footer: {
                    Text("Every account has full access for now. When plans arrive, nothing you've saved changes.")
                }
                .listRowBackground(TraceTheme.graphite)

                Section {
                    Toggle(isOn: $accounts.syncEnabled) {
                        SettingsRow(title: "Sync places and routes", icon: "arrow.triangle.2.circlepath")
                    }
                    .toggleStyle(TraceToggleStyle())
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Sync starts once the Trace account server is connected. Your pairing file and live position never leave this iPhone.")
                }
                .listRowBackground(TraceTheme.graphite)

                Section("Sign-in") {
                    LabeledContent("Signed in with", value: account.method.title)
                    LabeledContent("Member since", value: account.created.formatted(date: .abbreviated, time: .omitted))
                }
                .listRowBackground(TraceTheme.graphite)

                Section {
                    Button {
                        confirmSignOut = true
                    } label: {
                        Text("Sign out")
                            .foregroundStyle(TraceTheme.ink)
                            .frame(maxWidth: .infinity)
                    }
                    // A red label, never a red fill.
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Text("Delete account")
                            .frame(maxWidth: .infinity)
                    }
                } footer: {
                    Text("Deleting your account removes it from this iPhone. Your places and pairing stay on the device.")
                }
                .listRowBackground(TraceTheme.graphite)
            }
        }
        .traceList()
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
            .listRowBackground(TraceTheme.graphite)

            Section {
                if supportsOnDevicePairing {
                    NavigationLink {
                        PairOnDeviceView(mode: .pushed)
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        SettingsRow(title: "Pair on this iPhone", icon: "iphone.radiowaves.left.and.right")
                    }
                }
                Button {
                    showImporter = true
                } label: {
                    SettingsRow(title: "Import a pairing file", icon: "square.and.arrow.down")
                }
                Button {
                    do {
                        try pairing.importPairingFromClipboard()
                        message = "Pairing file installed."
                    } catch {
                        message = error.localizedDescription
                    }
                } label: {
                    SettingsRow(title: "Paste from clipboard", icon: "doc.on.clipboard")
                }
            } footer: {
                Text(supportsOnDevicePairing
                     ? "On iOS 27, pair on this iPhone with no computer: confirm the six-digit code under Settings › Privacy & Security › Developer Mode › Pair with Host. On iOS 26, import an RPPairing file made with idevice_pair. In LiveContainer, use Paste if the file picker doesn't work."
                     : "Import an RPPairing file made with idevice_pair (not a SideStore .mobiledevicepairing file). In LiveContainer, use Paste if the file picker doesn't work.")
            }
            .listRowBackground(TraceTheme.graphite)

            if pairing.hasPairingFile {
                Section {
                    Button(role: .destructive) {
                        confirmRemove = true
                    } label: {
                        Text("Remove pairing")
                            .frame(maxWidth: .infinity)
                    }
                }
                .listRowBackground(TraceTheme.graphite)
            }
        }
        .traceList()
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
                    SettingsRow(title: installed ? "Open LocalDevVPN" : "Get LocalDevVPN", icon: "lock.shield")
                }
            } footer: {
                Text("LocalDevVPN opens a private tunnel on this iPhone. Start your first move on Wi‑Fi; after that it keeps working on cellular.")
            }
            .listRowBackground(TraceTheme.graphite)

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
            .listRowBackground(TraceTheme.graphite)
        }
        .traceList()
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                licence("Locus", "Trace's location engine is based on Locus by ChrisMack32, released under the MIT licence.")
                licence("idevice", "Location simulation uses the idevice FFI by jkcoxson, released under the MIT licence.")
                Text("MIT licence: permission is granted, free of charge, to any person obtaining a copy of this software to deal in it without restriction, provided the copyright notice and this permission notice are included. The software is provided \"as is\", without warranty of any kind.")
                    .font(.footnote)
                    .foregroundStyle(TraceTheme.ink3)
            }
            .padding(24)
        }
        .background(Color.black)
        .navigationTitle("Licences")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func licence(_ name: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.headline).foregroundStyle(TraceTheme.ink)
            Text(text).font(.subheadline).foregroundStyle(TraceTheme.ink2)
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                point("On this iPhone", "Your pairing file, live position, favourites, recents and routes are stored on this iPhone.")
                point("Your account", "Your account is stored on this iPhone until the Trace account server is connected.")
                point("Sync", "When sync arrives, it covers favourites, recents and routes. Your pairing file and live position never leave this iPhone.")
                point("No tracking", "No analytics and no advertising.")
            }
            .padding(24)
        }
        .background(Color.black)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func point(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(TraceTheme.ink)
            Text(text).font(.subheadline).foregroundStyle(TraceTheme.ink2)
        }
    }
}
