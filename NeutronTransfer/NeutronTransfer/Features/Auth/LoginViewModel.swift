// Neutron Transfer — auth UI state (spike: no real login yet, bcrypt pending F2b).
import Foundation

@MainActor
@Observable
final class LoginViewModel {
    enum State: Equatable {
        case signedOut
        case needs2FA
        case signingIn
        case signedIn(uid: String)
        case error(String)
    }

    var username = ""
    var password = ""
    var totp = ""
    var state: State = .signedOut
    private let sessions = SessionManager()

    func signIn() async {
        state = .signingIn
        do {
            try await sessions.login(username: username, password: Data(password.utf8))
            // zero password copy ASAP
            password = ""
            let uid = await sessions.uid ?? ""
            state = .signedIn(uid: uid)
        } catch let e as ProtonAPIError where e == .needs2FA {
            password = ""
            state = .needs2FA
        } catch let e as ProtonAPIError where e == .bcryptNotAvailable {
            state = .error("Spike: bcrypt pending (F2b). Session/Keychain/SRP math ready.")
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func submit2FA() async {
        do {
            try await sessions.submit2FA(code: totp)
            totp = ""
            let uid = await sessions.uid ?? ""
            state = .signedIn(uid: uid)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
