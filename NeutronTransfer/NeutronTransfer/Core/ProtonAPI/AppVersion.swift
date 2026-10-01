// Neutron Transfer — third-party client, not affiliated with Proton.
import Foundation

/// Honest client identification required by Proton operational guidelines.
/// Shape: external-drive-{name}@{semver}-{channel}. Never spoof web-drive/*.
enum AppVersion {
    static let headerValue = "external-drive-neutron_transfer@0.1.0-alpha"
    static let baseURL = URL(string: "https://mail.proton.me/api")!
    /// Storage-host gate: GET {BareURL}/storage/blocks (and the F4.3
    /// POST /drive/blocks session) is proven with the rclone client string
    /// (rclone-captured /tmp/f5ref). Drive-API metadata calls keep
    /// `headerValue` above; only the storage host uses this override.
    static let storageHeaderValue = "external-drive-rclone@1.75.1-stable"
}
