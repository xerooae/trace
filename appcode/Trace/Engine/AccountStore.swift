import AuthenticationServices
import Foundation

struct TraceAccount: Codable, Equatable {
    enum Method: String, Codable {
        case apple, passkey, email

        var title: String {
            switch self {
            case .apple: return "Apple"
            case .passkey: return "Passkey"
            case .email: return "Email"
            }
        }
    }

    var id: String
    var name: String
    var email: String
    var method: Method
    var created: Date

    var displayName: String {
        name.isEmpty ? "Trace account" : name
    }

    var initials: String {
        let source = name.isEmpty ? email : name
        let words = source.split { $0 == " " || $0 == "." || $0 == "@" || $0 == "_" || $0 == "-" }
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "T" : String(letters).uppercased()
    }
}

enum AccessLevel: Equatable {
    case full
    case ended
}

enum AccountError: LocalizedError {
    case invalidEmail
    case appleUnavailable
    case passkeyUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "That email address doesn't look complete."
        case .appleUnavailable:
            return "Sign in with Apple isn't available in this build. Use email instead."
        case .passkeyUnavailable:
            return "Passkeys need the Trace account server, which isn't connected yet. Use Sign in with Apple or email for now."
        }
    }
}

/// The account lives on this iPhone until the account server exists. Sign-in
/// methods, sync and plans are shaped so a server can slot in behind them.
@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var account: TraceAccount? = nil
    @Published var syncEnabled = true {
        didSet { UserDefaults.standard.set(syncEnabled, forKey: Keys.sync) }
    }

    /// Every account has full access for now. When subscriptions go live, read
    /// `Transaction.currentEntitlements` here and return `.ended` when none is active.
    var access: AccessLevel { .full }
    var hasFullAccess: Bool { access == .full }

    private enum Keys {
        static let account = "trace.account"
        static let sync = "trace.syncEnabled"
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Keys.account),
           let saved = try? JSONDecoder().decode(TraceAccount.self, from: data) {
            account = saved
        }
        syncEnabled = Prefs.bool(Keys.sync)
    }

    func signIn(with credential: ASAuthorizationAppleIDCredential) {
        // Apple sends the name and email only on the first sign-in, so keep what we had.
        let previous = account?.id == credential.user ? account : nil
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        save(TraceAccount(
            id: credential.user,
            name: name.isEmpty ? previous?.name ?? "" : name,
            email: credential.email ?? previous?.email ?? "",
            method: .apple,
            created: previous?.created ?? .now
        ))
    }

    func signIn(email: String) throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isValidEmail(trimmed) else { throw AccountError.invalidEmail }
        let local = trimmed.split(separator: "@").first.map(String.init) ?? ""
        let name = local
            .split { $0 == "." || $0 == "_" || $0 == "-" || $0 == "+" }
            .map { $0.capitalized }
            .joined(separator: " ")
        save(TraceAccount(id: UUID().uuidString, name: name, email: trimmed, method: .email, created: .now))
    }

    func signOut() {
        account = nil
        UserDefaults.standard.removeObject(forKey: Keys.account)
    }

    /// Removes the account from this iPhone. Places and the pairing stay on the device.
    func deleteAccount() {
        signOut()
        syncEnabled = true
    }

    static func isValidEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !value.contains(" ") else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    private func save(_ account: TraceAccount) {
        self.account = account
        if let data = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(data, forKey: Keys.account)
        }
    }
}
