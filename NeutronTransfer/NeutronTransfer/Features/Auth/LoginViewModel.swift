// Neutron Transfer — auth UI state (F2b: real login via SessionManager).
// After login, unlocks the key hierarchy while the password scope is fresh
// (salts require it): saltedKeyPass -> user keys -> address keys. Password
// is zeroed as soon as the unlock completes; on needs2FA it is retained
// only until the post-2FA unlock finishes.
import Foundation

@MainActor
@Observable
final class LoginViewModel {
    enum State: Equatable {
        case signedOut
        case needs2FA
        case signingIn
        case signedIn(uid: String)
        case error(String)
    }

    var username = ""
    var password = ""
    var totp = ""
    var state: State = .signedOut
    private let sessions: SessionManager
    private let keyrings: KeyringCache
    private var userKeys: [KeyringCache.UnlockedKey] = []
    private var addrKeys: [KeyringCache.UnlockedKey] = []

    init() {
        let s = SessionManager()
        sessions = s
        keyrings = KeyringCache(sessions: s)
    }

    /// Shared session for Drive/transfer features (same actor instance).
    var sessionManager: SessionManager { sessions }
    var keyringCache: KeyringCache { keyrings }
    /// Address keys unlock share passphrases (browser root).
    var addressKeys: [KeyringCache.UnlockedKey] { addrKeys }

    func signIn() async {
        state = .signingIn
        let pwd = Data(password.utf8)
        do {
            try await sessions.login(username: username, password: pwd)
            try await finishSignIn(password: pwd)
            password = ""
            let uid = await sessions.uid ?? ""
            state = .signedIn(uid: uid)
        } catch let e as ProtonAPIError where e == .needs2FA {
            // Keep the password: unlock still needs to run after submit2FA.
            state = .needs2FA
        } catch let e as ProtonAPIError where e == .bcryptNotAvailable {
            password = ""
            state = .error("Crypto backend missing (bcrypt). Report this bug.")
        } catch {
            password = ""
            state = .error(error.localizedDescription)
        }
    }

    func submit2FA() async {
        let pwd = Data(password.utf8)
        do {
            try await sessions.submit2FA(code: totp)
            totp = ""
            try await finishSignIn(password: pwd)
            password = ""
            let uid = await sessions.uid ?? ""
            state = .signedIn(uid: uid)
        } catch {
            password = ""
            state = .error(error.localizedDescription)
        }
    }

    /// Runs while the password grant is fresh: salts -> user keys ->
    /// address keys. Seeds stay in the KeyringCache actor + these arrays
    /// (memory only, never disk).
    private func finishSignIn(password pwd: Data) async throws {
        let primaryID = try await keyrings.fetchUser().primaryKey?.id ?? ""
        let salted = try await sessions.fetchSaltedKeyPass(password: pwd, primaryKeyID: primaryID)
        userKeys = try await keyrings.unlockUserKeys(saltedPass: salted)
        addrKeys = try await keyrings.unlockAddressKeys(userKeys: userKeys)
    }
}
