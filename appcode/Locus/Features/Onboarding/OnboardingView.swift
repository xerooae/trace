import AuthenticationServices
import SwiftUI

/// First run: Welcome → Account → Plan → Pair → Tunnel. Steps that are already
/// done (signed in, paired, set up) are skipped. Back is the system button; an
/// edge swipe does the same.
struct OnboardingView: View {
    enum Step: Hashable {
        case welcome, account, email, plan, pair, tunnel
    }

    var startsSignedIn: Bool

    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var pairing: PairingStore
    @AppStorage(Prefs.setupComplete) private var setupComplete = false
    @State private var root: Step?
    @State private var path: [Step] = []

    var body: some View {
        NavigationStack(path: $path) {
            screen(root ?? .welcome)
                .navigationDestination(for: Step.self) { screen($0) }
        }
        .onAppear {
            if root == nil {
                root = startsSignedIn ? (next(after: .account) ?? .tunnel) : .welcome
            }
        }
    }

    @ViewBuilder private func screen(_ step: Step) -> some View {
        Group {
            switch step {
            case .welcome:
                WelcomeStep { path.append(.account) }
            case .account:
                AccountStep(onEmail: { path.append(.email) }, onDone: { advance(from: .account) })
            case .email:
                EmailStep { advance(from: .email) }
            case .plan:
                PlanView(mode: .choose) { advance(from: .plan) }
            case .pair:
                PairStep { advance(from: .pair) }
            case .tunnel:
                TunnelStep { advance(from: .tunnel) }
            }
        }
        .toolbar {
            if let index = progressIndex(step) {
                ToolbarItem(placement: .principal) {
                    StepProgress(index: index, count: visibleSteps.count)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// Plan only shows when the account lacks access.
    private var visibleSteps: [Step] {
        accounts.hasFullAccess ? [.account, .pair, .tunnel] : [.account, .plan, .pair, .tunnel]
    }

    private func progressIndex(_ step: Step) -> Int? {
        visibleSteps.firstIndex(of: step == .email ? .account : step)
    }

    private func next(after step: Step) -> Step? {
        switch step {
        case .welcome:
            return .account
        case .account, .email:
            return accounts.hasFullAccess ? afterPlan() : .plan
        case .plan:
            return afterPlan()
        case .pair:
            return setupComplete ? nil : .tunnel
        case .tunnel:
            return nil
        }
    }

    private func afterPlan() -> Step? {
        if !pairing.hasPairingFile { return .pair }
        return setupComplete ? nil : .tunnel
    }

    private func advance(from step: Step) {
        if let next = next(after: step) {
            path.append(next)
        } else {
            setupComplete = true
        }
    }
}

/// Thin step bars. Reading only.
struct StepProgress: View {
    let index: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= index ? Color.white : Color(uiColor: .systemGray4))
                    .frame(width: 40, height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}

// MARK: - Welcome

struct WelcomeStep: View {
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            // The rendered mark is allowed here: 120 pt tall on black.
            BearingMark()
                .frame(width: 90, height: 120)
            Image("Wordmark")
                .resizable()
                .scaledToFit()
                .frame(width: 150)
                .padding(.top, 28)
                .accessibilityLabel("Trace")
            Text("Precisely elsewhere.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(TraceTheme.ink)
                .padding(.top, 32)
            Text("Set where your iPhone says it is. System-wide, on this iPhone, with no computer after pairing.")
                .font(.body)
                .foregroundStyle(TraceTheme.ink2)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Spacer(minLength: 40)
            PrimaryButton("Get started", size: .extraLarge, action: onStart)
            Button("I already have an account", action: onStart)
                .buttonStyle(.borderless)
                .tint(.secondary)
                .frame(minHeight: 44)
                .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TraceTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Account

struct AccountStep: View {
    var onEmail: () -> Void
    var onDone: () -> Void

    @EnvironmentObject private var accounts: AccountStore
    @State private var message: String?

    var body: some View {
        StepLayout("Create your account",
                   message: "Your account holds your plan and keeps your places in sync on every device you sign in to.") {
            EmptyView()
        } actions: {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 56)
            .clipShape(Capsule())

            SecondaryButton(size: .extraLarge) {
                message = AccountError.passkeyUnavailable.localizedDescription
            } label: {
                Label("Continue with a passkey", systemImage: "person.badge.key")
            }

            Button("Use email instead", action: onEmail)
                .buttonStyle(.borderless)
                .tint(.secondary)
                .frame(minHeight: 44)

            Text("By continuing you agree to the Terms and Privacy Policy.")
                .font(.caption)
                .foregroundStyle(TraceTheme.ink3)
                .multilineTextAlignment(.center)
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

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            accounts.signIn(with: credential)
            onDone()
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            // Unsigned and LiveContainer builds can't use Sign in with Apple.
            message = AccountError.appleUnavailable.localizedDescription
        }
    }
}

struct EmailStep: View {
    var onDone: () -> Void

    @EnvironmentObject private var accounts: AccountStore
    @State private var email = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        StepLayout("Your email",
                   message: "Your account lives on this iPhone for now. Codes and passkeys arrive with the account server.") {
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(TraceTheme.signal)
            }
        } actions: {
            // The field and its action ride on the keyboard, the closest place to the thumb while typing.
            HStack(spacing: 10) {
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.continue)
                    .onSubmit(submit)
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .background(TraceTheme.fill, in: Capsule())
                Button(action: submit) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(email.isEmpty ? TraceTheme.ink3 : Color.black)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.white)
                .disabled(email.isEmpty)
            }
        }
        .onAppear { focused = true }
    }

    private func submit() {
        do {
            try accounts.signIn(email: email)
            error = nil
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Plan

enum PlanOption: String, CaseIterable, Identifiable {
    case yearly, monthly

    var id: String { rawValue }
    var title: String { self == .yearly ? "Yearly" : "Monthly" }
    // Placeholder prices. StoreKit supplies the real ones (`Product.displayPrice`).
    var price: String { self == .yearly ? "£29.99" : "£3.99" }
    var period: String { self == .yearly ? "a year" : "a month" }
    var detail: String { self == .yearly ? "£2.50 a month · save 37%" : "Cancel anytime" }
    var terms: String { "\(price) \(period). Renews automatically until cancelled." }
}

/// Choose a plan in first run, or the hard lock when a plan has ended.
/// Not reachable while every account has full access.
struct PlanView: View {
    enum Mode { case choose, ended }

    var mode: Mode
    var onDone: () -> Void = {}

    @EnvironmentObject private var accounts: AccountStore
    @State private var plan: PlanOption = .yearly
    @State private var message: String?

    var body: some View {
        StepLayout(mode == .choose ? "Choose your plan" : "Your plan has ended",
                   message: mode == .choose
                   ? "One plan unlocks everything on every device you sign in to."
                   : "Renew to keep moving. Your places, routes and settings are kept and come back as they were.") {
            if mode == .choose {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(["Move anywhere, system-wide", "Routes, joystick and GPX", "Places synced across devices"], id: \.self) { line in
                        HStack(spacing: 12) {
                            BearingShape().fill(TraceTheme.ink2).frame(width: 9, height: 12)
                            Text(line).foregroundStyle(TraceTheme.ink)
                        }
                    }
                    Text("Needs iOS 26 or later with Developer Mode, and the free LocalDevVPN app. On iOS 26, pairing needs a computer once.")
                        .font(.footnote)
                        .foregroundStyle(TraceTheme.ink3)
                        .padding(.top, 6)
                }
            }
        } actions: {
            ForEach(PlanOption.allCases) { option in
                PlanCard(option: option, selected: plan == option) { plan = option }
            }
            PrimaryButton(mode == .choose ? "Subscribe" : "Renew", size: .extraLarge) {
                // Every account has full access for now; StoreKit purchase goes here.
                onDone()
            }
            HStack(spacing: 4) {
                Button("Restore purchases") { onDone() }
                if mode == .ended {
                    Button("Sign out") { accounts.signOut() }
                }
            }
            .buttonStyle(.borderless)
            .tint(.secondary)
            .frame(minHeight: 44)
            Text("\(plan.terms) Placeholder prices.")
                .font(.caption)
                .foregroundStyle(TraceTheme.ink3)
                .multilineTextAlignment(.center)
        }
    }
}

/// A large choice: white outline and an inverted check, so the action keeps the only white fill.
struct PlanCard: View {
    let option: PlanOption
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(selected ? Color.white : Color.clear)
                        .overlay(Circle().stroke(selected ? Color.clear : Color(uiColor: .systemGray3), lineWidth: 1.5))
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.black)
                    }
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.headline).foregroundStyle(TraceTheme.ink)
                    Text(option.detail).font(.footnote).foregroundStyle(TraceTheme.ink2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(option.price).font(.headline).foregroundStyle(TraceTheme.ink)
                    Text(option.period).font(.caption).foregroundStyle(TraceTheme.ink3)
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 72)
            .background(TraceTheme.cell, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(selected ? Color.white : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.impact(weight: .light), trigger: selected)
    }
}

// MARK: - Pair

struct PairStep: View {
    var onDone: () -> Void

    private var supportsOnDevicePairing: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    var body: some View {
        if supportsOnDevicePairing {
            PairOnDeviceView(mode: .embedded, onFinished: onDone)
        } else {
            ImportPairingStep(onDone: onDone)
        }
    }
}

/// iOS 26: pairing needs an RPPairing file made once on a computer.
struct ImportPairingStep: View {
    var onDone: () -> Void

    @EnvironmentObject private var pairing: PairingStore
    @State private var showImporter = false
    @State private var error: String?

    var body: some View {
        StepLayout("Pair this iPhone",
                   message: "On iOS 26, pairing needs a file made once on a computer. After that, Trace works on its own.") {
            StepsCard(steps: [
                "On a computer, run idevice_pair and create an RPPairing file.",
                "AirDrop or share it to this iPhone, or copy its text.",
                "Import it below, or paste it if the file picker doesn't work (LiveContainer).",
            ])
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(TraceTheme.signal)
                    .padding(.top, 8)
            }
        } actions: {
            PrimaryButton("Import pairing file", size: .extraLarge) { showImporter = true }
            SecondaryButton("Paste from clipboard", size: .extraLarge) {
                do {
                    try pairing.importPairingFromClipboard()
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                    } catch {
                        self.error = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: pairing.hasPairingFile) { _, paired in
            if paired { onDone() }
        }
    }
}

// MARK: - Tunnel

struct TunnelStep: View {
    var onDone: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var connected = LocalDevVPN.isConnected
    @State private var installed = LocalDevVPN.isInstalled

    var body: some View {
        StepLayout(connected ? "Connected" : "Connect LocalDevVPN",
                   message: connected
                   ? "Start your first move on Wi‑Fi. After that it keeps working on cellular."
                   : "LocalDevVPN opens a private tunnel on this iPhone. Trace uses it to reach the location service.") {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.body.weight(.medium))
                    .foregroundStyle(TraceTheme.ink2)
                Text("LocalDevVPN").foregroundStyle(TraceTheme.ink)
                Spacer()
                Text(connected ? "Connected" : installed ? "Not connected" : "Not installed")
                    .foregroundStyle(TraceTheme.ink2)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(TraceTheme.cell, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        } actions: {
            if connected {
                PrimaryButton("Start using Trace", size: .extraLarge, action: onDone)
            } else {
                PrimaryButton(installed ? "Open LocalDevVPN" : "Get LocalDevVPN", size: .extraLarge) {
                    LocalDevVPN.openOrInstall()
                }
                Button("Skip for now", action: onDone)
                    .buttonStyle(.borderless)
                    .tint(.secondary)
                    .frame(minHeight: 44)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func refresh() {
        connected = LocalDevVPN.isConnected
        installed = LocalDevVPN.isInstalled
    }
}
