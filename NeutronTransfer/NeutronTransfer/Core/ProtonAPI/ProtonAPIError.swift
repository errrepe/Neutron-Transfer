// Neutron Transfer — Proton API error mapping.
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
             (.keyVerificationFailed, .keyVerificationFailed):
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
