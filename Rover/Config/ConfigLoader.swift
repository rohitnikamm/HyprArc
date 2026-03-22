import Combine
import Foundation
import os

/// Loads, saves, and watches the Rover config file for changes.
/// Publishes config updates via Combine.
@MainActor
class ConfigLoader: ObservableObject {
    @Published var config: RoverConfig = .default

    static let configDir = NSHomeDirectory() + "/.config/rover"
    static let configPath = configDir + "/config.toml"

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let logger = Logger(subsystem: "rohit.Rover", category: "ConfigLoader")

    // MARK: - Load

    func load() {
        createDefaultIfNeeded()

        guard let contents = try? String(contentsOfFile: Self.configPath, encoding: .utf8) else {
            logger.warning("Could not read config file, using defaults")
            config = .default
            return
        }

        config = TOMLParser.parse(contents)
        logger.debug("Config loaded: gaps=\(self.config.gaps.inner)/\(self.config.gaps.outer), layout=\(self.config.general.defaultLayout)")
    }

    /// Force reload from disk.
    func reload() {
        load()
    }

    // MARK: - Default Config

    private func createDefaultIfNeeded() {
        let fm = FileManager.default

        // Create directory if needed
        if !fm.fileExists(atPath: Self.configDir) {
            try? fm.createDirectory(atPath: Self.configDir, withIntermediateDirectories: true)
        }

        // Create default config if needed
        if !fm.fileExists(atPath: Self.configPath) {
            try? RoverConfig.defaultTOML.write(
                toFile: Self.configPath, atomically: true, encoding: .utf8)
            logger.debug("Created default config at \(Self.configPath)")
        }
    }

    // MARK: - File Watching

    func startWatching() {
        stopWatching()

        fileDescriptor = open(Self.configPath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            logger.warning("Could not open config file for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            // Debounce: editors often write multiple times in quick succession
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.load()
                self?.logger.debug("Config reloaded (file changed)")
            }
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        source.resume()
        fileWatcher = source
        logger.debug("Watching config file for changes")
    }

    func stopWatching() {
        fileWatcher?.cancel()
        fileWatcher = nil
    }
}
