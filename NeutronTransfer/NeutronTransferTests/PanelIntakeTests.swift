// Neutron Transfer — PanelIntake offline tests (Swift Testing, no AppKit).
// Covers the cancel-vs-confirm mapping behind the async sheet panels:
// cancel/dismiss never yields a destination (callers set "cancelled" status,
// never proceed, never block the MainActor).
import Foundation
import Testing

@testable import NeutronTransfer

struct PanelIntakeTests {
    @Test func downloadOKWithURLProceeds() {
        let dest = URL(fileURLWithPath: "/tmp/dl")
        #expect(PanelIntake.downloadDestination(responseOK: true, url: dest) == dest)
    }

    @Test func downloadCancelYieldsNilEvenWithStaleURL() {
        // NSOpenPanel.url may hold a stale value after cancel: response wins.
        let stale = URL(fileURLWithPath: "/tmp/stale")
        #expect(PanelIntake.downloadDestination(responseOK: false, url: stale) == nil)
    }

    @Test func downloadOKWithoutURLYieldsNil() {
        #expect(PanelIntake.downloadDestination(responseOK: true, url: nil) == nil)
    }

    @Test func downloadDismissedYieldsNil() {
        #expect(PanelIntake.downloadDestination(responseOK: false, url: nil) == nil)
    }

    @Test func downloadCancelledStatusMentionsRow() {
        let s = PanelIntake.downloadCancelledStatus(rowName: "NT-F43-FIXTURE.txt")
        #expect(s.lowercased().contains("cancelled"))
        #expect(s.contains("NT-F43-FIXTURE.txt"))
    }

    @Test func uploadOKPassesThrough() {
        let urls = [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")]
        #expect(PanelIntake.uploadURLs(responseOK: true, urls: urls) == urls)
    }

    @Test func uploadCancelIsEmptyNoop() {
        let urls = [URL(fileURLWithPath: "/tmp/a")]
        #expect(PanelIntake.uploadURLs(responseOK: false, urls: urls).isEmpty)
        #expect(PanelIntake.uploadURLs(responseOK: true, urls: []).isEmpty)
    }
}
