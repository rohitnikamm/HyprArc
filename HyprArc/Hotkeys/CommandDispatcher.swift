import AppKit
import Combine

/// All commands that can be triggered by hotkeys.
enum TilingCommand: Sendable {
    case focusDirection(Direction)
    case swapDirection(Direction)
    case switchWorkspace(Int)
    case moveToWorkspace(Int)
    case toggleFloat
    case cycleLayout
    case resizeSplit(CGFloat)
    case quitHyprArc
}

/// Maps key bindings to tiling commands and executes them.
@MainActor
class CommandDispatcher {
    private let tilingController: TilingController
    private let configLoader: ConfigLoader
    private var bindings: [KeyBinding: TilingCommand] = [:]
    private var cancellables: Set<AnyCancellable> = []

    /// Called when bindings change — HotkeyManager subscribes to update the event tap context.
    var onBindingsChanged: ((_ bindings: Set<KeyBinding>) -> Void)?

    /// Current set of registered key bindings (for seeding new HotkeyContext after restart).
    var currentBindings: Set<KeyBinding> { Set(bindings.keys) }

    init(tilingController: TilingController, configLoader: ConfigLoader) {
        self.tilingController = tilingController
        self.configLoader = configLoader
        loadBindings(from: configLoader.config)

        configLoader.$config
            .receive(on: DispatchQueue.main)
            .sink { [weak self] config in
                self?.loadBindings(from: config)
            }
            .store(in: &cancellables)
    }

    // MARK: - Binding Loading

    /// Rebuild bindings from config. Called on init and config changes.
    private func loadBindings(from config: HyprArcConfig) {
        bindings.removeAll()

        for (commandName, keyString) in config.keybindings.bindings {
            guard let binding = KeyBinding.parse(keyString),
                  let command = Self.commandForName(commandName) else {
                continue
            }
            bindings[binding] = command
        }

        onBindingsChanged?(Set(bindings.keys))
    }

    // MARK: - Command Name Mapping

    /// Map command name string to TilingCommand.
    static func commandForName(_ name: String) -> TilingCommand? {
        switch name {
        case "focus-left": return .focusDirection(.left)
        case "focus-down": return .focusDirection(.down)
        case "focus-up": return .focusDirection(.up)
        case "focus-right": return .focusDirection(.right)
        case "swap-left": return .swapDirection(.left)
        case "swap-down": return .swapDirection(.down)
        case "swap-up": return .swapDirection(.up)
        case "swap-right": return .swapDirection(.right)
        case "toggle-float": return .toggleFloat
        case "cycle-layout": return .cycleLayout
        case "resize-grow": return .resizeSplit(0.05)
        case "resize-shrink": return .resizeSplit(-0.05)
        case "quit": return .quitHyprArc
        default:
            // workspace-N and move-to-workspace-N
            if name.hasPrefix("workspace-"),
               let n = Int(name.dropFirst("workspace-".count)), (1...9).contains(n) {
                return .switchWorkspace(n)
            }
            if name.hasPrefix("move-to-workspace-"),
               let n = Int(name.dropFirst("move-to-workspace-".count)), (1...9).contains(n) {
                return .moveToWorkspace(n)
            }
            return nil
        }
    }

    /// All known command names in display order.
    static let allCommandNames: [String] = [
        "focus-left", "focus-down", "focus-up", "focus-right",
        "swap-left", "swap-down", "swap-up", "swap-right",
        "workspace-1", "workspace-2", "workspace-3",
        "workspace-4", "workspace-5", "workspace-6",
        "workspace-7", "workspace-8", "workspace-9",
        "move-to-workspace-1", "move-to-workspace-2", "move-to-workspace-3",
        "move-to-workspace-4", "move-to-workspace-5", "move-to-workspace-6",
        "move-to-workspace-7", "move-to-workspace-8", "move-to-workspace-9",
        "toggle-float", "cycle-layout",
        "resize-grow", "resize-shrink",
        "quit",
    ]

    // MARK: - Dispatch

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
        case .quitHyprArc:
            NSApplication.shared.terminate(nil)
        }
    }
}
