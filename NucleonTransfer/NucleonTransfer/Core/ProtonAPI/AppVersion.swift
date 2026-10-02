// Nucleon Transfer — third-party client, not affiliated with Proton.
import Foundation

/// Honest client identification required by Proton's third-party rules
/// (ProtonDriveApps/sdk README, "Identify your application"): every request —
/// Drive API and storage host alike — sends `x-pm-appversion` identifying THIS
/// build. The value must accurately represent the application; spoofing or
/// masquerading as another client is forbidden and may get the build blocked.
/// Shape: external-drive-{name}@{semver}-{channel}. Never spoof web-drive/*.
enum AppVersion {
    static let headerValue = "external-drive-nucleon_transfer@0.1.0-alpha"
    static let baseURL = URL(string: "https://mail.proton.me/api")!
}
