// Neutron Transfer — sidebar footer: storage quota + account/sign-out (S2.1).
// Quota bar tint escalates with occupancy (accent → orange → red) and hides
// entirely when the account has no quota. The account menu is always rendered
// so Sign Out stays reachable even if /users failed.
import SwiftUI

struct StorageFooterView: View {
    @Environment(AppSession.self) private var session
    @State private var showSignOutConfirm = false
    @State private var hasActiveTransfers = false

    /// used/max as a fraction; nil when the account reports no quota.
    private var quotaFraction: Double? {
        guard let account = session.account,
              let max = account.maxBytes, max > 0 else { return nil }
        return Double(account.usedBytes) / Double(max)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let fraction = quotaFraction {
                ProgressView(value: min(fraction, 1), total: 1)
                    .tint(quotaTint(for: fraction))
            }
            if let account = session.account {
                Text(DriveFormatting.storage(used: account.usedBytes, max: account.maxBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            accountRow
        }
        .padding(12)
        .confirmationDialog(
            hasActiveTransfers
                ? "Sign out? Active transfers will be paused."
                : "Sign out of \(session.account?.email ?? "this account")?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
        // S4.2: the App-menu "Sign Out…" command routes here so it lands
        // on this same confirmationDialog (with the active-transfers
        // warning) instead of a second, divergent flow.
        .focusedSceneValue(\.requestSignOut, beginSignOut)
    }

    private var accountRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(session.account?.displayName ?? "Account")
                    .font(.callout)
                    .lineLimit(1)
                if let email = session.account?.email, !email.isEmpty {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Menu {
                Button("Sign Out…") { beginSignOut() }
            } label: {
                Label("Account Options", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .help("Account Options")
        }
    }

    /// accent under 80%, orange under 95%, red at/above — matches spec 6.1.
    private func quotaTint(for fraction: Double) -> Color {
        if fraction < 0.8 { return .accentColor }
        if fraction < 0.95 { return .orange }
        return .red
    }

    /// Reads the queue snapshot right before confirming — the TransferQueue
    /// actor has no synchronous job-state read, so the check runs on tap
    /// (no polling). Downloads in flight count as active transfers too.
    /// `@MainActor`: published as a focusedSceneValue for the App-menu
    /// "Sign Out…" command, which invokes it from a MainActor context.
    @MainActor
    private func beginSignOut() {
        Task {
            let jobs = await session.queue.snapshot()
            hasActiveTransfers =
                jobs.contains { $0.state == .queued || $0.state == .uploading }
                || session.activity.downloads.contains { $0.state == .downloading }
            showSignOutConfirm = true
        }
    }
}

#if DEBUG
#Preview("Light") {
    StorageFooterView()
        .environment(PreviewFixtures.session())
        .frame(width: 220)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    StorageFooterView()
        .environment(PreviewFixtures.session())
        .frame(width: 220)
        .preferredColorScheme(.dark)
}
#endif
