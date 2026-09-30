// Neutron Transfer — SED/SEIPDv1 decrypt + literal extraction (F3b-2).
// Tag 9 (SED, no integrity) and tag 18 v1 (MDC SHA-1) share the CFB framing;
// only tag 18 carries the trailing MDC packet (0xD3 0x14 + 20-byte digest).
import Foundation

enum SEDError: Error, Sendable {
    case badPacket
    case mdcMissing
    case mdcMismatch
    case unsupportedCompression(UInt8)
    case noLiteralData
}

enum SEDDecrypt {
    /// Decrypts one SED body with the session key. `expectMDC` is true for
    /// tag-18 packets. Returns the inner packet bytes (literal/compressed).
    static func decrypt(sedBody: Data, sessionKey: Data, symAlgoID: UInt8, expectMDC: Bool) throws -> Data {
        let keyLen = try PGPSymmetricAlgo.keyLength(id: symAlgoID)
        guard sessionKey.count == keyLen else { throw SEDError.badPacket }
        let plain = try AESBlock.openPGPcfbDecrypt(ciphertext: sedBody, key: sessionKey)
        guard plain.count >= 18 else { throw SEDError.badPacket }
        var inner = plain.dropFirst(18)
        if expectMDC {
            // MDC packet: 0xD3 0x14 + SHA1(prefix + D3 14).
            guard inner.count >= 22,
                  inner[inner.index(inner.endIndex, offsetBy: -22)] == 0xD3,
                  inner[inner.index(inner.endIndex, offsetBy: -21)] == 0x14 else {
                throw SEDError.mdcMissing
            }
            let prefix = inner.prefix(inner.count - 20)
            var hashed = Data(prefix)
            hashed.append(contentsOf: [0xD3, 0x14])
            let digest = try PGPHash.digest(id: 2, hashed)
            guard digest == inner.suffix(20) else { throw SEDError.mdcMismatch }
            inner = prefix.prefix(prefix.count - 2)
        }
        return Data(inner)
    }

    /// Extracts literal data (tag 11) from inner packets. Compressed packets
    /// (tag 8) are reported for a follow-up (need live samples to pick codec).
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
