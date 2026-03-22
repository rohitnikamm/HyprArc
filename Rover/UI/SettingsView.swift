import AppKit
import SwiftUI

// MARK: - Sliding Pill Picker

private struct SlidingPicker<T: Hashable>: View {
    let options: [(label: String, value: T)]
    @Binding var selection: T
    @State private var localSelection: T
    @Namespace private var pillNamespace

    init(options: [(label: String, value: T)], selection: Binding<T>) {
        self.options = options
        self._selection = selection
        self._localSelection = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        localSelection = option.value
                    }
                    selection = option.value
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                } label: {
                    Text(option.label)
                        .font(.subheadline)
                        .fontWeight(localSelection == option.value ? .medium : .regular)
                        .foregroundStyle(localSelection == option.value ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background {
                            if localSelection == option.value {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "pill", in: pillNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
        )
        .onChange(of: selection) { _, newValue in
            withAnimation(.smooth(duration: 0.25)) {
                localSelection = newValue
            }
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case gaps = "Gaps"
    case layouts = "Layouts"
    case keybindings = "Keybindings"
    case windowRules = "Window Rules"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .gaps: "rectangle.split.3x3"
        case .layouts: "square.grid.2x2"
        case .keybindings: "keyboard"
        case .windowRules: "list.bullet.rectangle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var configLoader: ConfigLoader
    @State private var selectedSection: SettingsSection = .general
    @State private var hoveredSection: SettingsSection?
    @State private var hoverDebounceTask: DispatchWorkItem?
    @Namespace private var hoverNamespace
    @State private var showResetConfirmation = false
    @State private var resetDismissTask: DispatchWorkItem?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(section.rawValue, systemImage: section.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                            .background {
                                if selectedSection == section {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor)
                                } else if hoveredSection == section {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.white.opacity(0.08))
                                        .matchedGeometryEffect(id: "hover", in: hoverNamespace)
                                        .allowsHitTesting(false)
                                }
                            }
                            .foregroundStyle(selectedSection == section ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        if isHovered {
                            hoverDebounceTask?.cancel()
                            withAnimation(.smooth(duration: 0.2)) {
                                hoveredSection = section
                            }
                        } else {
                            let task = DispatchWorkItem {
                                withAnimation(.smooth(duration: 0.2)) {
                                    hoveredSection = nil
                                }
                            }
                            hoverDebounceTask = task
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: task)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .frame(maxHeight: .infinity)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: showResetConfirmation ? 8 : 0) {
                    // Cancel button — expands from zero width
                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showResetConfirmation = false
                        }
                        resetDismissTask?.cancel()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: showResetConfirmation ? .infinity : 0)
                    .opacity(showResetConfirmation ? 1 : 0)
                    .clipped()

                    // Main button — always visible, text and action change
                    Button {
                        if showResetConfirmation {
                            configLoader.resetToDefaults()
                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showResetConfirmation = false
                            }
                            resetDismissTask?.cancel()
                        } else {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showResetConfirmation = true
                            }
                            resetDismissTask?.cancel()
                            let task = DispatchWorkItem {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showResetConfirmation = false
                                }
                            }
                            resetDismissTask = task
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: task)
                        }
                    } label: {
                        Text(showResetConfirmation ? "Reset" : "Reset to Defaults")
                            .animation(nil, value: showResetConfirmation)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .frame(maxWidth: .infinity)
                }
                .animation(.easeInOut(duration: 0.25), value: showResetConfirmation)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        } detail: {
            Group {
                switch selectedSection {
                case .general:
                    GeneralTab(configLoader: configLoader)
                case .gaps:
                    GapsTab(configLoader: configLoader)
                case .layouts:
                    LayoutsTab(configLoader: configLoader)
                case .keybindings:
                    KeybindingsTab(configLoader: configLoader)
                case .windowRules:
                    WindowRulesTab(configLoader: configLoader)
                }
            }
            .navigationTitle(selectedSection.rawValue)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .containerBackground(.thinMaterial, for: .window)
        .frame(minWidth: 600, minHeight: 400)
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
            Section("Layout Algorithm") {
                SlidingPicker(
                    options: [("Dwindle", "dwindle"), ("Master-Stack", "master-stack")],
                    selection: layoutBinding
                )
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Gaps

private struct GapsTab: View {
    @ObservedObject var configLoader: ConfigLoader
    @State private var innerActive = false
    @State private var outerActive = false
    @State private var innerResetTask: DispatchWorkItem?
    @State private var outerResetTask: DispatchWorkItem?

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
            Section("Window Gaps") {
                LabeledContent {
                    Slider(value: innerBinding, in: 0...30, step: 1)
                } label: {
                    Text("Inner — \(Int(configLoader.config.gaps.inner))px")
                        .foregroundStyle(innerActive ? Color.accentColor : .primary)
                        .fontWeight(innerActive ? .medium : .regular)
                        .animation(.easeInOut(duration: 0.15), value: innerActive)
                }
                .onChange(of: configLoader.config.gaps.inner) {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    innerActive = true
                    innerResetTask?.cancel()
                    let task = DispatchWorkItem { innerActive = false }
                    innerResetTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
                }

                LabeledContent {
                    Slider(value: outerBinding, in: 0...50, step: 1)
                } label: {
                    Text("Outer — \(Int(configLoader.config.gaps.outer))px")
                        .foregroundStyle(outerActive ? Color.accentColor : .primary)
                        .fontWeight(outerActive ? .medium : .regular)
                        .animation(.easeInOut(duration: 0.15), value: outerActive)
                }
                .onChange(of: configLoader.config.gaps.outer) {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    outerActive = true
                    outerResetTask?.cancel()
                    let task = DispatchWorkItem { outerActive = false }
                    outerResetTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Layouts

private struct LayoutsTab: View {
    @ObservedObject var configLoader: ConfigLoader
    @State private var splitActive = false
    @State private var masterActive = false
    @State private var splitResetTask: DispatchWorkItem?
    @State private var masterResetTask: DispatchWorkItem?

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
                LabeledContent {
                    Slider(value: splitRatioBinding, in: 0.1...0.9, step: 0.05)
                } label: {
                    Text("Split Ratio — \(configLoader.config.dwindle.defaultSplitRatio, specifier: "%.2f")")
                        .foregroundStyle(splitActive ? Color.accentColor : .primary)
                        .fontWeight(splitActive ? .medium : .regular)
                        .animation(.easeInOut(duration: 0.15), value: splitActive)
                }
                .onChange(of: configLoader.config.dwindle.defaultSplitRatio) {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    splitActive = true
                    splitResetTask?.cancel()
                    let task = DispatchWorkItem { splitActive = false }
                    splitResetTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
                }
            }

            Section("Master-Stack") {
                LabeledContent {
                    Slider(value: masterRatioBinding, in: 0.1...0.9, step: 0.05)
                } label: {
                    Text("Master Ratio — \(configLoader.config.masterStack.masterRatio, specifier: "%.2f")")
                        .foregroundStyle(masterActive ? Color.accentColor : .primary)
                        .fontWeight(masterActive ? .medium : .regular)
                        .animation(.easeInOut(duration: 0.15), value: masterActive)
                }
                .onChange(of: configLoader.config.masterStack.masterRatio) {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    masterActive = true
                    masterResetTask?.cancel()
                    let task = DispatchWorkItem { masterActive = false }
                    masterResetTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
                }

                SlidingPicker(
                    options: [("Left", "left"), ("Right", "right"), ("Top", "top"), ("Bottom", "bottom")],
                    selection: orientationBinding
                )
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Window Rules

private struct WindowRulesTab: View {
    @ObservedObject var configLoader: ConfigLoader

    var body: some View {
        Group {
            if configLoader.config.windowRules.isEmpty {
                ContentUnavailableView(
                    "No Window Rules",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Add a rule to always float specific apps.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(configLoader.config.windowRules) { rule in
                            if let index = configLoader.config.windowRules.firstIndex(where: { $0.id == rule.id }) {
                                HStack {
                                    TextField("Bundle ID (e.g. com.spotify.client)",
                                              text: appIDBinding(at: index))
                                        .textFieldStyle(.roundedBorder)

                                    Picker("Action", selection: actionBinding(at: index)) {
                                        Text("Float").tag("float")
                                    }
                                    .labelsHidden()
                                    .fixedSize()

                                    Button {
                                        withAnimation(.smooth(duration: 0.25)) {
                                            configLoader.config.windowRules.removeAll { $0.id == rule.id }
                                        }
                                        configLoader.save()
                                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        configLoader.config.windowRules.append(
                            RoverConfig.WindowRule(appID: "", action: "float")
                        )
                    }
                    configLoader.save()
                } label: {
                    Image(systemName: "plus")
                }
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
    @State private var expandedGroups: Set<String> = ["Focus"]

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
        List {
            ForEach(groups, id: \.title) { group in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedGroups.contains(group.title) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedGroups.insert(group.title)
                            } else {
                                expandedGroups.remove(group.title)
                            }
                        }
                    )
                ) {
                    ForEach(group.commands, id: \.self) { command in
                        LabeledContent(displayName(for: command)) {
                            TextField("e.g. opt+h", text: bindingForCommand(command))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 160)
                        }
                    }
                } label: {
                    Text(group.title)
                }
            }
        }
        .scrollContentBackground(.hidden)
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
