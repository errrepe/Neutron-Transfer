// Neutron Transfer — Drive browser with decrypted names (F3b chain, F6 polish).
// Key hierarchy per share: address keys -> share keys -> root node keys.
// Names decrypt with the PARENT keyring (root name <- share keys,
// child name <- root node keys).
// F6: isLoading/empty-state support, UserFacingError on all user paths,
// download history reporting to the shared activity store.
import AppKit
import Foundation

@MainActor
@Observable
final class DriveBrowserViewModel {
    struct Row: Identifiable {
        var link: DriveLink
        var name: String
        var id: String { link.linkID }
    }

    struct Section: Identifiable {
        var shareID: String
        var rootName: String
        var rows: [Row]
        var note: String?
        var id: String { shareID }
    }

    var volumes: [Volume] = []
    var sections: [Section] = []
    var status = "Not loaded"
    var isLoading = false
    /// F5 download progress: linkID → 0…1 (files report per-block; folders
    /// report per completed file via the status line).
    var downloadProgress: [String: Double] = [:]
    var downloading: Set<String> = []
    var downloadStatus = ""
    private let drive: DriveClient
    private let addressKeys: [KeyringCache.UnlockedKey]
    private let activity: TransferActivityStore?

    init(sessions: SessionManager, addressKeys: [KeyringCache.UnlockedKey], activity: TransferActivityStore? = nil) {
        drive = DriveClient(sessions: sessions)
        self.addressKeys = addressKeys
        self.activity = activity
    }

    func load() async {
        isLoading = true
        status = "Loading…"
        defer { isLoading = false }
        do {
            volumes = try await drive.listVolumes()
            let metas = try await drive.listShares()
            var out: [Section] = []
            for meta in metas {
                do {
                    out.append(try await loadShare(meta))
                } catch {
                    out.append(Section(shareID: meta.shareID, rootName: "(unavailable)",
                                       rows: [], note: UserFacingError.message(for: error)))
                }
            }
            sections = out
            let total = out.reduce(0) { $0 + $1.rows.count }
            if metas.isEmpty {
                status = "No shares found — vault may be empty or still provisioning."
            } else if total == 0 {
                status = "\(metas.count) share(s) · empty — drop files in Transfers to upload."
            } else {
                status = "\(metas.count) shares · \(total) items"
            }
        } catch {
            status = "Error: \(UserFacingError.message(for: error))"
        }
    }

    private func loadShare(_ meta: ShareMetadata) async throws -> Section {
        let share = try await drive.getShare(meta.shareID)
        let shareKeys = try DecryptChain.unlockShare(share, addressKeys: addressKeys)
        let shareCands = shareKeys.compactMap(\.candidate)
        let signers = DecryptChain.edPoints(addressKeys)
        let rootID = share.linkID ?? meta.linkID
        let root = try await drive.getLink(shareID: share.shareID, linkID: rootID)
        let rootKeys = try DecryptChain.unlockNode(
            root, parentCandidates: shareCands, signerPoints: signers)
        let rootCands = rootKeys.compactMap(\.candidate)
        let rootName = (try? DecryptChain.decryptName(root, parentCandidates: shareCands))
            ?? "(unnamed folder)"
        let kids = try await drive.listChildren(shareID: share.shareID, linkID: rootID)
        var undecryptable = 0
        let rows = kids.map { kid -> Row in
            guard let name = try? DecryptChain.decryptName(kid, parentCandidates: rootCands) else {
                undecryptable += 1
                return Row(link: kid, name: "(could not decrypt name)")
            }
            return Row(link: kid, name: name)
        }
        let note: String?
        if undecryptable > 0 {
            note = "\(undecryptable) item(s) could not be decrypted with the current keys — re-login and reload; if it persists, the items may belong to another key."
        } else {
            note = nil
        }
        return Section(shareID: share.shareID, rootName: rootName, rows: rows, note: note)
    }

    // MARK: - download (F5)

    /// Picks a local destination directory and downloads `row` (file or
    /// recursive folder) into it, preserving structure. Blocks download in
    /// parallel (DriveDownloadAdapter); each block is SHA-256-verified
    /// before decrypt; writes are atomic (.neutron-part → rename);
    /// name conflicts get ` (1)` suffixes (FileDownload).
    func pickAndDownload(row: Row, shareID: String) async {
        guard let dest = await presentDestinationPanel() else {
            // User dismissed the panel: report, never proceed, never block.
            downloadStatus = PanelIntake.downloadCancelledStatus(rowName: row.name)
            return
        }
        let scoped = dest.startAccessingSecurityScopedResource()
        await download(row: row, shareID: shareID, destination: dest)
        if scoped { dest.stopAccessingSecurityScopedResource() }
    }

    /// Non-blocking destination picker: sheet on the key window, app-modal
    /// fallback when there is no key window (e.g. app inactive). Never spins
    /// a nested runModal loop, so the MainActor stays free while the panel
    /// is up. Resolves via PanelIntake (nil = cancelled/dismissed).
    private func presentDestinationPanel() async -> URL? {
        await withCheckedContinuation { cont in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Choose download destination"
            let completion: (NSApplication.ModalResponse) -> Void = { response in
                cont.resume(returning: PanelIntake.downloadDestination(
                    responseOK: response == .OK, url: panel.url
                ))
            }
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window, completionHandler: completion)
            } else {
                panel.begin(completionHandler: completion)
            }
        }
    }

    func download(row: Row, shareID: String, destination: URL) async {
        let id = row.link.linkID
        guard !downloading.contains(id) else { return }
        downloading.insert(id)
        downloadProgress[id] = 0
        downloadStatus = "Downloading \(row.name)…"
        let recordID = activity?.downloadStarted(
            name: row.name,
            kind: row.link.isFolder ? .folder : .file,
            destination: destination
        )
        defer {
            downloading.remove(id)
            downloadProgress.removeValue(forKey: id)
        }
        do {
            let adapter = DriveDownloadAdapter(drive: drive, addressKeys: addressKeys)
            if row.link.isFolder {
                let urls = try await adapter.downloadTree(
                    shareID: shareID, linkID: id, destination: destination
                ) { [weak self] name, _, _ in
                    Task { @MainActor [weak self] in
                        self?.downloadStatus = "Downloading \(row.name)… \(name)"
                    }
                }
                downloadStatus = "Downloaded \(row.name) (\(urls.count) file(s)) → \(destination.lastPathComponent)"
                if let recordID {
                    activity?.downloadFinished(id: recordID, fileCount: urls.count, destination: destination)
                }
            } else {
                let dest = try await adapter.downloadSingleFile(
                    shareID: shareID, linkID: id, directory: destination
                ) { [weak self] done, total in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress[id] = total > 0 ? Double(done) / Double(total) : 1
                        self?.downloadStatus = "Downloading \(row.name)… \(done)/\(total) blocks"
                    }
                }
                downloadProgress[id] = 1
                downloadStatus = "Downloaded \(row.name) → \(dest.lastPathComponent)"
                if let recordID {
                    activity?.downloadFinished(id: recordID, fileCount: 1, destination: destination)
                }
            }
            // Post-operation consistency: keep the browser fresh even though
            // a download does not mutate the remote tree.
            activity?.requestBrowserRefresh()
        } catch {
            let msg = UserFacingError.message(for: error)
            downloadStatus = "Download failed (\(row.name)): \(msg)"
            if let recordID {
                activity?.downloadFailed(id: recordID, error: error)
            }
        }
    }
}
