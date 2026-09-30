// Neutron Transfer — SRP-6a client proofs per ProtonMail/go-srp/srp.go
// Generator is always 2. Bit length 2048. Wire ints are fixed-size little-endian.
// Modulus signature (PGP clearsign) verification is TODO (F2b, GopenPGP bridge);
// callers must pass already-decoded modulus bytes for now.
import Foundation
import Security

struct SRPProofs: Sendable {
    var clientEphemeral: Data // 256 bytes LE
    var clientProof: Data      // 256 bytes (expandHash output)
    var expectedServerProof: Data
}

enum SRPClient {
    static let bitLength = 2048
    static let byteLength = 256

    static func checkParams(serverEphemeral: BigUInt, modulus: BigUInt) throws {
        let one = BigUInt.one
        let modMinusOne = BigUInt.sub(modulus, one)
        // modulus size
        guard modulus.bitLength == bitLength else {
            throw ProtonAPIError.srpParamsOutOfBounds("modulus size \(modulus.bitLength) != 2048")
        }
        // modulus must be 3 mod 8: bits 0,1 set, bit 2 clear
        let m0 = modulus.limbs[0]
        guard (m0 & 1) == 1, (m0 & 2) == 2, (m0 & 4) == 0 else {
            throw ProtonAPIError.srpParamsOutOfBounds("modulus is not 3 mod 8")
        }
        // 1 < serverEphemeral < N-1
        guard serverEphemeral.compare(one) > 0, serverEphemeral.compare(modMinusOne) < 0 else {
            throw ProtonAPIError.srpParamsOutOfBounds("server ephemeral out of bounds")
        }
    }

    static func multiplier(modulus: BigUInt) throws -> BigUInt {
        // k = expandHash(g || N) mod N, with g=2 and N as fixed LE; must satisfy 1 < k < N-1
        let g = BigUInt.two.toDataLE(length: byteLength)
        let n = modulus.toDataLE(length: byteLength)
        let h = ExpandHash.expand(g + n)
        let k = BigUInt(dataLE: h.prefix(byteLength))
        let kMod = BigUInt.mod(k, modulus)
        let modMinusOne = BigUInt.sub(modulus, .one)
        guard kMod.compare(.one) > 0, kMod.compare(modMinusOne) < 0 else {
            throw ProtonAPIError.srpParamsOutOfBounds("multiplier out of bounds")
        }
        return kMod
    }

    /// Full client-side proof generation. `clientSecret` injected for testability;
    /// pass nil to generate securely via SecRandomCopyBytes.
    static func generateProofs(
        hashedPassword: Data,
        serverEphemeral: Data,
        modulus: Data,
        clientSecret: Data? = nil
    ) throws -> SRPProofs {
        precondition(hashedPassword.count == byteLength)
        let n = BigUInt(dataLE: modulus)
        let sEphem = BigUInt(dataLE: serverEphemeral)
        try checkParams(serverEphemeral: sEphem, modulus: n)
        let modulusNat = n
        let modMinusOne = BigUInt.sub(n, .one)

        // client secret: random in [2*bitLength, N-1)
        let secret: BigUInt
        if let clientSecret {
            secret = BigUInt(dataLE: clientSecret)
        } else {
            var bytes = Data(repeating: 0, count: byteLength)
            let status = bytes.withUnsafeMutableBytes {
                SecRandomCopyBytes(kSecRandomDefault, byteLength, $0.baseAddress!)
            }
            guard status == errSecSuccess else {
                throw ProtonAPIError.srpParamsOutOfBounds("SecRandomCopyBytes failed")
            }
            var candidate = BigUInt(dataLE: bytes)
            // clamp into range by retrying at most a few times (mirrors go-srp loop)
            var tries = 0
            let lower = BigUInt(limbs: [UInt64(bitLength * 2)])
            while !(candidate.compare(lower) > 0 && candidate.compare(modMinusOne) < 0) && tries < 8 {
                var b2 = Data(repeating: 0, count: byteLength)
                _ = b2.withUnsafeMutableBytes {
                    SecRandomCopyBytes(kSecRandomDefault, byteLength, $0.baseAddress!)
                }
                candidate = BigUInt(dataLE: b2)
                tries += 1
            }
            secret = candidate
        }

        let clientEphemeral = BigUInt.modPow(.two, secret, modulusNat)
        let clientEphemData = clientEphemeral.toDataLE(length: byteLength)

        // u = expandHash(A || B) as LE int (scrambling param, must be != 0)
        let uData = ExpandHash.expand(clientEphemData + serverEphemeral)
        let u = BigUInt(dataLE: uData.prefix(byteLength))
        guard !u.isZero else {
            throw ProtonAPIError.srpParamsOutOfBounds("scrambling param is zero, retry")
        }

        let k = try multiplier(modulus: n)
        let x = BigUInt(dataLE: hashedPassword)
        let g: BigUInt = .two

        // base = (B - k * g^x) mod N
        let gx = BigUInt.modPow(g, x, modulusNat)
        let kgx = BigUInt.modMul(k, gx, modulusNat)
        // B >= kgx in valid flows; go-srp ModSub handles wrap, we mirror with +N
        let sEphemNat = sEphem
        let base: BigUInt
        if sEphemNat.compare(kgx) >= 0 {
            base = BigUInt.mod(BigUInt.sub(sEphemNat, kgx), modulusNat)
        } else {
            base = BigUInt.mod(BigUInt.add(BigUInt.sub(modulusNat, kgx), sEphemNat), modulusNat)
        }
        // exp = (u*x + a) mod (N-1)
        let ux = BigUInt.modMul(u, x, modMinusOne)
        let exp = BigUInt.mod(BigUInt.add(ux, secret), modMinusOne)
        let shared = BigUInt.modPow(base, exp, modulusNat)
        let sharedData = shared.toDataLE(length: byteLength)

        let clientProof = ExpandHash.expand(clientEphemData + serverEphemeral + sharedData)
        let serverProof = ExpandHash.expand(clientEphemData + clientProof + sharedData)
        return SRPProofs(clientEphemeral: clientEphemData, clientProof: clientProof, expectedServerProof: serverProof)
    }
}
