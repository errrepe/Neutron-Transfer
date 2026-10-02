// Nucleon Transfer — expandHash per go-srp/hash.go
// expandHash(data) = SHA512(data||0) || SHA512(data||1) || SHA512(data||2) || SHA512(data||3)
import CryptoKit
import Foundation

enum ExpandHash {
    static func expand(_ data: Data) -> Data {
        var out = Data()
        out.reserveCapacity(256)
        for i: UInt8 in [0, 1, 2, 3] {
            var input = data
            input.append(i)
            let digest = SHA512.hash(data: input)
            out.append(contentsOf: digest)
        }
        return out
    }
}
