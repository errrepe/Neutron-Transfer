// Neutron Transfer — signed-in shell (F7 S2.1).
// NavigationSplitView: classified roots in the sidebar, folder contents in
// the detail column (placeholder text until S2.2's BrowserContainerView).
// While roots load, a spinner; on failure, a retryable unavailable view.
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
                // S2.1 placeholder — S2.2 swaps in BrowserContainerView(root:).id(root.id).
                Text(root.displayName)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Drive Locations",
                    systemImage: "externaldrive",
                    description: Text("This account has no browsable drives.")
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

    /// Falls back to the first available root so the detail column never
    /// strands on a selection whose share disappeared after a reload.
    private func selectedRoot(in roots: DriveRoots) -> DriveRoot? {
        selection?.root(in: roots) ?? roots.all.first
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
