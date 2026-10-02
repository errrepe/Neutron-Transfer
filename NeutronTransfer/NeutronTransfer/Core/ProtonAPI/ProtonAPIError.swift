// Nucleon Transfer — Proton API error mapping.
// Reference: go-proton-api client.go (401 -> refresh), manager_auth.go, proton-cli HV handling.
import Foundation

enum ProtonAPIError: Error, Sendable, Equatable {
    case api(code: Int, message: String)
    case unauthorized
    case needs2FA
    case humanVerificationRequired
    case invalidServerProof
    case invalidModulusSignature
    case srpParamsOutOfBounds(String)
    case bcryptNotAvailable
    case invalidBcryptSalt
    case keyVerificationFailed
    /// 2028 Too many recent logins (or generic rate limit): NEVER auto-retry
    /// logins — surface immediately and back off. One spaced login per batch.
    case rateLimited
    case transport(Error)

    static func == (lhs: ProtonAPIError, rhs: ProtonAPIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized),
             (.needs2FA, .needs2FA),
             (.humanVerificationRequired, .humanVerificationRequired),
             (.invalidServerProof, .invalidServerProof),
             (.invalidModulusSignature, .invalidModulusSignature),
             (.bcryptNotAvailable, .bcryptNotAvailable),
             (.invalidBcryptSalt, .invalidBcryptSalt),
             (.keyVerificationFailed, .keyVerificationFailed),
             (.rateLimited, .rateLimited):
            return true
        case let (.api(c1, m1), .api(c2, m2)):
            return c1 == c2 && m1 == m2
        case let (.srpParamsOutOfBounds(a), .srpParamsOutOfBounds(b)):
            return a == b
        default:
            return false
        }
    }
}

/// Minimal envelope shared by Proton REST responses: { Code, Error }.
struct ProtonEnvelope: Decodable, Sendable {
    var code: Int
    var error: String?

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case error = "Error"
    }
}

extension ProtonAPIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Not signed in (or session expired)."
        case .needs2FA: return "Two-factor code required."
        case .humanVerificationRequired: return "Proton requires human verification. Try again later."
        case .rateLimited: return "Too many recent logins (Proton 2028 rate-limit). Wait ~10 minutes before retrying — do not log in repeatedly. If you are signed in, keep using this session."
        case .invalidServerProof: return "Server proof mismatch — possible downgrade attack. Aborted."
        case .invalidModulusSignature: return "Bad SRP modulus envelope."
        case .bcryptNotAvailable: return "Crypto backend missing (bcrypt)."
        case .invalidBcryptSalt: return "Malformed bcrypt salt."
        case .keyVerificationFailed: return "Unlocked key does not match its public key."
        case let .srpParamsOutOfBounds(msg): return "SRP parameter error: \(msg)."
        case let .api(code, message): return "Proton API \(code): \(message)."
        case let .transport(e): return e.localizedDescription
        }
    }
}
