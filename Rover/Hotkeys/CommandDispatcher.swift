import AppKit

/// All commands that can be triggered by hotkeys.
enum TilingCommand: Sendable {
    case focusDirection(Direction)
    case swapDirection(Direction)
    case switchWorkspace(Int)
    case moveToWorkspace(Int)
    case toggleFloat
    case cycleLayout
    case resizeSplit(CGFloat)
    case quitRover
}

/// Maps key bindings to tiling commands and executes them.
@MainActor
class CommandDispatcher {
    private let tilingController: TilingController
    private var bindings: [KeyBinding: TilingCommand] = [:]

    init(tilingController: TilingController) {
        self.tilingController = tilingController
        registerDefaultBindings()
    }

    /// Register Hyprland-inspired default key bindings.
    private func registerDefaultBindings() {
        let opt = KeyBinding.ModifierSet.opt
        let optShift = KeyBinding.ModifierSet.optShift

        // Focus: Opt+H/J/K/L
        bindings[KeyBinding(keyCode: KeyCode.h, modifiers: opt)] = .focusDirection(.left)
        bindings[KeyBinding(keyCode: KeyCode.j, modifiers: opt)] = .focusDirection(.down)
        bindings[KeyBinding(keyCode: KeyCode.k, modifiers: opt)] = .focusDirection(.up)
        bindings[KeyBinding(keyCode: KeyCode.l, modifiers: opt)] = .focusDirection(.right)

        // Swap: Opt+Shift+H/J/K/L
        bindings[KeyBinding(keyCode: KeyCode.h, modifiers: optShift)] = .swapDirection(.left)
        bindings[KeyBinding(keyCode: KeyCode.j, modifiers: optShift)] = .swapDirection(.down)
        bindings[KeyBinding(keyCode: KeyCode.k, modifiers: optShift)] = .swapDirection(.up)
        bindings[KeyBinding(keyCode: KeyCode.l, modifiers: optShift)] = .swapDirection(.right)

        // Workspaces: Opt+1-9
        let numberKeys: [UInt16] = [
            KeyCode.one, KeyCode.two, KeyCode.three,
            KeyCode.four, KeyCode.five, KeyCode.six,
            KeyCode.seven, KeyCode.eight, KeyCode.nine,
        ]
        for (i, keyCode) in numberKeys.enumerated() {
            bindings[KeyBinding(keyCode: keyCode, modifiers: opt)] = .switchWorkspace(i + 1)
            bindings[KeyBinding(keyCode: keyCode, modifiers: optShift)] = .moveToWorkspace(i + 1)
        }

        // Float: Opt+Space
        bindings[KeyBinding(keyCode: KeyCode.space, modifiers: opt)] = .toggleFloat

        // Layout: Opt+D
        bindings[KeyBinding(keyCode: KeyCode.d, modifiers: opt)] = .cycleLayout

        // Resize: Opt+Equal/Minus
        bindings[KeyBinding(keyCode: KeyCode.equal, modifiers: opt)] = .resizeSplit(0.05)
        bindings[KeyBinding(keyCode: KeyCode.minus, modifiers: opt)] = .resizeSplit(-0.05)

        // Quit: Opt+Shift+E
        bindings[KeyBinding(keyCode: KeyCode.e, modifiers: optShift)] = .quitRover
    }

    /// Try to dispatch a key event. Returns true if the event was handled (should be swallowed).
    func dispatch(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        for (binding, command) in bindings {
            if binding.matches(keyCode: keyCode, flags: flags) {
                execute(command)
                return true
            }
        }
        return false
    }

    private func execute(_ command: TilingCommand) {
        switch command {
        case .focusDirection(let dir):
            tilingController.focusDirection(dir)
        case .swapDirection(let dir):
            tilingController.swapDirection(dir)
        case .switchWorkspace(let id):
            tilingController.switchToWorkspace(id)
        case .moveToWorkspace(let id):
            tilingController.moveWindowToWorkspace(id)
        case .toggleFloat:
            tilingController.toggleFloat()
        case .cycleLayout:
            tilingController.cycleLayout()
        case .resizeSplit(let delta):
            tilingController.resizeFocusedSplit(delta: delta)
        case .quitRover:
            NSApplication.shared.terminate(nil)
        }
    }
}
