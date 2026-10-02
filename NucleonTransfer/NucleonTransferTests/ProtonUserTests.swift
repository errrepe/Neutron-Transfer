// Nucleon Transfer — ProtonUser account-field decoding (S0.3, Swift Testing).
// /core/v4/users may omit Name/DisplayName/Email/UsedSpace/MaxSpace
// (go-proton-api user_types.go `type User`): all are optional on our side,
// so payloads with and without them must decode. Offline only.
import Foundation
import Testing

@testable import NucleonTransfer

struct ProtonUserDecodeTests {
    @Test func decodesAccountFieldsWhenPresent() throws {
        let json = """
        {
          "User": {
            "Name": "alice",
            "DisplayName": "Alice A.",
            "Email": "alice@proton.me",
            "UsedSpace": 148480000000,
            "MaxSpace": 520000000000,
            "Keys": [
              { "ID": "k1", "PrivateKey": "-----BEGIN PGP PRIVATE KEY BLOCK-----", "Primary": 1, "Active": 1 }
            ]
          }
        }
        """.data(using: .utf8) ?? Data()
        let res = try JSONDecoder().decode(ProtonUserResponse.self, from: json)
        #expect(res.user.name == "alice")
        #expect(res.user.displayName == "Alice A.")
        #expect(res.user.email == "alice@proton.me")
        #expect(res.user.usedSpace == 148_480_000_000)
        #expect(res.user.maxSpace == 520_000_000_000)
        #expect(res.user.primaryKey?.id == "k1")
    }

    @Test func decodesWithoutAccountFields() throws {
        // Keys-only payload (minimal response): optionals must decode as nil.
        let json = """
        {
          "User": {
            "Keys": [
              { "ID": "k9", "PrivateKey": "x", "Primary": 1 }
            ]
          }
        }
        """.data(using: .utf8) ?? Data()
        let res = try JSONDecoder().decode(ProtonUserResponse.self, from: json)
        #expect(res.user.name == nil)
        #expect(res.user.displayName == nil)
        #expect(res.user.email == nil)
        #expect(res.user.usedSpace == nil)
        #expect(res.user.maxSpace == nil)
        #expect(res.user.primaryKey?.id == "k9")
    }

    @Test func toleratesZeroAndAbsentQuota() throws {
        // Free accounts report UsedSpace 0 / MaxSpace absent.
        let json = """
        { "User": { "Email": "b@proton.me", "UsedSpace": 0, "Keys": [] } }
        """.data(using: .utf8) ?? Data()
        let res = try JSONDecoder().decode(ProtonUserResponse.self, from: json)
        #expect(res.user.email == "b@proton.me")
        #expect(res.user.usedSpace == 0)
        #expect(res.user.maxSpace == nil)
    }
}
