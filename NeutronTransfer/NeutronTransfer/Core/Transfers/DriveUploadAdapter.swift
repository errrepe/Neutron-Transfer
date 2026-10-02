// Neutron Transfer — live upload adapter (F4.4; S1.2 key resolver).
// Bridges TransferQueue's offline-tested core to the live-verified F4.2/F4.3
// path (DriveClient.createFolder / uploadFile). Key material is resolved by
// the session's shared NodeKeyResolver (share/node memo + parent-chain
// walk), so uploads work under ANY existing remote folder — not just the
// root or session-created ones (P5/P6 fixed). Folder memo is per-session
// (in-memory, on the resolver); file jobs whose remote parent was created
// in a previous session now resolve remotely instead of failing — the
// "re-add" fallback is gone.

import Foundation

/// Live TransferUploader + RemoteFolderCreator over DriveClient.
actor DriveUploadAdapter: TransferUploader, RemoteFolderCreator {
    private let drive: DriveClient
    private let addressKeys: [KeyringCache.UnlockedKey]
    private let resolver: NodeKeyResolver

    init(drive: DriveClient, addressKeys: [KeyringCache.UnlockedKey], resolver: NodeKeyResolver) {
        self.drive = drive
        self.addressKeys = addressKeys
        self.resolver = resolver
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
        let parent = try await resolver.folder(shareID: job.shareID, linkID: job.parentLinkID)
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        await progress(0)
        // Whole-file, sequential blocks (F4.3 verified path — no per-block
        // progress yet; the queue jumps 0 → total per file at F4.4).
        let done = try await drive.uploadFile(
            shareID: job.shareID,
            parentLinkID: job.parentLinkID,
            fileName: job.fileName,
            data: data,
            parentKeys: parent.keys,
            parentHashKey: parent.hashKey,
            addressKeys: addressKeys,
            addressID: parent.addressID,
            signatureAddress: parent.signatureEmail,
            signatureEmail: parent.signatureEmail,
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
        let parent = try await resolver.folder(shareID: shareID, linkID: parentLinkID)
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
                // Resolve the fresh folder (getLink + unlock + hash key)
                // and register it, so later uploads into it hit the cache.
                let ctx = try await resolver.folder(shareID: shareID, linkID: created.linkID)
                await resolver.register(createdFolder: ctx)
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

    // MARK: - local files

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
