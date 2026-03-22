import SwiftUI

struct MenuBarView: View {
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

            Button("Quit Rover") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(4)
        .onAppear {
            refreshAccessibilityStatus()
        }
    }

    private func refreshAccessibilityStatus() {
        accessibilityGranted = AccessibilityHelper.isTrusted()
    }
}
