// Neutron Transfer — session orchestrator.
// Flow: info -> hashPassword(v4, bcrypt) -> SRP proofs -> /auth/v4
//       -> verify serverProof -> optional 2FA -> persist Keychain.
// 401 anywhere -> single /auth/v4/refresh retry (mirrors go-proton-api Client.doRes).
import CryptoKit
import Foundation

actor SessionManager {
    private var session: ProtonSession?
    private let api: APIClient
    private let bcrypt: any BcryptHasher

    init(api: APIClient = APIClient(), bcrypt: any BcryptHasher = ProtonBcryptHasher()) {
        self.api = api
        self.bcrypt = bcrypt
        if let saved = KeychainStore.load() { self.session = saved }
    }

    var isSignedIn: Bool { session != nil }
    var uid: String? { session?.uid }

    /// Login with username + password. Throws needs2FA when TOTP required —
    /// caller must invoke submit2FA(code:) to complete.
    func login(username: String, password: Data) async throws {
        let info = try await api.authInfo(username: username)
        // Modulus arrives PGP-clearsigned (go-srp readClearSignedMessage).
        // Signature verification is TODO F2c; transport is TLS-protected.
        let modulus = try ModulusDecoder.decode(info.modulus)
        guard let salt = Data(base64Encoded: info.salt),
              let serverEphem = Data(base64Encoded: info.serverEphemeral) else {
            throw ProtonAPIError.srpParamsOutOfBounds("auth/info not base64")
        }
        let hashed = try PasswordHash.hash(version: info.version, password: password,
                                           username: username, salt: salt,
                                           modulus: modulus, bcrypt: bcrypt)
        let proofs = try SRPClient.generateProofs(hashedPassword: hashed,
                                                 serverEphemeral: serverEphem,
                                                 modulus: modulus)
        let res = try await api.auth(AuthRequest(username: username,
                                                 clientEphemeral: proofs.clientEphemeral.base64EncodedString(),
                                                 clientProof: proofs.clientProof.base64EncodedString(),
                                                 srpSession: info.srpSession))
        guard let serverProof = Data(base64Encoded: res.auth.serverProof) else {
            throw ProtonAPIError.invalidServerProof
        }
        guard constantTimeEqual(serverProof, proofs.expectedServerProof) else {
            throw ProtonAPIError.invalidServerProof
        }
        let next = ProtonSession(uid: res.auth.uid, accessToken: res.auth.accessToken,
                                 refreshToken: res.auth.refreshToken)
        try KeychainStore.save(next)
        session = next
        if res.auth.requires2FA { throw ProtonAPIError.needs2FA }
    }

    func submit2FA(code: String) async throws {
        guard let s = session else { throw ProtonAPIError.unauthorized }
        try await api.auth2FA(code: code, uid: s.uid, accessToken: s.accessToken)
    }

    func signOut() {
        session = nil
        KeychainStore.delete()
    }

    /// Refresh tokens proactively (long syncs expire quickly — rclone #7381).
    func refresh() async throws {
        guard let s = session else { throw ProtonAPIError.unauthorized }
        var state = Data(count: 32)
        _ = state.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        let body = AuthRefreshRequest(uid: s.uid, refreshToken: s.refreshToken,
                                      state: state.base64EncodedString(), accessToken: s.accessToken)
        let auth = try await api.authRefresh(body)
        let next = ProtonSession(uid: auth.uid.isEmpty ? s.uid : auth.uid,
                                 accessToken: auth.accessToken, refreshToken: auth.refreshToken)
        try KeychainStore.save(next)
        session = next
    }
}

private func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for (x, y) in zip(a, b) { diff |= x ^ y }
    return diff == 0
}
