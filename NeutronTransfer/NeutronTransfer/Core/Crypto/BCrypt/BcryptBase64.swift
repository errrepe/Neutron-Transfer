// Neutron Transfer — bcrypt variant base64 ("./A-Za-z0-9", no padding).
// Encode/decode logic mirrors vapor-community/bcrypt Base64.swift (MIT)
// with native UInt8 tables.
enum BcryptBase64 {
    static let alphabet = Array("./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".utf8)

    private static let reverse: [UInt8] = {
        var table = [UInt8](repeating: 0xFF, count: 128)
        for (i, c) in alphabet.enumerated() {
            table[Int(c)] = UInt8(i)
        }
        return table
    }()

    static func encode(_ bytes: [UInt8]) -> String {
        var out = ""
        out.reserveCapacity(((bytes.count + 2) / 3) * 4)
        var off = 0
        while off < bytes.count {
            var c1 = bytes[off]
            off += 1
            out.append(Character(UnicodeScalar(alphabet[Int((c1 >> 2) & 0x3F)])))
            c1 = (c1 & 0x03) << 4
            if off >= bytes.count {
                out.append(Character(UnicodeScalar(alphabet[Int(c1 & 0x3F)])))
                break
            }
            var c2 = bytes[off]
            off += 1
            c1 |= (c2 >> 4) & 0x0F
            out.append(Character(UnicodeScalar(alphabet[Int(c1 & 0x3F)])))
            c1 = (c2 & 0x0F) << 2
            if off >= bytes.count {
                out.append(Character(UnicodeScalar(alphabet[Int(c1 & 0x3F)])))
                break
            }
            c2 = bytes[off]
            off += 1
            c1 |= (c2 >> 6) & 0x03
            out.append(Character(UnicodeScalar(alphabet[Int(c1 & 0x3F)])))
            out.append(Character(UnicodeScalar(alphabet[Int(c2 & 0x3F)])))
        }
        return out
    }

    /// Decodes exactly `expected` bytes; returns nil on invalid characters.
    static func decode(_ string: String, expected: Int) -> [UInt8]? {
        let chars = Array(string.utf8)
        var out = [UInt8](repeating: 0, count: expected)
        var off = 0
        var olen = 0
        while off < chars.count - 1, olen < expected {
            let v1 = val(chars[off]); off += 1
            let v2 = val(chars[off]); off += 1
            guard v1 != 0xFF, v2 != 0xFF else { return nil }
            out[olen] = (v1 << 2) | ((v2 & 0x30) >> 4)
            olen += 1
            if olen >= expected || off >= chars.count { break }
            let v3 = val(chars[off]); off += 1
            guard v3 != 0xFF else { return nil }
            out[olen] = ((v2 & 0x0F) << 4) | ((v3 & 0x3C) >> 2)
            olen += 1
            if olen >= expected || off >= chars.count { break }
            let v4 = val(chars[off]); off += 1
            guard v4 != 0xFF else { return nil }
            out[olen] = ((v3 & 0x03) << 6) | v4
            olen += 1
        }
        guard olen == expected else { return nil }
        return out
    }

    private static func val(_ c: UInt8) -> UInt8 {
        guard c < 128 else { return 0xFF }
        return reverse[Int(c)]
    }
}
