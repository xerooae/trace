import SwiftUI

/// iOS 27 on-device pairing. Reading at the top (steps, the code), actions at the bottom.
struct PairOnDeviceView: View {
    enum Mode {
        /// First run: calls `onFinished` after success.
        case embedded
        /// Pushed from Settings › Pairing: Done pops back.
        case pushed
    }

    var mode: Mode = .pushed
    var onFinished: (() -> Void)? = nil

    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var host = PairOnDeviceService()

    var body: some View {
        StepLayout(title, message: message) {
            content
        } actions: {
            actions
        }
        .onChange(of: host.phase) { _, phase in
            if case .succeeded = phase {
                pairing.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, host.isBusy {
                _ = host.pin
            }
        }
        .onDisappear {
            if host.isBusy { host.resetToIdle() }
        }
    }

    private var title: String {
        switch host.phase {
        case .idle: return "Pair this iPhone"
        case .advertising: return "Open Settings"
        case .deviceConnected: return "Almost there"
        case .awaitingPIN: return "Type this code in Settings"
        case .succeeded: return "Paired"
        case .failed: return "Pairing didn't finish"
        }
    }

    private var message: String {
        switch host.phase {
        case .idle:
            return "A one-time pairing lets Trace set your position. You won't need a computer."
        case .advertising:
            return "Go to Settings › Privacy & Security › Developer Mode › Pair with Host, then tap Pair with Trace. Keep Trace running."
        case .deviceConnected:
            return "Your iPhone connected. Trace is making your code."
        case .awaitingPIN:
            return "Settings asks for your passcode first. The code goes in the second prompt."
        case .succeeded:
            return mode == .embedded ? "This iPhone is paired. Next, the tunnel." : "This iPhone is paired."
        case .failed(let reason):
            return reason
        }
    }

    @ViewBuilder private var content: some View {
        switch host.phase {
        case .idle, .failed:
            StepsCard(steps: [
                "Tap Start pairing, and allow Local Network and notifications when asked.",
                "Open Settings › Privacy & Security › Developer Mode › Pair with Host.",
                "Enter your passcode, then type the six-digit code Trace shows you.",
            ])
        case .advertising, .deviceConnected:
            HStack(spacing: 10) {
                PositionMarker(state: .connecting, width: 11)
                Text("Waiting for Settings…")
                    .font(.subheadline)
                    .foregroundStyle(TraceTheme.ink2)
            }
            .padding(.top, 8)
        case .awaitingPIN(let pin):
            Text(Self.grouped(pin))
                .font(.system(size: 46, weight: .medium, design: .monospaced))
                .tracking(4)
                .foregroundStyle(TraceTheme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                .accessibilityLabel("Pairing code \(pin.map(String.init).joined(separator: " "))")
        case .succeeded:
            BearingShape()
                .fill(TraceTheme.ink)
                .frame(width: 36, height: 48)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var actions: some View {
        switch host.phase {
        case .idle, .failed:
            Button(host.phase == .idle ? "Start pairing" : "Try again") {
                host.acknowledgeFailure()
                host.start(pairingStore: pairing)
            }
            .buttonStyle(TracePrimaryButtonStyle(height: 56))
        case .succeeded:
            Button(mode == .embedded ? "Continue" : "Done") {
                if let onFinished {
                    onFinished()
                } else {
                    dismiss()
                }
            }
            .buttonStyle(TracePrimaryButtonStyle(height: 56))
        case .advertising, .deviceConnected, .awaitingPIN:
            Text("Don't force-quit Trace while you're in Settings.")
                .font(.footnote)
                .foregroundStyle(TraceTheme.ink3)
                .multilineTextAlignment(.center)
            Button("Cancel") { host.resetToIdle() }
                .buttonStyle(TraceGlassButtonStyle(height: 56))
        }
    }

    /// "418207" → "418 207"
    private static func grouped(_ pin: String) -> String {
        guard pin.count == 6 else { return pin }
        return "\(pin.prefix(3)) \(pin.suffix(3))"
    }
}
