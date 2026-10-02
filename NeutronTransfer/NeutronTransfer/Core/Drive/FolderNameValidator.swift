// Neutron Transfer — new-folder name validation (F7 S2.3).
// Pure value checks for the New Folder sheet + FolderOperations: the rules
// mirror what Proton Drive clients enforce before hitting the API (the
// server answers duplicates with 2500/AlreadyExists, but bad names should
// never leave the client). NFC output: Drive name hashes are computed over
// the NFC form (FolderCreate.buildRequest applies the same normalization).
import Foundation

enum FolderNameError: Error, Equatable, Sendable {
    case empty
    case invalidCharacters // "/" or NUL
    case reserved          // "." or ".."
    case tooLong           // > 255 UTF-8 bytes

    /// Short inline message for the New Folder sheet (sentence case).
    var message: String {
        switch self {
        case .empty:
            return "Enter a folder name."
        case .invalidCharacters:
            return "Folder names can’t contain “/”."
        case .reserved:
            return "“.” and “..” are reserved names."
        case .tooLong:
            return "Folder names can’t exceed 255 bytes."
        }
    }
}

enum FolderNameValidator {
    /// Trim → reject empty / "/" or NUL / "." and ".." / >255 UTF-8 bytes;
    /// on success returns the NFC-normalized name (what the API stores and
    /// hashes). Never throws — validation is total.
    static func validate(_ raw: String) -> Result<String, FolderNameError> {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        if name.isEmpty { return .failure(.empty) }
        if name.contains("/") || name.contains("\0") { return .failure(.invalidCharacters) }
        if name == "." || name == ".." { return .failure(.reserved) }
        if name.utf8.count > 255 { return .failure(.tooLong) }
        return .success(name)
    }
}
