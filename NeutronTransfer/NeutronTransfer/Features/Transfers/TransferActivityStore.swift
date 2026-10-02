// Neutron Transfer — shared transfers activity (F6; S2.3 progress +
// remote-changed signal).
// Minimal upload+download unification WITHOUT rewriting TransferQueue:
// uploads stay in the TransferQueue actor; downloads (F5 dedicated
// downloader, S2.3 DownloadCoordinator) report lightweight records here so
// ONE Transfers surface shows both. Post-operation consistency (S2.3):
// upload/folder/trash ops publish the touched parent linkIDs via
// `remoteChanged` — browsers observe `remoteChangedToken` and mark those
// folders stale (BrowserModel.markStale) instead of a blind global refresh.

import Foundation

@MainActor
@Observable
final class TransferActivityStore {
    var downloads: [DownloadRecord] = []
    /// Record ID → local file/folder URL for a future "Reveal in Finder"
    /// action. In-memory only (never Codable): DownloadRecord keeps the
    /// destination NAME only — full paths stay out of the record and out
    /// of any persisted state, for privacy.
    private(set) var revealURLs: [UUID: URL] = [:]
    /// Parent linkIDs whose remote contents changed since the last
    /// published token. Accumulates (union) so a burst of ops between two
    /// view passes never drops a parent; `markStale` only flags cache
    /// entries, so a lingering parent degrades to a lazy refresh on visit.
    private(set) var remoteChangedParents: Set<String> = []
    /// Incremented on every `remoteChanged` — views key `.task(id:)` on it.
    private(set) var remoteChangedToken = 0
    /// Set by UploadCoordinator on intake (S3.1); S3.2's toolbar button
    /// binds the transfers popover to this flag.
    var presentTransfers = false

    func downloadStarted(name: String, kind: DownloadKind, destination: URL?) -> UUID {
        let rec = DownloadRecord(
            name: name, kind: kind, state: .downloading,
            destinationName: destination?.lastPathComponent
        )
        downloads.insert(rec, at: 0)
        trim()
        return rec.id
    }

    /// Per-block progress while downloading (0…1, clamped; unknown ids are
    /// ignored so a cleared record can't resurrect).
    func downloadProgress(id: UUID, fraction: Double) {
        guard let i = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[i].progress = min(max(fraction, 0), 1)
    }

    func downloadFinished(id: UUID, fileCount: Int, destination: URL?, reveal: URL? = nil) {
        guard let i = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[i].state = .done
        downloads[i].fileCount = fileCount
        if let destination { downloads[i].destinationName = destination.lastPathComponent }
        downloads[i].progress = nil
        downloads[i].errorMessage = nil
        downloads[i].updatedAt = Date()
        if let reveal {
            revealURLs[id] = reveal
        } else if let destination {
            revealURLs[id] = destination
        }
    }

    func downloadFailed(id: UUID, error: Error) {
        guard let i = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[i].state = .failed
        downloads[i].progress = nil
        downloads[i].errorMessage = UserFacingError.message(for: error)
        downloads[i].updatedAt = Date()
    }

    func clearFinished() {
        let keep = downloads.filter { $0.state != .done && $0.state != .failed }
        let removed = Set(downloads.map(\.id)).subtracting(keep.map(\.id))
        downloads = keep
        for id in removed { revealURLs.removeValue(forKey: id) }
    }

    /// Post-operation consistency (S2.3): publish the parent linkIDs a
    /// remote mutation touched (folder create, trash, upload enqueue/done).
    /// Browsers keyed on `remoteChangedToken` call `markStale` — only the
    /// affected folders refetch, and only on demand.
    func remoteChanged(parentLinkIDs: [String]) {
        remoteChangedParents.formUnion(parentLinkIDs)
        remoteChangedToken += 1
    }

    private func trim() {
        if downloads.count > 50 {
            let dropped = downloads.suffix(from: 50).map(\.id)
            downloads = Array(downloads.prefix(50))
            for id in dropped { revealURLs.removeValue(forKey: id) }
        }
    }
}
