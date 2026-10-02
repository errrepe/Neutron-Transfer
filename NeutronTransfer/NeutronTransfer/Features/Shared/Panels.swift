// Nucleon Transfer — shared NSOpenPanel presenters (F7 S2.3).
// Single home for the app's file/folder pickers so browser, transfers and
// future upload flows share ONE non-blocking pattern: sheet on the key
// window, app-modal fallback when there is no key window, never a nested
// runModal loop — the MainActor stays free while the panel is up (the
// sample /tmp/nt-sample.txt hang came from runModal on a non-key app).
// Outcomes resolve through PanelIntake (pure, unit-tested): nil/empty =
// cancelled/dismissed, callers never proceed.
import AppKit
import Foundation

@MainActor
enum Panels {
    /// Download destination picker: directories only, single selection.
    /// Returns the chosen directory on OK, nil on cancel/dismiss — the
    /// caller reports a cancelled status and never proceeds. URLs from
    /// NSOpenPanel arrive with security-scoped access already started;
    /// the CALLER owns the matching stopAccessingSecurityScopedResource.
    static func chooseDownloadFolder() async -> URL? {
        await withCheckedContinuation { cont in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Choose download destination"
            let completion: (NSApplication.ModalResponse) -> Void = { response in
                cont.resume(returning: PanelIntake.downloadDestination(
                    responseOK: response == .OK, url: panel.url
                ))
            }
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window, completionHandler: completion)
            } else {
                panel.begin(completionHandler: completion)
            }
        }
    }

    /// Upload intake picker (S3.1): `folders: false` = files only,
    /// `folders: true` = folders only — both multi-selection. Returns the
    /// confirmed URLs, or [] on cancel/dismiss (a no-op for the caller).
    /// The returned URLs carry security-scoped access already started;
    /// the caller decides how long to hold the grant.
    static func chooseUploadItems(folders: Bool) async -> [URL] {
        await withCheckedContinuation { cont in
            let panel = NSOpenPanel()
            panel.canChooseFiles = !folders
            panel.canChooseDirectories = folders
            panel.allowsMultipleSelection = true
            panel.canCreateDirectories = false
            panel.prompt = "Upload"
            let completion: (NSApplication.ModalResponse) -> Void = { response in
                cont.resume(returning: PanelIntake.uploadURLs(
                    responseOK: response == .OK, urls: panel.urls
                ))
            }
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window, completionHandler: completion)
            } else {
                panel.begin(completionHandler: completion)
            }
        }
    }
}
