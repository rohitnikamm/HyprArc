import CoreGraphics
import Foundation

/// The complete configuration model for HyprArc.
struct HyprArcConfig: Equatable {
    var general = GeneralConfig()
    var gaps = GapsConfig()
    var dwindle = DwindleConfig()
    var masterStack = MasterStackConfig()
    var keybindings = KeybindingsConfig()
    var windowRules: [WindowRule] = []

    struct GeneralConfig: Equatable {
        var defaultLayout: String = "dwindle"
    }

    struct GapsConfig: Equatable {
        var inner: CGFloat = 5
        var outer: CGFloat = 10
    }

    struct DwindleConfig: Equatable {
        var defaultSplitRatio: CGFloat = 0.5
    }

    struct MasterStackConfig: Equatable {
        var masterRatio: CGFloat = 0.55
        var orientation: String = "left"
    }

    struct KeybindingsConfig: Equatable {
        /// Command name → key string (e.g. "focus-left": "opt+h").
        var bindings: [String: String] = Self.defaults

        static let defaults: [String: String] = [
            "focus-left": "opt+h",
            "focus-down": "opt+j",
            "focus-up": "opt+k",
            "focus-right": "opt+l",
            "swap-left": "opt+shift+h",
            "swap-down": "opt+shift+j",
            "swap-up": "opt+shift+k",
            "swap-right": "opt+shift+l",
            "workspace-1": "opt+1",
            "workspace-2": "opt+2",
            "workspace-3": "opt+3",
            "workspace-4": "opt+4",
            "workspace-5": "opt+5",
            "workspace-6": "opt+6",
            "workspace-7": "opt+7",
            "workspace-8": "opt+8",
            "workspace-9": "opt+9",
            "move-to-workspace-1": "opt+shift+1",
            "move-to-workspace-2": "opt+shift+2",
            "move-to-workspace-3": "opt+shift+3",
            "move-to-workspace-4": "opt+shift+4",
            "move-to-workspace-5": "opt+shift+5",
            "move-to-workspace-6": "opt+shift+6",
            "move-to-workspace-7": "opt+shift+7",
            "move-to-workspace-8": "opt+shift+8",
            "move-to-workspace-9": "opt+shift+9",
            "toggle-float": "opt+space",
            "cycle-layout": "opt+d",
            "resize-grow": "opt+equal",
            "resize-shrink": "opt+minus",
            "quit": "opt+shift+e",
        ]
    }

    struct WindowRule: Equatable, Identifiable {
        let id = UUID()
        var appID: String
        var action: String  // "float"
        var workspace: Int?  // nil = no assignment, 1-9 = target workspace

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.appID == rhs.appID && lhs.action == rhs.action && lhs.workspace == rhs.workspace
        }
    }

    /// Convert gaps config to the engine's GapConfig type.
    var gapConfig: GapConfig {
        GapConfig(inner: gaps.inner, outer: gaps.outer)
    }

    /// Default config with sensible values.
    static let `default` = HyprArcConfig()

    /// Generate a TOML string with comments for the default config file.
    static var defaultTOML: String {
        """
        # HyprArc Configuration
        # Edit this file and save — changes apply automatically.

        [general]
        # Layout algorithm: "dwindle" or "master-stack"
        default-layout = "dwindle"

        [gaps]
        # Gap between tiled windows (pixels)
        inner = 5
        # Gap at screen edges (pixels)
        outer = 10

        [dwindle]
        # Default split ratio (0.1 - 0.9)
        default-split-ratio = 0.5

        [master-stack]
        # Master area ratio (0.1 - 0.9)
        master-ratio = 0.55
        # Master area position: "left", "right", "top", "bottom"
        orientation = "left"

        [keybindings]
        # Format: command = "modifier+key"
        # Modifiers: opt, shift, cmd, ctrl
        focus-left = "opt+h"
        focus-down = "opt+j"
        focus-up = "opt+k"
        focus-right = "opt+l"
        swap-left = "opt+shift+h"
        swap-down = "opt+shift+j"
        swap-up = "opt+shift+k"
        swap-right = "opt+shift+l"
        workspace-1 = "opt+1"
        workspace-2 = "opt+2"
        workspace-3 = "opt+3"
        workspace-4 = "opt+4"
        workspace-5 = "opt+5"
        workspace-6 = "opt+6"
        workspace-7 = "opt+7"
        workspace-8 = "opt+8"
        workspace-9 = "opt+9"
        move-to-workspace-1 = "opt+shift+1"
        move-to-workspace-2 = "opt+shift+2"
        move-to-workspace-3 = "opt+shift+3"
        move-to-workspace-4 = "opt+shift+4"
        move-to-workspace-5 = "opt+shift+5"
        move-to-workspace-6 = "opt+shift+6"
        move-to-workspace-7 = "opt+shift+7"
        move-to-workspace-8 = "opt+shift+8"
        move-to-workspace-9 = "opt+shift+9"
        toggle-float = "opt+space"
        cycle-layout = "opt+d"
        resize-grow = "opt+equal"
        resize-shrink = "opt+minus"
        quit = "opt+shift+e"

        # Window rules — uncomment and customize:
        # [[window-rules]]
        # app-id = "com.spotify.client"
        # action = "float"
        # workspace = 2
        """
    }
}
