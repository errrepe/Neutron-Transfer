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
        // NOTE: go uses `struct { Share }` (embedded) so the response is FLAT
        // (all fields top-level), unlike the nested list endpoints.
        try await authed { uid, token in
            try await api.get(DriveShare.self, path: "/drive/shares/\(shareID)", uid: uid, accessToken: token)
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

    // MARK: - folder creation (F4.2)

    /// Creates a folder under `parentLinkID`: generates a fresh node keypair +
    /// passphrase client-side (FolderCreate, mirroring Proton clients),
    /// encrypts Name/NodePassphrase to the parent keyring, signs with the
    /// address key, and POSTs /drive/shares/{shareID}/folders. Returns the
    /// created LinkID plus the node material needed to read it back.
    /// - `parentKeys`: unlocked PARENT keyring (share keys for a root child).
    /// - `parentHashKey`: parent folder's 32-byte hash key for the name HMAC.
    /// - `addressKeys`: unlocked address keys (the #22 key signs).
    func createFolder(
        shareID: String,
        parentLinkID: String,
        name: String,
        parentKeys: [KeyringCache.UnlockedKey],
        parentHashKey: Data,
        addressKeys: [KeyringCache.UnlockedKey],
        signatureAddress: String? = nil,
        signatureEmail: String? = nil,
        signArmoredPassphrase: Bool = false,
        xAttrPlaintext: Data? = nil
    ) async throws -> (linkID: String, node: FolderCreate.NodeMaterial) {
        let (request, node) = try FolderCreate.buildRequest(
            name: name, parentLinkID: parentLinkID, parentKeys: parentKeys,
            parentHashKey: parentHashKey, addressKeys: addressKeys,
            signatureAddress: signatureAddress, signatureEmail: signatureEmail,
            signArmoredPassphrase: signArmoredPassphrase,
            xAttrPlaintext: xAttrPlaintext
        )
        let res: CreateFolderResponse = try await authed { uid, token in
            try await api.post(
                CreateFolderResponse.self, path: "/drive/shares/\(shareID)/folders",
                uid: uid, accessToken: token, body: request
            )
        }
        return (res.folder.id, node)
    }

    // MARK: - file upload (F4.3)

    /// Duplicate-name probe under `parentLinkID` (pre-draft, mirrors the
    /// reference order). `hashes` are NameHash hex strings.
    func checkAvailableHashes(
        shareID: String, parentLinkID: String, hashes: [String]
    ) async throws -> (available: [String], pending: [String]) {
        let res: CheckAvailableHashesResponse = try await authed { uid, token in
            try await api.post(
                CheckAvailableHashesResponse.self,
                path: "/drive/shares/\(shareID)/links/\(parentLinkID)/checkAvailableHashes",
                uid: uid, accessToken: token,
                body: CheckAvailableHashesRequest(hashes: hashes)
            )
        }
        return (res.availableHashes, res.pendingHashes)
    }

    /// Posts a prepared file draft. Returns the draft LinkID + RevisionID.
    func createFileDraft(
        shareID: String, request: CreateFileRequest
    ) async throws -> (linkID: String, revisionID: String) {
        let res: CreateFileResponse = try await authed { uid, token in
            try await api.post(
                CreateFileResponse.self, path: "/drive/shares/\(shareID)/files",
                uid: uid, accessToken: token, body: request
            )
        }
        return (res.file.id, res.file.revisionID)
    }

    /// Opens a block-upload session for one revision. `blocks` are the
    /// descriptors from FileUpload.prepareUpload (Hash = base64 SHA-256 of
    /// plaintext, Size = encrypted packet length, EncSignature armored).
    func requestBlockUploads(
        addressID: String, shareID: String, linkID: String,
        revisionID: String, blocks: [FileUpload.BlockDescriptor]
    ) async throws -> [StorageUploadLink] {
        let entries = blocks.map {
            BlockUploadEntry(
                index: $0.index, size: $0.encrypted.count,
                encSignature: $0.encSignature,
                hash: $0.hash.base64EncodedString()
            )
        }
        let res: RequestBlockUploadsResponse = try await authed { uid, token in
            try await api.post(
                RequestBlockUploadsResponse.self, path: "/drive/blocks",
                uid: uid, accessToken: token,
                body: RequestBlockUploadsRequest(
                    addressID: addressID, shareID: shareID, linkID: linkID,
                    revisionID: revisionID, blockList: entries
                )
            )
        }
        return res.uploadLinks
    }

    /// Uploads one raw encrypted block packet to its BareURL (runtime
    /// storage host) with the link Token. Match links to blocks by Index.
    func uploadBlockBytes(bareURL: String, token: String, bytes: Data) async throws {
        let boundary = FileUpload.freshBoundary()
        let body = FileUpload.multipartBlockBody(boundary: boundary, blockBytes: bytes)
        try await authed { uid, accessToken in
            try await api.uploadRawBlock(
                bareURL: bareURL, token: token, uid: uid,
                accessToken: accessToken, body: body, boundary: boundary
            )
        }
    }

    /// Commits a revision: manifest signature + node-encrypted XAttr.
    /// Returns the echoed link id/state (partial — use getLink for full).
    func commitRevision(
        shareID: String, linkID: String, revisionID: String,
        request: CommitRevisionRequest
    ) async throws -> CommitRevisionResponse {
        let res: CommitRevisionResponse = try await authed { uid, token in
            try await api.put(
                CommitRevisionResponse.self,
                path: "/drive/shares/\(shareID)/files/\(linkID)/revisions/\(revisionID)",
                uid: uid, accessToken: token, body: request
            )
        }
        guard res.code == 1000 || res.code == 1001 else {
            throw ProtonAPIError.api(code: res.code, message: "commit failed")
        }
        return res
    }

    /// Single-file upload (F4.3 — no queue/UI; that is F4.4). Returns the
    /// created LinkID + RevisionID + node material (needed to read back).
    /// - `parentKeys`: unlocked PARENT keyring (share keys for a root child).
    /// - `parentHashKey`: parent folder's 32-byte hash key (name HMAC).
    /// - `addressKeys`: unlocked address keys (the #22 key signs).
    /// - `addressID`: uploader's address ID for the /drive/blocks session.
    /// - `blockSize`: plaintext chunk size (default 4 MiB); empty data takes
    ///   the no-blocks path (draft + commit, manifest over zero hashes).
    func uploadFile(
        shareID: String,
        parentLinkID: String,
        fileName: String,
        data: Data,
        mimeType: String? = nil,
        parentKeys: [KeyringCache.UnlockedKey],
        parentHashKey: Data,
        addressKeys: [KeyringCache.UnlockedKey],
        addressID: String,
        signatureAddress: String? = nil,
        signatureEmail: String? = nil,
        blockSize: Int = FileUpload.defaultBlockSize,
        modificationTime: Date = Date()
    ) async throws -> (linkID: String, revisionID: String, node: FolderCreate.NodeMaterial) {
        let prepared = try FileUpload.prepareUpload(
            fileName: fileName, parentLinkID: parentLinkID, data: data,
            mimeType: mimeType, modificationTime: modificationTime,
            blockSize: blockSize, parentKeys: parentKeys,
            parentHashKey: parentHashKey, addressKeys: addressKeys,
            signatureAddress: signatureAddress, signatureEmail: signatureEmail
        )
        _ = try await checkAvailableHashes(
            shareID: shareID, parentLinkID: parentLinkID,
            hashes: [prepared.request.hash]
        )
        let ids = try await createFileDraft(shareID: shareID, request: prepared.request)
        var manifestHashes: [Data] = []
        if !prepared.blocks.isEmpty {
            let links = try await requestBlockUploads(
                addressID: addressID, shareID: shareID, linkID: ids.linkID,
                revisionID: ids.revisionID, blocks: prepared.blocks
            )
            guard !links.isEmpty, links.count == prepared.blocks.count else {
                throw FileUploadError.emptyUploadLinks
            }
            for block in prepared.blocks {
                guard let link = links.first(where: { $0.index == block.index }) else {
                    throw FileUploadError.uploadLinkMismatch
                }
                try await uploadBlockBytes(
                    bareURL: link.bareURL, token: link.token, bytes: block.encrypted
                )
            }
            manifestHashes = prepared.blocks.map(\.hash)
        }
        let commit = try FileUpload.buildCommit(
            manifestHashes: manifestHashes, xAttrJSON: prepared.xAttrJSON,
            node: prepared.node, addressKeys: addressKeys,
            signatureAddress: signatureAddress, signatureEmail: signatureEmail
        )
        try await commitRevision(
            shareID: shareID, linkID: ids.linkID,
            revisionID: ids.revisionID, request: commit
        )
        return (ids.linkID, ids.revisionID, prepared.node)
    }

    /// Trashes children (state -> trashed). Per-item API codes surface as errors.
    func trashChildren(shareID: String, parentLinkID: String, linkIDs: [String]) async throws {
        let res: BatchChildrenResponse = try await authed { uid, token in
            try await api.post(
                BatchChildrenResponse.self,
                path: "/drive/shares/\(shareID)/folders/\(parentLinkID)/trash_multiple",
                uid: uid, accessToken: token, body: BatchChildrenRequest(linkIDs: linkIDs)
            )
        }
        for r in res.responses where r.response.code != 1000 && r.response.code != 1001 {
            throw ProtonAPIError.api(code: r.response.code, message: r.response.error ?? "trash failed")
        }
    }

    /// Permanently deletes (trashed) children. Per-item codes surface as errors.
    func deleteChildren(shareID: String, parentLinkID: String, linkIDs: [String]) async throws {
        let res: BatchChildrenResponse = try await authed { uid, token in
            try await api.post(
                BatchChildrenResponse.self,
                path: "/drive/shares/\(shareID)/folders/\(parentLinkID)/delete_multiple",
                uid: uid, accessToken: token, body: BatchChildrenRequest(linkIDs: linkIDs)
            )
        }
        for r in res.responses where r.response.code != 1000 && r.response.code != 1001 {
            throw ProtonAPIError.api(code: r.response.code, message: r.response.error ?? "delete failed")
        }
    }

    // MARK: - plumbing

    private func authed<T: Sendable>(_ op: @Sendable (String, String) async throws -> T) async throws -> T {
        try await sessions.withAuth(op)
    }
}
