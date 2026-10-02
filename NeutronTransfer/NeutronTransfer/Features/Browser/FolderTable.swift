// Neutron Transfer — the drive listing as a sortable table (F7 S2.2).
// Columns per spec 6.3: Name (16×16 system icon + middle-truncated name +
// lock badge for undecrypted names), Modified (monospaced digits), Size
// (folders show "—", trailing-aligned). Selection and sort order live in
// BrowserModel; DriveItemOrdering keeps folders first under any order.
// S2.3 completes the context menu — for now only "Open" on folders.
import SwiftUI

struct FolderTable: View {
    /// The visible rows for the current folder — already filtered and
    /// sorted by BrowserModel.visibleItems(for:).
    let items: [DriveItem]

    @Environment(BrowserModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Table(items, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { item in
                HStack(spacing: 6) {
                    FileIcon(item: item)
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !item.isNameDecrypted {
                        Image(systemName: "lock.trianglebadge.exclamationmark")
                            .foregroundStyle(.secondary)
                            .help("This name couldn't be decrypted with your current keys.")
                    }
                }
            }
            .width(min: 160, ideal: 280)
            TableColumn("Modified", value: \.modified) { item in
                Text(item.modified, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            TableColumn("Size", value: \.size) { item in
                Text(DriveFormatting.size(item))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .alignment(.trailing)
        }
        .contextMenu(forSelectionType: DriveItem.ID.self) { ids in
            if items.contains(where: { ids.contains($0.id) && $0.isFolder }) {
                Button("Open") { model.openSelection(ids) }
            }
        } primaryAction: { ids in
            model.openSelection(ids)
        }
    }
}
