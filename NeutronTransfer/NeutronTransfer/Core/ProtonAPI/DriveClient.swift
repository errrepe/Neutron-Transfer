// Neutron Transfer — Drive read client (F3a: metadata only, no key unlock).
// Endpoints mirror rclone/go-proton-api + ProtonMail/go-proton-api:
//   GET /drive/volumes, /drive/shares[?ShowAll=1], /drive/shares/{id},
//   GET /drive/shares/{id}/links/{linkID},
//   GET /drive/shares/{id}/folders/{linkID}/children?Page=&PageSize=&ShowAll=
// 401 -> single SessionManager.refresh() + retry (mirrors go-proton-api doRes).
import Foundation

actor DriveClient {
    private let api: APIClient
    private let sessions: SessionManager
    private let pageSize = 100

    init(api: APIClient = APIClient(), sessions: SessionManager) {
        self.api = api
        self.sessions = sessions
    }

    func listVolumes() async throws -> [Volume] {
        try await authed { uid, token in
            try await api.get(VolumesResponse.self, path: "/drive/volumes", uid: uid, accessToken: token).volumes
        }
    }

    func listShares(showAll: Bool = true) async throws -> [ShareMetadata] {
        try await authed { uid, token in
            var query: [String: String]? = nil
            if showAll { query = ["ShowAll": "1"] }
            return try await api.get(SharesResponse.self, path: "/drive/shares", uid: uid, accessToken: token, query: query).shares
        }
    }

    func getShare(_ shareID: String) async throws -> DriveShare {
        try await authed { uid, token in
            try await api.get(ShareResponse.self, path: "/drive/shares/\(shareID)", uid: uid, accessToken: token).share
        }
    }

    func getLink(shareID: String, linkID: String) async throws -> DriveLink {
        try await authed { uid, token in
            try await api.get(LinkResponse.self, path: "/drive/shares/\(shareID)/links/\(linkID)", uid: uid, accessToken: token).link
        }
    }

    /// All children across pages (stops on first empty page, like go ListChildren).
    func listChildren(shareID: String, linkID: String, showAll: Bool = false) async throws -> [DriveLink] {
        var all: [DriveLink] = []
        var page = 0
        while true {
            let current = page
            let batch: [DriveLink] = try await authed { uid, token in
                try await api.get(
                    LinksResponse.self,
                    path: "/drive/shares/\(shareID)/folders/\(linkID)/children",
                    uid: uid,
                    accessToken: token,
                    query: [
                        "Page": String(current),
                        "PageSize": String(pageSize),
                        "ShowAll": showAll ? "1" : "0",
                    ]
                ).links
            }
            if batch.isEmpty { break }
            all.append(contentsOf: batch)
            page += 1
        }
        return all
    }

    // MARK: - plumbing

    private func authed<T: Sendable>(_ op: @Sendable (String, String) async throws -> T) async throws -> T {
        guard let creds = await sessions.credentials() else {
            throw ProtonAPIError.unauthorized
        }
        do {
            return try await op(creds.uid, creds.accessToken)
        } catch let e as ProtonAPIError where e == .unauthorized {
            // Single refresh + retry (long syncs expire quickly — rclone #7381).
            try await sessions.refresh()
            guard let retry = await sessions.credentials() else {
                throw ProtonAPIError.unauthorized
            }
            return try await op(retry.uid, retry.accessToken)
        }
    }
}
