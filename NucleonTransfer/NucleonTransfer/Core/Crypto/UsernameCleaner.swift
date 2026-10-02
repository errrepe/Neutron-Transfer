// Nucleon Transfer — username + bcrypt dot-slash base64 per go-srp/hash.go
import Foundation

enum UsernameCleaner {
    /// Lowercases and strips "-", ".", "_". Used by auth versions 1 and 2.
    static func clean(_ username: String) -> String {
        username.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "_", with: "")
    }
}

/// Bcrypt's adapted base64: "./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789", no padding.
enum DotSlashBase64 {
    static let alphabet = "./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

    static func encode(_ data: Data) -> String {
        let table = Array(alphabet)
        var out = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 6 {
                bits -= 6
                out.append(table[(buffer >> bits) & 0x3F])
            }
        }
        if bits > 0 {
            out.append(table[(buffer << (6 - bits)) & 0x3F])
        }
        return out
    }
}
