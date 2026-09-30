// Neutron Transfer — offline crypto vector suite (Swift Testing).
// Every vector is independently verified: RFC text, Python reference
// implementations, or synthetic interop fixtures. NO network, NO secrets.
// Slow ops (cost-10 bcrypt ~0.5s debug) are kept to a minimum.
import CryptoKit
import Foundation
import Testing

@testable import NeutronTransfer

private func HX(_ s: String) -> Data {
    var d = Data()
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        d.append(UInt8(s[i..<j], radix: 16)!)
        i = j
    }
    return d
}

private func HEX(_ d: Data) -> String {
    d.map { String(format: "%02x", $0) }.joined()
}

struct CryptoVectorsTests {
    @Test func expandHashLength() {
        #expect(ExpandHash.expand(Data("abc".utf8)).count == 256)
    }

    @Test func usernameCleaner() {
        #expect(UsernameCleaner.clean("User.Name-_X") == "usernamex")
    }

    @Test func dotSlashBase64() {
        #expect(DotSlashBase64.encode(Data([0xFF, 0x00, 0xAB])) == "9uAp")
    }

    @Test func md5KnownAnswer() {
        #expect(PasswordHash.md5Hex("abc") == "900150983cd24fb0d6963f7d28e17f72")
    }

    @Test func bigUIntMulExact() {
        // Verified against Python integers. toDataLE is little-endian, so the
        // expected big-endian hex is byte-reversed for comparison.
        let a = BigUInt(dataLE: Data(HX("5555555555555555AAAAAAAAAAAAAAAA0FEDCBA987654321123456789ABCDEF0").reversed()))
        let b = BigUInt(dataLE: Data(HX("4444444444444444333333333333333322222222222222221111111111111111").reversed()))
        let p = BigUInt.mul(a, b)
        let exp = Data(HX("16c16c16c16c16c17d27d27d27d27d279dd9031c241b00d59d6480f2b9d6480a97530eca8641fdba9d0369d0369d036afdb97530eca86420fec94f918f48bdf0").reversed())
        #expect(p.toDataLE(length: 64) == exp)
    }

    @Test func bigUIntModPowExact() {
        // pow(a, 3, 2^256 - 1), verified against Python pow().
        let a = BigUInt(dataLE: Data(HX("5555555555555555AAAAAAAAAAAAAAAA0FEDCBA987654321123456789ABCDEF0").reversed()))
        let m = BigUInt(dataLE: Data(HX(String(repeating: "ff", count: 32)).reversed()))
        let r = BigUInt.modPow(a, BigUInt(limbs: [3]), m)
        let exp = Data(HX("3cc587e308a7979de889a8ab357fa91174f4220784832b68ee4535f2c5de093f").reversed())
        #expect(r.toDataLE(length: 32) == exp)
    }

    @Test func bigUIntDivmodConsistent() {
        let a = BigUInt(dataLE: Data(HX("5555555555555555AAAAAAAAAAAAAAAA0FEDCBA987654321123456789ABCDEF0").reversed()))
        let m = BigUInt(dataLE: Data(HX(String(repeating: "ff", count: 32)).reversed()))
        let t = BigUInt.mul(BigUInt.mul(a, a), a)
        let (q, r) = BigUInt.divmod(t, m)
        #expect(BigUInt.add(BigUInt.mul(q, m), r) == t)
    }

    @Test func bcryptVectors() throws {
        let h = ProtonBcryptHasher()
        // Cost-6 canonical (ground truth: Python reference bcrypt).
        let v1 = try h.hash(password: Data("password".utf8), dotSlashSalt: "$2a$06$DCq7YPn5Rq63x1Lad4cll.")
        #expect(String(data: v1, encoding: .utf8) == "$2a$06$DCq7YPn5Rq63x1Lad4cll.kD3zZ845LsvMekyowTQk2VNmbDdQsWO")
        // Cost-10 ASCII + UTF-8 (verified vs Python reference bcrypt).
        // NOTE: hasher mirrors go (versions a/y only), so vectors use $2a$.
        let v2 = try h.hash(password: Data("hello".utf8), dotSlashSalt: "$2a$10$abcdefghijklmnopqrstuu")
        #expect(String(data: v2, encoding: .utf8) == "$2a$10$abcdefghijklmnopqrstuubpco9BuLQZBZtn/gwh0hqaJSVqpe2FC")
        let v3 = try h.hash(password: Data("pässwörd".utf8), dotSlashSalt: "$2y$10$abcdefghijklmnopqrstuu")
        #expect(String(data: v3, encoding: .utf8) == "$2y$10$abcdefghijklmnopqrstuunYspUDVwxKwnshT7FzjzjwI57RV2KKa")
    }

    @Test func s2kIteratedSHA256() throws {
        // Iterated (t=3), SHA-256, 8-byte salt, count 65536 (0x60).
        // Reference: independent Python implementation.
        let spec = Data([3, 8]) + HX("0011223344556677") + Data([0x60])
        let (key, _) = try S2K.derive(spec: spec, passphrase: Data("s2k-test-password".utf8), keyLength: 32)
        #expect(HEX(try PGPHash.digest(id: 8, key)) == "fe374027e9a56b96b530a248d0bd29f168b9e0414c311712c7151ee5b8425411")
    }

    @Test func aesKeyWrapRFC3394() throws {
        // RFC 3394 §4.1 unwrap.
        let kek = HX("000102030405060708090A0B0C0D0E0F")
        let ct = HX("1FA68B0A8112B447AEF34BD8FB5A7B829D3E862371D2CFE5")
        let pt = try AESKeyWrap.unwrap(ct, kek: kek)
        #expect(HEX(pt) == "00112233445566778899aabbccddeeff")
        let rt = try AESKeyWrap.unwrap(try AESKeyWrap.wrap(pt, kek: kek), kek: kek)
        #expect(rt == pt)
        do {
            _ = try AESKeyWrap.unwrap(HX("1FA68B0A8112B447AEF34BD8FB5A7B829D3E862371D2CFE4"), kek: kek)
            Issue.record("tampered wrap accepted")
        } catch { /* expected */ }
    }

    @Test func ecdhInteropSynthetic() throws {
        // Synthetic PKESK built by Python (cryptography lib): X25519 agree +
        // RFC 6637 KDF (SHA-256) + AES-KW. Fresh throwaway keys (see
        // /tmp/nt-ecdh.py recipe); the test self-validates via checksum.
        let pkesk = try PKESK_ECDH.parse(body: HX(
            "03000000000000000012010740f474476e193c23677f57d4e6f221bd855bae0964db6f5334961e3b0d915cfb2030dadc36e52cc6494938656c9913ec334292893c5be6ce19666b20cad4e8869a5f9576ab705ebfc3ebe79cc3c3ef311d7b"
        ))
        let (cf, sess) = try ECDHDecrypt.decrypt(
            pkesk,
            privateScalarLE: HX("e8d23e7e0d35f39ed28d558d11a0ead65af0b663cb69abd7fa31777a2ec5c75b"),
            curveOIDBody: HX("2b06010401da470f00"),
            fingerprint: HX("00112233445566778899aabbccddeeff00112233"),
            kdfHash: 8, kdfCipher: 9
        )
        #expect(cf == 0x09)
        #expect(HEX(sess) == "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff")
    }

    @Test func ed25519DetachedRoundtrip() throws {
        let key = Curve25519.Signing.PrivateKey()
        let pub = key.publicKey.rawRepresentation
        let data = Data("neutron-transfer".utf8)
        let time: UInt32 = 1_700_000_000
        let hashed: [UInt8] = [0x02, 0x04,
            UInt8((time >> 24) & 0xFF), UInt8((time >> 16) & 0xFF),
            UInt8((time >> 8) & 0xFF), UInt8(time & 0xFF)]
        var body = Data([0x04, 0x00, 0x16, 0x0A])
        body.append(UInt8(hashed.count >> 8)); body.append(UInt8(hashed.count & 0xFF))
        body.append(contentsOf: hashed)
        let hashedEnd = body.count
        body.append(contentsOf: [0x00, 0x00])
        var trailer = Data(body.prefix(hashedEnd))
        trailer.append(contentsOf: [0x04, 0xFF])
        let hl = UInt32(hashedEnd)
        trailer.append(contentsOf: [UInt8((hl >> 24) & 0xFF), UInt8((hl >> 16) & 0xFF), UInt8((hl >> 8) & 0xFF), UInt8(hl & 0xFF)])
        var pre = data; pre.append(trailer)
        let digest = Data(SHA512.hash(data: pre))
        let sig = try key.signature(for: digest)
        body.append(contentsOf: digest.prefix(2))
        body.append(contentsOf: [0x02, 0x00])
        body.append(contentsOf: sig)
        let parsed = try DetachedSig.parse(body: body)
        #expect(try parsed.verify(data: data, signerPointMPI: pub))
        #expect(!(try parsed.verify(data: Data("tampered!".utf8), signerPointMPI: pub)))
    }

    @Test func fingerprintV4Synthetic() throws {
        // Synthetic v4 EdDSA public body; reference: independent Python hashlib.
        let publicBody = HX("04" + "01020304" + "16" + "09" + "2b06010401da470f01" + "0107" + "40" + String(repeating: "ab", count: 32))
        #expect(HEX(try PGPFingerprint.v4(publicBody: publicBody)) == "d579b2eadb5b4eb52fd370a757604d5cd1a491c2")
    }
}
