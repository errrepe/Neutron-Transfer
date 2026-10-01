// Neutron Transfer — Drive browser with decrypted names (F3b chain).
// Key hierarchy per share: address keys -> share keys -> root node keys.
// Names decrypt with the PARENT keyring (root name <- share keys,
// child name <- root node keys).
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
    /// F5 download progress: linkID → 0…1 (files report per-block; folders
    /// report per completed file via the status line).
    var downloadProgress: [String: Double] = [:]
    var downloading: Set<String> = []
    var downloadStatus = ""
    private let drive: DriveClient
    private let addressKeys: [KeyringCache.UnlockedKey]

    init(sessions: SessionManager, addressKeys: [KeyringCache.UnlockedKey]) {
        drive = DriveClient(sessions: sessions)
        self.addressKeys = addressKeys
    }

    func load() async {
        status = "Loading…"
        do {
            volumes = try await drive.listVolumes()
            let metas = try await drive.listShares()
            var out: [Section] = []
            for meta in metas {
                do {
                    out.append(try await loadShare(meta))
                } catch {
                    out.append(Section(shareID: meta.shareID, rootName: "(unavailable)",
                                       rows: [], note: "\(error)"))
                }
            }
            sections = out
            let total = out.reduce(0) { $0 + $1.rows.count }
            status = "\(metas.count) shares · \(total) items"
        } catch {
            status = "Error: \(error)"
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
        let rows = kids.map { kid in
            Row(link: kid,
                name: (try? DecryptChain.decryptName(kid, parentCandidates: rootCands))
                    ?? "(could not decrypt name)")
        }
        return Section(shareID: share.shareID, rootName: rootName, rows: rows)
    }

    // MARK: - download (F5)

    /// Picks a local destination directory and downloads `row` (file or
    /// recursive folder) into it, preserving structure. Blocks download in
    /// parallel (DriveDownloadAdapter); each block is SHA-256-verified
    /// before decrypt; writes are atomic (.neutron-part → rename);
    /// name conflicts get ` (1)` suffixes (FileDownload).
    func pickAndDownload(row: Row, shareID: String) async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose download destination"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        _ = dest.startAccessingSecurityScopedResource() // held for the session
        await download(row: row, shareID: shareID, destination: dest)
    }

    func download(row: Row, shareID: String, destination: URL) async {
        let id = row.link.linkID
        guard !downloading.contains(id) else { return }
        downloading.insert(id)
        downloadProgress[id] = 0
        downloadStatus = "Downloading \(row.name)…"
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
            }
        } catch {
            downloadStatus = "Download failed (\(row.name)): \(error.localizedDescription)"
        }
    }
}
