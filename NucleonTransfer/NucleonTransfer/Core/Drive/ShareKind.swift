// Nucleon Transfer — Drive share classification.
// Typed view over the raw `Type`/`State` ints on ShareMetadata.
import Foundation

/// Kind of a Drive share, decoded from the wire `Type` int.
///
/// Values confirmed against go-proton-api `share_types.go`
/// (`ShareTypeMain = 1`, `ShareTypeStandard = 2`, `ShareTypeDevice = 3`)
/// and the Proton Drive rust SDK `src/api/share.rs` (`ShareType::Photos = 4`
/// — go-proton-api predates photos and has no constant for it); the JS SDK's
/// `convertShareTypeNumberToEnum` (internal/shares/apiService.ts) agrees and
/// reserves 5 for organization shares.
enum ShareKind: Hashable, Sendable {
    /// The user's primary volume ("My Files").
    case main
    /// Secondary/shareable share rooted inside another share.
    case standard
    /// "Computer" backup share created by a desktop client.
    case device
    /// Photos volume share.
    case photos
    /// Anything else (e.g. 5, organization shares) — kept for forward-compat.
    case unknown(Int)

    init(rawType: Int) {
        switch rawType {
        case 1: self = .main
        case 2: self = .standard
        case 3: self = .device
        case 4: self = .photos
        default: self = .unknown(rawType)
        }
    }
}

/// Raw `ShareMetadata.state` values from go-proton-api `share_types.go`:
/// `ShareStateActive = 1`, `ShareStateDeleted = 2`.
enum ShareState {
    static let active = 1
}
