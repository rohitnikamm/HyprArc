import AppKit
import SwiftUI

/// First-launch onboarding flow. 5 steps, navigable with ← → buttons or
/// progress dots. Step index persists in @AppStorage so closing mid-flow
/// and reopening lands in the same place.
struct WelcomeView: View {
    @ObservedObject var tilingController: TilingController

    @AppStorage("welcomeStep") private var currentStep: Int = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Step content — swap with smooth cross-fade
            ZStack {
                stepContent
                    .id(currentStep)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.smooth(duration: 0.3), value: currentStep)

            // Bottom bar: progress dots + nav buttons
            bottomBar
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)
        }
        .frame(width: 640, height: 520)
        .containerBackground(.thinMaterial, for: .window)
        .onAppear {
            // Clamp on reopen in case AppStorage has a stale value from before.
            if currentStep < 0 || currentStep >= totalSteps { currentStep = 0 }
        }
    }

    // MARK: - Step content router

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0: WelcomeStepOne()
        case 1: WelcomeStepTwo()
        case 2: WelcomeStepThree(tilingController: tilingController)
        case 3: WelcomeStepFour(tilingController: tilingController)
        default: WelcomeStepFive(onOpenSettings: openSettingsAndFinish)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            // Back — hidden on step 0, still reserves space
            Button {
                withAnimation(.smooth(duration: 0.25)) {
                    currentStep = max(0, currentStep - 1)
                }
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .opacity(currentStep == 0 ? 0 : 1)
            .disabled(currentStep == 0)

            Spacer()

            // Dots
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { currentStep = i }
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    } label: {
                        Circle()
                            .fill(i == currentStep ? Color.accentColor : Color.primary.opacity(0.18))
                            .frame(width: 7, height: 7)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Next / Finish
            Button {
                if currentStep == totalSteps - 1 {
                    finish()
                } else {
                    withAnimation(.smooth(duration: 0.25)) { currentStep += 1 }
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            } label: {
                if currentStep == totalSteps - 1 {
                    Text("Finish")
                } else {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Actions

    private func finish() {
        hasCompletedOnboarding = true
        currentStep = 0  // reset so next open (via Settings) starts fresh
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        dismissWindow(id: "welcome")
    }

    private func openSettingsAndFinish() {
        hasCompletedOnboarding = true
        currentStep = 0
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
        dismissWindow(id: "welcome")
    }
}
