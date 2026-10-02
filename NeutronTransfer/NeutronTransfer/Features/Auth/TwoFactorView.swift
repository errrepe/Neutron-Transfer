// Nucleon Transfer — TOTP prompt (F7 S4.1).
// Shown while AppSession.phase == .needsTwoFactor: a six-digit code field
// (digits only, auto-submits at 6), Back cancels the whole sign-in and
// lands on the login screen.
import SwiftUI

struct TwoFactorView: View {
    @Environment(AppSession.self) private var session
    @State private var code = ""
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Two-Factor Authentication")
                .font(.title2.weight(.semibold))
            Text("Enter the 6-digit code from your authenticator app.")
                .foregroundStyle(.secondary)
            TextField(
                "Authentication code",
                text: $code,
                prompt: Text("123456")
            )
            .textContentType(.oneTimeCode)
            .textFieldStyle(.roundedBorder)
            .font(.title2.monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: 180)
            .focused($codeFocused)
            .onChange(of: code) { _, newValue in
                // Digits only, six max — then the code sends itself.
                let filtered = String(newValue.filter(\.isNumber).prefix(6))
                if filtered != newValue { code = filtered }
                if code.count == 6 { verify() }
            }
            .onSubmit(verify)
            .accessibilityLabel("Authentication code")
            HStack(spacing: 12) {
                Button("Back") {
                    Task { await session.cancelTwoFactor() }
                }
                Button("Verify", action: verify)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(code.count != 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 420, minHeight: 320)
        .task { codeFocused = true }
    }

    /// Submits the code once it is complete — AppSession flips the phase
    /// to .unlocking and RootView swaps this screen out.
    private func verify() {
        guard code.count == 6 else { return }
        let submitted = code
        Task { await session.submitTwoFactor(code: submitted) }
    }
}

#if DEBUG
#Preview("Light") {
    TwoFactorView()
        .environment(PreviewFixtures.session(phase: .needsTwoFactor))
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    TwoFactorView()
        .environment(PreviewFixtures.session(phase: .needsTwoFactor))
        .preferredColorScheme(.dark)
}
#endif
