// Neutron Transfer — one folder screen in the browser stack (F7 S2.2).
// FolderTable plus the spec-6.4 overlay states (loading / empty / filtered
// / error), the window title + item-count subtitle, the title-menu
// breadcrumb and the Photos read-only banner. Loading kicks off in
// .task(id:) so revisits are cheap (cache hit in BrowserModel.load).
import SwiftUI

struct FolderView: View {
    let location: DriveLocation

    @Environment(BrowserModel.self) private var model

    private var state: BrowserModel.FolderState { model.state(for: location) }
    private var items: [DriveItem] { model.visibleItems(for: location) }

    var body: some View {
        FolderTable(items: items)
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
                ToolbarItem(placement: .primaryAction) {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        Task { await model.reloadCurrent() }
                    }
                    .help("Reload")
                    .disabled(state.phase == .loading)
                }
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
