// Neutron Transfer — system file icons for browser rows (F7 S2.2).
// NSWorkspace resolves the Finder icon for the item's content type
// (folder → .folder, files → UTType from the name extension, .data
// fallback). Icons are cached per extension — a folder listing reuses a
// handful of lookups instead of hitting NSWorkspace per row.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum FileIconCache {
    private static var icons: [String: NSImage] = [:]
    private static var folderIcon: NSImage?

    static func icon(for item: DriveItem) -> NSImage {
        icon(forName: item.name, isFolder: item.isFolder)
    }

    /// Icon for a bare file name — the transfers popover has no DriveItem,
    /// only a name + folder flag (S3.2).
    static func icon(forName name: String, isFolder: Bool) -> NSImage {
        if isFolder {
            if let folderIcon { return folderIcon }
            let icon = NSWorkspace.shared.icon(for: .folder)
            folderIcon = icon
            return icon
        }
        let ext = (name as NSString).pathExtension.lowercased()
        if let cached = icons[ext] { return cached }
        let type = UTType(filenameExtension: ext) ?? .data
        let icon = NSWorkspace.shared.icon(for: type)
        icons[ext] = icon
        return icon
    }
}

/// 16×16 content-type icon for a table row.
struct FileIcon: View {
    let item: DriveItem

    var body: some View {
        Image(nsImage: FileIconCache.icon(for: item))
            .resizable()
            .frame(width: 16, height: 16)
            // Decorative: the adjacent name cell is the accessible content.
            .accessibilityHidden(true)
    }
}
