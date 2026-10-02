// Nucleon Transfer — S1.1 pure drive-model suite (Swift Testing).
// Share catalog rules, item building, ordering/filtering, formatting.
// Fixed en_US locale for byte formatting; no network, no secrets.
import Foundation
import Testing

@testable import NucleonTransfer

// MARK: - fixtures

private func makeMeta(
    _ id: String, type: Int, state: Int = ShareState.active,
    creationTime: Int64 = 0, locked: Bool? = nil, softDeleted: Bool? = nil
) -> ShareMetadata {
    ShareMetadata(
        shareID: id, linkID: "link-\(id)", volumeID: "vol-\(id)",
        type: type, state: state, creationTime: creationTime,
        modifyTime: creationTime, locked: locked, volumeSoftDeleted: softDeleted
    )
}

private func makeLink(
    _ id: String, type: Int, name: String = "enc-name",
    size: Int64 = 0, modifyTime: Int64 = 1_700_000_000,
    mimeType: String? = nil
) -> DriveLink {
    DriveLink(
        linkID: id, parentLinkID: "root-link", type: type, name: name,
        hash: nil, size: size, state: 1, mimeType: mimeType,
        createTime: modifyTime, modifyTime: modifyTime, expirationTime: nil,
        nodeKey: nil, nodePassphrase: nil, nodePassphraseSignature: nil,
        signatureEmail: nil, xAttr: nil, fileProperties: nil, folderProperties: nil
    )
}

private func makeItem(
    _ id: String, name: String, folder: Bool = false, size: Int64 = 0
) -> DriveItem {
    DriveItem(
        id: id, shareID: "s1", parentLinkID: "root-link", name: name,
        isNameDecrypted: true, kind: folder ? .folder : .file, size: size,
        modified: .distantPast, mimeType: nil
    )
}

// MARK: - ShareKind

struct ShareKindTests {
    @Test func rawTypeMapping() {
        #expect(ShareKind(rawType: 1) == .main)
        #expect(ShareKind(rawType: 2) == .standard)
        #expect(ShareKind(rawType: 3) == .device)
        #expect(ShareKind(rawType: 4) == .photos)
    }

    @Test func unknownKeepsRawValue() {
        #expect(ShareKind(rawType: 5) == .unknown(5))
        #expect(ShareKind(rawType: 0) == .unknown(0))
        #expect(ShareKind(rawType: -1) == .unknown(-1))
    }
}

// MARK: - ShareCatalog

struct ShareCatalogTests {
    @Test func inactiveSharesDiscarded() {
        let roots = ShareCatalog.roots(from: [
            makeMeta("a", type: 1, state: 2), // deleted
            makeMeta("b", type: 1, state: 99),
            makeMeta("c", type: 1),
        ], mainShareIDs: [])
        #expect(roots.myFiles?.shareID == "c")
        #expect(roots.all.count == 1)
    }

    @Test func lockedSharesDiscarded() {
        let roots = ShareCatalog.roots(from: [
            makeMeta("a", type: 1, locked: true),
            makeMeta("b", type: 1, locked: false),
        ], mainShareIDs: [])
        #expect(roots.myFiles?.shareID == "b")
    }

    @Test func softDeletedVolumesDiscarded() {
        let roots = ShareCatalog.roots(from: [
            makeMeta("a", type: 3, softDeleted: true),
            makeMeta("b", type: 3),
        ], mainShareIDs: [])
        #expect(roots.computers.map(\.shareID) == ["b"])
    }

    @Test func mainSharePrefersVolumeReference() {
        // Two mains: the one referenced by a volume wins even when newer.
        let roots = ShareCatalog.roots(from: [
            makeMeta("old-main", type: 1, creationTime: 10),
            makeMeta("vol-main", type: 1, creationTime: 99),
        ], mainShareIDs: ["vol-main"])
        #expect(roots.myFiles?.shareID == "vol-main")
        #expect(roots.myFiles?.displayName == "My Files")
        #expect(roots.myFiles?.rootLinkID == "link-vol-main")
    }

    @Test func mainShareFallsBackToOldest() {
        // No volume reference: smallest creationTime decides.
        let roots = ShareCatalog.roots(from: [
            makeMeta("new", type: 1, creationTime: 20),
            makeMeta("old", type: 1, creationTime: 10),
        ], mainShareIDs: ["unrelated"])
        #expect(roots.myFiles?.shareID == "old")
    }

    @Test func photosRootFirstMatch() {
        let roots = ShareCatalog.roots(from: [
            makeMeta("p1", type: 4, creationTime: 5),
            makeMeta("p2", type: 4, creationTime: 1),
        ], mainShareIDs: [])
        #expect(roots.photos?.shareID == "p1")
        #expect(roots.photos?.displayName == "Photos")
        #expect(roots.photos?.allowsWrites == false)
    }

    @Test func computersOrderedAndNumbered() {
        let roots = ShareCatalog.roots(from: [
            makeMeta("c2", type: 3, creationTime: 20),
            makeMeta("c1", type: 3, creationTime: 10),
            makeMeta("c3", type: 3, creationTime: 30),
        ], mainShareIDs: [])
        #expect(roots.computers.map(\.shareID) == ["c1", "c2", "c3"])
        #expect(roots.computers.map(\.displayName) == ["Computer 1", "Computer 2", "Computer 3"])
    }

    @Test func standardAndUnknownIgnored() {
        let roots = ShareCatalog.roots(from: [
            makeMeta("std", type: 2),
            makeMeta("org", type: 5),
            makeMeta("main", type: 1),
        ], mainShareIDs: [])
        #expect(roots.all.map(\.shareID) == ["main"])
    }

    @Test func allConcatenatesInKindOrder() {
        let roots = ShareCatalog.roots(from: [
            makeMeta("dev", type: 3),
            makeMeta("main", type: 1),
            makeMeta("pho", type: 4),
        ], mainShareIDs: [])
        #expect(roots.all.map(\.kind) == [.main, .photos, .device])
    }

    @Test func allowsWritesPerKind() {
        let roots = ShareCatalog.roots(from: [
            makeMeta("main", type: 1), makeMeta("pho", type: 4), makeMeta("dev", type: 3),
        ], mainShareIDs: [])
        #expect(roots.myFiles?.allowsWrites == true)
        #expect(roots.photos?.allowsWrites == false)
        #expect(roots.computers.first?.allowsWrites == true)
    }

    @Test func emptyInputYieldsEmptyRoots() {
        let roots = ShareCatalog.roots(from: [], mainShareIDs: [])
        #expect(roots.myFiles == nil && roots.photos == nil)
        #expect(roots.computers.isEmpty && roots.all.isEmpty)
    }
}

// MARK: - DriveItem

struct DriveItemTests {
    @Test func fileItemFromLink() {
        let link = makeLink("f1", type: 2, size: 1234, modifyTime: 1_000,
                            mimeType: "text/plain")
        let item = DriveItem(link: link, shareID: "s9", decryptedName: "Notes.txt")
        #expect(item.id == "f1" && item.shareID == "s9")
        #expect(item.kind == .file && !item.isFolder)
        #expect(item.name == "Notes.txt" && item.isNameDecrypted)
        #expect(item.size == 1234)
        #expect(item.modified == Date(timeIntervalSince1970: 1_000))
        #expect(item.mimeType == "text/plain")
        #expect(item.fileExtension == "txt")
    }

    @Test func folderItemForcesSizeZero() {
        let link = makeLink("d1", type: 1, size: 777)
        let item = DriveItem(link: link, shareID: "s1", decryptedName: "Docs")
        #expect(item.isFolder && item.size == 0)
    }

    @Test func undecryptedNameGetsPlaceholder() {
        let item = DriveItem(link: makeLink("x", type: 2), shareID: "s1",
                             decryptedName: nil)
        #expect(item.name == "Encrypted Item")
        #expect(item.isNameDecrypted == false)
    }

    @Test func locationAndExtension() {
        let item = DriveItem(link: makeLink("p", type: 2), shareID: "s7",
                             decryptedName: "PHOTO.JPEG")
        #expect(item.location == DriveLocation(shareID: "s7", linkID: "p", name: "PHOTO.JPEG"))
        #expect(item.fileExtension == "jpeg")
    }
}

// MARK: - ordering + filtering

struct DriveItemOrderingTests {
    private let items = [
        makeItem("f-b", name: "b.txt"),
        makeItem("d-a", name: "a-dir", folder: true),
        makeItem("f-a", name: "a.txt"),
        makeItem("d-b", name: "b-dir", folder: true),
    ]

    @Test func foldersFirstAscending() {
        let sorted = DriveItemOrdering.sorted(items, using: [KeyPathComparator(\.name)])
        #expect(sorted.map(\.name) == ["a-dir", "b-dir", "a.txt", "b.txt"])
    }

    @Test func foldersFirstDescending() {
        let sorted = DriveItemOrdering.sorted(
            items, using: [KeyPathComparator(\.name, order: .reverse)])
        #expect(sorted.map(\.name) == ["b-dir", "a-dir", "b.txt", "a.txt"])
    }

    @Test func partitionIsStableWithoutComparators() {
        let sorted = DriveItemOrdering.sorted(items, using: [])
        // Comparator order (the input order) is preserved inside each group.
        #expect(sorted.map(\.id) == ["d-a", "d-b", "f-b", "f-a"])
    }

    @Test func filterMatchesNameCaseInsensitive() {
        let hits = DriveItemOrdering.filtered(items, query: "A.TXT")
        #expect(hits.map(\.id) == ["f-a"])
    }

    @Test func filterBlankQueryReturnsAll() {
        #expect(DriveItemOrdering.filtered(items, query: "").count == 4)
        #expect(DriveItemOrdering.filtered(items, query: "   \n").count == 4)
    }
}

// MARK: - drop targeting (B10)

struct DropTargetingTests {
    private let current = DriveLocation(shareID: "s1", linkID: "root-link", name: "My Files")

    @Test func folderRowTargetsItself() {
        let folder = makeItem("d1", name: "Docs", folder: true)
        #expect(DropTargeting.destination(for: folder, fallback: current) == folder.location)
    }

    @Test func fileRowFallsBackToCurrentFolder() {
        let file = makeItem("f1", name: "notes.txt")
        #expect(DropTargeting.destination(for: file, fallback: current) == current)
    }

    @Test func noRowUnderPointerFallsBack() {
        #expect(DropTargeting.destination(for: nil, fallback: current) == current)
    }
}

// MARK: - formatting

struct DriveFormattingTests {
    private let enUS = Locale(identifier: "en_US")

    @Test func sizeFormatsFileAndDashForFolder() {
        let file = makeItem("f", name: "clip.mov", size: 2_560_000_000)
        let dir = makeItem("d", name: "Docs", folder: true)
        #expect(DriveFormatting.size(file, locale: enUS) == "2.56 GB")
        #expect(DriveFormatting.size(dir, locale: enUS) == "—")
    }

    @Test func storageWithAndWithoutQuota() {
        #expect(DriveFormatting.storage(used: 148_480_000_000, max: 520_000_000_000,
                                        locale: enUS) == "148.48 GB of 520 GB used")
        #expect(DriveFormatting.storage(used: 148_480_000_000, max: nil,
                                        locale: enUS) == "148.48 GB used")
    }

    @Test func itemCountSingularPlural() {
        #expect(DriveFormatting.itemCount(1) == "1 item")
        #expect(DriveFormatting.itemCount(0) == "0 items")
        #expect(DriveFormatting.itemCount(42) == "42 items")
    }
}
