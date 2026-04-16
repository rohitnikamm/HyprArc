import SwiftUI
import Combine
import os

extension Notification.Name {
    /// Broadcast by AppDelegate once AX is granted and services are running,
    /// so the SwiftUI layer (which owns `openWindow`) can decide whether to
    /// show the first-launch onboarding.
    static let hyprArcServicesDidStart = Notification.Name("hyprArcServicesDidStart")
}

/// Dedicated view for the menu bar label so @ObservedObject
/// properly subscribes to TilingController changes. Also observes the
/// services-started notification to trigger first-launch onboarding.
struct MenuBarLabel: View {
    @ObservedObject var tilingController: TilingController

    @Environment(\.openWindow) private var openWindow
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        Text("\(tilingController.activeWorkspaceID)")
            .onReceive(NotificationCenter.default.publisher(for: .hyprArcServicesDidStart)) { _ in
                if !hasCompletedOnboarding {
                    openWindow(id: "welcome")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
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

        Window("Welcome to HyprArc", id: "welcome") {
            WelcomeView(tilingController: appDelegate.tilingController)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowLevel(.floating)
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
    private let logger = Logger(subsystem: "rohit.HyprArc", category: "AppDelegate")

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
        registerWakeNotifications()

        // Let SwiftUI-side hooks (welcome onboarding trigger) run on next tick
        // so the scene graph is fully settled before `openWindow` fires.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .hyprArcServicesDidStart, object: nil)
        }
    }

    private func registerWakeNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(handleWake),
                       name: NSWorkspace.didWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleWake),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)

        // Screen lock/unlock (power button press, screensaver) — NOT covered by
        // didWakeNotification since the Mac doesn't actually sleep.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleWake),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    /// Recover from sleep/wake: restart CGEvent tap, re-enumerate windows, retile.
    /// macOS suspends all run loops during sleep — the tap dies, AXObservers freeze,
    /// and window state goes stale. Full stop/start is the only reliable recovery.
    @objc private func handleWake(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            guard AccessibilityHelper.isTrusted() else { return }

            // Clear any in-progress mouse operations
            tilingController.endResize()

            // Restart CGEvent tap (fresh background thread + MachPort)
            hotkeyManager.stop()
            hotkeyManager.start()

            // Re-enumerate all windows (fresh AXObservers + window discovery)
            windowTracker.stop()
            windowTracker.start()

            // Reconcile tracked windows with reality and retile
            tilingController.syncAndRetile()

            // Refresh menu bar workspace icons
            tilingController.objectWillChange.send()

            logger.debug("Recovered from sleep/wake")
        }
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
