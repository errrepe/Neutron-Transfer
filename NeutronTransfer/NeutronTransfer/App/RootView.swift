// Neutron Transfer — root switch between signed-in shell and login (F7).
// Only `.signedIn` shows the app; every other phase (signedOut, signingIn,
// needsTwoFactor, unlocking) renders the login screen, which owns its own
// busy/prompt sub-states.
import SwiftUI

struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        switch session.phase {
        case .signedIn:
            LegacyMainView()
        case .signedOut, .signingIn, .needsTwoFactor, .unlocking:
            LoginView()
        }
    }
}
