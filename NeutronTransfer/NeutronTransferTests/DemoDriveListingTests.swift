// Neutron Transfer — DemoDriveListing suite (Swift Testing, F7.1 R1).
// The DEBUG-only demo fixture runs under `swift test` (debug config): the
// tree is deterministic, Broken Folder throws, and the expected shapes
// (Drafts ×3, Photos empty, stable IDs) hold. No network, no secrets.
import Foundation
import Testing

@testable import NeutronTransfer

#if DEBUG
struct DemoDriveListingTests {
    private let listing = DemoDriveListing()

    /// My Files root location — share/link IDs match the fixture roots.
    private var mainRoot: DriveLocation {
        DriveLocation(shareID: "share-main", linkID: "link-main-root", name: "My Files")
    }

    private func child(named name: String, of location: DriveLocation) async throws -> DriveItem {
        let items = try await listing.children(of: location)
        return try #require(items.first { $0.name == name }, "missing \(name)")
    }

    // MARK: - roots

    @Test func rootsAreThreeStableRoots() async throws {
        let roots = try await listing.roots()
        #expect(roots.myFiles?.shareID == "share-main")
        #expect(roots.myFiles?.rootLinkID == "link-main-root")
        #expect(roots.photos?.shareID == "share-photos")
        #expect(roots.computers.map(\.displayName) == ["Computer 1"])
        #expect(roots.all.count == 3)
    }

    // MARK: - determinism

    @Test func treeIsDeterministicAcrossInstances() async throws {
        let other = DemoDriveListing()
        let rootsA = try await listing.roots()
        let rootsB = try await other.roots()
        #expect(rootsA == rootsB)
        let projects = DriveLocation(
            shareID: "share-main", linkID: "demo-projects", name: "Projects"
        )
        let a = try await listing.children(of: projects)
        let b = try await other.children(of: projects)
        #expect(a == b)
        let rootA = try await listing.children(of: mainRoot)
        let rootB = try await other.children(of: mainRoot)
        #expect(rootA == rootB)
    }

    // MARK: - My Files shape

    @Test func myFilesRootShape() async throws {
        let items = try await listing.children(of: mainRoot)
        #expect(items.contains { $0.id == "demo-projects" && $0.isFolder })
        #expect(items.contains { $0.name == "Empty Folder" && $0.isFolder })
        #expect(items.contains { $0.name == "Broken Folder" && $0.isFolder })
        #expect(items.contains { $0.name == "ação ✓ unicode" && $0.isFolder })
        #expect(items.contains { $0.isNameDecrypted == false })
        #expect(items.contains { $0.name.count >= 100 })
        #expect(items.filter(\.isFolder).count == 4)
    }

    // MARK: - nested folders

    @Test func draftsHasThreeItems() async throws {
        let projects = try await child(named: "Projects", of: mainRoot)
        #expect(projects.id == "demo-projects")
        let clientA = try await child(named: "Client A", of: projects.location)
        #expect(clientA.id == "demo-client-a")
        let drafts = try await child(named: "Drafts", of: clientA.location)
        let items = try await listing.children(of: drafts.location)
        #expect(items.count == 3)
        #expect(items.allSatisfy { !$0.isFolder })
    }

    @Test func emptyFoldersReturnEmpty() async throws {
        let projects = try await child(named: "Projects", of: mainRoot)
        let clientB = try await child(named: "Client B", of: projects.location)
        #expect(try await listing.children(of: clientB.location).isEmpty)
        let empty = try await child(named: "Empty Folder", of: mainRoot)
        #expect(try await listing.children(of: empty.location).isEmpty)
    }

    @Test func brokenFolderThrowsNetworkError() async throws {
        let broken = try await child(named: "Broken Folder", of: mainRoot)
        await #expect(throws: ProtonAPIError.self) {
            try await listing.children(of: broken.location)
        }
    }

    @Test func unicodeFolderHasOneFile() async throws {
        let unicode = try await child(named: "ação ✓ unicode", of: mainRoot)
        #expect(try await listing.children(of: unicode.location).count == 1)
    }

    // MARK: - other roots

    @Test func photosIsEmpty() async throws {
        let photos = DriveLocation(
            shareID: "share-photos", linkID: "link-photos-root", name: "Photos"
        )
        #expect(try await listing.children(of: photos).isEmpty)
    }

    @Test func computerOneHasTwoFoldersAndThreeFiles() async throws {
        let mac = DriveLocation(
            shareID: "share-macbook", linkID: "link-macbook-root", name: "Computer 1"
        )
        let items = try await listing.children(of: mac)
        #expect(items.filter(\.isFolder).count == 2)
        #expect(items.filter { !$0.isFolder }.count == 3)
    }
}
#endif
