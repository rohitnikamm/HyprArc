import CoreGraphics
import Testing
@testable import Rover

@Suite("TOML Parser")
struct TOMLParserTests {

    @Test("Parse default config")
    func parseDefaultConfig() {
        let config = TOMLParser.parse(RoverConfig.defaultTOML)

        #expect(config.general.defaultLayout == "dwindle")
        #expect(config.gaps.inner == 5)
        #expect(config.gaps.outer == 10)
        #expect(config.dwindle.defaultSplitRatio == 0.5)
        #expect(config.masterStack.masterRatio == 0.55)
        #expect(config.masterStack.orientation == "left")
    }

    @Test("Parse custom gaps")
    func parseCustomGaps() {
        let toml = """
        [gaps]
        inner = 20
        outer = 15
        """
        let config = TOMLParser.parse(toml)

        #expect(config.gaps.inner == 20)
        #expect(config.gaps.outer == 15)
    }

    @Test("Parse master-stack config")
    func parseMasterStack() {
        let toml = """
        [master-stack]
        master-ratio = 0.7
        orientation = "right"
        """
        let config = TOMLParser.parse(toml)

        #expect(config.masterStack.masterRatio == 0.7)
        #expect(config.masterStack.orientation == "right")
    }

    @Test("Parse window rules")
    func parseWindowRules() {
        let toml = """
        [[window-rules]]
        app-id = "com.spotify.client"
        action = "float"

        [[window-rules]]
        app-id = "com.apple.systempreferences"
        action = "float"
        """
        let config = TOMLParser.parse(toml)

        #expect(config.windowRules.count == 2)
        #expect(config.windowRules[0].appID == "com.spotify.client")
        #expect(config.windowRules[0].action == "float")
        #expect(config.windowRules[1].appID == "com.apple.systempreferences")
    }

    @Test("Skip comments and blank lines")
    func skipCommentsAndBlanks() {
        let toml = """
        # This is a comment

        [gaps]
        # Another comment
        inner = 8

        outer = 12
        """
        let config = TOMLParser.parse(toml)

        #expect(config.gaps.inner == 8)
        #expect(config.gaps.outer == 12)
    }

    @Test("Missing sections use defaults")
    func missingUsesDefaults() {
        let config = TOMLParser.parse("")

        #expect(config.general.defaultLayout == "dwindle")
        #expect(config.gaps.inner == 5)
        #expect(config.gaps.outer == 10)
    }

    @Test("Partial config — only specified values change")
    func partialConfig() {
        let toml = """
        [gaps]
        inner = 0
        """
        let config = TOMLParser.parse(toml)

        #expect(config.gaps.inner == 0)
        #expect(config.gaps.outer == 10)  // Default unchanged
        #expect(config.general.defaultLayout == "dwindle")  // Default
    }

    @Test("GapConfig conversion")
    func gapConfigConversion() {
        var config = RoverConfig()
        config.gaps.inner = 15
        config.gaps.outer = 25

        let gaps = config.gapConfig
        #expect(gaps.inner == 15)
        #expect(gaps.outer == 25)
    }

    @Test("Parse window rule with workspace")
    func parseWindowRuleWithWorkspace() {
        let toml = """
        [[window-rules]]
        app-id = "com.apple.mail"
        workspace = 3
        """
        let config = TOMLParser.parse(toml)

        #expect(config.windowRules.count == 1)
        #expect(config.windowRules[0].appID == "com.apple.mail")
        #expect(config.windowRules[0].action == "")
        #expect(config.windowRules[0].workspace == 3)
    }

    @Test("Parse window rule with action and workspace")
    func parseWindowRuleWithActionAndWorkspace() {
        let toml = """
        [[window-rules]]
        app-id = "com.spotify.client"
        action = "float"
        workspace = 2
        """
        let config = TOMLParser.parse(toml)

        #expect(config.windowRules.count == 1)
        #expect(config.windowRules[0].action == "float")
        #expect(config.windowRules[0].workspace == 2)
    }

    @Test("Parse window rule ignores invalid workspace")
    func parseInvalidWorkspace() {
        let toml = """
        [[window-rules]]
        app-id = "com.example.app"
        workspace = 15
        """
        let config = TOMLParser.parse(toml)

        #expect(config.windowRules.count == 1)
        #expect(config.windowRules[0].workspace == nil)
    }

    @Test("Parse window rule without workspace defaults to nil")
    func parseWithoutWorkspace() {
        let toml = """
        [[window-rules]]
        app-id = "com.spotify.client"
        action = "float"
        """
        let config = TOMLParser.parse(toml)

        #expect(config.windowRules[0].workspace == nil)
    }

    @Test("Serialize window rule with workspace only")
    func serializeWithWorkspaceOnly() {
        var config = RoverConfig()
        config.windowRules = [
            RoverConfig.WindowRule(appID: "com.apple.mail", action: "", workspace: 3),
        ]
        let toml = TOMLSerializer.serialize(config)

        #expect(toml.contains("workspace = 3"))
        #expect(!toml.contains("action ="))
    }

    @Test("Serialize window rule with action and workspace")
    func serializeWithActionAndWorkspace() {
        var config = RoverConfig()
        config.windowRules = [
            RoverConfig.WindowRule(appID: "com.spotify.client", action: "float", workspace: 2),
        ]
        let toml = TOMLSerializer.serialize(config)

        #expect(toml.contains("action = \"float\""))
        #expect(toml.contains("workspace = 2"))
    }

    @Test("Round-trip window rule with workspace")
    func roundTripWorkspace() {
        var original = RoverConfig()
        original.windowRules = [
            RoverConfig.WindowRule(appID: "com.apple.mail", action: "", workspace: 5),
            RoverConfig.WindowRule(appID: "com.spotify.client", action: "float", workspace: 2),
        ]
        let toml = TOMLSerializer.serialize(original)
        let parsed = TOMLParser.parse(toml)

        #expect(parsed.windowRules.count == 2)
        #expect(parsed.windowRules[0].appID == "com.apple.mail")
        #expect(parsed.windowRules[0].workspace == 5)
        #expect(parsed.windowRules[1].action == "float")
        #expect(parsed.windowRules[1].workspace == 2)
    }
}
