// Neutron Transfer — one folder screen in the browser stack (F7 S2.2/S2.3).
// FolderTable plus the spec-6.4 overlay states (loading / empty / filtered
// / error), the window title + item-count subtitle, the title-menu
// breadcrumb and the Photos read-only banner. S2.3 adds the action toolbar
// (New Folder / Download / Trash / Reload), the New Folder sheet, the
// trash confirmationDialog and the action-error alert — presentation flags
// live on BrowserModel so the table's context menu can trigger them too.
// Loading kicks off in .task(id:) so revisits are cheap (cache hit in
// BrowserModel.load).
import SwiftUI

struct FolderView: View {
    let location: DriveLocation

    @Environment(BrowserModel.self) private var model

    private var state: BrowserModel.FolderState { model.state(for: location) }
    private var items: [DriveItem] { model.visibleItems(for: location) }

    var body: some View {
        @Bindable var model = model
        return FolderTable(items: items)
            .overlay { stateOverlay }
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.root.kind == .photos {
                    Label("Photos is read-only in Neutron Transfer.", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.regularMaterial)
                }
            }
            .navigationTitle(location.name)
            .navigationSubtitle(DriveFormatting.itemCount(items.count))
            .toolbarTitleMenu {
                // Finder-style: current folder first, root last.
                ForEach(model.ancestors(of: location).reversed(), id: \.self) { ancestor in
                    Button(ancestor.name) { model.pop(to: ancestor) }
                }
            }
            .toolbar {
                // Spec-6.2 order (Upload lands in S3.1): New Folder,
                // Download, Trash, Reload. All act on `model.current` —
                // the topmost FolderView owns the toolbar.
                ToolbarItem(placement: .primaryAction) {
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        model.showingNewFolder = true
                    }
                    .help("New Folder")
                    .disabled(!model.root.allowsWrites)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Download", systemImage: "arrow.down.circle") {
                        model.downloadItems(model.selection)
                    }
                    .help("Download")
                    .disabled(model.selection.isEmpty)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Move to Trash", systemImage: "trash") {
                        model.confirmingTrash = true
                    }
                    .help("Move to Trash")
                    .disabled(model.selection.isEmpty || !model.root.allowsWrites)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        Task { await model.reloadCurrent() }
                    }
                    .help("Reload")
                    .disabled(state.phase == .loading)
                }
            }
            .sheet(isPresented: $model.showingNewFolder) {
                NewFolderSheet { name in
                    try await model.createFolder(named: name)
                }
            }
            .confirmationDialog(
                "Move ^[\(model.selection.count) item](inflect: true) to Trash?",
                isPresented: $model.confirmingTrash,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive) {
                    let ids = model.selection
                    Task { await model.trashItems(ids) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can restore them from Trash in Proton Drive on the web.")
            }
            .alert(
                "Couldn’t Move to Trash",
                isPresented: Binding(
                    get: { model.actionError != nil },
                    set: { if !$0 { model.actionError = nil } }
                ),
                presenting: model.actionError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .task(id: location) {
                await model.load(location)
            }
    }

    /// Spec-6.4 states, drawn over the table. Cached rows stay visible
    /// through reloads and failed refreshes — the blocking states only
    /// appear when there is nothing on screen.
    @ViewBuilder
    private var stateOverlay: some View {
        switch state.phase {
        case .loading where state.items.isEmpty:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message) where state.items.isEmpty:
            ContentUnavailableView {
                Label("Couldn't Load Folder", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await model.load(location, force: true) }
                }
            }
        case .loaded where state.items.isEmpty:
            ContentUnavailableView(
                "This Folder Is Empty",
                systemImage: "folder",
                description: Text("Drop files here or use Upload.")
            )
        case _ where items.isEmpty && isFiltering:
            ContentUnavailableView.search(text: model.filterText)
        default:
            EmptyView()
        }
    }

    private var isFiltering: Bool {
        !model.filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
