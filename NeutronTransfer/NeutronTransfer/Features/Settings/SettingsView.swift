// Neutron Transfer — Settings scene (F7 S4.2), opened with ⌘,.
// General: the "simultaneous uploads" cap — persisted in @AppStorage and
// applied to the TransferQueue on change (the app scene's launch .task
// applies the stored value; SettingsView only exists on demand).
// About: icon, name, version + build, the 6.6 disclaimer, source link.
import AppKit
import SwiftUI

/// UserDefaults keys shared between the Settings scene and the app
/// scene's launch apply (a single home for the key string + default).
enum AppSettings {
    static let maxConcurrentUploadsKey = "maxConcurrentUploads"
    static let defaultMaxConcurrentUploads = 4
}

/// About-panel copy (spec 6.6) — shared by the App menu's About command
/// (shown in the standard panel's credits) and the Settings › About tab.
enum AboutContent {
    static let disclaimer = "Neutron Transfer is an independent, open-source app. It is not affiliated with or endorsed by Proton AG. Your password is used only to sign in and unlock your keys on this Mac — it is never stored."
    static let sourceCodeURL = URL(string: "https://github.com/errrepe/Neutron-Transfer")
}

struct SettingsView: View {
    @AppStorage(AppSettings.maxConcurrentUploadsKey)
    private var maxConcurrentUploads = AppSettings.defaultMaxConcurrentUploads
    @Environment(AppSession.self) private var session

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 440, height: 260)
    }

    private var generalTab: some View {
        Form {
            Stepper(
                "Simultaneous uploads: \(maxConcurrentUploads)",
                value: $maxConcurrentUploads,
                in: 1...8
            )
            .monospacedDigit()
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: maxConcurrentUploads) { _, newValue in
            Task { await session.queue.setMaxConcurrent(newValue) }
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("Neutron Transfer")
                .font(.title3)
                .bold()
            Text("Version \(versionString)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(AboutContent.disclaimer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
            if let url = AboutContent.sourceCodeURL {
                Link("Source Code", destination: url)
            }
            Text("MIT License")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    /// "0.1.0 (4)" — marketing version plus build number; degrades to
    /// whichever Info.plist value is present (preview hosts included).
    private var versionString: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String
        switch (version, build) {
        case let (version?, build?): return "\(version) (\(build))"
        case let (version?, nil): return version
        case let (nil, build?): return build
        case (nil, nil): return "—"
        }
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView()
        .environment(PreviewFixtures.session())
}
#endif
