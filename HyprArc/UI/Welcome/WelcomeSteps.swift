import AppKit
import SwiftUI

// MARK: - Step 1: Welcome

struct WelcomeStepOne: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            }

            Text("Welcome to HyprArc")
                .font(.system(size: 28, weight: .semibold))

            Text("A tiling window manager for macOS that builds the layout for you.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            VStack(alignment: .leading, spacing: 10) {
                bullet("Pick a layout")
                bullet("Move with the keyboard")
                bullet("Organize into workspaces")
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bullet(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
            Text(text).font(.body)
        }
    }
}

// MARK: - Step 2: Core moves

struct WelcomeStepTwo: View {
    @State private var detectedFocusChange = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("The moves that matter")
                    .font(.system(size: 24, weight: .semibold))
                Text("Every shortcut is remappable in Settings → Keybindings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
                shortcutCard(keys: "⌥ H J K L", title: "Focus", subtitle: "Move focus left/down/up/right")
                shortcutCard(keys: "⌥ ⇧ H J K L", title: "Swap", subtitle: "Swap focused window with neighbor")
                shortcutCard(keys: "⌥ 1…9", title: "Workspaces", subtitle: "Jump to workspace N")
                shortcutCard(keys: "⌥ ⇧ 1…9", title: "Move", subtitle: "Move window to workspace N")
            }
            .padding(.horizontal, 40)

            HStack(spacing: 10) {
                Image(systemName: detectedFocusChange ? "checkmark.circle.fill" : "circle.dotted")
                    .foregroundStyle(detectedFocusChange ? Color.accentColor : .secondary)
                    .font(.title3)
                Text(detectedFocusChange
                     ? "Nice — focus navigation detected."
                     : "Try ⌥ H or ⌥ L in another app now.")
                    .font(.callout)
                    .foregroundStyle(detectedFocusChange ? .primary : .secondary)
            }
            .padding(.top, 8)
            .animation(.smooth(duration: 0.3), value: detectedFocusChange)

            Spacer()
        }
        .onAppear { detectedFocusChange = false }
        .onReceive(NotificationCenter.default.publisher(for: .hyprArcFocusDirectionPressed)) { _ in
            detectedFocusChange = true
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func shortcutCard(keys: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - Step 3: Three layouts

struct WelcomeStepThree: View {
    @ObservedObject var tilingController: TilingController

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("Three layouts")
                    .font(.system(size: 24, weight: .semibold))
                Text("Tap to try — or press ⌥ D to cycle.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            HStack(spacing: 14) {
                layoutCard(
                    kind: .dwindle, name: "Dwindle",
                    hint: "Recursive binary split",
                    hotkey: "⌥ T",
                    isActive: tilingController.layoutName == "Dwindle"
                ) { tilingController.setLayoutDwindle() }
                layoutCard(
                    kind: .masterStack, name: "Master-Stack",
                    hint: "One main + stack",
                    hotkey: "⌥ M",
                    isActive: tilingController.layoutName == "Master-Stack"
                ) { tilingController.setLayoutMasterStack() }
                layoutCard(
                    kind: .accordion, name: "Accordion",
                    hint: "Peek stack (MRU)",
                    hotkey: "⌥ A",
                    isActive: tilingController.layoutName == "Accordion"
                ) { tilingController.setLayoutAccordion() }
            }
            .padding(.horizontal, 30)

            Text("Currently: **\(tilingController.layoutName)**")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer()
        }
    }

    private func layoutCard(
        kind: LayoutPreviewCard.Kind, name: String,
        hint: String, hotkey: String, isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            action()
        }) {
            VStack(alignment: .leading, spacing: 8) {
                LayoutPreviewCard(kind: kind, isSelected: isActive)
                    .frame(height: 90)
                HStack {
                    Text(name).font(.headline)
                    Spacer()
                    Text(hotkey)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .animation(.smooth(duration: 0.25), value: isActive)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 4: Workspaces

struct WelcomeStepFour: View {
    @ObservedObject var tilingController: TilingController
    @State private var detectedWorkspaceChange = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Nine workspaces")
                    .font(.system(size: 24, weight: .semibold))
                Text("Instant switching. No macOS Space flicker.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            HStack(spacing: 8) {
                ForEach(1...9, id: \.self) { id in
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(id == tilingController.activeWorkspaceID
                                  ? Color.accentColor
                                  : Color.primary.opacity(0.08))
                        Text("\(id)")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(id == tilingController.activeWorkspaceID ? .white : .primary)
                    }
                    .frame(width: 48, height: 48)
                    .animation(.smooth(duration: 0.2), value: tilingController.activeWorkspaceID)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                row(keys: "⌥ 1 … 9", text: "Switch to workspace")
                row(keys: "⌥ ⇧ 1 … 9", text: "Move focused window with you")
                row(icon: "person.badge.key", text: "Auto-assign apps in Settings → Window Rules")
            }
            .padding(.horizontal, 60)
            .padding(.top, 8)

            HStack(spacing: 10) {
                Image(systemName: detectedWorkspaceChange ? "checkmark.circle.fill" : "sparkle")
                    .foregroundStyle(detectedWorkspaceChange ? Color.accentColor : .secondary)
                    .font(.title3)
                Text(detectedWorkspaceChange
                     ? "Nice — workspace switch detected."
                     : "Try ⌥ 2 now — watch the icon above shift.")
                    .font(.callout)
                    .foregroundStyle(detectedWorkspaceChange ? .primary : .secondary)
            }
            .padding(.top, 4)
            .animation(.smooth(duration: 0.3), value: detectedWorkspaceChange)

            Spacer()
        }
        .onAppear { detectedWorkspaceChange = false }
        .onReceive(NotificationCenter.default.publisher(for: .hyprArcSwitchWorkspacePressed)) { _ in
            detectedWorkspaceChange = true
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func row(keys: String? = nil, icon: String? = nil, text: String) -> some View {
        HStack(spacing: 12) {
            if let keys {
                Text(keys)
                    .font(.system(.callout, design: .monospaced))
                    .frame(width: 80, alignment: .leading)
            } else if let icon {
                Image(systemName: icon).frame(width: 80, alignment: .leading)
            }
            Text(text).font(.callout)
            Spacer()
        }
    }
}

// MARK: - Step 5: You're set

struct WelcomeStepFive: View {
    let onOpenSettings: () -> Void

    private let configPath = "~/.config/hyprarc/config.toml"

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("You're set")
                    .font(.system(size: 24, weight: .semibold))
                Text("Two ways to tune HyprArc going forward.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            HStack(spacing: 14) {
                column(
                    icon: "gearshape.fill",
                    title: "Customize",
                    body: "Open Settings to adjust gaps, layouts, keybindings, and window rules.",
                    buttonTitle: "Open Settings",
                    action: {
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        onOpenSettings()
                    }
                )
                column(
                    icon: "doc.text.fill",
                    title: "Or edit directly",
                    body: "Config lives at \(configPath). Saved changes hot-reload instantly.",
                    buttonTitle: "Show in Finder",
                    action: revealConfig
                )
            }
            .padding(.horizontal, 30)

            Text("Reopen this tour anytime from Settings → General.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Spacer()
        }
    }

    private func column(
        icon: String, title: String, body: String,
        buttonTitle: String, action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(title).font(.headline)
            Text(body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: action) { Text(buttonTitle) }
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func revealConfig() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        let expanded = (configPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        // Ensure the file exists so Finder can reveal it; ConfigLoader creates it on launch
        // but be defensive here.
        if FileManager.default.fileExists(atPath: expanded) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
