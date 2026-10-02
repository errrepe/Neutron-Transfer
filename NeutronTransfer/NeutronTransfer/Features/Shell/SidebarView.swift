// Nucleon Transfer — sidebar for the signed-in shell (F7 S2.1).
// "Drive" section: My Files + Photos (when the share exists); "Computers"
// lists device shares, hidden when empty. Icons per spec 6.2; the storage
// footer sits in the bottom safe-area inset. System materials only.
import SwiftUI

struct SidebarView: View {
    @Environment(AppSession.self) private var session
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            if let roots = session.roots, roots.myFiles != nil || roots.photos != nil {
                Section("Drive") {
                    if roots.myFiles != nil {
                        Label("My Files", systemImage: "folder")
                            .tag(SidebarItem.myFiles)
                    }
                    if roots.photos != nil {
                        Label("Photos", systemImage: "photo.on.rectangle")
                            .tag(SidebarItem.photos)
                    }
                }
            }
            if let computers = session.roots?.computers, !computers.isEmpty {
                Section("Computers") {
                    ForEach(computers) { root in
                        Label(root.displayName, systemImage: "desktopcomputer")
                            .tag(SidebarItem.computer(shareID: root.shareID))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            StorageFooterView()
        }
    }
}

#if DEBUG
#Preview("Light") {
    @Previewable @State var selection: SidebarItem? = .myFiles
    SidebarView(selection: $selection)
        .environment(PreviewFixtures.session())
        .frame(width: 220, height: 420)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    @Previewable @State var selection: SidebarItem? = .myFiles
    SidebarView(selection: $selection)
        .environment(PreviewFixtures.session())
        .frame(width: 220, height: 420)
        .preferredColorScheme(.dark)
}
#endif
