// Neutron Transfer — minimal Proton REST client.
// Mirrors go-proton-api Manager.r(): base mail.proton.me/api, x-pm-appversion,
// x-pm-uid + Bearer on authed calls, 401 -> single refresh retry (in SessionManager).
import Foundation

struct APIClient: Sendable {
    var baseURL: URL = AppVersion.baseURL
    var session: URLSession = .shared

    func request(
        _ path: String,
        method: String = "POST",
        uid: String? = nil,
        accessToken: String? = nil,
        body: (any Encodable & Sendable)? = nil
    ) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppVersion.headerValue, forHTTPHeaderField: "x-pm-appversion")
        if let uid { req.setValue(uid, forHTTPHeaderField: "x-pm-uid") }
        if let accessToken { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        return req
    }

    func authInfo(username: String) async throws -> AuthInfo {
        let req = try request("/auth/v4/info", body: AuthInfoRequest(username: username))
        return try await decode(AuthInfoResponse.self, request: req).authInfo
    }

    func auth(_ body: AuthRequest) async throws -> AuthResponse {
        let req = try request("/auth/v4", body: body)
        return try await decode(AuthResponse.self, request: req)
    }

    func auth2FA(code: String, uid: String, accessToken: String) async throws {
        let req = try request("/auth/v4/2fa", uid: uid, accessToken: accessToken,
                              body: Auth2FARequest(twoFACode: code))
        _ = try await data(for: req)
    }

    func authRefresh(_ body: AuthRefreshRequest) async throws -> ProtonAuth {
        let req = try request("/auth/v4/refresh", body: body)
        return try await decode(AuthResponse.self, request: req).auth
    }

    // MARK: - plumbing

    func decode<T: Decodable>(_ type: T.Type, request: URLRequest) async throws -> T {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProtonAPIError.transport(URLError(.badServerResponse))
        }
        if http.statusCode == 401 { throw ProtonAPIError.unauthorized }
        // Proton nests payloads; envelope check for human-verification / 2FA signals
        if let env = try? JSONDecoder().decode(ProtonEnvelope.self, from: data), env.code != 1000, env.code != 1001 {
            switch env.code {
            case 9001: throw ProtonAPIError.humanVerificationRequired
            case 2011, 2021: throw ProtonAPIError.needs2FA
            default: throw ProtonAPIError.api(code: env.code, message: env.error ?? "unknown")
            }
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // surface nested API error if present
            if let env = try? JSONDecoder().decode(ProtonEnvelope.self, from: data) {
                throw ProtonAPIError.api(code: env.code, message: env.error ?? error.localizedDescription)
            }
            throw error
        }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw ProtonAPIError.transport(error)
        }
    }
}

// Response wrappers (Proton nests under capitalized keys in some endpoints)
struct AuthInfoResponse: Decodable, Sendable {
    var authInfo: AuthInfo
    // /auth/v4/info returns fields flat; be liberal:
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try? c.nestedContainer(keyedBy: AuthInfo.CodingKeys.self, forKey: .authInfo) {
            authInfo = AuthInfo(
                version: try nested.decode(Int.self, forKey: .version),
                modulus: try nested.decode(String.self, forKey: .modulus),
                salt: try nested.decode(String.self, forKey: .salt),
                serverEphemeral: try nested.decode(String.self, forKey: .serverEphemeral),
                srpSession: try nested.decode(String.self, forKey: .srpSession)
            )
        } else {
            authInfo = try AuthInfo(from: decoder)
        }
    }
    enum CodingKeys: String, CodingKey { case authInfo = "AuthInfo" }
}

struct AuthResponse: Decodable, Sendable {
    var auth: ProtonAuth
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if (try? c.nestedContainer(keyedBy: ProtonAuth.CodingKeys.self, forKey: .auth)) != nil {
            auth = try c.decode(ProtonAuth.self, forKey: .auth)
        } else {
            auth = try ProtonAuth(from: decoder)
        }
    }
    enum CodingKeys: String, CodingKey { case auth = "Auth" }
}

/// Type-erase Encodable for generic request builder.
private struct AnyEncodable: Encodable {
    var base: any Encodable
    init(_ base: any Encodable & Sendable) { self.base = base }
    func encode(to encoder: Encoder) throws { try base.encode(to: encoder) }
}
