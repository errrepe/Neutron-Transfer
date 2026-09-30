// Neutron Transfer — minimal read-only Drive browser view (F3a).
import SwiftUI

struct DriveBrowserView: View {
    @State private var model: DriveBrowserViewModel

    init(sessions: SessionManager) {
        model = DriveBrowserViewModel(sessions: sessions)
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
                    Text("Used \(bytes(v.usedSpace))" + (v.maxSpace.map { " of \(bytes($0))" } ?? "") + " · \(model.sharesCount) shares")
                        .font(.caption)
                }
            }
            List(model.rootChildren) { link in
                HStack {
                    Image(systemName: link.isFolder ? "folder" : "doc")
                    VStack(alignment: .leading) {
                        Text(String(link.name.prefix(24)) + "…")
                            .font(.body).lineLimit(1)
                            .help(link.name)
                        Text("\(link.isFolder ? "Folder" : "File") · \(bytes(link.size)) · \(date(link.modifyTime))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Names are end-to-end encrypted; decryption lands in F3b.")
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
