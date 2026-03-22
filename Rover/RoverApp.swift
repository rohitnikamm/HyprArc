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
                tilingController: appDelegate.tilingController
            )
        } label: {
            MenuBarLabel(tilingController: appDelegate.tilingController)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let windowTracker = WindowTracker()
    lazy var tilingController = TilingController(windowTracker: windowTracker)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AccessibilityHelper.isTrusted() {
            AccessibilityHelper.requestPermission()
        }
        windowTracker.start()
        tilingController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tilingController.workspaceManager.restoreAllWindows()
        tilingController.stop()
        windowTracker.stop()
    }
}
