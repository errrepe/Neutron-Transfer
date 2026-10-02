// Neutron Transfer — drive tree listing service (F7/S1.3).
// Network glue between DriveClient and NodeKeyResolver: roots() classifies
// the browsable shares (ShareCatalog), children(of:) lists a folder's active
// links with decrypted names and feeds the resolver's link cache. Name
// decryption is CPU work — it runs on this actor, never on the main thread.
import Foundation

actor DriveListing {
    private let drive: DriveClient
    private let resolver: NodeKeyResolver

    init(drive: DriveClient, resolver: NodeKeyResolver) {
        self.drive = drive
        self.resolver = resolver
    }

    /// Volumes + shares → classified roots (ShareCatalog). The volume share
    /// IDs pick the canonical main share when several `.main` rows exist.
    func roots() async throws -> DriveRoots {
        let volumes = try await drive.listVolumes()
        let mainShareIDs = Set(volumes.map(\.share.shareID))
        let metas = try await drive.listShares()
        return ShareCatalog.roots(from: metas, mainShareIDs: mainShareIDs)
    }

    /// Active children of a folder with decrypted names. Feeding the fetched
    /// links into the resolver's cache lets a later nodeKeys/folder lookup on
    /// a child resolve without a getLink. Names decrypt with the PARENT
    /// (location) keyring — a failure yields DriveItem's "Encrypted Item".
    /// `listChildren` already aggregates all pages (stops on first empty).
    func children(of location: DriveLocation) async throws -> [DriveItem] {
        let links = try await drive.listChildren(
            shareID: location.shareID, linkID: location.linkID
        ).filter(\.isActive)
        await resolver.remember(links)
        let keys = try await resolver.nodeKeys(
            shareID: location.shareID, linkID: location.linkID
        )
        let candidates = keys.compactMap(\.candidate)
        return links.map { link in
            DriveItem(
                link: link,
                shareID: location.shareID,
                decryptedName: try? DecryptChain.decryptName(
                    link, parentCandidates: candidates
                )
            )
        }
    }
}
