// Nucleon Transfer — SED/SEIPDv1 decrypt + literal extraction (F3b-2).
// Tag 9 (SED, no integrity) and tag 18 v1 (MDC SHA-1) share the CFB framing;
// only tag 18 carries the trailing MDC packet (0xD3 0x14 + 20-byte digest).
import Foundation

enum SEDError: Error, Sendable, Equatable {
    case badPacket
    case mdcMissing
    case mdcMismatch
    case unsupportedCompression(UInt8)
    case noLiteralData
}

enum SEDDecrypt {
    /// Decrypts one SED body with the session key.
    /// - `expectMDC` true for tag 18 (SEIPDv1): body starts with version
    ///   octet 0x01 (RFC 9580; GnuPG 2.5 requires it — the live Token packet
    ///   starts with 0x01), then CFB, then trailing MDC. False for tag 9
    ///   (plain SED: CFB directly, no MDC).
    /// - MDC input (go-crypto parity) is the FULL plaintext prefix (18 bytes,
    ///   incl. check) + data + D3 14 — NOT data-after-prefix alone.
    /// Returns the inner packet bytes (literal/compressed).
    static func decrypt(sedBody: Data, sessionKey: Data, symAlgoID: UInt8, expectMDC: Bool) throws -> Data {
        let keyLen = try PGPSymmetricAlgo.keyLength(id: symAlgoID)
        guard sessionKey.count == keyLen else { throw SEDError.badPacket }
        var body = sedBody
        if expectMDC {
            guard let first = body.first, first == 1 else { throw SEDError.badPacket }
            body = body.dropFirst()
        }
        let plain = try AESBlock.openPGPcfbDecrypt(ciphertext: body, key: sessionKey, resync: !expectMDC)
        guard plain.count >= 18 else { throw SEDError.badPacket }
        if expectMDC {
            // MDC packet: D3 14 + SHA1 hash. The hash covers everything before
            // it — full plaintext prefix + data + the D3 14 header itself
            // (go-crypto hashes the stream including the header, then compares
            // the trailing 20 bytes). Do NOT append D3 14: it is already the
            // last 2 bytes of the hashed region.
            guard plain.count >= 18 + 22,
                  plain[plain.index(plain.endIndex, offsetBy: -22)] == 0xD3,
                  plain[plain.index(plain.endIndex, offsetBy: -21)] == 0x14 else {
                throw SEDError.mdcMissing
            }
            let hashed = plain.prefix(plain.count - 20)
            let digest = try PGPHash.digest(id: 2, Data(hashed))
            guard digest == plain.suffix(20) else { throw SEDError.mdcMismatch }
            return Data(plain[plain.startIndex + 18 ..< plain.index(plain.endIndex, offsetBy: -22)])
        }
        return Data(plain.dropFirst(18))
    }

    /// Extracts literal data (tag 11) from inner packets.
    /// Compressed packets (tag 8) are rejected: Proton passphrase/name
    /// messages are uncompressed literals, and raw-DEFLATE needs a vendored
    /// inflater (e.g. miniz) — Apple’s Compression framework only handles
    /// zlib-wrapped streams. Verified: GnuPG-made ZIP messages fail loudly
    /// here instead of corrupting silently.
    static func literalData(_ inner: Data) throws -> Data {
        let packets = try PGPPackets.parse(inner)
        for p in packets {
            switch p.tag {
            case 11:
                return try parseLiteral(p.body)
            case 8:
                guard !p.body.isEmpty else { throw SEDError.badPacket }
                throw SEDError.unsupportedCompression(p.body[p.body.startIndex])
            default:
                continue
            }
        }
        throw SEDError.noLiteralData
    }

    /// Literal packet: format(1) + filenameLen(1) + filename + date(4) + data.
    static func parseLiteral(_ body: Data) throws -> Data {
        var o = body.startIndex
        guard let fEnd = body.index(o, offsetBy: 2, limitedBy: body.endIndex) else {
            throw SEDError.badPacket
        }
        let fnLen = Int(body[body.index(o, offsetBy: 1)])
        o = fEnd
        guard let dStart = body.index(o, offsetBy: fnLen + 4, limitedBy: body.endIndex) else {
            throw SEDError.badPacket
        }
        return Data(body[dStart...])
    }
}
