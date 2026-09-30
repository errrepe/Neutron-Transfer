// Neutron Transfer — in-memory unlocked key seeds (F3b-1: user keys).
// Seeds live ONLY in this actor's memory: never Keychain, never disk, never logs.
// Salted pass comes from SessionManager.fetchSaltedKeyPass (password scope).
import Foundation

actor KeyringCache {
    struct UnlockedKey: Sendable {
        var keyID: String
        var algo: UInt8
        var seed: Data
    }

    private let api: APIClient
    private let sessions: SessionManager
    private var seeds: [String: Data] = [:]

    init(api: APIClient = APIClient(), sessions: SessionManager) {
        self.api = api
        self.sessions = sessions
    }

    func fetchUser() async throws -> ProtonUser {
        try await sessions.withAuth { uid, token in
            try await self.api.get(ProtonUserResponse.self, path: "/core/v4/users", uid: uid, accessToken: token).user
        }
    }

    /// Unlocks all active user secret keys with the salted pass, verifying each
    /// decrypted seed against its public point (constant-size compare only).
    @discardableResult
    func unlockUserKeys(saltedPass: Data) async throws -> [UnlockedKey] {
        let user = try await fetchUser()
        var out: [UnlockedKey] = []
        for ref in user.keys where ref.isActive {
            let raw = try Armor.decode(ref.privateKey)
            for packet in try PGPPackets.parse(raw) where packet.tag == 5 || packet.tag == 7 {
                let sk = try SecretKeyPacket.parse(body: packet.body)
                let plain = try SecretKeyUnlock.decrypt(sk, passphrase: saltedPass)
                let seed = sk.publicAlgo == 18
                    ? try SecretKeyUnlock.ecdhScalar(plaintext: plain)
                    : try SecretKeyUnlock.secretScalar(plaintext: plain)
                let point = sk.publicPoint ?? Data()
                let ok = sk.publicAlgo == 22
                    ? SecretKeyVerify.ed25519PublicMatches(seed: seed, pointMPI: point)
                    : SecretKeyVerify.x25519PublicMatches(scalar: seed, pointMPI: point)
                guard ok else { throw ProtonAPIError.keyVerificationFailed }
                let id = "\(ref.id)#\(sk.publicAlgo)"
                seeds[id] = seed
                out.append(UnlockedKey(keyID: id, algo: sk.publicAlgo, seed: seed))
            }
        }
        guard !out.isEmpty else { throw ProtonAPIError.keyVerificationFailed }
        return out
    }

    func seed(for keyID: String) -> Data? { seeds[keyID] }

    func lock() { seeds.removeAll() }
}
