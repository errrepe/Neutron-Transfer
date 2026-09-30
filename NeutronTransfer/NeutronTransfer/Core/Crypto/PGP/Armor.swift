// Neutron Transfer — ASCII armor decode (RFC 4880 §6). CRC24 is not enforced
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
}
