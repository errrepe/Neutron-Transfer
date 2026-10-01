// Neutron Transfer — upload queue view-model (F4.4, live only).
// Bridges the offline-tested TransferQueue actor to SwiftUI: destination
// share picking, NSOpenPanel + drop intake, bookmark capture, live snapshots.
import AppKit
import Foundation

@MainActor
@Observable
final class TransferQueueViewModel {
    struct ShareOption: Identifiable, Equatable {
        var id: String
        var label: String
        /// Root LinkID (upload target for the tree).
        var rootLinkID: String
    }

    var jobs: [TransferJob] = []
    var shares: [ShareOption] = []
    var selectedShareID: String?
    var status = "Queue.device idle"
    var isAdding = false

    private let queue: TransferQueue
    private let sessions: SessionManager
    private let addressKeys: [KeyringCache.UnlockedKey]
    private let drive: DriveClient
    private var started = false

    init(queue: TransferQueue, sessions: SessionManager, addressKeys: [KeyringCache.UnlockedKey]) {
        self.queue = queue
        self.sessions = sessions
        self.addressKeys = addressKeys
        drive = DriveClient(sessions: sessions)
    }

    var selectedShare: ShareOption? {
        shares.first { $0.id == selectedShareID }
    }

    /// Idempotent: wires the live uploader, loads shares, subscribes snapshots.
    func start() async {
        if !started {
            started = true
            await queue.setUploader(DriveUploadAdapter(drive: drive, addressKeys: addressKeys))
            await queue.setListener { [weak self] snap in
                Task { @MainActor [weak self] in self?.jobs = snap }
            }
            await queue.start()
        }
        jobs = await queue.snapshot()
        await loadShares()
    }

    func stop() async {
        await queue.setListener(nil)
    }

    func loadShares() async {
        do {
            let metas = try await drive.listShares()
            shares = metas.map {
                ShareOption(
                    id: $0.shareID,
                    label: "Share \($0.shareID.prefix(8))… · type \($0.type)",
                    rootLinkID: $0.linkID
                )
            }
            if selectedShareID == nil { selectedShareID = shares.first?.id }
            status = shares.isEmpty ? "No shares found" : "Ready — pick a destination share"
        } catch {
            status = "Shares error: \(error.localizedDescription)"
        }
    }

    // MARK: intake

    /// Adds dropped/picked URLs (files and/or folders), preserving structure.
    func add(urls: [URL]) async {
        guard let dest = selectedShare else {
            status = "Pick a destination share first"
            return
        }
        guard !urls.isEmpty else { return }
        isAdding = true
        defer { isAdding = false }
        var totalFiles = 0
        for url in urls {
            _ = url.startAccessingSecurityScopedResource() // held for the session
            do {
                let entries: [LocalTreeScan.Entry]
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    entries = try LocalTreeScan.collect(root: url).entries
                } else {
                    entries = [LocalTreeScan.Entry(
                        url: url,
                        relativePath: url.lastPathComponent.precomposedStringWithCanonicalMapping,
                        isDirectory: false,
                        size: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    )]
                }
                let adapter = DriveUploadAdapter(drive: drive, addressKeys: addressKeys)
                let ids = try await queue.enqueueTree(
                    entries: entries,
                    shareID: dest.id,
                    rootParentLinkID: dest.rootLinkID,
                    folders: adapter
                )
                // Best-effort bookmarks so jobs survive moves within the grant.
                let files = entries.filter { !$0.isDirectory }
                for (id, entry) in zip(ids, files) {
                    let bookmark = try? entry.url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    await queue.setBookmark(id: id, bookmark)
                }
                totalFiles += files.count
                status = "Enqueued \(totalFiles) file(s) → \(dest.label)"
            } catch {
                status = "Add failed (\(url.lastPathComponent)): \(error.localizedDescription)"
            }
        }
        jobs = await queue.snapshot()
    }

    func addPanel() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Add to upload queue"
        guard panel.runModal() == .OK else { return }
        await add(urls: panel.urls)
    }

    // MARK: operators (thin pass-through + snapshot refresh)

    func pause(_ id: UUID) async { await queue.pause(id: id); jobs = await queue.snapshot() }
    func resume(_ id: UUID) async { await queue.resume(id: id); jobs = await queue.snapshot() }
    func cancel(_ id: UUID) async { await queue.cancel(id: id); jobs = await queue.snapshot() }
    func relaunch(_ id: UUID) async { await queue.relaunch(id: id); jobs = await queue.snapshot() }
    func remove(_ id: UUID) async { await queue.remove(id: id); jobs = await queue.snapshot() }
    func relaunchAllFailed() async { await queue.relaunchAllFailed(); jobs = await queue.snapshot() }

    func stateLabel(_ s: TransferJobState) -> String {
        switch s {
        case .queued: return "Queued"
        case .uploading: return "Uploading"
        case .paused: return "Paused"
        case .done: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
