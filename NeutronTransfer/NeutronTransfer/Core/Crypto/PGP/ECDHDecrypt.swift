// Neutron Transfer — ECDH session-key decrypt (RFC 6637 §8, go-crypto ecdh.go).
// Covers v4 keys with legacy ECDH (algo 18, e.g. Cv25519): PKESK v3 holds an
// ephemeral-point MPI + length-prefixed wrapped session. KDF = Hash over
// (0x00000001 || ZB || Param) with legacy leading/trailing-zero workarounds.
import CryptoKit
import Foundation

enum ECDHDecryptError: Error, Sendable {
    case badPacket
    case unsupportedKDF
    case unwrapFailed
    case badSessionKey
}

/// v3 PKESK for ECDH (algo 18): version(1)=3, keyID(8), algo(1), MPI ephemeral
/// (0x40 + 32 LE bytes), lenOctet(1) + wrapped session bytes.
struct PKESK_ECDH: Sendable {
    var keyID: UInt64
    var ephemeral: Data // 32 LE bytes (0x40 stripped)
    var wrapped: Data

    static func parse(body: Data) throws -> PKESK_ECDH {
        var o = body.startIndex
        func u8() throws -> UInt8 {
            guard o < body.endIndex else { throw ECDHDecryptError.badPacket }
            defer { o = body.index(after: o) }
            return body[o]
        }
        func take(_ n: Int) throws -> Data {
            guard let e = body.index(o, offsetBy: n, limitedBy: body.endIndex), e <= body.endIndex else {
                throw ECDHDecryptError.badPacket
            }
            defer { o = e }
            return body[o..<e]
        }
        guard try u8() == 3 else { throw ECDHDecryptError.badPacket }
        let kid = try take(8)
        guard try u8() == 18 else { throw ECDHDecryptError.badPacket }
        let (eph, next) = try MPI.read(body, from: o - body.startIndex)
        o = body.startIndex + next
        var ephBytes = Data(eph)
        if ephBytes.count == 33, ephBytes.first == 0x40 { ephBytes = ephBytes.dropFirst() }
        guard ephBytes.count == 32 else { throw ECDHDecryptError.badPacket }
        let wlen = Int(try u8())
        let wrapped = try take(wlen)
        var keyID: UInt64 = 0
        for b in kid { keyID = (keyID << 8) | UInt64(b) }
        return PKESK_ECDH(keyID: keyID, ephemeral: ephBytes, wrapped: wrapped)
    }
}

enum ECDHDecrypt {
    /// - Parameters:
    ///   - privateScalarLE: recipient X25519 scalar, little-endian 32 bytes.
    ///   - curveOIDBody: curve OID content bytes (no DER header), e.g. Cv25519.
    ///   - fingerprint: recipient v4 fingerprint (20 bytes).
    ///   - kdfHash/kdfCipher: from the recipient key's KDF params (e.g. 8/9).
    /// - Returns: (cipherFunc, sessionKey).
    static func decrypt(
        _ pkesk: PKESK_ECDH,
        privateScalarLE: Data,
        curveOIDBody: Data,
        fingerprint: Data,
        kdfHash: UInt8,
        kdfCipher: UInt8
    ) throws -> (cipherFunc: UInt8, sessionKey: Data) {
        guard privateScalarLE.count == 32, pkesk.ephemeral.count == 32,
              fingerprint.count == 20 else { throw ECDHDecryptError.badPacket }
        let priv: Curve25519.KeyAgreement.PrivateKey
        let eph: Curve25519.KeyAgreement.PublicKey
        do {
            priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateScalarLE)
            eph = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: pkesk.ephemeral)
        } catch {
            throw ECDHDecryptError.badPacket
        }
        let zb = try priv.sharedSecretFromKeyAgreement(with: eph).withUnsafeBytes { Data($0) }

        // param = curveOID DER TLV || 18 || 03 || 01 || hashID || cipherID
        //         || "Anonymous Sender    " || fingerprint  (RFC 6637 §8)
        var param = Data([0x06, UInt8(curveOIDBody.count)])
        param.append(curveOIDBody)
        param.append(contentsOf: [18, 3, 1, kdfHash, kdfCipher])
        param.append(contentsOf: "Anonymous Sender    ".utf8)
        param.append(fingerprint)

        let kekLen = try PGPSymmetricAlgo.keyLength(id: kdfCipher)
        // Legacy workarounds from go-crypto buildKey: normal, strip leading
        // zeros, strip trailing zeros of ZB.
        let variants: [Data] = [
            zb,
            Data(zb.drop(while: { $0 == 0 })),
            Data(zb.reversed().drop(while: { $0 == 0 }).reversed()),
        ]
        var lastError: Error = ECDHDecryptError.unwrapFailed
        for variant in variants {
            do {
                var input = Data([0, 0, 0, 1])
                input.append(variant)
                input.append(param)
                let mb = try PGPHash.digest(id: kdfHash, input)
                let z = mb.prefix(kekLen)
                let m = try AESKeyWrap.unwrap(pkesk.wrapped, kek: Data(z))
                return try parseSession(m)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// m (after PKCS#5 pad strip) = symm_alg_ID || session key || 2-byte checksum.
    private static func parseSession(_ m: Data) throws -> (UInt8, Data) {
        guard !m.isEmpty else { throw ECDHDecryptError.badSessionKey }
        let padLen = Int(m[m.index(before: m.endIndex)])
        guard padLen <= m.count else { throw ECDHDecryptError.badSessionKey }
        let inner = m.prefix(m.count - padLen)
        guard inner.count >= 3 else { throw ECDHDecryptError.badSessionKey }
        let cipherFunc = inner[inner.startIndex]
        let keyAndSum = inner.dropFirst()
        guard keyAndSum.count >= 2 else { throw ECDHDecryptError.badSessionKey }
        let key = keyAndSum.prefix(keyAndSum.count - 2)
        let expect = (UInt16(keyAndSum[keyAndSum.index(keyAndSum.endIndex, offsetBy: -2)]) << 8)
            | UInt16(keyAndSum[keyAndSum.index(keyAndSum.endIndex, offsetBy: -1)])
        var sum: UInt16 = 0
        for b in key { sum = sum &+ UInt16(b) }
        guard sum == expect else { throw ECDHDecryptError.badSessionKey }
        return (cipherFunc, Data(key))
    }
}

/// v4 fingerprint: SHA-1(0x99 || len16BE || public packet body).
enum PGPFingerprint {
    static func v4(publicBody: Data) throws -> Data {
        var input = Data([0x99])
        let len = publicBody.count
        input.append(UInt8((len >> 8) & 0xFF))
        input.append(UInt8(len & 0xFF))
        input.append(publicBody)
        return try PGPHash.digest(id: 2, input)
    }
}
