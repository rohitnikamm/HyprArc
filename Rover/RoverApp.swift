import SwiftUI

@main
struct RoverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Rover", systemImage: "square.grid.2x2") {
            MenuBarView(windowTracker: appDelegate.windowTracker)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let windowTracker = WindowTracker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AccessibilityHelper.isTrusted() {
            AccessibilityHelper.requestPermission()
        }
        windowTracker.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowTracker.stop()
    }
}
