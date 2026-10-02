// Nucleon Transfer — root switch between the signed-in shell and the auth
// flow (F7 S4.1). One screen per phase: login covers signedOut + signingIn
// (its own busy sub-state), needsTwoFactor gets the TOTP prompt, unlocking
// the key-decryption spinner — all crossfading on a short opacity.
import SwiftUI

struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ZStack {
            switch session.phase {
            case .signedIn:
                MainView()
                    .transition(.opacity)
            case .signedOut, .signingIn:
                LoginView()
                    .transition(.opacity)
            case .needsTwoFactor:
                TwoFactorView()
                    .transition(.opacity)
            case .unlocking:
                UnlockingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.phase)
        // S4.2: publish the session for app-level menu commands (Sign
        // Out, Show Transfers) — they must work even where no BrowserModel
        // is on screen (e.g. the root-load error state).
        .focusedSceneValue(\.appSession, session)
    }
}
