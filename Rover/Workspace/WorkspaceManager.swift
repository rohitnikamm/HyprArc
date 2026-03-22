import AppKit
import Combine
import CoreGraphics
import os

/// Manages 9 persistent virtual workspaces.
/// Switching hides current windows offscreen and restores target workspace windows.
@MainActor
class WorkspaceManager: ObservableObject {
    @Published var activeWorkspaceID: Int = 1
    var workspaces: [Workspace]

    private let windowTracker: WindowTracker
    private let logger = Logger(subsystem: "rohit.Rover", category: "WorkspaceManager")

    /// Position window at screen's bottom-right corner. Windows keep their
    /// original size — body extends off-screen, only 1px origin on-screen.
    /// macOS won't clamp this (origin is technically on-screen).
    static var offscreenPoint: CGPoint {
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        return CGPoint(x: screen.maxX - 1, y: screen.maxY - 1)
    }

    init(windowTracker: WindowTracker, defaultEngine: @autoclosure () -> any TilingEngine = DwindleLayout()) {
        self.windowTracker = windowTracker
        self.workspaces = (1...9).map { Workspace(id: $0, engine: defaultEngine()) }
    }

    var activeWorkspace: Workspace {
        get { workspaces[activeWorkspaceID - 1] }
        set { workspaces[activeWorkspaceID - 1] = newValue }
    }

    // MARK: - Workspace Switching

    func switchToWorkspace(_ id: Int) {
        guard id != activeWorkspaceID, (1...9).contains(id) else { return }

        // Hide current workspace windows: move offscreen, keep size to preserve
        // rendered content (avoids re-render flicker on switch back)
        for windowID in activeWorkspace.allWindowIDs {
            guard let info = windowTracker.trackedWindows[windowID] else { continue }
            info.axElement.setPosition(Self.offscreenPoint)
        }

        logger.debug("Switching from workspace \(self.activeWorkspaceID) to \(id)")
        activeWorkspaceID = id
    }

    // MARK: - Move Window Between Workspaces

    func moveWindowToWorkspace(_ windowID: WindowID, workspace targetID: Int) {
        guard (1...9).contains(targetID) else { return }
        guard targetID != activeWorkspaceID else { return }

        // Remove from current workspace
        if activeWorkspace.windowIDs.contains(windowID) {
            activeWorkspace.engine.removeWindow(windowID)
            activeWorkspace.windowIDs.remove(windowID)
        } else if activeWorkspace.floatingWindowIDs.contains(windowID) {
            activeWorkspace.floatingWindowIDs.remove(windowID)
        } else {
            return // Window not in active workspace
        }

        // Add to target workspace
        workspaces[targetID - 1].engine.insertWindow(windowID, afterFocused: nil)
        workspaces[targetID - 1].windowIDs.insert(windowID)

        // Hide the window (it's now on an inactive workspace)
        if let info = windowTracker.trackedWindows[windowID] {
            info.axElement.setPosition(Self.offscreenPoint)
        }

        logger.debug("Moved window \(windowID) to workspace \(targetID)")
    }

    // MARK: - Window Ownership

    /// Find which workspace owns a given window. Returns nil if unowned.
    func workspaceOwning(_ windowID: WindowID) -> Int? {
        for ws in workspaces {
            if ws.allWindowIDs.contains(windowID) {
                return ws.id
            }
        }
        return nil
    }

    /// Remove a window from whichever workspace owns it.
    func removeWindowFromAnyWorkspace(_ windowID: WindowID) {
        for i in workspaces.indices {
            if workspaces[i].windowIDs.contains(windowID) {
                workspaces[i].engine.removeWindow(windowID)
                workspaces[i].windowIDs.remove(windowID)
                return
            }
            if workspaces[i].floatingWindowIDs.contains(windowID) {
                workspaces[i].floatingWindowIDs.remove(windowID)
                return
            }
        }
    }

    /// Restore all offscreen windows to visible positions.
    /// Called on quit so users don't lose windows.
    func restoreAllWindows() {
        let screenRect = ScreenHelper.axScreenRect()

        for ws in workspaces where ws.id != activeWorkspaceID {
            for windowID in ws.allWindowIDs {
                guard let info = windowTracker.trackedWindows[windowID] else { continue }
                // Move to center of screen so it's visible
                let centerX = screenRect.midX - 400
                let centerY = screenRect.midY - 300
                info.axElement.setPosition(CGPoint(x: centerX, y: centerY))
            }
        }
        logger.debug("Restored all offscreen windows to visible positions")
    }

    /// All window IDs across all workspaces.
    var allManagedWindowIDs: Set<WindowID> {
        var all = Set<WindowID>()
        for ws in workspaces {
            all.formUnion(ws.allWindowIDs)
        }
        return all
    }
}
