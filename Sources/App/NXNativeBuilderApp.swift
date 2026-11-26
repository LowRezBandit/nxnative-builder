import SwiftUI
import AppKit

@main
struct NXNativeBuilderApp: App {
    @State private var manager = BuildManager()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup("NXNative Builder") {
            ContentView(manager: manager)
        }
        .defaultSize(width: 1220, height: 760)
        .commands {
            CommandGroup(after: .windowSize) {
                Divider()
                Button("Reset Layout") {
                    NotificationCenter.default.post(name: .resetLayout, object: nil)
                }
            }
        }

        Settings {
            SettingsView(manager: manager)
        }
    }
}
