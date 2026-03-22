import SwiftUI

/// Dedicated view for the menu bar label so @ObservedObject
/// properly subscribes to TilingController changes.
struct MenuBarLabel: View {
    @ObservedObject var tilingController: TilingController

    var body: some View {
        Text("\(tilingController.activeWorkspaceID)")
    }
}

@main
struct RoverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                windowTracker: appDelegate.windowTracker,
                tilingController: appDelegate.tilingController,
                configLoader: appDelegate.configLoader
            )
        } label: {
            MenuBarLabel(tilingController: appDelegate.tilingController)
        }

        Window("Rover Settings", id: "settings") {
            SettingsView(configLoader: appDelegate.configLoader)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 650, height: 450)
        .defaultPosition(.center)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let windowTracker = WindowTracker()
    let configLoader = ConfigLoader()
    lazy var tilingController = TilingController(
        windowTracker: windowTracker, configLoader: configLoader)
    lazy var hotkeyManager = HotkeyManager(
        dispatcher: CommandDispatcher(tilingController: tilingController, configLoader: configLoader),
        tilingController: tilingController
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AccessibilityHelper.isTrusted() {
            AccessibilityHelper.requestPermission()
        }
        configLoader.load()
        configLoader.startWatching()
        windowTracker.start()
        tilingController.start()
        hotkeyManager.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
        configLoader.stopWatching()
        tilingController.workspaceManager.restoreAllWindows()
        tilingController.stop()
        windowTracker.stop()
    }
}
