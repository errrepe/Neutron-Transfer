// Nucleon Transfer — SED/SEIPDv1 encrypt (RFC 4880 §13.9, F4.1).
// Exact inverse of SEDDecrypt + AESBlock.openPGPcfbDecrypt: random prefix +
// check bytes, resync=true CFB for tag 9, resync=false CFB + MDC (SHA-1 over
// full prefix + data + D3 14) for tag 18 v1.
import Foundation

enum SEDEncryptError: Error, Sendable {
    case badKeyLength
    case plaintextTooShort
}

enum SEDEncrypt {
    /// Encrypts inner packet bytes with the session key.
    /// - `useMDC` true: returns version octet 0x01 + NoResync CFB over
    ///   (prefix + inner + D3 14 + MDC). False: resync CFB over
    ///   (prefix + inner). Returns the SED body (caller frames tag 9/18).
    static func encrypt(inner: Data, sessionKey: Data, symAlgoID: UInt8, useMDC: Bool) throws -> Data {
        let keyLen = try PGPSymmetricAlgo.keyLength(id: symAlgoID)
        guard sessionKey.count == keyLen else { throw SEDEncryptError.badKeyLength }
        let prefix = (0..<16).map { _ in UInt8.random(in: .min ... .max) }
        var plain = Data(prefix)
        plain.append(prefix[14])
        plain.append(prefix[15])
        if useMDC {
            plain.append(inner)
            plain.append(contentsOf: [0xD3, 0x14])
            // MDC input (go-crypto parity) is the FULL plaintext prefix
            // (18 bytes, incl. check) + data + D3 14.
            plain.append(try PGPHash.digest(id: 2, plain))
            return Data([0x01]) + (try openPGPcfbEncrypt(plaintext: plain, key: sessionKey, resync: false))
        }
        plain.append(inner)
        return try openPGPcfbEncrypt(plaintext: plain, key: sessionKey, resync: true)
    }

    /// OpenPGP CFB encrypt with prefix, mirroring
    /// AESBlock.openPGPcfbDecrypt (same zero IV, same resync branches).
    /// `plaintext` must include the blockSize+2 prefix (caller-built).
    static func openPGPcfbEncrypt(plaintext: Data, key: Data, blockSize: Int = 16, resync: Bool) throws -> Data {
        guard plaintext.count >= blockSize + 2 else { throw SEDEncryptError.plaintextTooShort }
        let p = Array(plaintext)
        var out: [UInt8] = []
        out.reserveCapacity(p.count)

        var fr = [UInt8](repeating: 0, count: blockSize)
        guard fr.count == blockSize else { throw SEDEncryptError.plaintextTooShort }
        var fre = try Array(AESBlock.encrypt(block: Data(fr), key: key))
        for i in 0..<blockSize {
            out.append(p[i] ^ fre[i])
        }
        fr = Array(out[0..<blockSize])
        fre = try Array(AESBlock.encrypt(block: Data(fr), key: key))
        out.append(p[blockSize] ^ fre[0])
        out.append(p[blockSize + 1] ^ fre[1])
        if resync {
            fr = Array(out[2..<(blockSize + 2)])
            var pos = blockSize + 2
            while pos < p.count {
                fre = try Array(AESBlock.encrypt(block: Data(fr), key: key))
                let end = min(pos + blockSize, p.count)
                for i in pos..<end {
                    out.append(p[i] ^ fre[i - pos])
                }
                if end - pos == blockSize {
                    fr = Array(out[pos..<end])
                }
                pos = end
            }
        } else {
            // No resync (SEIPDv1): splice check ciphertext into FR, continue.
            fre[0] = out[blockSize]
            fre[1] = out[blockSize + 1]
            var used = 2
            var pos = blockSize + 2
            while pos < p.count {
                if used == fre.count {
                    fre = try Array(AESBlock.encrypt(block: Data(fre), key: key))
                    used = 0
                }
                let c = p[pos] ^ fre[used]
                fre[used] = c
                used += 1
                out.append(c)
                pos += 1
            }
        }
        return Data(out)
    }
}
