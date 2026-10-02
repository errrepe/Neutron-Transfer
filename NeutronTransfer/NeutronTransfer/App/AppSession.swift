// Neutron Transfer — session root: single DI container + auth lifecycle (F7).
// Owns the ONLY SessionManager / KeyringCache / DriveClient / TransferQueue /
// TransferActivityStore; views read them via .environment (injected at the
// WindowGroup). Secrets stay inside the owning actors, memory only; the
// password exists as Data solely between signIn and the post-2FA key unlock,
// then is zeroed on every path (success, error, cancel, sign-out).
import Foundation

@MainActor
@Observable
final class AppSession {
    enum Phase: Equatable {
        case signedOut
        case signingIn      // SRP handshake in flight
        case needsTwoFactor // TOTP required; password retained for post-2FA unlock
        case unlocking      // session OK; decrypting key hierarchy (salts → user → address)
        case signedIn
    }

    /// Public account summary for the shell header (email, display name, quota).
    struct Account: Equatable, Sendable {
        var email: String
        var displayName: String
        var usedBytes: Int64
        var maxBytes: Int64?
    }

    private(set) var phase: Phase = .signedOut
    private(set) var account: Account?
    /// Error or sign-out reason shown on the login screen.
    var loginError: String?

    let activity = TransferActivityStore()
    let queue: TransferQueue
    let sessions: SessionManager
    let keyrings: KeyringCache
    /// The ONLY DriveClient in the app — features share this instance.
    let drive: DriveClient

    /// Unlocked address keys (share-passphrase chain root). Memory only.
    private(set) var addressKeys: [KeyringCache.UnlockedKey] = []
    /// Single resolver for share/node key material (S1.2) — shared by the
    /// upload/download adapters; created once `addressKeys` unlock, reset +
    /// dropped on sign-out.
    private(set) var resolver: NodeKeyResolver?
    /// Retained only between signIn and the post-2FA unlock; zeroed on exit.
    private var pendingPassword: Data?
    /// Username being signed in — account fallback when /users has no email.
    private var loginUsername: String?

    init(queueStoreURL: URL? = TransferQueue.defaultStoreURL()) {
        let sessions = SessionManager()
        self.sessions = sessions
        keyrings = KeyringCache(sessions: sessions)
        drive = DriveClient(sessions: sessions)
        queue = TransferQueue(storeURL: queueStoreURL)
    }

    // MARK: - sign-in

    /// SRP login, then the key-hierarchy unlock while the password grant is
    /// fresh (salts → user keys → address keys), then account info.
    /// Throws-needs2FA parks the phase and keeps `pendingPassword` alive for
    /// `submitTwoFactor` — every other exit zeroes it.
    func signIn(username: String, password: String) async {
        guard phase != .signingIn, phase != .unlocking else { return }
        phase = .signingIn
        loginError = nil
        loginUsername = username
        clearPendingPassword() // re-entry: never overwrite live bytes unzeroed
        pendingPassword = Data(password.utf8)
        do {
            guard let pwd = pendingPassword else { throw ProtonAPIError.unauthorized }
            try await sessions.login(username: username, password: pwd)
            phase = .unlocking
            try await finishSignIn()
            await refreshAccount()
            phase = .signedIn
        } catch let e as ProtonAPIError where e == .needs2FA {
            // Keep pendingPassword: the unlock still runs after submitTwoFactor.
            phase = .needsTwoFactor
            return
        } catch let e as ProtonAPIError where e == .bcryptNotAvailable {
            loginError = "Crypto backend missing (bcrypt). Report this bug."
            phase = .signedOut
        } catch {
            loginError = UserFacingError.message(for: error)
            phase = .signedOut
        }
        clearPendingPassword()
    }

    /// Completes a 2FA-gated login (TOTP code), then the same unlock path.
    func submitTwoFactor(code: String) async {
        guard phase == .needsTwoFactor else { return }
        phase = .unlocking
        do {
            try await sessions.submit2FA(code: code)
            try await finishSignIn()
            await refreshAccount()
            phase = .signedIn
        } catch let e as ProtonAPIError where e == .bcryptNotAvailable {
            loginError = "Crypto backend missing (bcrypt). Report this bug."
            phase = .signedOut
        } catch {
            loginError = UserFacingError.message(for: error)
            phase = .signedOut
        }
        clearPendingPassword()
    }

    /// Backs out of the 2FA prompt — a plain sign-out with no error message.
    func cancelTwoFactor() async {
        await signOut()
    }

    /// Sign-out order (S0.3): pause + detach the upload queue BEFORE dropping
    /// auth, revoke the session server-side (best-effort), wipe key seeds,
    /// then reset UI-visible state. `reason` lands on the login screen.
    func signOut(reason: String? = nil) async {
        await queue.pauseAll()
        await queue.setUploader(nil)
        await resolver?.reset()
        resolver = nil
        await sessions.signOut()
        await keyrings.lock()
        addressKeys = []
        clearPendingPassword()
        loginUsername = nil
        account = nil
        loginError = reason
        phase = .signedOut
    }

    /// Fetches /core/v4/users + /core/v4/addresses for the account header.
    /// Cosmetic: a failure degrades to the typed username, never blocks login.
    func refreshAccount() async {
        do {
            let user = try await keyrings.fetchUser()
            let addresses = try await keyrings.fetchAddresses()
            let email = user.email ?? addresses.first?.email ?? loginUsername ?? ""
            account = Account(
                email: email,
                displayName: user.displayName ?? user.name ?? email,
                usedBytes: user.usedSpace ?? 0,
                maxBytes: user.maxSpace
            )
        } catch {
            guard account == nil, let loginUsername else { return }
            account = Account(email: loginUsername, displayName: loginUsername,
                              usedBytes: 0, maxBytes: nil)
        }
    }

    // MARK: - internals

    /// Salts → user keys → address keys, while the password grant is fresh
    /// (moved from LoginViewModel, semantics unchanged). Seeds stay in the
    /// KeyringCache actor + `addressKeys` (memory only, never disk).
    private func finishSignIn() async throws {
        guard let pwd = pendingPassword else { throw ProtonAPIError.unauthorized }
        let primaryID = try await keyrings.fetchUser().primaryKey?.id ?? ""
        let salted = try await sessions.fetchSaltedKeyPass(password: pwd, primaryKeyID: primaryID)
        let userKeys = try await keyrings.unlockUserKeys(saltedPass: salted)
        addressKeys = try await keyrings.unlockAddressKeys(userKeys: userKeys)
        resolver = NodeKeyResolver(source: drive, addressKeys: addressKeys)
    }

    /// Scrubs the retained password: resetBytes writes zeros into the buffer
    /// BEFORE the reference drops. Call sites run only after every `let pwd`
    /// copy is out of scope, so pendingPassword uniquely owns its storage and
    /// the mutation hits the real bytes (Data is copy-on-write — zeroing a
    /// shared copy would silently scrub a detached buffer instead).
    private func clearPendingPassword() {
        if let count = pendingPassword?.count {
            pendingPassword?.resetBytes(in: 0..<count)
        }
        pendingPassword = nil
    }
}

#if DEBUG
extension AppSession {
    /// Preview seam: no disk persistence (queue storeURL nil), no network —
    /// stays in `.signedOut` so login/2FA screens render offline.
    static func preview() -> AppSession {
        AppSession(queueStoreURL: nil)
    }
}
#endif
