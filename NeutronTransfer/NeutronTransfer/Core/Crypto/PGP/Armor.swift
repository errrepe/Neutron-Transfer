// Nucleon Transfer — ASCII armor decode (RFC 4880 §6). CRC24 is not enforced
// (secret keys carry an internal SHA-1 checksum that IS verified on unlock).
import Foundation

enum ArmorError: Error, Sendable {
    case noBeginLine
    case invalidBase64
}

enum Armor {
    static func decode(_ text: String) throws -> Data {
        var b64 = ""
        b64.reserveCapacity(text.count)
        var inBody = false
        var sawBegin = false
        for rawLine in text.components(separatedBy: "\n") {
            var line = rawLine
            if line.hasSuffix("\r") { line = String(line.dropLast()) }
            if line.hasPrefix("-----BEGIN") { inBody = true; sawBegin = true; continue }
            if line.hasPrefix("-----END") { break }
            if !inBody { continue }
            if line.isEmpty { continue }
            if line.contains(":") { continue } // armor headers (Version/Comment/...)
            if line.hasPrefix("=") { continue } // CRC24 line
            b64 += line
        }
        guard sawBegin else { throw ArmorError.noBeginLine }
        guard let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else {
            throw ArmorError.invalidBase64
        }
        return data
    }

    /// ASCII-armors packet bytes (RFC 4880 §6): BEGIN/END lines, 64-column
    /// base64, CRC24 trailer. Inverse of decode.
    static func encode(_ data: Data, header: String = "MESSAGE") -> String {
        let b64 = data.base64EncodedString()
        var lines = ["-----BEGIN PGP \(header)-----", ""]
        var i = b64.startIndex
        while i < b64.endIndex {
            let j = b64.index(i, offsetBy: 64, limitedBy: b64.endIndex) ?? b64.endIndex
            lines.append(String(b64[i..<j]))
            i = j
        }
        lines.append("=" + crc24(data))
        lines.append("-----END PGP \(header)-----")
        return lines.joined(separator: "\n") + "\n"
    }

    /// CRC24 (RFC 4880 §6.1): poly 0x1864CFB, init 0xB704CE.
    private static func crc24(_ data: Data) -> String {
        var crc: UInt32 = 0xB704CE
        for byte in data {
            crc ^= UInt32(byte) << 16
            for _ in 0..<8 {
                crc <<= 1
                if crc & 0x1000000 != 0 { crc ^= 0x1864CFB }
            }
        }
        crc &= 0xFFFFFF
        let bytes = [UInt8((crc >> 16) & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8(crc & 0xFF)]
        return Data(bytes).base64EncodedString()
    }
}
