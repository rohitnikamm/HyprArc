import CoreGraphics
import Foundation

/// Serializes a HyprArcConfig back to a TOML string for writing to disk.
enum TOMLSerializer {

    static func serialize(_ config: HyprArcConfig) -> String {
        var lines: [String] = []

        lines.append("# HyprArc Configuration")
        lines.append("# Edit this file and save — changes apply automatically.")
        lines.append("")

        lines.append("[general]")
        lines.append("# Layout algorithm: \"dwindle\" or \"master-stack\"")
        lines.append("default-layout = \"\(config.general.defaultLayout)\"")
        lines.append("")

        lines.append("[gaps]")
        lines.append("# Gap between tiled windows (pixels)")
        lines.append("inner = \(formatNumber(config.gaps.inner))")
        lines.append("# Gap at screen edges (pixels)")
        lines.append("outer = \(formatNumber(config.gaps.outer))")
        lines.append("")

        lines.append("[dwindle]")
        lines.append("# Default split ratio (0.1 - 0.9)")
        lines.append("default-split-ratio = \(formatNumber(config.dwindle.defaultSplitRatio))")
        lines.append("")

        lines.append("[master-stack]")
        lines.append("# Master area ratio (0.1 - 0.9)")
        lines.append("master-ratio = \(formatNumber(config.masterStack.masterRatio))")
        lines.append("# Master area position: \"left\", \"right\", \"top\", \"bottom\"")
        lines.append("orientation = \"\(config.masterStack.orientation)\"")

        lines.append("")
        lines.append("[keybindings]")
        lines.append("# Format: command = \"modifier+key\"")
        lines.append("# Modifiers: opt, shift, cmd, ctrl")
        for key in config.keybindings.bindings.keys.sorted() {
            let value = config.keybindings.bindings[key]!
            lines.append("\(key) = \"\(value)\"")
        }

        if !config.windowRules.isEmpty {
            lines.append("")
            for rule in config.windowRules {
                lines.append("")
                lines.append("[[window-rules]]")
                lines.append("app-id = \"\(rule.appID)\"")
                if !rule.action.isEmpty {
                    lines.append("action = \"\(rule.action)\"")
                }
                if let workspace = rule.workspace {
                    lines.append("workspace = \(workspace)")
                }
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Format CGFloat cleanly: "5" not "5.0", "0.55" not "0.55000000000000004".
    private static func formatNumber(_ value: CGFloat) -> String {
        if value == value.rounded(.towardZero) && value >= 0 && value < 10000 {
            return String(Int(value))
        }
        // Use enough precision to round-trip through the parser
        let formatted = String(format: "%.2f", Double(value))
        // Strip trailing zeros: "0.50" → "0.5"
        if formatted.contains(".") {
            var result = formatted
            while result.hasSuffix("0") { result.removeLast() }
            if result.hasSuffix(".") { result.removeLast() }
            return result
        }
        return formatted
    }
}
