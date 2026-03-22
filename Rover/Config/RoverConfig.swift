import CoreGraphics

/// The complete configuration model for Rover.
struct RoverConfig {
    var general = GeneralConfig()
    var gaps = GapsConfig()
    var dwindle = DwindleConfig()
    var masterStack = MasterStackConfig()
    var windowRules: [WindowRule] = []

    struct GeneralConfig {
        var defaultLayout: String = "dwindle"
    }

    struct GapsConfig {
        var inner: CGFloat = 5
        var outer: CGFloat = 10
    }

    struct DwindleConfig {
        var defaultSplitRatio: CGFloat = 0.5
    }

    struct MasterStackConfig {
        var masterRatio: CGFloat = 0.55
        var orientation: String = "left"
    }

    struct WindowRule {
        var appID: String
        var action: String  // "float"
    }

    /// Convert gaps config to the engine's GapConfig type.
    var gapConfig: GapConfig {
        GapConfig(inner: gaps.inner, outer: gaps.outer)
    }

    /// Default config with sensible values.
    static let `default` = RoverConfig()

    /// Generate a TOML string with comments for the default config file.
    static var defaultTOML: String {
        """
        # Rover Configuration
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

        # Window rules — uncomment and customize:
        # [[window-rules]]
        # app-id = "com.spotify.client"
        # action = "float"
        """
    }
}
