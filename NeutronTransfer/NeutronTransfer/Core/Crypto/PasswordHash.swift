// Neutron Transfer — password hashing dispatch per go-srp/hash.go
// Bcrypt core is vendored (Core/Crypto/BCrypt, MIT vapor-community/bcrypt).
import CryptoKit
import Foundation

protocol BcryptHasher: Sendable {
    /// bcrypt with cost 10 and given dot-slash encoded salt string, matching
    /// go-srp bcryptHash(password, "$2y$10$"+encodedSalt). Returns raw hash bytes.
    func hash(password: Data, dotSlashSalt: String) throws -> Data
}

struct UnimplementedBcryptHasher: BcryptHasher {
    func hash(password: Data, dotSlashSalt: String) throws -> Data {
        throw ProtonAPIError.bcryptNotAvailable
    }
}

enum PasswordHash {
    static func hash(
        version: Int,
        password: Data,
        username: String,
        salt: Data,
        modulus: Data,
        bcrypt: any BcryptHasher
    ) throws -> Data {
        switch version {
        case 3, 4:
            // encodedSalt = dotSlashBase64(salt + "proton")
            var salted = salt
            salted.append(contentsOf: "proton".utf8)
            let encoded = DotSlashBase64.encode(salted)
            let crypted = try bcrypt.hash(password: password, dotSlashSalt: "$2y$10$\(encoded)")
            return ExpandHash.expand(crypted + modulus)
        case 1, 2:
            let cleaned = version == 2 ? UsernameCleaner.clean(username) : username
            // Legacy: md5(lower(username)) hex as salt. Go passes the 32-char hex
            // where bcrypt consumes the first 22 chars; mirror that here.
            let prehash = String(md5Hex(cleaned).prefix(22))
            let crypted = try bcrypt.hash(password: password, dotSlashSalt: "$2y$10$\(prehash)")
            return ExpandHash.expand(crypted + modulus)
        case 0:
            // Legacy: base64(sha512(lower(username) + password)) then v1 path.
            var userAndPass = Array(username.lowercased().utf8) + Array(password)
            defer { userAndPass = Array(repeating: 0, count: userAndPass.count) }
            let prehashed = SHA512.hash(data: userAndPass)
            let b64 = Data(prehashed).base64EncodedString()
            return try hash(version: 1, password: Data(b64.utf8), username: username,
                            salt: Data(), modulus: modulus, bcrypt: bcrypt)
        default:
            throw ProtonAPIError.srpParamsOutOfBounds("unsupported auth version \(version)")
        }
    }

    /// MD5 hex helper without external deps (needed only for legacy v1/v2).
    static func md5Hex(_ string: String) -> String {
        var message = Array(string.utf8)
        let ml = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for i in 0..<8 { message.append(UInt8((ml >> (i * 8)) & 0xFF)) }
        // initial state
        var a: UInt32 = 0x67452301, b: UInt32 = 0xEFCDAB89
        var c: UInt32 = 0x98BADCFE, d: UInt32 = 0x10325476
        let s: [UInt32] = [
            7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
            5,9,14,20, 5,9,14,20, 5,9,14,20, 5,9,14,20,
            4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
            6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21
        ]
        // MD5 K constants: floor(2^32 * abs(sin(i+1))) for i in 0..<64
        let k: [UInt32] = [
            0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
            0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
            0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
            0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
            0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
            0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
            0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
            0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
            0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
            0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
            0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
            0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
            0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
            0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
            0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
            0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
        ]
        func rol(_ x: UInt32, _ n: UInt32) -> UInt32 { (x << n) | (x >> (32 - n)) }
        for chunk in stride(from: 0, to: message.count, by: 64) {
            var m = [UInt32](repeating: 0, count: 16)
            for j in 0..<16 {
                let o = chunk + j * 4
                m[j] = UInt32(message[o]) | (UInt32(message[o+1]) << 8) | (UInt32(message[o+2]) << 16) | (UInt32(message[o+3]) << 24)
            }
            var A = a, B = b, C = c, D = d
            for i in 0..<64 {
                var F: UInt32 = 0; var g = 0
                switch i {
                case 0..<16: F = (B & C) | ((~B) & D); g = i
                case 16..<32: F = (D & B) | ((~D) & C); g = (5*i+1) % 16
                case 32..<48: F = B ^ C ^ D; g = (3*i+5) % 16
                default: F = C ^ (B | (~D)); g = (7*i) % 16
                }
                F = F &+ A &+ k[i] &+ m[g]
                A = D; D = C; C = B
                B = B &+ rol(F, s[i])
            }
            a = a &+ A; b = b &+ B; c = c &+ C; d = d &+ D
        }
        var out = Data()
        for v in [a, b, c, d] {
            out.append(UInt8(v & 0xFF)); out.append(UInt8((v >> 8) & 0xFF))
            out.append(UInt8((v >> 16) & 0xFF)); out.append(UInt8((v >> 24) & 0xFF))
        }
        return out.map { String(format: "%02x", $0) }.joined()
    }
}
