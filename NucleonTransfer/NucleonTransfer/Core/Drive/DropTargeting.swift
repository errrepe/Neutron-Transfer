// Nucleon Transfer — where a table drop lands (B10 fix).
// A file drag over the file table resolves to ONE upload destination:
// a folder row accepts into itself; anything else (a file row, the
// table's empty area, no row under the pointer) falls back to the
// folder on screen. Pure and SwiftUI-free so the decision is
// unit-testable — the view layer only wires it to
// TableRow.dropDestination and the drop overlay's label.
import Foundation

enum DropTargeting {
    /// `hoveredItem` is the row under the pointer; `fallback` is the
    /// folder on screen (used for nil and file rows).
    static func destination(for hoveredItem: DriveItem?, fallback: DriveLocation) -> DriveLocation {
        guard let hoveredItem, hoveredItem.isFolder else { return fallback }
        return hoveredItem.location
    }
}
