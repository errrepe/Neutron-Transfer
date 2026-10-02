// Neutron Transfer — browser download orchestration (F7 S2.3).
// Extracted from the pre-F7 browser view-model, same behavior: the user picks
// ONE destination folder for the whole batch, then items download
// SEQUENTIALLY (a file via downloadSingleFile with per-block progress, a
// folder via downloadTree preserving structure). Each item reports a
// DownloadRecord to the shared activity store; failures land on the
// record, never block the remaining items. Downloads do not mutate the
// remote tree, so the browser is NOT invalidated afterwards.
// Security scope: the panel URL arrives already started; we still call
// startAccessing (harmless no-op) and ALWAYS balance it with
// stopAccessing when the batch ends.
import Foundation

@MainActor
final class DownloadCoordinator {
    private let drive: DriveClient
    private let addressKeys: [KeyringCache.UnlockedKey]
    private let resolver: NodeKeyResolver
    private let activity: TransferActivityStore
    /// LinkIDs with a download in flight — a double activation never
    /// duplicates a transfer (the legacy `downloading` set did the same).
    private var inFlight: Set<String> = []
    /// Guards against two destination panels stacking when the user
    /// triggers Download twice in quick succession.
    private var choosingDestination = false

    init(drive: DriveClient, addressKeys: [KeyringCache.UnlockedKey], resolver: NodeKeyResolver, activity: TransferActivityStore) {
        self.drive = drive
        self.addressKeys = addressKeys
        self.resolver = resolver
        self.activity = activity
    }

    /// Picks one destination folder, then downloads `items` one by one.
    /// Cancellation (nil panel result) silently no-ops — the user dismissed.
    func download(_ items: [DriveItem]) async {
        guard !items.isEmpty, !choosingDestination else { return }
        choosingDestination = true
        defer { choosingDestination = false }
        guard let destination = await Panels.chooseDownloadFolder() else { return }
        let scoped = destination.startAccessingSecurityScopedResource()
        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
        let adapter = DriveDownloadAdapter(
            drive: drive, addressKeys: addressKeys, resolver: resolver
        )
        for item in items {
            await download(item, with: adapter, to: destination)
        }
    }

    /// One item, errors captured on its record so the batch continues.
    private func download(
        _ item: DriveItem, with adapter: DriveDownloadAdapter, to destination: URL
    ) async {
        guard !inFlight.contains(item.id) else { return }
        inFlight.insert(item.id)
        defer { inFlight.remove(item.id) }
        let recordID = activity.downloadStarted(
            name: item.name,
            kind: item.isFolder ? .folder : .file,
            destination: destination
        )
        do {
            if item.isFolder {
                let urls = try await adapter.downloadTree(
                    shareID: item.shareID, linkID: item.id, destination: destination
                )
                activity.downloadFinished(
                    id: recordID, fileCount: urls.count, destination: destination
                )
            } else {
                let file = try await adapter.downloadSingleFile(
                    shareID: item.shareID, linkID: item.id, directory: destination
                ) { [weak self] done, total in
                    // @Sendable adapter context → hop to the MainActor to
                    // write the fraction (same shape the legacy VM used).
                    Task { @MainActor [weak self] in
                        self?.reportProgress(id: recordID, done: done, total: total)
                    }
                }
                // Reveal the FILE itself (not its folder) — matches Finder's
                // "Reveal in Finder" expectation for single-file downloads.
                activity.downloadFinished(
                    id: recordID, fileCount: 1, destination: destination, reveal: file
                )
            }
        } catch {
            activity.downloadFailed(id: recordID, error: error)
        }
    }

    /// Per-block progress hop: done/total blocks → a clamped 0…1 fraction.
    private func reportProgress(id: UUID, done: Int, total: Int) {
        activity.downloadProgress(
            id: id, fraction: total > 0 ? Double(done) / Double(total) : 1
        )
    }
}
