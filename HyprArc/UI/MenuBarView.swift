import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var windowTracker: WindowTracker
    @ObservedObject var tilingController: TilingController
    var configLoader: ConfigLoader
    @State private var accessibilityGranted = AccessibilityHelper.isTrusted()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            spacedLabel(
                accessibilityGranted ? "Accessibility: Granted" : "Accessibility: Not Granted",
                systemImage: accessibilityGranted ? "checkmark.shield.fill" : "xmark.shield.fill"
            )

            if !accessibilityGranted {
                Button("Grant Permission…") {
                    AccessibilityHelper.requestPermission()
                }
            }

            Divider()

            Button {
                tilingController.isEnabled.toggle()
            } label: {
                spacedLabel(
                    tilingController.isEnabled ? "Tiling: On" : "Tiling: Off",
                    systemImage: tilingController.isEnabled ? "square.grid.2x2.fill" : "square.grid.2x2"
                )
            }

            Button {
                tilingController.cycleLayout()
            } label: {
                spacedLabel(
                    "Layout: \(tilingController.layoutName)",
                    systemImage: tilingController.layoutName == "Dwindle" ? "arrow.trianglehead.branch" : "sidebar.left"
                )
            }

            Button {
                tilingController.configLoader.reload()
            } label: {
                spacedLabel("Reload Config", systemImage: "arrow.clockwise")
            }

            Divider()

            Text("Workspaces")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(1...9, id: \.self) { id in
                let isActive = id == tilingController.workspaceManager.activeWorkspaceID
                let workspace = tilingController.workspaceManager.workspaces[id - 1]
                let apps = uniqueApps(for: workspace)

                Button {
                    tilingController.switchToWorkspace(id)
                } label: {
                    workspaceLabel(id: id, isActive: isActive, apps: apps)
                }
            }

            Divider()

            Button {
                openWindow(id: "settings")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                spacedLabel("Settings…", systemImage: "gearshape")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                spacedLabel("Quit HyprArc", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .padding(4)
        .onAppear {
            accessibilityGranted = AccessibilityHelper.isTrusted()
        }
    }

    /// Build a label with an invisible spacer to match workspace row height.
    private func spacedLabel(_ title: String, systemImage: String) -> some View {
        Label {
            let spacer = NSImage(size: NSSize(width: 1, height: 14))
            Text(title) + Text(Image(nsImage: spacer))
        } icon: {
            Image(systemName: systemImage)
        }
    }

    /// Build a workspace label with number followed by inline app icons.
    private func workspaceLabel(id: Int, isActive: Bool, apps: [(id: String, icon: NSImage)]) -> Text {
        var result = Text(isActive ? "[\(id)]" : " \(id) ")
            .fontWeight(isActive ? .bold : .regular)

        // Invisible spacer image to normalize row height across all workspaces
        // (prevents NSMenu tracking rect misalignment when some rows have icons and others don't)
        let spacer = NSImage(size: NSSize(width: 1, height: 14))
        result = result + Text(Image(nsImage: spacer))

        for app in apps {
            let icon = retinaIcon(app.icon, size: 14)
            result = result + Text(" ") + Text(Image(nsImage: icon)).baselineOffset(-3)
        }

        return result
    }

    /// Render an icon at 2x pixel density for Retina-sharp display at the given point size.
    private func retinaIcon(_ icon: NSImage, size: CGFloat) -> NSImage {
        let pointSize = NSSize(width: size, height: size)
        let pixelSize = Int(size * 4)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize, pixelsHigh: pixelSize,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { icon.size = pointSize; return icon }

        rep.size = pointSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(in: NSRect(origin: .zero, size: pointSize))
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: pointSize)
        result.addRepresentation(rep)
        return result
    }

    /// Get deduplicated (bundleID, icon) pairs for all windows in a workspace.
    private func uniqueApps(for workspace: Workspace) -> [(id: String, icon: NSImage)] {
        var seenBundleIDs = Set<String>()
        var apps: [(id: String, icon: NSImage)] = []

        for windowID in workspace.allWindowIDs.sorted() {
            guard let bundleID = windowTracker.trackedWindows[windowID]?.bundleID,
                  !seenBundleIDs.contains(bundleID) else { continue }
            seenBundleIDs.insert(bundleID)

            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                apps.append((id: bundleID, icon: NSWorkspace.shared.icon(forFile: url.path)))
            }
        }
        return apps
    }
}
