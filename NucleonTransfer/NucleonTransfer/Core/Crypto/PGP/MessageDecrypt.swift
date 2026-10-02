// Nucleon Transfer — armored message decrypt (F3b-2).
// Layout (pre-refresh format): [PKESK v3 ECDH (tag 1)] + [SED (tag 9) |
// SEIPDv1 (tag 18 v1)]. Tries each candidate recipient seed (mini keyring,
// like go-crypto keyring decryption). Tag 18 v2 (AEAD) is out of scope.
import Foundation

enum MessageDecryptError: Error, Sendable {
    case badMessage
    case noPKESK
    case noSED
    case noRecipientMatched
    case aeadUnsupported
}

struct DecryptCandidate: Sendable {
    var scalarLE: Data // X25519 private scalar, little-endian 32 bytes
    var fingerprint: Data // recipient v4 fingerprint (20 bytes)
    var kdfHash: UInt8
    var kdfCipher: UInt8
    var curveOIDBody: Data
}

enum MessageDecrypt {
    /// Decrypts to literal bytes, trying each candidate seed.
    static func decrypt(armored: String, candidates: [DecryptCandidate]) throws -> Data {
        let raw = try Armor.decode(armored)
        let packets = try PGPPackets.parse(raw)
        guard let pkeskBody = packets.first(where: { $0.tag == 1 })?.body else {
            throw MessageDecryptError.noPKESK
        }
        let pkesk = try PKESK_ECDH.parse(body: pkeskBody)
        guard let sed = packets.first(where: { $0.tag == 9 || $0.tag == 18 }) else {
            throw MessageDecryptError.noSED
        }
        var lastError: Error = MessageDecryptError.noRecipientMatched
        for c in candidates {
            do {
                let (cipherFunc, session) = try ECDHDecrypt.decrypt(
                    pkesk,
                    privateScalarLE: c.scalarLE,
                    curveOIDBody: c.curveOIDBody,
                    fingerprint: c.fingerprint,
                    kdfHash: c.kdfHash,
                    kdfCipher: c.kdfCipher
                )
                let inner = try SEDDecrypt.decrypt(
                    sedBody: sed.body, sessionKey: session,
                    symAlgoID: cipherFunc, expectMDC: sed.tag == 18
                )
                return try SEDDecrypt.literalData(inner)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
