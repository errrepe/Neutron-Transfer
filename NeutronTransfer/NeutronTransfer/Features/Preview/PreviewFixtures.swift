// Nucleon Transfer — offline sample data for SwiftUI previews (F7 S2.x).
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

    /// The fixture Photos root — used by the browser previews for the
    /// read-only (and R6 empty) states. Falls back to a literal so a
    /// preview never dies on a nil fixture.
    static var photosRoot: DriveRoot {
        roots.photos ?? DriveRoot(
            shareID: "share-photos", rootLinkID: "link-photos-root",
            volumeID: "vol-photos", kind: .photos, displayName: "Photos"
        )
    }

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

    // MARK: - Transfers (S3.2)

    /// Upload jobs for the transfers panel: one mid-flight with a
    /// destination breadcrumb, one failed. `init` always starts `.queued`,
    /// so preview states are assigned after construction.
    static let uploadJobs: [TransferJob] = {
        var uploading = TransferJob(
            fileName: "keynote-draft.mov",
            relativePath: "keynote-draft.mov",
            localPath: "/tmp/keynote-draft.mov",
            shareID: "share-main",
            parentLinkID: "link-main-root",
            bytesTotal: 80_000_000
        )
        uploading.state = .uploading
        uploading.bytesDone = 12_400_000

        var failed = TransferJob(
            fileName: "big.iso",
            relativePath: "big.iso",
            localPath: "/tmp/big.iso",
            shareID: "share-main",
            parentLinkID: "link-main-root",
            bytesTotal: 4_200_000_000
        )
        failed.state = .failed
        failed.errorMessage = "Network connection lost."
        return [uploading, failed]
    }()

    /// Download records: one in flight, one completed folder, one done
    /// file — exercises every popover section but Failed.
    static let downloadRecords: [DownloadRecord] = [
        DownloadRecord(
            name: "Praia do Rosa.heic", kind: .file, state: .downloading,
            destinationName: "Downloads", progress: 0.45
        ),
        DownloadRecord(
            name: "Projects", kind: .folder, state: .done,
            fileCount: 14, destinationName: "Downloads"
        ),
        DownloadRecord(
            name: "Invoice March.pdf", kind: .file, state: .done,
            fileCount: 1, destinationName: "Downloads"
        ),
    ]

    /// A failed download for the popover's error-state preview.
    static let failedDownload = DownloadRecord(
        name: "archive.zip", kind: .file, state: .failed,
        destinationName: "Downloads",
        errorMessage: "Network connection lost. Retry…"
    )

    /// Breadcrumb lookup matching `uploadJobs` (UploadCoordinator shape).
    static var uploadDestinationNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: uploadJobs.map { ($0.id, "My Files › Projects") })
    }

    /// Reveal targets for completed fixture downloads (memory-only paths,
    /// never persisted — same rule as TransferActivityStore.revealURLs).
    static var downloadRevealURLs: [UUID: URL] {
        let done = downloadRecords.filter { $0.state == .done }
        return Dictionary(uniqueKeysWithValues: done.map {
            ($0.id, URL(fileURLWithPath: "/tmp", isDirectory: true))
        })
    }

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
