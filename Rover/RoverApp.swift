import SwiftUI

@main
struct RoverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Rover", systemImage: "square.grid.2x2") {
            MenuBarView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AccessibilityHelper.isTrusted() {
            AccessibilityHelper.requestPermission()
        }
    }
}
