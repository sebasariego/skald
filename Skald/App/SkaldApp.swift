import SwiftUI

@main
struct SkaldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        TreeSitterSupport.install()
    }

    var body: some Scene {
        Window(Branding.appName, id: "main") {
            MainWindowView()
                .environment(appDelegate.workspace)
                .frame(minWidth: 720, minHeight: 440)
        }
        .defaultSize(width: 1120, height: 740)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            SkaldCommands(workspace: appDelegate.workspace)
        }

        Settings {
            SettingsView()
                .environment(appDelegate.workspace)
        }
    }
}
