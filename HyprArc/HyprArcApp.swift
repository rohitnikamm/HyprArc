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
struct HyprArcApp: App {
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

        Window("HyprArc Settings", id: "settings") {
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
    private var permissionTimer: DispatchSourceTimer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configLoader.load()
        configLoader.startWatching()

        if AccessibilityHelper.isTrusted() {
            startServices()
        } else {
            AccessibilityHelper.requestPermission()
            startPermissionPolling()
        }
    }

    private func startServices() {
        tilingController.accessibilityGranted = true
        windowTracker.start()
        tilingController.start()
        hotkeyManager.start()
    }

    private func startPermissionPolling() {
        // Background queue so polling works even if main thread is blocked
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now() + 1, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            // Dual check: TCC API + live AX test (bypasses per-process cache)
            if AccessibilityHelper.isTrusted() || AccessibilityHelper.isAXWorking() {
                self?.permissionTimer?.cancel()
                self?.permissionTimer = nil
                Self.relaunchApp()
            }
        }
        timer.resume()
        permissionTimer = timer
    }

    /// Relaunch the app for clean AX initialization after permission is granted.
    /// macOS caches TCC state per process — a relaunch ensures fresh state.
    /// Terminates first, then a detached shell process reopens the app after 0.5s.
    /// (Opening while still running makes Launch Services activate the existing instance instead.)
    static func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5 && open \"\(bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.cancel()
        permissionTimer = nil
        hotkeyManager.stop()
        configLoader.stopWatching()
        tilingController.workspaceManager.restoreAllWindows()
        tilingController.stop()
        windowTracker.stop()
    }
}
