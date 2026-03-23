import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A "press to record" keybinding field with a Raycast-style popover.
/// Click the button to open a recording popover with live modifier badges.
struct KeyRecorderField: View {
    let command: String
    @ObservedObject var configLoader: ConfigLoader
    @State private var isRecording = false
    @State private var liveModifiers = ""
    @State private var errorKey: String?
    @State private var errorID = 0
    @State private var successBinding: KeyBinding?
    @State private var successID = 0

    private var currentBinding: KeyBinding? {
        let str = configLoader.config.keybindings.bindings[command]
            ?? HyprArcConfig.KeybindingsConfig.defaults[command]
            ?? ""
        return KeyBinding.parse(str)
    }

    private var displayText: String {
        currentBinding?.toDisplayString() ?? "None"
    }

    var body: some View {
        Button {
            errorKey = nil
            liveModifiers = ""
            successBinding = nil
            isRecording = true
        } label: {
            Text(displayText)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 120, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
        )
        .popover(isPresented: $isRecording, arrowEdge: .bottom) {
            RecordingPopover(
                liveModifiers: $liveModifiers,
                errorKey: $errorKey,
                errorID: $errorID,
                successBinding: $successBinding,
                successID: $successID,
                onKeyRecorded: { binding in
                    isRecordingKeybinding = false
                    DispatchQueue.main.async {
                        configLoader.config.keybindings.bindings[command] = binding.toString()
                        configLoader.save()
                    }
                    errorKey = nil
                    liveModifiers = ""
                    withAnimation(.easeInOut(duration: 0.2)) {
                        successBinding = binding
                    }
                    successID += 1
                },
                onModifiersChanged: { modString in
                    liveModifiers = modString
                },
                onCancel: {
                    isRecordingKeybinding = false
                    isRecording = false
                    liveModifiers = ""
                    errorKey = nil
                    successBinding = nil
                },
                onRejectedKey: { keyName in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        errorKey = keyName
                    }
                    errorID += 1
                }
            )
        }
    }
}

// MARK: - Recording Popover Content

private struct RecordingPopover: View {
    @Binding var liveModifiers: String
    @Binding var errorKey: String?
    @Binding var errorID: Int
    @Binding var successBinding: KeyBinding?
    @Binding var successID: Int
    var onKeyRecorded: (KeyBinding) -> Void
    var onModifiersChanged: (String) -> Void
    var onCancel: () -> Void
    var onRejectedKey: (String) -> Void

    private var hasCtrl: Bool { liveModifiers.contains("⌃") }
    private var hasOpt: Bool { liveModifiers.contains("⌥") }
    private var hasShift: Bool { liveModifiers.contains("⇧") }
    private var hasCmd: Bool { liveModifiers.contains("⌘") }
    private var hasAnyModifier: Bool { !liveModifiers.isEmpty }

    var body: some View {
        VStack(spacing: 8) {
            if let binding = successBinding {
                // Success state: green badges + message
                HStack(spacing: 6) {
                    if binding.modifiers.control { successBadge("⌃") }
                    if binding.modifiers.option { successBadge("⌥") }
                    if binding.modifiers.shift { successBadge("⇧") }
                    if binding.modifiers.command { successBadge("⌘") }
                    successBadge(keyCodeToName[binding.keyCode]?.uppercased() ?? "?")
                }

                Text("Your new hotkey is set!")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else if let rejectedKey = errorKey {
                // Error state: rejected key badge + message
                errorBadge(rejectedKey)

                Text("At least one modifier should be\nincluded into a hotkey.")
                    .font(.subheadline)
                    .foregroundStyle(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else if hasAnyModifier {
                // Active modifiers + key placeholder
                HStack(spacing: 6) {
                    if hasCtrl { modifierBadge("⌃", active: true) }
                    if hasOpt { modifierBadge("⌥", active: true) }
                    if hasShift { modifierBadge("⇧", active: true) }
                    if hasCmd { modifierBadge("⌘", active: true) }
                    keyPlaceholder()
                }
                .animation(.easeInOut(duration: 0.15), value: liveModifiers)

                Text("Recording\u{2026}")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Idle: all four modifier badges
                HStack(spacing: 6) {
                    modifierBadge("⌃", active: false)
                    modifierBadge("⌥", active: false)
                    modifierBadge("⇧", active: false)
                    modifierBadge("⌘", active: false)
                }

                Text("Recording\u{2026}")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(minWidth: 260, minHeight: 80)
        .background {
            if successBinding == nil {
                KeyCaptureRepresentable(
                    onKeyRecorded: onKeyRecorded,
                    onModifiersChanged: onModifiersChanged,
                    onCancel: onCancel,
                    onRejectedKey: onRejectedKey
                )
                .frame(width: 0, height: 0)
                .opacity(0)
            }
        }
        .overlay(alignment: .topTrailing) {
            if successBinding == nil {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
        .task(id: errorID) {
            guard errorKey != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                errorKey = nil
            }
        }
        .task(id: successID) {
            guard successBinding != nil else { return }
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            onCancel()
        }
    }

    private func successBadge(_ symbol: String) -> some View {
        Text(symbol)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.green)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.green.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.green.opacity(0.4), lineWidth: 1)
            )
    }

    private func errorBadge(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.red.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.red.opacity(0.9), lineWidth: 1)
            )
    }

    private func keyPlaceholder() -> some View {
        Text("_")
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
    }

    private func modifierBadge(_ symbol: String, active: Bool) -> some View {
        Text(symbol)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(active ? .primary : .tertiary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(active ? .white.opacity(0.15) : .white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(active ? .white.opacity(0.25) : .white.opacity(0.08), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.1), value: active)
    }
}

// MARK: - NSViewRepresentable for key capture

private struct KeyCaptureRepresentable: NSViewRepresentable {
    var onKeyRecorded: (KeyBinding) -> Void
    var onModifiersChanged: (String) -> Void
    var onCancel: () -> Void
    var onRejectedKey: (String) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyRecorded = onKeyRecorded
        view.onModifiersChanged = onModifiersChanged
        view.onCancel = onCancel
        view.onRejectedKey = onRejectedKey
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyRecorded = onKeyRecorded
        nsView.onModifiersChanged = onModifiersChanged
        nsView.onCancel = onCancel
        nsView.onRejectedKey = onRejectedKey
    }
}

// MARK: - NSView subclass that captures key events

private class KeyCaptureNSView: NSView {
    var onKeyRecorded: ((KeyBinding) -> Void)?
    var onModifiersChanged: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onRejectedKey: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        isRecordingKeybinding = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        isRecordingKeybinding = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags

        if keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }

        let modifiers = KeyBinding.ModifierSet(
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            command: flags.contains(.command),
            control: flags.contains(.control)
        )

        let binding = KeyBinding(keyCode: keyCode, modifiers: modifiers)

        guard binding.hasModifier else {
            if let name = keyCodeToName[keyCode] {
                onRejectedKey?(name.uppercased())
            }
            return
        }
        guard keyCodeToName[keyCode] != nil else { return }

        onKeyRecorded?(binding)
    }

    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        onModifiersChanged?(symbols)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        return true
    }
}
