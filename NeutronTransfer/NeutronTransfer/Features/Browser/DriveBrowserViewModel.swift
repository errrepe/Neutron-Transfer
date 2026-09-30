// Neutron Transfer — Drive browser with decrypted names (F3b chain).
// Key hierarchy per share: address keys -> share keys -> root node keys.
// Names decrypt with the PARENT keyring (root name <- share keys,
// child name <- root node keys).
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
}
