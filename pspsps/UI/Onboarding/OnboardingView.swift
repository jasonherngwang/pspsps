import SwiftUI

/// Orchestrates the three-step onboarding flow:
///   1. ASRPickerView  – pick and download a transcription engine
///   2. AccessibilityPermissionView  – grant Accessibility access
///   3. MicrophonePermissionView     – grant Microphone access
struct OnboardingView: View {
    @EnvironmentObject var downloadManager: ModelDownloadManager
    @EnvironmentObject var coordinator: AppCoordinator

    enum Step { case asrPicker, accessibility, microphone }

    @State private var currentStep: Step = .asrPicker

    /// Called after the user completes all three steps.
    let onComplete: () -> Void

    var body: some View {
        switch currentStep {
        case .asrPicker:
            ASRPickerView(onContinue: { currentStep = .accessibility })
        case .accessibility:
            AccessibilityPermissionView(onContinue: { currentStep = .microphone })
        case .microphone:
            MicrophonePermissionView(onComplete: onComplete)
        }
    }
}
