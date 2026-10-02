// Nucleon Transfer — sort and filter for drive listings.
// Sorting applies the caller's comparators, then a stable partition so
// folders always precede files. Filtering matches the display name.
import Foundation

enum DriveItemOrdering {
    /// Sorts by `comparators` (the Table column order), then partitions the
    /// result with folders first. The partition is stable: inside each group
    /// the comparator order is preserved. Empty comparators just group.
    static func sorted(
        _ items: [DriveItem],
        using comparators: [KeyPathComparator<DriveItem>]
    ) -> [DriveItem] {
        let ordered = items.sorted(using: comparators)
        return ordered.filter(\.isFolder) + ordered.filter { !$0.isFolder }
    }

    /// Name filter for the search field. Empty/whitespace queries return the
    /// input untouched; matching is case- and diacritic-insensitive
    /// (`localizedStandardContains`).
    static func filtered(_ items: [DriveItem], query: String) -> [DriveItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.name.localizedStandardContains(trimmed) }
    }
}
