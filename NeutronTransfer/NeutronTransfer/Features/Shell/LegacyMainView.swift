// Neutron Transfer — temporary signed-in shell (the F6 TabView), pending the
// S2.x NavigationSplitView redesign; dies in S3.2. Header shows the account
// email (was: session UID) plus a confirmed Sign Out; the legacy browser and
// queue views receive the shared AppSession services.
import SwiftUI

struct LegacyMainView: View {
    @Environment(AppSession.self) private var session
    @State private var showSignOutConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Signed in: \(session.account?.email ?? "")")
                    .font(.headline)
                Spacer()
                Button("Sign Out…") { showSignOutConfirm = true }
            }
            // Compact windows (e.g. 559x450) center the TabView pills over
            // this header: keep clearance so "Signed in" never slides
            // under Browse/Transfers.
            .padding(.top, 28)
            .frame(minHeight: 30)
            .confirmationDialog(
                "Sign out of \(session.account?.email ?? "this account")?",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task { await session.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            }
            TabView {
                // Session resolver is always set once signed in; the `??`
                // fallback only covers previews/edge rebuilds (empty caches,
                // same source — harmless).
                DriveBrowserView(
                    sessions: session.sessions, drive: session.drive,
                    addressKeys: session.addressKeys,
                    resolver: session.resolver ?? NodeKeyResolver(
                        source: session.drive, addressKeys: session.addressKeys
                    ),
                    activity: session.activity
                )
                .tabItem { Label("Browse", systemImage: "folder") }
                TransferQueueView(
                    queue: session.queue, sessions: session.sessions, drive: session.drive,
                    addressKeys: session.addressKeys,
                    resolver: session.resolver ?? NodeKeyResolver(
                        source: session.drive, addressKeys: session.addressKeys
                    ),
                    activity: session.activity
                )
                .tabItem { Label("Transfers", systemImage: "arrow.up.arrow.down.circle") }
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 320)
    }
}
