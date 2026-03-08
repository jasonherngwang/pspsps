import SwiftUI

/// Engine selection view shown during onboarding and accessible from Settings.
/// Displays two engine cards; the user selects one and triggers a download.
/// On download completion, calls `onContinue` to advance the onboarding flow.
struct ASRPickerView: View {
    @EnvironmentObject var downloadManager: ModelDownloadManager
    @EnvironmentObject var coordinator: AppCoordinator

    @State private var selectedEngine: AppConfig.ASREngineOption = .parakeet

    /// Set to false when ParakeetEngine is a stub (FluidAudio did not resolve).
    /// True in this build because FluidAudio resolved successfully.
    private let parakeetEngineAvailable: Bool = true

    /// Called after a successful download (or immediately if already downloaded).
    var onContinue: (() -> Void)? = nil

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            header
            engineCards
            downloadSection
        }
        .padding(32)
        .frame(minWidth: 480)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("Choose your transcription engine")
                .font(.title2).bold()
            Text("You can switch engines later in Settings → ASR Engine.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Engine Cards

    private var engineCards: some View {
        VStack(spacing: 12) {
            engineCard(
                engine: .parakeet,
                title: "Parakeet",
                size: "~480 MB",
                latency: "~0.19s latency",
                bestFor: "Best for clear speech, speed",
                isRecommended: true,
                available: parakeetEngineAvailable
            )
            engineCard(
                engine: .whisperKit,
                title: "WhisperKit",
                size: "~600 MB",
                latency: "~0.45s latency",
                bestFor: "Best for whispers, accents, noise",
                isRecommended: false,
                available: true
            )
        }
    }

    @ViewBuilder
    private func engineCard(
        engine: AppConfig.ASREngineOption,
        title: String,
        size: String,
        latency: String,
        bestFor: String,
        isRecommended: Bool,
        available: Bool
    ) -> some View {
        let isSelected = selectedEngine == engine
        Button(action: {
            if available { selectedEngine = engine }
        }) {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        if isRecommended {
                            Text("Recommended")
                                .font(.caption2).bold()
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                        if !available {
                            Text("Coming soon")
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(size) · \(latency)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(bestFor)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1.0 : 0.5)
    }

    // MARK: - Download / Continue Section

    @ViewBuilder
    private var downloadSection: some View {
        let state = selectedEngine == .whisperKit
            ? downloadManager.whisperKitState
            : downloadManager.parakeetState

        switch state {
        case .downloading(let progress):
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(maxWidth: .infinity)
                Text("Downloading… \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .downloaded:
            Button("Continue") {
                coordinator.config.asrEngine = selectedEngine
                onContinue?()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .notDownloaded, .failed:
            VStack(spacing: 8) {
                if case .failed(let msg) = state {
                    Text("Download failed: \(msg)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Button("Download & Continue") {
                    Task {
                        switch selectedEngine {
                        case .whisperKit: await downloadManager.downloadWhisperKit()
                        case .parakeet:   await downloadManager.downloadParakeet()
                        }
                        coordinator.config.asrEngine = selectedEngine
                        onContinue?()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}
