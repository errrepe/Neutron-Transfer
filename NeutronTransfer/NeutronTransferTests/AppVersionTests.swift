// Neutron Transfer — AppVersion / storage-request identity tests (Swift Testing).
// Offline only: verifies the storage-host block GET identifies THIS build
// (x-pm-appversion == AppVersion.headerValue) — never a foreign client string.
import Foundation
import Testing

@testable import NeutronTransfer

struct AppVersionHeaderTests {
    @Test func headerValueIsHonestExternalDrive() {
        // ProtonDriveApps/sdk README: identify your own build honestly.
        #expect(AppVersion.headerValue.hasPrefix("external-drive-"))
        #expect(AppVersion.headerValue.contains("neutron_transfer@"))
        // Must never claim to be another client (spoofing is forbidden).
        #expect(!AppVersion.headerValue.lowercased().contains("rclone"))
    }

    @Test func bareURLBlockRequestSendsHonestAppVersion() throws {
        let api = APIClient()
        let req = try api.blockDownloadRequest(
            bareURL: "https://storage.example.com/blocks",
            token: "tok123",
            uid: "uid-abc",
            accessToken: "at-xyz"
        )
        #expect(req.httpMethod == "GET")
        #expect(req.url?.absoluteString == "https://storage.example.com/blocks")
        #expect(req.value(forHTTPHeaderField: "x-pm-appversion") == AppVersion.headerValue)
        #expect(req.value(forHTTPHeaderField: "Pm-Storage-Token") == "tok123")
        #expect(req.value(forHTTPHeaderField: "x-pm-uid") == "uid-abc")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer at-xyz")
    }

    @Test func blockURLRequestSendsHonestAppVersion() throws {
        let api = APIClient()
        let req = try api.blockDownloadURLRequest(
            url: "https://storage.example.com/blocks/embedded-token",
            token: "tok123",
            uid: "uid-abc",
            accessToken: "at-xyz"
        )
        #expect(req.httpMethod == "GET")
        #expect(req.value(forHTTPHeaderField: "x-pm-appversion") == AppVersion.headerValue)
        #expect(req.value(forHTTPHeaderField: "Pm-Storage-Token") == "tok123")
        #expect(req.value(forHTTPHeaderField: "x-pm-uid") == "uid-abc")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer at-xyz")
    }

    @Test func blockURLRequestOmitsEmptyStorageToken() throws {
        let api = APIClient()
        let req = try api.blockDownloadURLRequest(
            url: "https://storage.example.com/blocks/embedded-token",
            token: "",
            uid: "uid-abc",
            accessToken: "at-xyz"
        )
        #expect(req.value(forHTTPHeaderField: "Pm-Storage-Token") == nil)
        #expect(req.value(forHTTPHeaderField: "x-pm-appversion") == AppVersion.headerValue)
    }

    @Test func invalidBareURLThrows() {
        let api = APIClient()
        #expect(throws: ProtonAPIError.self) {
            _ = try api.blockDownloadRequest(
                bareURL: "",
                token: "t",
                uid: "u",
                accessToken: "a"
            )
        }
    }
}
