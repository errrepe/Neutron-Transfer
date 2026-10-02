// Neutron Transfer — login screen (legacy layout until the S4.1 redesign).
// Third-party disclosure up front (SDK third-party rules). Credentials go to
// AppSession; the password field clears immediately — the unlock copy lives
// as zeroed-after-use Data inside AppSession.pendingPassword, never here.
import SwiftUI

struct LoginView: View {
    @Environment(AppSession.self) private var session
    @State private var username = ""
    @State private var password = ""
    @State private var totp = ""

    /// SRP or key-unlock in flight: fields stay visible but inert.
    private var isBusy: Bool {
        session.phase == .signingIn || session.phase == .unlocking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Neutron Transfer")
                .font(.title)
            Text("This is a third-party application not officially supported by Proton.")
                .font(.caption)
                .foregroundStyle(.secondary)
            switch session.phase {
            case .needsTwoFactor:
                Text("Two-factor code required").font(.headline)
                TextField("TOTP code", text: $totp)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 12) {
                    Button("Verify") {
                        let code = totp
                        Task { await session.submitTwoFactor(code: code) }
                    }
                    Button("Cancel") {
                        Task { await session.cancelTwoFactor() }
                    }
                }
            case .signedOut, .signingIn, .unlocking, .signedIn:
                TextField("Email or username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                Button(isBusy ? "Signing in…" : "Sign In") {
                    let name = username
                    let pwd = password
                    // Clear the field up front: the retained copy lives in
                    // AppSession.pendingPassword (Data, zeroed after unlock).
                    password = ""
                    Task { await session.signIn(username: name, password: pwd) }
                }
                .disabled(isBusy)
                if let error = session.loginError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 420, minHeight: 320)
    }
}

#Preview {
    LoginView()
        .environment(AppSession.preview())
}
