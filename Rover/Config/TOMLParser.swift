import CoreGraphics
import Foundation

/// Lightweight TOML parser that handles the subset Rover needs:
/// key-value pairs, sections, and arrays of tables.
/// No external dependencies.
enum TOMLParser {

    /// Parse a TOML string into a RoverConfig.
    static func parse(_ toml: String) -> RoverConfig {
        var config = RoverConfig()
        var currentSection = ""

        for rawLine in toml.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if line.isEmpty || line.hasPrefix("#") { continue }

            // Section header: [section-name]
            if line.hasPrefix("[") && line.hasSuffix("]") && !line.hasPrefix("[[") {
                currentSection = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            // Array of tables: [[window-rules]]
            if line.hasPrefix("[[") && line.hasSuffix("]]") {
                currentSection = String(line.dropFirst(2).dropLast(2))
                    .trimmingCharacters(in: .whitespaces)
                if currentSection == "window-rules" {
                    config.windowRules.append(RoverConfig.WindowRule(appID: "", action: ""))
                }
                continue
            }

            // Key = value
            guard let equalsIndex = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<equalsIndex]
                .trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespaces)

            // Strip quotes from string values
            let value: String
            if rawValue.hasPrefix("\"") && rawValue.hasSuffix("\"") {
                value = String(rawValue.dropFirst().dropLast())
            } else {
                value = rawValue
            }

            // Strip inline comments
            let cleanValue = value.components(separatedBy: "#").first?
                .trimmingCharacters(in: .whitespaces) ?? value

            apply(key: key, value: cleanValue, section: currentSection, config: &config)
        }

        return config
    }

    private static func apply(
        key: String, value: String, section: String, config: inout RoverConfig
    ) {
        switch section {
        case "general":
            switch key {
            case "default-layout":
                config.general.defaultLayout = value
            default: break
            }

        case "gaps":
            switch key {
            case "inner":
                config.gaps.inner = CGFloat(Double(value) ?? 5)
            case "outer":
                config.gaps.outer = CGFloat(Double(value) ?? 10)
            default: break
            }

        case "dwindle":
            switch key {
            case "default-split-ratio":
                config.dwindle.defaultSplitRatio = CGFloat(Double(value) ?? 0.5)
            default: break
            }

        case "master-stack":
            switch key {
            case "master-ratio":
                config.masterStack.masterRatio = CGFloat(Double(value) ?? 0.55)
            case "orientation":
                config.masterStack.orientation = value
            default: break
            }

        case "keybindings":
            config.keybindings.bindings[key] = value

        case "window-rules":
            guard !config.windowRules.isEmpty else { break }
            let idx = config.windowRules.count - 1
            switch key {
            case "app-id":
                config.windowRules[idx].appID = value
            case "action":
                config.windowRules[idx].action = value
            default: break
            }

        default: break
        }
    }
}
