// Nucleon Transfer — Modulus decoding per go-srp NewAuth.
// Server sends the modulus as a PGP-clearsigned base64 string; go-srp verifies
// the signature against the embedded Proton SRP pubkey (readClearSignedMessage).
// This spike parses the clearsign envelope and decodes the body. Signature
// verification is TODO F2c (GopenPGP bridge); transport is TLS-protected.
import Foundation

enum ModulusDecoder {
    static func decode(_ string: String) throws -> Data {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("PGP SIGNED MESSAGE") {
            return try decodeClearsign(trimmed)
        }
        guard let data = Data(base64Encoded: trimmed) else {
            throw ProtonAPIError.srpParamsOutOfBounds("modulus is not base64")
        }
        return data
    }

    private static func decodeClearsign(_ message: String) throws -> Data {
        let lines = message.components(separatedBy: "\n").map {
            $0.hasSuffix("\r") ? String($0.dropLast()) : $0
        }
        guard let sigIdx = lines.firstIndex(where: { $0.hasPrefix("-----BEGIN PGP SIGNATURE-----") }),
              let emptyIdx = lines.firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces).isEmpty
              }),
              emptyIdx < sigIdx else {
            throw ProtonAPIError.invalidModulusSignature
        }
        // Dash-unescape body lines ("- " -> "-") per clearsign spec.
        let body = lines[(emptyIdx + 1)..<sigIdx].map { line in
            line.hasPrefix("- ") ? String(line.dropFirst(2)) : line
        }.joined()
        guard let data = Data(base64Encoded: body) else {
            throw ProtonAPIError.invalidModulusSignature
        }
        return data
    }
}
