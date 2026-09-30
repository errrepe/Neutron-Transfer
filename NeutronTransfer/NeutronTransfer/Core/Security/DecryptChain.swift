// Neutron Transfer — key hierarchy unlock orchestration (F3b chain).
// Mirrors go-proton-api Share.GetKeyRing + Link.GetKeyRing/GetName and the
// rclone bridge flow: share via address keys, node via parent keyring,
// names via node keyring. Pure crypto: callers supply fetched models.
// EC only (algo 18/22); RSA keys throw unsupportedAlgo (follow-up).
import CryptoKit
import Foundation

enum DecryptChainError: Error, Sendable {
    case missingMaterial(String)
    case signatureRejected
}

enum DecryptChain {
    /// Unlocks a share's private key: decrypts Passphrase with address ECDH
    /// candidates, verifies the detached signature with an address Ed25519
    /// point, unlocks Share.Key with the passphrase.
    static func unlockShare(
        _ share: DriveShare,
        addressKeys: [KeyringCache.UnlockedKey]
    ) throws -> KeyringCache.UnlockedKey {
        guard let passArmored = share.passphrase, !passArmored.isEmpty,
              let keyArmored = share.key, !keyArmored.isEmpty else {
            throw DecryptChainError.missingMaterial("share passphrase/key")
        }
        let candidates = addressKeys.compactMap(\.candidate)
        let passphrase = try MessageDecrypt.decrypt(armored: passArmored, candidates: candidates)
        if let sigArmored = share.passphraseSignature, !sigArmored.isEmpty {
            try verifyDetached(message: Data(passphrase), signatureArmored: sigArmored,
                               signerPoints: edPoints(addressKeys))
        }
        return try unlockSecretKey(armored: keyArmored, passphrase: Data(passphrase),
                                   id: "share/\(share.shareID)")
    }

    /// Unlocks a link's node key with parent candidates (share seeds for the
    /// root, folder node seeds below), verifying the passphrase signature.
    static func unlockNode(
        _ link: DriveLink,
        parentCandidates: [DecryptCandidate],
        signerPoints: [Data]
    ) throws -> KeyringCache.UnlockedKey {
        guard let passArmored = link.nodePassphrase, !passArmored.isEmpty,
              let keyArmored = link.nodeKey, !keyArmored.isEmpty else {
            throw DecryptChainError.missingMaterial("node passphrase/key")
        }
        let passphrase = try MessageDecrypt.decrypt(armored: passArmored, candidates: parentCandidates)
        if let sigArmored = link.nodePassphraseSignature, !sigArmored.isEmpty {
            try verifyDetached(message: Data(passphrase), signatureArmored: sigArmored,
                               signerPoints: signerPoints)
        }
        return try unlockSecretKey(armored: keyArmored, passphrase: Data(passphrase),
                                   id: "node/\(link.linkID)")
    }

    /// Decrypts a link's filename with node candidates (no signature on names).
    static func decryptName(
        _ link: DriveLink,
        nodeCandidates: [DecryptCandidate]
    ) throws -> String {
        let bytes = try MessageDecrypt.decrypt(armored: link.name, candidates: nodeCandidates)
        guard let name = String(data: bytes, encoding: .utf8) else {
            throw DecryptChainError.missingMaterial("name encoding")
        }
        return name
    }

    /// Address Ed25519 points for passphrase-signature verification.
    static func edPoints(_ keys: [KeyringCache.UnlockedKey]) -> [Data] {
        keys.filter { $0.algo == 22 }.compactMap { k in
            try? Curve25519.Signing.PrivateKey(rawRepresentation: k.seed).publicKey.rawRepresentation
        }
    }

    // MARK: - private

    private static func verifyDetached(message: Data, signatureArmored: String, signerPoints: [Data]) throws {
        let raw = try Armor.decode(signatureArmored)
        guard let sigBody = try PGPPackets.parse(raw).first(where: { $0.tag == 2 })?.body else {
            throw DecryptChainError.missingMaterial("signature packet")
        }
        let sig = try DetachedSig.parse(body: sigBody)
        for point in signerPoints {
            if (try? sig.verify(data: message, signerPointMPI: point)) == true { return }
        }
        throw DecryptChainError.signatureRejected
    }

    private static func unlockSecretKey(armored: String, passphrase: Data, id: String) throws -> KeyringCache.UnlockedKey {
        let raw = try Armor.decode(armored)
        let packets = try PGPPackets.parse(raw)
        // Node/share keys are single-key blobs; use the first secret packet.
        guard let packet = packets.first(where: { $0.tag == 5 || $0.tag == 7 }) else {
            throw DecryptChainError.missingMaterial("secret packet")
        }
        let sk = try SecretKeyPacket.parse(body: packet.body)
        guard sk.publicAlgo == 18 || sk.publicAlgo == 22 else {
            throw SecretKeyError.unsupportedAlgo(sk.publicAlgo)
        }
        let plain = try SecretKeyUnlock.decrypt(sk, passphrase: passphrase)
        let seed = sk.publicAlgo == 18
            ? try SecretKeyUnlock.ecdhScalar(plaintext: plain)
            : try SecretKeyUnlock.secretScalar(plaintext: plain)
        let point = sk.publicPoint ?? Data()
        let ok = sk.publicAlgo == 22
            ? SecretKeyVerify.ed25519PublicMatches(seed: seed, pointMPI: point)
            : SecretKeyVerify.x25519PublicMatches(scalar: seed, pointMPI: point)
        guard ok else { throw ProtonAPIError.keyVerificationFailed }
        return KeyringCache.UnlockedKey(
            keyID: "\(id)#\(sk.publicAlgo)", algo: sk.publicAlgo, seed: seed,
            fingerprint: try PGPFingerprint.v4(publicBody: sk.publicBody),
            kdfHash: sk.kdfHash ?? 8, kdfCipher: sk.kdfCipher ?? 9,
            curveOIDBody: sk.curveOID ?? Data()
        )
    }
}
