import SwiftUI

struct SettingsView: View {
    @ObservedObject var configLoader: ConfigLoader
    @State private var showResetAlert = false

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                GeneralTab(configLoader: configLoader)
                    .tabItem { Label("General", systemImage: "gearshape") }

                GapsTab(configLoader: configLoader)
                    .tabItem { Label("Gaps", systemImage: "rectangle.split.3x3") }

                LayoutsTab(configLoader: configLoader)
                    .tabItem { Label("Layouts", systemImage: "square.grid.2x2") }

                KeybindingsTab(configLoader: configLoader)
                    .tabItem { Label("Keybindings", systemImage: "keyboard") }

                WindowRulesTab(configLoader: configLoader)
                    .tabItem { Label("Window Rules", systemImage: "list.bullet.rectangle") }
            }

            Divider()

            HStack {
                Button("Reset to Defaults") {
                    showResetAlert = true
                }
                Spacer()
            }
            .padding(10)
        }
        .frame(width: 480, height: 450)
        .alert("Reset to Defaults?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                configLoader.resetToDefaults()
            }
        } message: {
            Text("This will reset all settings, including keybindings, to their default values.")
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var configLoader: ConfigLoader

    private var layoutBinding: Binding<String> {
        Binding(
            get: { configLoader.config.general.defaultLayout },
            set: { newValue in
                DispatchQueue.main.async {
                    configLoader.config.general.defaultLayout = newValue
                    configLoader.save()
                }
            }
        )
    }

    var body: some View {
        Form {
            Section("Default Layout") {
                Picker("Layout Algorithm", selection: layoutBinding) {
                    Text("Dwindle").tag("dwindle")
                    Text("Master-Stack").tag("master-stack")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Gaps

private struct GapsTab: View {
    @ObservedObject var configLoader: ConfigLoader

    private var innerBinding: Binding<Double> {
        Binding(
            get: { Double(configLoader.config.gaps.inner) },
            set: { newValue in
                DispatchQueue.main.async {
                    configLoader.config.gaps.inner = CGFloat(newValue)
                    configLoader.save()
                }
            }
        )
    }

    private var outerBinding: Binding<Double> {
        Binding(
            get: { Double(configLoader.config.gaps.outer) },
            set: { newValue in
                DispatchQueue.main.async {
                    configLoader.config.gaps.outer = CGFloat(newValue)
                    configLoader.save()
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Inner Gap: \(Int(configLoader.config.gaps.inner))px")
                        .frame(width: 120, alignment: .leading)
                    Slider(value: innerBinding, in: 0...30, step: 1)
                }
            } header: {
                Text("Inner Gap")
            } footer: {
                Text("Space between tiled windows")
            }

            Section {
                HStack {
                    Text("Outer Gap: \(Int(configLoader.config.gaps.outer))px")
                        .frame(width: 120, alignment: .leading)
                    Slider(value: outerBinding, in: 0...50, step: 1)
                }
            } header: {
                Text("Outer Gap")
            } footer: {
                Text("Space at screen edges")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Layouts

private struct LayoutsTab: View {
    @ObservedObject var configLoader: ConfigLoader

    private var splitRatioBinding: Binding<Double> {
        Binding(
            get: { Double(configLoader.config.dwindle.defaultSplitRatio) },
            set: { newValue in
                DispatchQueue.main.async {
                    configLoader.config.dwindle.defaultSplitRatio = CGFloat(newValue)
                    configLoader.save()
                }
            }
        )
    }

    private var masterRatioBinding: Binding<Double> {
        Binding(
            get: { Double(configLoader.config.masterStack.masterRatio) },
            set: { newValue in
                DispatchQueue.main.async {
                    configLoader.config.masterStack.masterRatio = CGFloat(newValue)
                    configLoader.save()
                }
            }
        )
    }

    private var orientationBinding: Binding<String> {
        Binding(
            get: { configLoader.config.masterStack.orientation },
            set: { newValue in
                DispatchQueue.main.async {
                    configLoader.config.masterStack.orientation = newValue
                    configLoader.save()
                }
            }
        )
    }

    var body: some View {
        Form {
            Section("Dwindle") {
                HStack {
                    Text("Split Ratio: \(configLoader.config.dwindle.defaultSplitRatio, specifier: "%.2f")")
                        .frame(width: 140, alignment: .leading)
                    Slider(value: splitRatioBinding, in: 0.1...0.9, step: 0.05)
                }
            }

            Section("Master-Stack") {
                HStack {
                    Text("Master Ratio: \(configLoader.config.masterStack.masterRatio, specifier: "%.2f")")
                        .frame(width: 140, alignment: .leading)
                    Slider(value: masterRatioBinding, in: 0.1...0.9, step: 0.05)
                }

                Picker("Master Position", selection: orientationBinding) {
                    Text("Left").tag("left")
                    Text("Right").tag("right")
                    Text("Top").tag("top")
                    Text("Bottom").tag("bottom")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Window Rules

private struct WindowRulesTab: View {
    @ObservedObject var configLoader: ConfigLoader

    var body: some View {
        VStack(spacing: 0) {
            if configLoader.config.windowRules.isEmpty {
                Spacer()
                Text("No window rules configured")
                    .foregroundStyle(.secondary)
                Text("Add a rule to always float specific apps")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                List {
                    ForEach(configLoader.config.windowRules.indices, id: \.self) { index in
                        HStack {
                            TextField("Bundle ID (e.g. com.spotify.client)",
                                      text: appIDBinding(at: index))
                                .textFieldStyle(.roundedBorder)

                            Picker("", selection: actionBinding(at: index)) {
                                Text("Float").tag("float")
                            }
                            .frame(width: 80)

                            Button {
                                DispatchQueue.main.async {
                                    configLoader.config.windowRules.remove(at: index)
                                    configLoader.save()
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button {
                    DispatchQueue.main.async {
                        configLoader.config.windowRules.append(
                            RoverConfig.WindowRule(appID: "", action: "float")
                        )
                        configLoader.save()
                    }
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .padding(8)
            }
        }
    }

    private func appIDBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard index < configLoader.config.windowRules.count else { return "" }
                return configLoader.config.windowRules[index].appID
            },
            set: { newValue in
                DispatchQueue.main.async {
                    guard index < configLoader.config.windowRules.count else { return }
                    configLoader.config.windowRules[index].appID = newValue
                    configLoader.save()
                }
            }
        )
    }

    private func actionBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard index < configLoader.config.windowRules.count else { return "float" }
                return configLoader.config.windowRules[index].action
            },
            set: { newValue in
                DispatchQueue.main.async {
                    guard index < configLoader.config.windowRules.count else { return }
                    configLoader.config.windowRules[index].action = newValue
                    configLoader.save()
                }
            }
        )
    }
}

// MARK: - Keybindings

private struct KeybindingsTab: View {
    @ObservedObject var configLoader: ConfigLoader

    private struct CommandGroup {
        let title: String
        let commands: [String]
    }

    private let groups: [CommandGroup] = [
        CommandGroup(title: "Focus", commands: [
            "focus-left", "focus-down", "focus-up", "focus-right",
        ]),
        CommandGroup(title: "Swap", commands: [
            "swap-left", "swap-down", "swap-up", "swap-right",
        ]),
        CommandGroup(title: "Workspaces", commands: [
            "workspace-1", "workspace-2", "workspace-3",
            "workspace-4", "workspace-5", "workspace-6",
            "workspace-7", "workspace-8", "workspace-9",
        ]),
        CommandGroup(title: "Move to Workspace", commands: [
            "move-to-workspace-1", "move-to-workspace-2", "move-to-workspace-3",
            "move-to-workspace-4", "move-to-workspace-5", "move-to-workspace-6",
            "move-to-workspace-7", "move-to-workspace-8", "move-to-workspace-9",
        ]),
        CommandGroup(title: "Other", commands: [
            "toggle-float", "cycle-layout",
            "resize-grow", "resize-shrink", "quit",
        ]),
    ]

    var body: some View {
        Form {
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.commands, id: \.self) { command in
                        HStack {
                            Text(displayName(for: command))
                                .frame(width: 160, alignment: .leading)
                            TextField("e.g. opt+h", text: bindingForCommand(command))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 180)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }

    private func displayName(for command: String) -> String {
        command.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func bindingForCommand(_ command: String) -> Binding<String> {
        Binding(
            get: {
                configLoader.config.keybindings.bindings[command]
                    ?? RoverConfig.KeybindingsConfig.defaults[command]
                    ?? ""
            },
            set: { newValue in
                DispatchQueue.main.async {
                    configLoader.config.keybindings.bindings[command] = newValue
                    configLoader.save()
                }
            }
        )
    }
}
