// Neutron Transfer — live upload adapter (F4.4).
// Bridges TransferQueue's offline-tested core to the live-verified F4.2/F4.3
// path (DriveClient.createFolder / uploadFile). All key material stays in
// memory: addressKeys (init) + per-share/per-folder caches in this actor.
// Folder memo is per-session (in-memory); file jobs whose remote parent was
// created in a previous session fail permanent with "re-add" guidance —
// persisting relativePath→nodeID in the job (TRANSFERS.md §1.3) is F4.5.

import Foundation

/// Live TransferUploader + RemoteFolderCreator over DriveClient.
actor DriveUploadAdapter: TransferUploader, RemoteFolderCreator {
    /// Unlocked keyring for one remote folder (root or created child).
    struct ResolvedKeys: Sendable {
        /// Node keys of this folder (share keys when this is the root).
        var keys: [KeyringCache.UnlockedKey]
        /// This folder's 32-byte hash key (name-HMAC key for its children).
        var hashKey: Data
        var linkID: String
        var addressID: String
        var signatureEmail: String
    }

    private let drive: DriveClient
    private let addressKeys: [KeyringCache.UnlockedKey]
    private var roots: [String: ResolvedKeys] = [:] // shareID → root
    private var nodes: [String: ResolvedKeys] = [:] // linkID → created folder

    init(drive: DriveClient, addressKeys: [KeyringCache.UnlockedKey]) {
        self.drive = drive
        self.addressKeys = addressKeys
    }

    // MARK: - TransferUploader

    func upload(
        job: TransferJob,
        progress: @Sendable (Int64) async -> Void
    ) async throws -> String? {
        let url = try localFileURL(for: job)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TransferFailure.permanent("cannot read \(job.fileName): \(error.localizedDescription)")
        }
        let keys = try await keysFor(shareID: job.shareID, linkID: job.parentLinkID)
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        await progress(0)
        // Whole-file, sequential blocks (F4.3 verified path — no per-block
        // progress yet; the queue jumps 0 → total per file at F4.4).
        let done = try await drive.uploadFile(
            shareID: job.shareID,
            parentLinkID: job.parentLinkID,
            fileName: job.fileName,
            data: data,
            parentKeys: keys.keys,
            parentHashKey: keys.hashKey,
            addressKeys: addressKeys,
            addressID: keys.addressID,
            signatureAddress: keys.signatureEmail,
            signatureEmail: keys.signatureEmail,
            modificationTime: mtime
        )
        await progress(Int64(data.count))
        return done.linkID
    }

    // MARK: - RemoteFolderCreator

    /// Creates `name` under `parentLinkID`, retrying with ` (1)`/` (2)`
    /// suffixes on API errors (best-effort duplicate handling — the exact
    /// duplicate-name code is still VARIANT-UNCERTAIN; the live battery
    /// confirms it in F4.5). Transport errors throw immediately.
    func ensureFolder(name: String, parentLinkID: String, shareID: String) async throws -> String {
        let parent = try await keysFor(shareID: shareID, linkID: parentLinkID)
        let signers = DecryptChain.edPoints(addressKeys)
        var lastError: Error = TransferFailure.permanent("unreachable")
        for candidate in [name, "\(name) (1)", "\(name) (2)"] {
            do {
                let created = try await drive.createFolder(
                    shareID: shareID,
                    parentLinkID: parentLinkID,
                    name: candidate,
                    parentKeys: parent.keys,
                    parentHashKey: parent.hashKey,
                    addressKeys: addressKeys,
                    signatureAddress: parent.signatureEmail,
                    signatureEmail: parent.signatureEmail
                )
                let link = try await drive.getLink(shareID: shareID, linkID: created.linkID)
                let nodeKeys = try DecryptChain.unlockNode(
                    link,
                    parentCandidates: parent.keys.compactMap(\.candidate),
                    signerPoints: signers
                )
                let hashKey = try Self.folderHashKey(link: link, nodeKeys: nodeKeys)
                nodes[created.linkID] = ResolvedKeys(
                    keys: nodeKeys, hashKey: hashKey, linkID: created.linkID,
                    addressID: parent.addressID, signatureEmail: parent.signatureEmail
                )
                return created.linkID
            } catch let e as ProtonAPIError {
                switch e {
                case .api:
                    lastError = e // maybe a duplicate — try the next suffix
                default:
                    throw e
                }
            }
        }
        throw lastError
    }

    // MARK: - key resolution (memory only)

    private func keysFor(shareID: String, linkID: String) async throws -> ResolvedKeys {
        if let root = roots[shareID], root.linkID == linkID { return root }
        if let node = nodes[linkID] { return node }
        if roots[shareID] == nil {
            let root = try await resolveRoot(shareID: shareID)
            roots[shareID] = root
            if root.linkID == linkID { return root }
        } else if let root = roots[shareID], root.linkID == linkID {
            return root
        }
        throw TransferFailure.permanent(
            "unknown remote parent — re-add the folder (folder memo is per-session at F4.4)"
        )
    }

    private func resolveRoot(shareID: String) async throws -> ResolvedKeys {
        let share = try await drive.getShare(shareID)
        let shareKeys = try DecryptChain.unlockShare(share, addressKeys: addressKeys)
        let signers = DecryptChain.edPoints(addressKeys)
        guard let rootID = share.linkID else {
            throw TransferFailure.permanent("share has no root link")
        }
        let root = try await drive.getLink(shareID: shareID, linkID: rootID)
        let rootKeys = try DecryptChain.unlockNode(
            root,
            parentCandidates: shareKeys.compactMap(\.candidate),
            signerPoints: signers
        )
        let hashKey = try Self.folderHashKey(link: root, nodeKeys: rootKeys)
        return ResolvedKeys(
            keys: rootKeys, hashKey: hashKey, linkID: rootID,
            addressID: share.addressID ?? "",
            signatureEmail: share.creator ?? ""
        )
    }

    /// Folder hash key: armored NodeHashKey → node candidates → base64-utf8
    /// of 32 random bytes (F4.2 live-verified convention).
    private static func folderHashKey(
        link: DriveLink,
        nodeKeys: [KeyringCache.UnlockedKey]
    ) throws -> Data {
        guard let armored = link.folderProperties?.nodeHashKey, !armored.isEmpty else {
            throw TransferFailure.permanent("folder has no NodeHashKey")
        }
        let plain = try MessageDecrypt.decrypt(
            armored: armored,
            candidates: nodeKeys.compactMap(\.candidate)
        )
        guard let token = String(data: plain, encoding: .utf8),
              let seed = Data(base64Encoded: token),
              seed.count == 32
        else {
            throw TransferFailure.permanent("malformed NodeHashKey")
        }
        return seed
    }

    /// Prefers the enqueue-time path; falls back to the security-scoped
    /// bookmark (survives moves/renames within a session grant).
    private func localFileURL(for job: TransferJob) throws -> URL {
        if FileManager.default.fileExists(atPath: job.localPath) {
            return URL(fileURLWithPath: job.localPath)
        }
        if let bookmark = job.localBookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        throw TransferFailure.permanent("local file missing — re-add \(job.fileName)")
    }
}
