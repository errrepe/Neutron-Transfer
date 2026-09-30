// Neutron Transfer — Keychain session storage (no secrets in UserDefaults/logs).
import Foundation
import Security

struct ProtonSession: Codable, Sendable, Equatable {
    var uid: String
    var accessToken: String
    var refreshToken: String
    /// Salted key password (base64 of MailboxPassword output) for unlocking user
    /// keys without re-prompting. Password-equivalent: Keychain only, never logs.
    /// Nil for sessions saved before F3b-1 (re-login repopulates).
    var saltedKeyPass: String? = nil
}

enum KeychainStore {
    static let service = "dev.neutron.transfer.session"
    static let account = "proton-session"

    /// Test seam (CLI probes, unit tests): when false, load returns nil and
    /// save/delete are no-ops. Production always leaves this true.
    /// Set once at startup before any use; not mutated concurrently.
    nonisolated(unsafe) static var isEnabled = true

    static func save(_ session: ProtonSession) throws {
        guard isEnabled else { return }
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        let add = query.merging([kSecValueData as String: data]) { _, new in new }
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ProtonAPIError.api(code: Int(status), message: "keychain save failed")
        }
    }

    static func load() -> ProtonSession? {
        guard isEnabled else { return nil }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(ProtonSession.self, from: data)
    }

    static func delete() {
        guard isEnabled else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
