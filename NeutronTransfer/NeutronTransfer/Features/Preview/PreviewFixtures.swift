// Neutron Transfer — offline sample data for SwiftUI previews (F7 S2.x).
// Pure value-type fixtures: no network, no disk, deterministic dates so
// rendered previews are stable. DEBUG-only — never ships.
#if DEBUG
import Foundation

enum PreviewFixtures {
    /// "148.48 GB of 520 GB used" — exercises the accent-tint quota bar.
    static let account = AppSession.Account(
        email: "raphael@proton.me",
        displayName: "Raphael",
        usedBytes: 148_480_000_000,
        maxBytes: 520_000_000_000
    )

    /// My Files + Photos + two device shares — every sidebar section filled.
    static let roots = DriveRoots(
        myFiles: DriveRoot(
            shareID: "share-main", rootLinkID: "link-main-root",
            volumeID: "vol-main", kind: .main, displayName: "My Files"
        ),
        photos: DriveRoot(
            shareID: "share-photos", rootLinkID: "link-photos-root",
            volumeID: "vol-photos", kind: .photos, displayName: "Photos"
        ),
        computers: [
            DriveRoot(
                shareID: "share-macbook", rootLinkID: "link-macbook-root",
                volumeID: "vol-macbook", kind: .device, displayName: "Computer 1"
            ),
            DriveRoot(
                shareID: "share-imac", rootLinkID: "link-imac-root",
                volumeID: "vol-imac", kind: .device, displayName: "Computer 2"
            ),
        ]
    )

    /// Mixed listing: folders first in spirit, varied file extensions, and
    /// one row whose name failed decryption (renders as "Encrypted Item").
    static let items: [DriveItem] = [
        DriveItem(
            id: "link-documents", shareID: "share-main", parentLinkID: "link-main-root",
            name: "Documents", isNameDecrypted: true, kind: .folder, size: 0,
            modified: Date(timeIntervalSince1970: 1_758_000_000), mimeType: nil
        ),
        DriveItem(
            id: "link-pictures", shareID: "share-main", parentLinkID: "link-main-root",
            name: "Pictures", isNameDecrypted: true, kind: .folder, size: 0,
            modified: Date(timeIntervalSince1970: 1_757_000_000), mimeType: nil
        ),
        DriveItem(
            id: "link-invoice", shareID: "share-main", parentLinkID: "link-main-root",
            name: "Invoice March.pdf", isNameDecrypted: true, kind: .file,
            size: 241_172, modified: Date(timeIntervalSince1970: 1_759_500_000),
            mimeType: "application/pdf"
        ),
        DriveItem(
            id: "link-photo", shareID: "share-main", parentLinkID: "link-main-root",
            name: "Praia do Rosa.heic", isNameDecrypted: true, kind: .file,
            size: 4_812_300, modified: Date(timeIntervalSince1970: 1_760_100_000),
            mimeType: "image/heic"
        ),
        DriveItem(
            id: "link-notes", shareID: "share-main", parentLinkID: "link-main-root",
            name: "release-notes.md", isNameDecrypted: true, kind: .file,
            size: 8_412, modified: Date(timeIntervalSince1970: 1_760_300_000),
            mimeType: "text/markdown"
        ),
        DriveItem(
            id: "link-archive", shareID: "share-main", parentLinkID: "link-main-root",
            name: "backup-2026.zip", isNameDecrypted: true, kind: .file,
            size: 1_204_002_211, modified: Date(timeIntervalSince1970: 1_758_900_000),
            mimeType: "application/zip"
        ),
        DriveItem(
            id: "link-video", shareID: "share-main", parentLinkID: "link-main-root",
            name: "keynote-draft.mov", isNameDecrypted: true, kind: .file,
            size: 822_114_050, modified: Date(timeIntervalSince1970: 1_759_000_000),
            mimeType: "video/quicktime"
        ),
        DriveItem(
            id: "link-encrypted", shareID: "share-main", parentLinkID: "link-main-root",
            name: "Encrypted Item", isNameDecrypted: false, kind: .file,
            size: 51_200, modified: Date(timeIntervalSince1970: 1_757_500_000),
            mimeType: nil
        ),
    ]

    /// Signed-in session with the fixture roots + account injected.
    /// No network (queueStoreURL nil, phase assigned, never signIn()).
    @MainActor
    static func session(
        phase: AppSession.Phase = .signedIn,
        roots: DriveRoots? = PreviewFixtures.roots,
        rootsError: String? = nil,
        account: AppSession.Account? = PreviewFixtures.account
    ) -> AppSession {
        AppSession.preview(
            phase: phase, account: account, roots: roots, rootsError: rootsError
        )
    }
}
#endif
