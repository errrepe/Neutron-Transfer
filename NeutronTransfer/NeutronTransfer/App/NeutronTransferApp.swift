// Neutron Transfer — app entry point (F7 S4.2): a single main window
// (`Window`, not WindowGroup — there is exactly one drive browser), the
// menu commands (AppCommands), and the Settings scene. The launch `.task`
// applies the persisted "simultaneous uploads" cap to the TransferQueue;
// the Settings stepper writes the same key and applies on change.
import SwiftUI

@main
struct NeutronTransferApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        Window("Neutron Transfer", id: "main") {
            RootView()
                .environment(session)
                .task {
                    let stored = UserDefaults.standard.integer(
                        forKey: AppSettings.maxConcurrentUploadsKey
                    )
                    await session.queue.setMaxConcurrent(
                        stored > 0 ? stored : AppSettings.defaultMaxConcurrentUploads
                    )
                }
        }
        .defaultSize(width: 1100, height: 700)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands()
        }

        Settings {
            SettingsView()
                .environment(session)
        }
    }
}
