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
        let pw: CGFloat = 160
        let ph: CGFloat = 60
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
        NyanCatView(isRecording: viewModel.mode == .recording)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .animation(.easeInOut(duration: 0.3), value: viewModel.mode)
    }
}
