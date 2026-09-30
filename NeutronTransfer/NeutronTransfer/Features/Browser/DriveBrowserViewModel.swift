// Neutron Transfer — minimal read-only Drive browser (F3a).
// Shows volumes + root children with encrypted metadata. Name decryption is F3b.
import Foundation

@MainActor
@Observable
final class DriveBrowserViewModel {
    var volumes: [Volume] = []
    var sharesCount = 0
    var rootChildren: [DriveLink] = []
    var status = "Not loaded"
    private let drive: DriveClient

    init(sessions: SessionManager) {
        drive = DriveClient(sessions: sessions)
    }

    func load() async {
        status = "Loading…"
        do {
            volumes = try await drive.listVolumes()
            let shares = try await drive.listShares()
            sharesCount = shares.count
            guard let main = volumes.first else {
                status = "No volumes"
                return
            }
            rootChildren = try await drive.listChildren(shareID: main.share.shareID, linkID: main.share.linkID)
            let active = rootChildren.filter(\.isActive).count
            status = "\(rootChildren.count) items (\(active) active) in vault root"
        } catch {
            status = "Error: \(error)"
        }
    }
}
