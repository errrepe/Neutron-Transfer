// Neutron Transfer — ECDH session-key encrypt (RFC 6637 §8, go-crypto ecdh.go).
// Exact inverse of ECDHDecrypt: fresh ephemeral X25519 keypair, shared
// secret ZB, KDF = Hash(0x00000001 || ZB || Param) with Param =
// len||OID||18 03 01 hash cipher||"Anonymous Sender    "||fp20 (NO DER tag),
// AES-KW wrap of the PKCS#5-padded session payload (cipherID || key ||
// checksum16). Covers v4 keys with legacy ECDH (algo 18, e.g. Cv25519).
import CryptoKit
import Foundation

enum ECDHEncryptError: Error, Sendable {
    case badInput
    case wrappedTooLong
}

enum ECDHEncrypt {
    /// Builds a v3 PKESK body for ECDH (algo 18): version(1)=3, keyID(8) =
    /// recipient fingerprint tail, algo(1)=18, MPI ephemeral (0x40 + 32
    /// bytes), lenOctet(1) + AES-KW wrapped session.
    /// - Parameters:
    ///   - sessionKey: random session key, length matching `cipherFunc`.
    ///   - cipherFunc: session symmetric algo (7/8/9).
    ///   - recipientPublicPoint: recipient X25519 point, 32 bytes
    ///     (0x40 prefix tolerated).
    ///   - recipientFingerprint: recipient v4 fingerprint (20 bytes).
    ///   - curveOIDBody: curve OID content bytes (no DER header).
    ///   - kdfHash/kdfCipher: from the recipient key's KDF params.
    ///   - ephemeralPrivateLE: override for deterministic vectors; random
    ///     ephemeral keypair when nil.
    static func encrypt(
        sessionKey: Data,
        cipherFunc: UInt8,
        recipientPublicPoint: Data,
        recipientFingerprint: Data,
        curveOIDBody: Data,
        kdfHash: UInt8,
        kdfCipher: UInt8,
        ephemeralPrivateLE: Data? = nil
    ) throws -> Data {
        let keyLen = try PGPSymmetricAlgo.keyLength(id: cipherFunc)
        guard sessionKey.count == keyLen, recipientFingerprint.count == 20 else {
            throw ECDHEncryptError.badInput
        }
        var point = recipientPublicPoint
        if point.count == 33, point.first == 0x40 { point = point.dropFirst() }
        guard point.count == 32 else { throw ECDHEncryptError.badInput }
        let recipientPub: Curve25519.KeyAgreement.PublicKey
        do {
            recipientPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: point)
        } catch {
            throw ECDHEncryptError.badInput
        }
        let ephPriv: Curve25519.KeyAgreement.PrivateKey
        if let eph = ephemeralPrivateLE {
            guard eph.count == 32 else { throw ECDHEncryptError.badInput }
            do {
                ephPriv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: eph)
            } catch {
                throw ECDHEncryptError.badInput
            }
        } else {
            ephPriv = Curve25519.KeyAgreement.PrivateKey()
        }
        let ephPub = ephPriv.publicKey.rawRepresentation
        let zb: Data
        do {
            zb = try ephPriv.sharedSecretFromKeyAgreement(with: recipientPub)
                .withUnsafeBytes { Data($0) }
        } catch {
            throw ECDHEncryptError.badInput
        }

        // Same Param construction as ECDHDecrypt (RFC 6637 §8).
        var param = Data([UInt8(curveOIDBody.count)])
        param.append(curveOIDBody)
        param.append(contentsOf: [18, 3, 1, kdfHash, kdfCipher])
        param.append(contentsOf: "Anonymous Sender    ".utf8)
        param.append(recipientFingerprint)

        let kekLen = try PGPSymmetricAlgo.keyLength(id: kdfCipher)
        var kdfInput = Data([0, 0, 0, 1])
        kdfInput.append(zb)
        kdfInput.append(param)
        let kek = try PGPHash.digest(id: kdfHash, kdfInput).prefix(kekLen)

        // Session payload + checksum, PKCS#5-padded to a multiple of 8
        // (AES-KW needs >= 16 bytes, multiple of 8).
        var m = Data([cipherFunc])
        m.append(sessionKey)
        var sum: UInt16 = 0
        for b in sessionKey { sum = sum &+ UInt16(b) }
        m.append(UInt8((sum >> 8) & 0xFF))
        m.append(UInt8(sum & 0xFF))
        let padLen = 8 - (m.count % 8)
        m.append(Data(repeating: UInt8(padLen), count: padLen))
        let wrapped = try AESKeyWrap.wrap(m, kek: Data(kek))
        guard wrapped.count <= 255 else { throw ECDHEncryptError.wrappedTooLong }

        var body = Data([3])
        body.append(recipientFingerprint.suffix(8))
        body.append(18)
        body.append(mpiEncode(Data([0x40]) + ephPub))
        body.append(UInt8(wrapped.count))
        body.append(wrapped)
        return body
    }

    /// MPI encoding: 2-octet bit length + big-endian content.
    private static func mpiEncode(_ content: Data) -> Data {
        let bytes = Array(content)
        var i = 0
        while i < bytes.count, bytes[i] == 0 { i += 1 }
        let bitlen: Int
        if i == bytes.count {
            bitlen = 0
        } else {
            var b = bytes[i]
            var n = 0
            while b != 0 { n += 1; b >>= 1 }
            bitlen = (bytes.count - i - 1) * 8 + n
        }
        return Data([UInt8((bitlen >> 8) & 0xFF), UInt8(bitlen & 0xFF)]) + content
    }
}
