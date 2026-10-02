// Nucleon Transfer — AES single-block + OpenPGP CFB (RFC 4880 §13.9).
// CryptoKit has no ECB/CFB; CommonCrypto CCCrypt provides the raw block op.
import CommonCrypto
import Foundation

enum AESError: Error, Sendable {
    case badKeyLength
    case badBlockLength
    case cryptorFailed(CCCryptorStatus)
    case checkBytesMismatch
}

enum AESBlock {
    /// Key lengths: AES-128/192/256. Returns the 16-byte ciphertext block.
    static func encrypt(block: Data, key: Data) throws -> Data {
        guard block.count == kCCBlockSizeAES128 else { throw AESError.badBlockLength }
        let keyLen: Int
        switch key.count {
        case kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256:
            keyLen = key.count
        default:
            throw AESError.badKeyLength
        }
        var out = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        var outLen = 0
        let status = key.withUnsafeBytes { kptr in
            block.withUnsafeBytes { bptr in
                CCCrypt(
                    CCOperation(kCCEncrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionECBMode),
                    kptr.baseAddress, keyLen,
                    nil,
                    bptr.baseAddress, kCCBlockSizeAES128,
                    &out, out.count,
                    &outLen
                )
            }
        }
        guard status == kCCSuccess, outLen == kCCBlockSizeAES128 else {
            throw AESError.cryptorFailed(status)
        }
        return Data(out)
    }

    /// Raw AES-ECB single-block decrypt (for key unwrap).
    static func decrypt(block: Data, key: Data) throws -> Data {
        guard block.count == kCCBlockSizeAES128 else { throw AESError.badBlockLength }
        switch key.count {
        case kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256:
            break
        default:
            throw AESError.badKeyLength
        }
        var out = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        var outLen = 0
        let status = key.withUnsafeBytes { kptr in
            block.withUnsafeBytes { bptr in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionECBMode),
                    kptr.baseAddress, key.count,
                    nil,
                    bptr.baseAddress, kCCBlockSizeAES128,
                    &out, out.count,
                    &outLen
                )
            }
        }
        guard status == kCCSuccess, outLen == kCCBlockSizeAES128 else {
            throw AESError.cryptorFailed(status)
        }
        return Data(out)
    }

    /// OpenPGP CFB decrypt with prefix (RFC 4880 §13.9 + go-crypto ocfb.go):
    /// FR starts at `iv` (zeros when nil, as in SED packets); the first
    /// blockSize octets are random prefix, the next 2 are check octets
    /// (copies of the LAST two prefix octets).
    /// `resync` selects the post-prefix behavior (go-crypto OCFBResyncOption):
    /// true (SED tag 9) re-encrypts c[2..<BS+2] as the new FR; false
    /// (SEIPDv1 tag 18, MDC) continues the stream with the check ciphertext
    /// spliced into FR (no re-encryption).
    /// Returns full plaintext INCLUDING the prefix (caller strips blockSize+2).
    static func openPGPcfbDecrypt(ciphertext: Data, key: Data, blockSize: Int = 16, iv: Data? = nil, resync: Bool = true) throws -> Data {
        guard ciphertext.count >= blockSize + 2 else { throw AESError.badBlockLength }
        let c = Array(ciphertext)
        var out: [UInt8] = []
        out.reserveCapacity(c.count)

        var fr = iv.map(Array.init) ?? [UInt8](repeating: 0, count: blockSize)
        guard fr.count == blockSize else { throw AESError.badBlockLength }
        var fre = try Array(encrypt(block: Data(fr), key: key))
        for i in 0..<blockSize {
            out.append(c[i] ^ fre[i])
        }
        fr = Array(c[0..<blockSize])
        fre = try Array(encrypt(block: Data(fr), key: key))
        out.append(c[blockSize] ^ fre[0])
        out.append(c[blockSize + 1] ^ fre[1])
        guard out[blockSize] == out[blockSize - 2], out[blockSize + 1] == out[blockSize - 1] else {
            throw AESError.checkBytesMismatch
        }
        if resync {
            fr = Array(c[2..<(blockSize + 2)])
            var pos = blockSize + 2
            while pos < c.count {
                fre = try Array(encrypt(block: Data(fr), key: key))
                let end = min(pos + blockSize, c.count)
                for i in pos..<end {
                    out.append(c[i] ^ fre[i - pos])
                }
                if end - pos == blockSize {
                    fr = Array(c[pos..<end])
                }
                pos = end
            }
        } else {
            // No resync (SEIPDv1): splice check ciphertext into FR, continue.
            fre[0] = c[blockSize]
            fre[1] = c[blockSize + 1]
            var used = 2
            var pos = blockSize + 2
            while pos < c.count {
                if used == fre.count {
                    fre = try Array(encrypt(block: Data(fre), key: key))
                    used = 0
                }
                out.append(c[pos] ^ fre[used])
                fre[used] = c[pos]
                used += 1
                pos += 1
            }
        }
        return Data(out)
    }

    /// Plain CFB decrypt (NO prefix/resync): FR starts at `iv`, standard CFB.
    /// Proton secret keys encrypt MPI+checksum this way (empirically: secretData
    /// is exactly MPI + SHA-1 with no random prefix on current key packets).
    static func cfbDecrypt(ciphertext: Data, key: Data, iv: Data, blockSize: Int = 16) throws -> Data {
        guard iv.count == blockSize else { throw AESError.badBlockLength }
        let c = Array(ciphertext)
        var fr = Array(iv)
        var out: [UInt8] = []
        out.reserveCapacity(c.count)
        var pos = 0
        while pos < c.count {
            let fre = try Array(encrypt(block: Data(fr), key: key))
            let end = min(pos + blockSize, c.count)
            for i in pos..<end {
                out.append(c[i] ^ fre[i - pos])
            }
            if end - pos == blockSize {
                fr = Array(c[pos..<end])
            } else {
                break // trailing partial block has no next FR; done
            }
            pos = end
        }
        return Data(out)
    }

    /// Plain CFB encrypt (NO prefix/resync): FR starts at `iv`, standard CFB.
    /// Exact inverse of cfbDecrypt (used to lock generated secret keys).
    static func cfbEncrypt(plaintext: Data, key: Data, iv: Data, blockSize: Int = 16) throws -> Data {
        guard iv.count == blockSize else { throw AESError.badBlockLength }
        let p = Array(plaintext)
        var fr = Array(iv)
        var out: [UInt8] = []
        out.reserveCapacity(p.count)
        var pos = 0
        while pos < p.count {
            let fre = try Array(encrypt(block: Data(fr), key: key))
            let end = min(pos + blockSize, p.count)
            for i in pos..<end {
                out.append(p[i] ^ fre[i - pos])
            }
            if end - pos == blockSize {
                fr = Array(out[pos..<end])
            } else {
                break // trailing partial block has no next FR; done
            }
            pos = end
        }
        return Data(out)
    }
}

enum PGPSymmetricAlgo {
    static func keyLength(id: UInt8) throws -> Int {
        switch id {
        case 7: return 16 // AES-128
        case 8: return 24 // AES-192
        case 9: return 32 // AES-256
        default: throw AESError.badKeyLength
        }
    }
}
