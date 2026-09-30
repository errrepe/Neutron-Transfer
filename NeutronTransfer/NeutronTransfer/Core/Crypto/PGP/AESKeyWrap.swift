// Neutron Transfer — AES Key Wrap/Unwrap (RFC 3394 §2.2, index-based).
// Used by ECDH session-key packets. Unwrap enforces the A6..A6 integrity check.
import Foundation

enum KeyWrapError: Error, Sendable {
    case badLength
    case integrityFailure
}

enum AESKeyWrap {
    private static let iv: [UInt8] = [0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6]

    /// Unwraps `ciphertext` (C0..Cn, 8-byte registers) with KEK, verifying IV.
    static func unwrap(_ ciphertext: Data, kek: Data) throws -> Data {
        let c = Array(ciphertext)
        guard c.count >= 16, c.count % 8 == 0 else { throw KeyWrapError.badLength }
        let n = c.count / 8 - 1
        var a = Array(c[0..<8])
        var r = (1...n).map { Array(c[$0 * 8..<($0 + 1) * 8]) }
        for j in stride(from: 5, through: 0, by: -1) {
            for i in stride(from: n, through: 1, by: -1) {
                let t = UInt64(n * j + i)
                var at = a
                for k in 0..<8 {
                    at[k] ^= UInt8((t >> (56 - k * 8)) & 0xFF)
                }
                let b = try AESBlock.decrypt(block: Data(at + r[i - 1]), key: kek)
                a = Array(b[0..<8])
                r[i - 1] = Array(b[8..<16])
            }
        }
        guard a == iv else { throw KeyWrapError.integrityFailure }
        return Data(r.flatMap { $0 })
    }

    /// Wraps key data (multiple of 8 bytes, >= 16) — for tests/future encrypt paths.
    static func wrap(_ plaintext: Data, kek: Data) throws -> Data {
        let p = Array(plaintext)
        guard p.count >= 16, p.count % 8 == 0 else { throw KeyWrapError.badLength }
        let n = p.count / 8
        var a = iv
        var r = (0..<n).map { Array(p[$0 * 8..<($0 + 1) * 8]) }
        for j in 0...5 {
            for i in 1...n {
                let b = try AESBlock.encrypt(block: Data(a + r[i - 1]), key: kek)
                var at = Array(b[0..<8])
                let t = UInt64(n * j + i)
                for k in 0..<8 {
                    at[k] ^= UInt8((t >> (56 - k * 8)) & 0xFF)
                }
                a = at
                r[i - 1] = Array(b[8..<16])
            }
        }
        return Data(a + r.flatMap { $0 })
    }
}
