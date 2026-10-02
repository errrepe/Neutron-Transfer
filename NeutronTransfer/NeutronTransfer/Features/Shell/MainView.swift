// Neutron Transfer — signed-in shell (F7 S2.1 + S2.2).
// NavigationSplitView: classified roots in the sidebar, BrowserContainerView
// (Table + folder navigation) in the detail column. While roots load, a
// spinner; on failure, a retryable unavailable view.
// The "Legacy Transfers" toolbar sheet keeps upload access until S3.
import SwiftUI

struct MainView: View {
    @Environment(AppSession.self) private var session
    @State private var selection: SidebarItem? = .myFiles
    @State private var showTransfers = false

    var body: some View {
        Group {
            if let roots = session.roots {
                splitView(roots: roots)
            } else if let error = session.rootsError {
                ContentUnavailableView {
                    Label("Couldn't Load Your Drive", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await session.loadRoots() } }
                }
            } else {
                ProgressView("Loading your drive…")
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .sheet(isPresented: $showTransfers) {
            // Same resolver fallback the legacy shell used: a fresh resolver
            // over the shared DriveClient — empty caches, but safe.
            TransferQueueView(
                queue: session.queue, sessions: session.sessions,
                drive: session.drive, addressKeys: session.addressKeys,
                resolver: session.resolver ?? NodeKeyResolver(
                    source: session.drive, addressKeys: session.addressKeys
                ),
                activity: session.activity
            )
        }
    }

    private func splitView(roots: DriveRoots) -> some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            if let root = selectedRoot(in: roots) {
                // One browser stack per root — .id rebuilds the model, path
                // and caches when the sidebar selection changes.
                BrowserContainerView(root: root, session: session)
                    .id(root.id)
            } else if roots.all.isEmpty {
                ContentUnavailableView(
                    "No Drive Locations",
                    systemImage: "externaldrive",
                    description: Text("This account has no browsable drives.")
                )
            } else {
                ContentUnavailableView(
                    "Select a Location",
                    systemImage: "sidebar.left"
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Legacy Transfers", systemImage: "arrow.up.arrow.down") {
                    showTransfers = true
                }
                .help("Legacy Transfers")
            }
        }
    }

    /// The root for the sidebar selection, or nil when nothing is selected
    /// (detail shows "Select a Location"). A selection whose share vanished
    /// after a reload falls back to the first root so the detail never
    /// strands.
    private func selectedRoot(in roots: DriveRoots) -> DriveRoot? {
        guard let selection else { return nil }
        return selection.root(in: roots) ?? roots.all.first
    }
}

#if DEBUG
#Preview("Light") {
    MainView()
        .environment(PreviewFixtures.session())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    MainView()
        .environment(PreviewFixtures.session())
        .preferredColorScheme(.dark)
}

#Preview("Roots Error") {
    MainView()
        .environment(PreviewFixtures.session(
            roots: nil,
            rootsError: "Network issue. Check your connection."
        ))
}
#endif
