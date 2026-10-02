// Nucleon Transfer — a position inside a drive tree.
// shareID + linkID is the pair every Drive endpoint needs; `name` is the
// decrypted display name carried along for headers and breadcrumbs.
import Foundation

struct DriveLocation: Hashable, Sendable, Codable {
    let shareID: String
    let linkID: String
    let name: String
}
