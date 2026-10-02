// Neutron Transfer — folder browser state for one drive root (F7 S2.2).
// Owns the NavigationStack path, a per-folder listing cache, selection,
// sort order and the filter text. All network + name decryption stays
// inside the DriveListing actor; this model only reorders and caches the
// already-decrypted rows, so no CPU work ever runs on the main executor.
// Nothing is persisted to disk — the cache dies with the view.
import Foundation

@MainActor
@Observable
final class BrowserModel {
    enum LoadPhase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    /// Cached listing for one folder, keyed by folder linkID. Old rows stay
    /// visible while `phase == .loading` so reloads never blank the table.
    struct FolderState {
        var items: [DriveItem] = []
        var phase: LoadPhase = .idle
        /// Set by `markStale` after an app operation touched the folder;
        /// the next `load` refetches instead of serving the cache.
        var isStale = false
    }

    let root: DriveRoot
    /// Synthetic location for the root folder; `name` is the classified
    /// display name ("My Files", "Photos", "Computer N") so the title and
    /// breadcrumb read like the sidebar.
    let rootLocation: DriveLocation
    /// Pushed folders — bound directly to the NavigationStack. Clears the
    /// selection on every change (forward, back, breadcrumb jump).
    var path: [DriveLocation] = [] {
        didSet { selection = [] }
    }
    /// Where the window is right now: deepest pushed folder, or the root.
    var current: DriveLocation { path.last ?? rootLocation }
    private(set) var folders: [String: FolderState] = [:] // by folder linkID
    var selection: Set<DriveItem.ID> = []
    var sortOrder: [KeyPathComparator<DriveItem>] = [
        KeyPathComparator(\.name, comparator: .localizedStandard)
    ]
    var filterText = ""

    private let session: AppSession
    /// DEBUG preview seam: when true, `load` is a no-op so seeded folder
    /// states render offline (see `BrowserModel.preview` below).
    private var previewStubbed = false

    init(root: DriveRoot, session: AppSession) {
        self.root = root
        self.session = session
        rootLocation = DriveLocation(
            shareID: root.shareID,
            linkID: root.rootLinkID,
            name: root.displayName
        )
    }

    /// Breadcrumb chain from the root down to (and including) `location`.
    /// Unknown locations degrade to root + location so the menu never
    /// renders empty.
    func ancestors(of loc: DriveLocation) -> [DriveLocation] {
        if loc == rootLocation { return [rootLocation] }
        guard let index = path.firstIndex(of: loc) else {
            return [rootLocation, loc]
        }
        return [rootLocation] + Array(path.prefix(through: index))
    }

    /// Cached state for `loc`, or an empty idle state when never loaded.
    func state(for loc: DriveLocation) -> FolderState {
        folders[loc.linkID] ?? FolderState()
    }

    /// Rows for `loc` after the search filter and the Table sort order.
    func visibleItems(for loc: DriveLocation) -> [DriveItem] {
        DriveItemOrdering.sorted(
            DriveItemOrdering.filtered(state(for: loc).items, query: filterText),
            using: sortOrder
        )
    }

    /// Fetches `loc`'s children into the cache. Skips the network when the
    /// folder is already `loaded`, unless `force` or the stale flag says the
    /// contents may have changed. Keeps the previous rows on screen while
    /// the refresh is in flight (no flicker). A `401` means the session is
    /// gone → sign out so the whole app returns to the login screen.
    func load(_ loc: DriveLocation, force: Bool = false) async {
        if previewStubbed { return }
        var state = state(for: loc)
        if state.phase == .loaded, !force, !state.isStale { return }
        state.phase = .loading
        state.isStale = false
        folders[loc.linkID] = state
        guard let listing = session.listing else {
            state.phase = .failed("Session not ready. Sign in again.")
            folders[loc.linkID] = state
            return
        }
        do {
            let items = try await listing.children(of: loc)
            // Sign-out mid-flight replaced/nilled the listing: drop the
            // result instead of showing another session's data.
            guard session.listing === listing else { return }
            state.items = items
            state.phase = .loaded
            folders[loc.linkID] = state
        } catch let error as ProtonAPIError where error == .unauthorized {
            await session.signOut(reason: "Your session expired. Sign in again.")
        } catch {
            guard session.listing === listing else { return }
            state.phase = .failed(UserFacingError.message(for: error))
            folders[loc.linkID] = state
        }
    }

    /// Primary activation (double click / Open). Folders push onto the
    /// navigation path; files request a download — wired in S2.3, a no-op
    /// for now.
    func open(_ item: DriveItem) {
        guard item.isFolder else { return }
        path.append(item.location)
    }

    /// Double-click activation on the current selection. In-place
    /// navigation can only go one way, so the first selected folder wins;
    /// files are S2.3's download hook.
    func openSelection(_ ids: Set<DriveItem.ID>) {
        for item in visibleItems(for: current) where ids.contains(item.id) {
            if item.isFolder {
                path.append(item.location)
                return
            }
        }
    }

    /// Back one level (bound to nothing yet — the NavigationStack back
    /// button already pops `path`; kept for keyboard/menu wiring).
    func goToParent() {
        if !path.isEmpty { path.removeLast() }
    }

    /// Breadcrumb jump: pops the path back to `loc` (root = pop everything).
    /// Unknown locations leave the path untouched.
    func pop(to loc: DriveLocation) {
        if loc == rootLocation {
            path.removeAll()
        } else if let index = path.lastIndex(of: loc) {
            path.removeLast(path.count - index - 1)
        }
    }

    /// Explicit user reload of the visible folder — always refetches.
    func reloadCurrent() async {
        await load(current, force: true)
    }

    /// Post-operation consistency (uploads/deletes in S2.3): flags every
    /// touched parent as stale, and refetches only if one of them is the
    /// folder on screen. Other stale folders lazily refresh on next visit.
    func markStale(parentLinkIDs: Set<String>) {
        for linkID in parentLinkIDs {
            folders[linkID]?.isStale = true
        }
        guard parentLinkIDs.contains(current.linkID) else { return }
        Task { await load(current) }
    }
}

#if DEBUG
extension BrowserModel {
    /// Preview seam: seeds the folder cache with fixture rows and freezes
    /// `load`, so every state renders offline. `.loading` + no items shows
    /// the spinner; `error` non-nil forces the retryable failure state.
    static func preview(
        root: DriveRoot = PreviewFixtures.roots.myFiles ?? DriveRoot(
            shareID: "share-main", rootLinkID: "link-main-root",
            volumeID: "vol-main", kind: .main, displayName: "My Files"
        ),
        items: [DriveItem] = PreviewFixtures.items,
        phase: LoadPhase = .loaded,
        error: String? = nil
    ) -> BrowserModel {
        let model = BrowserModel(root: root, session: PreviewFixtures.session())
        var state = FolderState()
        state.items = items
        if let error {
            state.phase = .failed(error)
        } else {
            state.phase = phase
        }
        model.folders[model.rootLocation.linkID] = state
        model.previewStubbed = true
        return model
    }
}
#endif
