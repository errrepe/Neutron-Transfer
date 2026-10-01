// Neutron Transfer — download history model (F6).
// Minimal unification: uploads stay in TransferQueue (upload-specific actor,
// NOT rewritten per F5 scope decision); downloads get a lightweight,
// UI-observable record list so the Transfers tab shows BOTH. Pure Foundation
// (Codable/Sendable) — the @Observable store lives in Features.

import Foundation

enum DownloadState: String, Codable, Sendable, Equatable {
    case downloading
    case done
    case failed
}

enum DownloadKind: String, Codable, Sendable, Equatable {
    case file
    case folder
}

/// One user-visible download (file or recursive folder). Secrets-free by
/// construction: only names, counts, destinations and error strings.
struct DownloadRecord: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var kind: DownloadKind
    var state: DownloadState
    /// Files downloaded (folders) or 1 (single file, on success).
    var fileCount: Int
    /// Local destination directory name (lastPathComponent, never full path).
    var destinationName: String?
    var errorMessage: String?
    var startedAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        kind: DownloadKind,
        state: DownloadState = .downloading,
        fileCount: Int = 0,
        destinationName: String? = nil,
        errorMessage: String? = nil,
        startedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.state = state
        self.fileCount = fileCount
        self.destinationName = destinationName
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    var stateLabel: String {
        switch state {
        case .downloading: return "Downloading"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }

    /// One-line summary for the Transfers tab (no secrets, no full paths).
    var summary: String {
        switch state {
        case .downloading:
            return kind == .folder ? "Downloading folder…" : "Downloading…"
        case .done:
            if kind == .folder {
                return "Downloaded \(fileCount) file(s)" + (destinationName.map { " → \($0)" } ?? "")
            }
            return "Downloaded" + (destinationName.map { " → \($0)" } ?? "")
        case .failed:
            return errorMessage ?? "Download failed"
        }
    }
}
