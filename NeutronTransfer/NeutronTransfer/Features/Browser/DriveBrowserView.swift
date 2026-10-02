// Neutron Transfer — read-only Drive browser view (F3b names, F6 polish:
// spinners, empty states, post-upload refresh via activity store).
import SwiftUI

struct DriveBrowserView: View {
    @State private var model: DriveBrowserViewModel
    private let activity: TransferActivityStore?

    init(sessions: SessionManager, drive: DriveClient, addressKeys: [KeyringCache.UnlockedKey], activity: TransferActivityStore? = nil) {
        model = DriveBrowserViewModel(drive: drive, addressKeys: addressKeys, activity: activity)
        self.activity = activity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Proton Drive vault").font(.headline)
                Spacer()
                if model.isLoading { ProgressView().scaleEffect(0.7) }
                Button("Reload") { Task { await model.load() } }
                    .disabled(model.isLoading)
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary)
            if !model.downloadStatus.isEmpty {
                Text(model.downloadStatus).font(.caption).foregroundStyle(.secondary)
            }
            if !model.volumes.isEmpty {
                ForEach(model.volumes, id: \.volumeID) { v in
                    Text("Used \(bytes(v.usedSpace))" + (v.maxSpace.map { " of \(bytes($0))" } ?? "") + " · \(model.sections.count) shares")
                        .font(.caption)
                }
            }
            if model.isLoading && model.sections.isEmpty {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("Loading vault…").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
            } else if model.sections.isEmpty {
                Text("No shares to show — vault may be empty or still provisioning. Use Transfers to upload.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                List {
                    ForEach(model.sections) { section in
                        SwiftUI.Section(section.rootName) {
                            if let note = section.note {
                                Text(note).font(.caption).foregroundStyle(.orange)
                            }
                            if section.rows.isEmpty {
                                Text("Empty folder — nothing here yet.")
                                    .font(.caption).foregroundStyle(.secondary)
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
                                        if let p = model.downloadProgress[row.link.linkID] {
                                            ProgressView(value: p)
                                                .frame(maxWidth: 220)
                                        }
                                    }
                                    Spacer()
                                    if model.downloading.contains(row.link.linkID) {
                                        ProgressView().scaleEffect(0.7)
                                    } else {
                                        Button("Download") {
                                            Task {
                                                await model.pickAndDownload(
                                                    row: row, shareID: section.shareID
                                                )
                                            }
                                        }
                                        .font(.caption)
                                        .help(row.link.isFolder
                                            ? "Download folder recursively"
                                            : "Download file")
                                    }
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
        .onChange(of: activity?.browserRefreshCounter ?? 0) { _, _ in
            Task { await model.load() }
        }
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    private func date(_ unix: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(unix)).formatted(date: .abbreviated, time: .shortened)
    }
}
