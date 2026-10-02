// Neutron Transfer — one row in a drive listing (file or folder).
// Built from a wire DriveLink plus its decrypted name (F3b chain); pure
// value type for table/outline display.
import Foundation

struct DriveItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case folder, file }

    /// The link's `LinkID` — unique within its share.
    let id: String
    let shareID: String
    let parentLinkID: String?
    /// Decrypted name, or "Encrypted Item" when the name could not be read.
    let name: String
    let isNameDecrypted: Bool
    let kind: Kind
    /// Always 0 for folders (their wire size is ciphertext size — backlog B2).
    let size: Int64
    let modified: Date
    let mimeType: String?

    var isFolder: Bool { kind == .folder }
    var fileExtension: String { (name as NSString).pathExtension.lowercased() }
    var location: DriveLocation { .init(shareID: shareID, linkID: id, name: name) }
}

extension DriveItem {
    /// Builds a row from a wire link. `decryptedName == nil` means the F3b
    /// chain could not read the name — the row still renders, flagged.
    init(link: DriveLink, shareID: String, decryptedName: String?) {
        self.init(
            id: link.linkID,
            shareID: shareID,
            parentLinkID: link.parentLinkID,
            name: decryptedName ?? "Encrypted Item",
            isNameDecrypted: decryptedName != nil,
            kind: link.isFolder ? .folder : .file,
            size: link.isFolder ? 0 : link.size,
            modified: Date(timeIntervalSince1970: TimeInterval(link.modifyTime)),
            mimeType: link.mimeType
        )
    }
}
