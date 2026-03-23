import Combine
import Foundation
import os

/// Loads, saves, and watches the HyprArc config file for changes.
/// Publishes config updates via Combine.
@MainActor
class ConfigLoader: ObservableObject {
    @Published var config: HyprArcConfig = .default

    static let configDir = NSHomeDirectory() + "/.config/hyprarc"
    static let configPath = configDir + "/config.toml"

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var isSaving = false
    private var saveWorkItem: DispatchWorkItem?
    private let logger = Logger(subsystem: "rohit.HyprArc", category: "ConfigLoader")

    // MARK: - Load

    func load() {
        createDefaultIfNeeded()

        guard let contents = try? String(contentsOfFile: Self.configPath, encoding: .utf8) else {
            logger.warning("Could not read config file, using defaults")
            config = .default
            return
        }

        let newConfig = TOMLParser.parse(contents)
        if newConfig != config {
            config = newConfig
        }
        logger.debug("Config loaded: gaps=\(self.config.gaps.inner)/\(self.config.gaps.outer), layout=\(self.config.general.defaultLayout)")
    }

    /// Force reload from disk.
    func reload() {
        load()
    }

    /// Reset all settings to their default values and save to disk.
    func resetToDefaults() {
        config = .default
        save()
    }

    // MARK: - Save

    /// Debounced save: updates disk 200ms after the last call.
    /// The in-memory config is already updated by the caller.
    func save() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let toml = TOMLSerializer.serialize(self.config)
            self.createDefaultIfNeeded()
            self.isSaving = true
            try? toml.write(toFile: Self.configPath, atomically: true, encoding: .utf8)
            self.logger.debug("Config saved to disk")
            // Reset after the file-watcher debounce window (300ms) has passed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isSaving = false
            }
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
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
            try? HyprArcConfig.defaultTOML.write(
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
                guard let self, !self.isSaving else { return }
                self.load()
                self.logger.debug("Config reloaded (file changed)")
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
