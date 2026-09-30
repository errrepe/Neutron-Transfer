// Neutron Transfer — third-party client, not affiliated with Proton.
import Foundation

/// Honest client identification required by Proton operational guidelines.
/// Shape: external-drive-{name}@{semver}-{channel}. Never spoof web-drive/*.
enum AppVersion {
    static let headerValue = "external-drive-neutron_transfer@0.1.0-alpha"
    static let baseURL = URL(string: "https://mail.proton.me/api")!
}
