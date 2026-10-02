// Nucleon Transfer — client-side node-key generation (F4.2).
// Mirrors gopenpgp helper.GenerateKey("Drive key", ..., "x25519", 0) used by
// Proton-API-Bridge/rclone for new folder/file nodes: a fresh Ed25519
// primary (algo 22) + X25519 subkey (algo 18, legacy ECDH KDF 03 01 08 07),
// each secret locked with a fresh random passphrase via iterated+salted S2K
// (type 3, SHA-256) + plain CFB under a random IV, usage 254 (SHA-1
// checksum). The armor is a full transferable key, byte-layout-identical to
// official creates (rclone-captured): primary (tag 5) + UID "Drive key
// <noreply@protonmail.com>" (tag 13) + self-certification (tag 2, type 0x13,
// SHA-256) + subkey (tag 7) + binding signature (tag 2, type 0x18). The
// server requires the self-sigs to establish key ownership (bare 5+7 blobs
// are rejected with 200501). OIDs and KDF ids match live Proton keys
// byte-for-byte (probe-verified).
import CryptoKit
import Foundation

enum NodeKeyGenError: Error, Sendable {
    case badPassphrase
}

enum NodeKeyGen {
    /// Curve OIDs (content bytes, no DER header), probe-verified live.
    static let edOID = Data([0x2B, 0x06, 0x01, 0x04, 0x01, 0xDA, 0x47, 0x0F, 0x01])
    static let ecdhOID = Data([0x2B, 0x06, 0x01, 0x04, 0x01, 0x97, 0x55, 0x01, 0x05, 0x01])
    /// Legacy ECDH KDF params (RFC 6637 §8): len(1)=3, reserved=1, SHA-256, AES-128.
    static let ecdhKDF = Data([0x03, 0x01, 0x08, 0x07])
    /// S2K locking for generated secrets: AES-256, iterated+salted SHA-256.
    static let lockSymAlgo: UInt8 = 9
    static let lockS2KHash: UInt8 = 8
    /// Coded iteration count 0x60 = 65536 (S2K.codedCount parity).
    static let lockS2KCount: UInt8 = 0x60

    struct GeneratedKey: Sendable {
        var armoredKey: String
        var edSeed: Data // 32-byte Ed25519 seed (algo 22 primary)
        var xScalarLE: Data // 32-byte X25519 scalar, little-endian (algo 18 subkey)
        var edFingerprint: Data // v4 fingerprints of each packet's public part
        var xFingerprint: Data
        var createdAt: UInt32
    }

    /// Generates a fresh node key, locking both secrets with `passphrase`
    /// (the node passphrase bytes). Returns seeds + fingerprints alongside
    /// the armored key so callers can build recipients/candidates without
    /// re-parsing.
    static func generate(passphrase: Data, createdAt: UInt32? = nil) throws -> GeneratedKey {
        guard !passphrase.isEmpty else { throw NodeKeyGenError.badPassphrase }
        let created = createdAt ?? UInt32(Date().timeIntervalSince1970)
        let edPriv = Curve25519.Signing.PrivateKey()
        let xPriv = Curve25519.KeyAgreement.PrivateKey()
        let edSeed = edPriv.rawRepresentation
        let xScalarLE = xPriv.rawRepresentation
        let edPoint = edPriv.publicKey.rawRepresentation
        let xPoint = xPriv.publicKey.rawRepresentation

        let (edBody, edPub) = try secretPacket(
            algo: 22, point: edPoint, seedMPIContent: edSeed,
            kdf: nil, passphrase: passphrase, createdAt: created
        )
        // X25519 secrets are stored big-endian MPI numbers (unlock reverses
        // back to LE — SecretKeyUnlock.ecdhScalar parity).
        let (xBody, xPub) = try secretPacket(
            algo: 18, point: xPoint, seedMPIContent: Data(xScalarLE.reversed()),
            kdf: ecdhKDF, passphrase: passphrase, createdAt: created
        )
        let edFP = try PGPFingerprint.v4(publicBody: edPub)
        let xFP = try PGPFingerprint.v4(publicBody: xPub)
        let uid = Data(nodeKeyUID.utf8)
        let cert = try DetachedSign.certificationBody(
            primaryPub: edPub, uid: uid, signerSeedLE: edSeed,
            signerKeyID: Data(edFP.suffix(8)), signerFingerprint: edFP,
            hashAlgo: 8, createdAt: created, salt: DetachedSign.freshSalt(16)
        )
        let bind = try DetachedSign.subkeyBindingBody(
            primaryPub: edPub, subkeyPub: xPub, signerSeedLE: edSeed,
            signerKeyID: Data(edFP.suffix(8)), signerFingerprint: edFP,
            hashAlgo: 8, createdAt: created, salt: DetachedSign.freshSalt(16)
        )
        var raw = PGPPacketsEncode.packet(tag: 5, body: edBody)
        raw.append(PGPPacketsEncode.packet(tag: 13, body: uid))
        raw.append(PGPPacketsEncode.packet(tag: 2, body: cert))
        raw.append(PGPPacketsEncode.packet(tag: 7, body: xBody))
        raw.append(PGPPacketsEncode.packet(tag: 2, body: bind))
        return GeneratedKey(
            armoredKey: Armor.encode(raw, header: "PRIVATE KEY BLOCK"),
            edSeed: edSeed, xScalarLE: xScalarLE,
            edFingerprint: edFP, xFingerprint: xFP,
            createdAt: created
        )
    }

    /// Fresh node passphrase: base64(std) of 32 random bytes (44 chars),
    /// matching Proton-API-Bridge generatePassphrase (crypto.RandomToken(32)).
    static func randomPassphrase() -> Data {
        let token = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        return Data(token.base64EncodedString().utf8)
    }

    // MARK: - private

    /// Builds one secret-key packet body. Returns (body, publicBody) where
    /// publicBody is exactly what SecretKeyPacket.parse extracts for
    /// fingerprinting (version..end of public material).
    private static func secretPacket(
        algo: UInt8,
        point: Data,
        seedMPIContent: Data,
        kdf: Data?,
        passphrase: Data,
        createdAt: UInt32
    ) throws -> (body: Data, publicBody: Data) {
        precondition(point.count == 32 && seedMPIContent.count == 32)
        let oid = algo == 22 ? edOID : ecdhOID
        var pub = Data([0x04])
        pub.append(UInt8((createdAt >> 24) & 0xFF))
        pub.append(UInt8((createdAt >> 16) & 0xFF))
        pub.append(UInt8((createdAt >> 8) & 0xFF))
        pub.append(UInt8(createdAt & 0xFF))
        pub.append(algo)
        pub.append(UInt8(oid.count))
        pub.append(oid)
        pub.append(DetachedSign.mpiEncode(Data([0x40]) + point))
        if let kdf { pub.append(kdf) }

        // S2K lock: type 3 (iterated+salted), SHA-256, fresh salt, 64k rounds.
        let salt = Data((0..<8).map { _ in UInt8.random(in: .min ... .max) })
        let s2kSpec = Data([0x03, lockS2KHash]) + salt + Data([lockS2KCount])
        let (key, _) = try S2K.derive(spec: s2kSpec, passphrase: passphrase, keyLength: 32)
        let iv = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        let secretMPI = DetachedSign.mpiEncode(seedMPIContent)
        let secretPlain = secretMPI + (try PGPHash.digest(id: 2, secretMPI)) // usage 254
        let secretData = try AESBlock.cfbEncrypt(plaintext: secretPlain, key: key, iv: iv)

        var body = pub
        body.append(0xFE) // s2kUsage 254: SHA-1 checksum
        body.append(lockSymAlgo)
        body.append(s2kSpec)
        body.append(iv)
        body.append(secretData)
        return (body, pub)
    }
}
