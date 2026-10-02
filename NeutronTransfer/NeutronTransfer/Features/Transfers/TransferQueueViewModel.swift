// Neutron Transfer — upload queue view-model (F4.4 live, F6 unified).
// Bridges the offline-tested TransferQueue actor to SwiftUI: destination
// share picking, NSOpenPanel + drop intake, bookmark capture, live snapshots.
// F6: reports remote-tree mutations to the shared TransferActivityStore so
// the browser refreshes post-operation; all user-facing strings go through
// UserFacingError (actionable, 2028 wait guidance).
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
    var isLoadingShares = false

    private let queue: TransferQueue
    private let sessions: SessionManager
    private let addressKeys: [KeyringCache.UnlockedKey]
    private let drive: DriveClient
    private let resolver: NodeKeyResolver
    private var started = false
    private let activity: TransferActivityStore?
    private var knownDone: Set<UUID> = []

    init(queue: TransferQueue, sessions: SessionManager, drive: DriveClient, addressKeys: [KeyringCache.UnlockedKey], resolver: NodeKeyResolver, activity: TransferActivityStore? = nil) {
        self.queue = queue
        self.sessions = sessions
        self.drive = drive
        self.addressKeys = addressKeys
        self.resolver = resolver
        self.activity = activity
    }

    var selectedShare: ShareOption? {
        shares.first { $0.id == selectedShareID }
    }

    /// Idempotent: wires the live uploader, loads shares, subscribes snapshots.
    func start() async {
        if !started {
            started = true
            await queue.setUploader(DriveUploadAdapter(drive: drive, addressKeys: addressKeys, resolver: resolver))
            await queue.setListener { [weak self] snap in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.jobs = snap
                    // Post-operation consistency: a newly completed upload
                    // changed the remote tree — ask the browser to reload.
                    let doneNow = Set(snap.filter { $0.state == .done }.map(\.id))
                    if !doneNow.subtracting(self.knownDone).isEmpty {
                        self.activity?.requestBrowserRefresh()
                    }
                    self.knownDone = doneNow
                }
            }
            await queue.start()
        }
        jobs = await queue.snapshot()
        knownDone = Set(jobs.filter { $0.state == .done }.map(\.id))
        await loadShares()
    }

    func stop() async {
        await queue.setListener(nil)
    }

    func loadShares() async {
        isLoadingShares = true
        defer { isLoadingShares = false }
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
            status = shares.isEmpty ? "No shares found — vault may be empty or still provisioning." : "Ready — pick a destination share"
        } catch {
            status = "Shares error: \(UserFacingError.message(for: error))"
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
            // Scoped access must be held on the MainActor before the worker
            // reads; the queue persists bookmarks for later reads, so the
            // grant is intentionally held for the session (see audit note).
            _ = url.startAccessingSecurityScopedResource() // held for the session
            do {
                let entries: [LocalTreeScan.Entry]
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    // Directory scan is synchronous disk I/O: keep it off the
                    // MainActor so large trees don't freeze the UI (spinner
                    // stays alive via isAdding).
                    entries = try await Task.detached(priority: .userInitiated) {
                        try LocalTreeScan.collect(root: url).entries
                    }.value
                } else {
                    entries = [LocalTreeScan.Entry(
                        url: url,
                        relativePath: url.lastPathComponent.precomposedStringWithCanonicalMapping,
                        isDirectory: false,
                        size: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    )]
                }
                let adapter = DriveUploadAdapter(drive: drive, addressKeys: addressKeys, resolver: resolver)
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
                // Folder creation happened inside enqueueTree (parent→child):
                // the remote tree changed — refresh the browser.
                activity?.requestBrowserRefresh()
            } catch {
                status = "Add failed (\(url.lastPathComponent)): \(UserFacingError.message(for: error))"
            }
        }
        jobs = await queue.snapshot()
    }

    func addPanel() async {
        guard let urls = await presentIntakePanel(), !urls.isEmpty else { return }
        await add(urls: urls)
    }

    /// Non-blocking intake picker: sheet on the key window, app-modal
    /// fallback when there is no key window. Never spins a nested runModal
    /// loop, so the MainActor stays free while the panel is up. Nil/empty =
    /// cancelled/dismissed (caller no-ops, status untouched).
    private func presentIntakePanel() async -> [URL]? {
        await withCheckedContinuation { cont in
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.canCreateDirectories = false
            panel.prompt = "Add to upload queue"
            let completion: (NSApplication.ModalResponse) -> Void = { response in
                cont.resume(returning: PanelIntake.uploadURLs(
                    responseOK: response == .OK, urls: panel.urls
                ))
            }
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window, completionHandler: completion)
            } else {
                panel.begin(completionHandler: completion)
            }
        }
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
