import SwiftUI

@main
struct RoverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Rover", systemImage: "square.grid.2x2") {
            MenuBarView(
                windowTracker: appDelegate.windowTracker,
                tilingController: appDelegate.tilingController
            )
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
        tilingController.stop()
        windowTracker.stop()
    }
}
