// Neutron Transfer — sidebar selection model (F7 S2.1).
// Value identity for the sidebar rows; resolves to a `DriveRoot` against the
// loaded `DriveRoots` so selection survives reloads by shareID, not index.
import Foundation

enum SidebarItem: Hashable {
    case myFiles
    case photos
    case computer(shareID: String)

    /// The root this selection points at, or nil when that share is absent
    /// from the loaded catalog (e.g. a removed device share).
    func root(in roots: DriveRoots) -> DriveRoot? {
        switch self {
        case .myFiles:
            return roots.myFiles
        case .photos:
            return roots.photos
        case .computer(let shareID):
            return roots.computers.first { $0.shareID == shareID }
        }
    }
}
