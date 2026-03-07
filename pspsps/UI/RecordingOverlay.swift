import AppKit
import Combine
import SwiftUI

/// Floating status pill showing recording/transcribing state.
///
/// Uses `.nonactivatingPanel` so it never steals focus from the active app.
/// Positioned at the top-right of the main screen and auto-dismisses
/// after `AppConfig.overlayDurationSeconds`.
@MainActor
final class RecordingOverlay {

    private var panel: NSPanel?
    private let viewModel = OverlayViewModel()
    private var dismissTask: Task<Void, Never>?
    private var previousState: AppCoordinator.AppState = .idle
    private var cancellables: Set<AnyCancellable> = []

    init(coordinator: AppCoordinator) {
        panel = makePanel()
        subscribeToState(of: coordinator)
        subscribeToToasts(of: coordinator)
    }

    // MARK: - Private

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        let hostingController = NSHostingController(rootView: OverlayView(viewModel: viewModel))
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = .clear
        panel.contentViewController = hostingController
        return panel
    }

    private func subscribeToState(of coordinator: AppCoordinator) {
        coordinator.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self else { return }
                switch newState {
                case .recording:
                    self.viewModel.mode = .recording
                    self.present()
                case .transcribing:
                    self.viewModel.mode = .transcribing
                    self.present()
                case .idle:
                    if self.previousState != .transcribing {
                        self.dismiss()
                    }
                }
                self.previousState = newState
            }
            .store(in: &cancellables)
    }

    private func subscribeToToasts(of coordinator: AppCoordinator) {
        coordinator.showToast
            .sink { [weak self] _ in
                self?.dismiss()
            }
            .store(in: &cancellables)
    }

    private func present() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let panel else { return }
        positionTopCenter(panel)
        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    private func scheduleDismiss() {
        let seconds = AppConfig.current.overlayDurationSeconds
        dismissTask = Task {
            do {
                try await Task.sleep(for: .seconds(seconds))
                self.dismiss()
            } catch {}
        }
    }

    private func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
    }

    private func positionTopCenter(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let pw: CGFloat = 80
        let ph: CGFloat = 40
        let topMargin: CGFloat = 8
        
        panel.setFrame(
            NSRect(
                x: visible.midX - (pw / 2),
                y: visible.maxY - ph - topMargin,
                width: pw,
                height: ph
            ),
            display: false
        )
    }
}

// MARK: - ViewModel

private enum OverlayMode: Equatable {
    case recording
    case transcribing
}

private final class OverlayViewModel: ObservableObject {
    @Published var mode: OverlayMode = .recording
}

// MARK: - View

private struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        ZStack {
            Group {
                switch viewModel.mode {
                case .recording:
                    RecordingPillContent()
                        .transition(.opacity)
                case .transcribing:
                    TranscribingPillContent()
                        .transition(.opacity)
                }
            }
            .frame(width: 32, height: 16)
        }
        .frame(width: 56, height: 28)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .animation(.easeInOut(duration: 0.3), value: viewModel.mode)
    }
}

private struct RecordingPillContent: View {
    @State private var peaks: [CGFloat] = [0.3, 0.6, 0.9, 0.5, 0.4]
    private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(.primary.opacity(0.8))
                    .frame(width: 2.5, height: 12 * peaks[index])
                    .animation(.easeInOut(duration: 0.15), value: peaks[index])
            }
        }
        .frame(height: 12)
        .onReceive(timer) { _ in
            for i in 0..<peaks.count {
                peaks[i] = CGFloat.random(in: 0.2...1.0)
            }
        }
    }
}

private struct TranscribingPillContent: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .scaleEffect(0.8)
    }
}
