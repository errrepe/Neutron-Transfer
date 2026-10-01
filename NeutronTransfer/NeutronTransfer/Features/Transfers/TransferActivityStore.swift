// Neutron Transfer — shared transfers activity (F6).
// Minimal upload+download unification WITHOUT rewriting TransferQueue:
// uploads stay in the TransferQueue actor; downloads (F5 dedicated
// downloader) report lightweight records here so ONE Transfers tab shows
// both. Also carries a browser-refresh counter: upload folder creation and
// completed jobs bump it, the browser reloads on change (post-operation
// consistency, TRANSFERS.md F6).

import Foundation

@MainActor
@Observable
final class TransferActivityStore {
    var downloads: [DownloadRecord] = []
    /// Bumped whenever the remote tree likely changed (upload done, tree
    /// enqueued, download finished). The browser observes and reloads.
    var browserRefreshCounter = 0

    func downloadStarted(name: String, kind: DownloadKind, destination: URL?) -> UUID {
        let rec = DownloadRecord(
            name: name, kind: kind, state: .downloading,
            destinationName: destination?.lastPathComponent
        )
        downloads.insert(rec, at: 0)
        trim()
        return rec.id
    }

    func downloadFinished(id: UUID, fileCount: Int, destination: URL?) {
        guard let i = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[i].state = .done
        downloads[i].fileCount = fileCount
        if let destination { downloads[i].destinationName = destination.lastPathComponent }
        downloads[i].errorMessage = nil
        downloads[i].updatedAt = Date()
    }

    func downloadFailed(id: UUID, error: Error) {
        guard let i = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[i].state = .failed
        downloads[i].errorMessage = UserFacingError.message(for: error)
        downloads[i].updatedAt = Date()
    }

    func clearFinished() {
        downloads.removeAll { $0.state == .done || $0.state == .failed }
    }

    func requestBrowserRefresh() {
        browserRefreshCounter += 1
    }

    private func trim() {
        if downloads.count > 50 {
            downloads = Array(downloads.prefix(50))
        }
    }
}
