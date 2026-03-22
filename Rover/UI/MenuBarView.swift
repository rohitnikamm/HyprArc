import SwiftUI

struct MenuBarView: View {
    @ObservedObject var windowTracker: WindowTracker
    @ObservedObject var tilingController: TilingController
    @State private var accessibilityGranted = AccessibilityHelper.isTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
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
                Label(
                    tilingController.isEnabled ? "Tiling: On" : "Tiling: Off",
                    systemImage: tilingController.isEnabled ? "square.grid.2x2.fill" : "square.grid.2x2"
                )
            }

            Divider()

            let tileableWindows = windowTracker.trackedWindows.values
                .filter { $0.isTileable }
                .sorted { $0.windowID < $1.windowID }

            if tileableWindows.isEmpty {
                Text("No windows detected")
                    .foregroundStyle(.secondary)
            } else {
                Text("Windows (\(tileableWindows.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(tileableWindows, id: \.windowID) { window in
                    HStack(spacing: 4) {
                        if window.windowID == windowTracker.focusedWindowID {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.caption2)
                        }

                        Text(windowLabel(for: window))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }

            Divider()

            Button("Quit Rover") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(4)
        .onAppear {
            accessibilityGranted = AccessibilityHelper.isTrusted()
        }
    }

    private func windowLabel(for window: WindowInfo) -> String {
        let app = window.bundleID?.split(separator: ".").last.map(String.init) ?? "Unknown"
        let title = window.title.isEmpty ? "Untitled" : window.title
        return "\(app): \(title)"
    }
}
