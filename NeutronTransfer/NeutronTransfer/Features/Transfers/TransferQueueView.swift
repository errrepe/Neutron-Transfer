// Neutron Transfer — unified transfers UI (F6): uploads (queue) + downloads.
// Destination = selected share root; dropped folders are recreated remotely
// parent→child before their files enqueue (TransferQueue.enqueueTree).
// Downloads report here via the shared TransferActivityStore (F5 downloader
// stays dedicated — this tab only OBSERVES both, per F5 scope decision).
import SwiftUI
import UniformTypeIdentifiers

struct TransferQueueView: View {
    @State private var model: TransferQueueViewModel
    @State private var isTargeted = false
    private let activity: TransferActivityStore?

    init(queue: TransferQueue, sessions: SessionManager, drive: DriveClient, addressKeys: [KeyringCache.UnlockedKey], resolver: NodeKeyResolver, activity: TransferActivityStore? = nil) {
        model = TransferQueueViewModel(queue: queue, sessions: sessions, drive: drive, addressKeys: addressKeys, resolver: resolver, activity: activity)
        self.activity = activity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transfers — uploads & downloads").font(.headline)
                Spacer()
                if model.isAdding || model.isLoadingShares { ProgressView().scaleEffect(0.7) }
                Button("Add files…") { Task { await model.addPanel() } }
            }
            HStack {
                Text("Destination:").font(.caption)
                Picker("Share", selection: Binding(
                    get: { model.selectedShareID ?? "" },
                    set: { model.selectedShareID = $0 }
                )) {
                    ForEach(model.shares) { s in
                        Text(s.label).tag(s.id)
                    }
                }
                .frame(maxWidth: 320)
                Button("Reload shares") { Task { await model.loadShares() } }
                    .font(.caption)
                    .disabled(model.isLoadingShares)
            }
            if model.isLoadingShares && model.shares.isEmpty {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("Loading shares…").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
            dropZone
            HStack {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.jobs.contains(where: { $0.state == .failed }) {
                    Button("Retry all failed") { Task { await model.relaunchAllFailed() } }
                        .font(.caption)
                }
            }
            if model.jobs.isEmpty {
                Text("No uploads yet — drop files or folders above, or use Add files…")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                List {
                    ForEach(model.jobs) { job in
                        jobRow(job)
                    }
                }
                .frame(minHeight: 120)
            }
            downloadsSection
            Text("Photo-type shares reject creation (2511) — upload to Drive shares.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
        .frame(minWidth: 480, minHeight: 400)
        .task { await model.start() }
    }

    @ViewBuilder
    private var downloadsSection: some View {
        HStack {
            Text("Downloads").font(.headline)
            Spacer()
            if let activity, activity.downloads.contains(where: { $0.state == .done || $0.state == .failed }) {
                Button("Clear finished") { activity.clearFinished() }
                    .font(.caption)
            }
        }
        if let activity, !activity.downloads.isEmpty {
            List {
                ForEach(activity.downloads) { rec in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: rec.kind == .folder ? "folder" : "doc")
                            Text(rec.name).font(.body).lineLimit(1).help(rec.name)
                            Spacer()
                            Text(rec.stateLabel).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(rec.summary).font(.caption).foregroundStyle(.secondary)
                        if rec.state == .downloading {
                            ProgressView().scaleEffect(0.7).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 80, maxHeight: 180)
        } else {
            Text("No downloads yet — use Browse → Download to fetch files.")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                          style: StrokeStyle(lineWidth: 2, dash: [6]))
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear))
            .frame(height: 72)
            .overlay {
                Text("Drop files or folders here — structure is preserved")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                loadDropped(providers)
                return true
            }
            .accessibilityLabel("Upload drop zone")
    }

    private func jobRow(_ job: TransferJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: job.state == .done ? "checkmark.circle" : "doc")
                VStack(alignment: .leading) {
                    Text(job.fileName).font(.body).lineLimit(1).help(job.fileName)
                    Text("\(job.relativePath) · \(model.stateLabel(job.state)) · \(model.bytes(job.bytesDone)) of \(model.bytes(job.bytesTotal))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                actions(job)
            }
            if job.state == .uploading || (job.state == .paused && job.bytesDone > 0) {
                ProgressView(value: job.progress)
            }
            if let err = job.errorMessage, job.state == .failed {
                Text(UserFacingError.message(forMessage: err)).font(.caption).foregroundStyle(.orange).lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func actions(_ job: TransferJob) -> some View {
        switch job.state {
        case .queued, .uploading:
            Button("Pause") { Task { await model.pause(job.id) } }.font(.caption)
            Button("Cancel") { Task { await model.cancel(job.id) } }.font(.caption)
        case .paused:
            Button("Resume") { Task { await model.resume(job.id) } }.font(.caption)
            Button("Cancel") { Task { await model.cancel(job.id) } }.font(.caption)
        case .failed, .cancelled:
            Button("Relaunch") { Task { await model.relaunch(job.id) } }.font(.caption)
            Button("Remove") { Task { await model.remove(job.id) } }.font(.caption)
        case .done:
            Button("Remove") { Task { await model.remove(job.id) } }.font(.caption)
        }
    }

    private func loadDropped(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for p in providers {
                guard p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
                if let item = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                   let url = (item as? URL) ?? (item as? NSURL as URL?) {
                    urls.append(url)
                }
            }
            await model.add(urls: urls)
        }
    }
}
