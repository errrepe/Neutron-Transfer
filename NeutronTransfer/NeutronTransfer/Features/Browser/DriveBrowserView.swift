// Neutron Transfer — read-only Drive browser view (F3b: decrypted names).
import SwiftUI

struct DriveBrowserView: View {
    @State private var model: DriveBrowserViewModel

    init(sessions: SessionManager, addressKeys: [KeyringCache.UnlockedKey]) {
        model = DriveBrowserViewModel(sessions: sessions, addressKeys: addressKeys)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Proton Drive vault").font(.headline)
                Spacer()
                Button("Reload") { Task { await model.load() } }
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary)
            if !model.volumes.isEmpty {
                ForEach(model.volumes, id: \.volumeID) { v in
                    Text("Used \(bytes(v.usedSpace))" + (v.maxSpace.map { " of \(bytes($0))" } ?? "") + " · \(model.sections.count) shares")
                        .font(.caption)
                }
            }
            List {
                ForEach(model.sections) { section in
                    SwiftUI.Section(section.rootName) {
                        if let note = section.note {
                            Text(note).font(.caption).foregroundStyle(.orange)
                        }
                        ForEach(section.rows) { row in
                            HStack {
                                Image(systemName: row.link.isFolder ? "folder" : "doc")
                                VStack(alignment: .leading) {
                                    Text(row.name)
                                        .font(.body).lineLimit(1)
                                        .help(row.name)
                                    Text("\(row.link.isFolder ? "Folder" : "File") · \(bytes(row.link.size)) · \(date(row.link.modifyTime))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            Text("Names are decrypted locally; seeds never leave memory.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
        .frame(minWidth: 480, minHeight: 400)
        .task { await model.load() }
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    private func date(_ unix: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(unix)).formatted(date: .abbreviated, time: .shortened)
    }
}
