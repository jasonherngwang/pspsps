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
            .sink { [weak self] message in
                guard let self else { return }
                if message.isEmpty {
                    self.dismiss()
                } else {
                    self.viewModel.mode = .toast(message)
                    self.present()
                    self.scheduleDismiss()
                }
            }
            .store(in: &cancellables)
    }

    private func present() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let panel else { return }
        positionTopRight(panel)
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

    private func positionTopRight(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let pw: CGFloat = 48
        let ph: CGFloat = 48
        let margin: CGFloat = 12
        panel.setFrame(
            NSRect(
                x: visible.maxX - pw - margin,
                y: visible.maxY - ph - margin,
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
    case toast(String)
}

private final class OverlayViewModel: ObservableObject {
    @Published var mode: OverlayMode = .recording
}

// MARK: - View

private struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var pulse = false

    var body: some View {
        Group {
            switch viewModel.mode {
            case .recording:
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .scaleEffect(pulse ? 1.3 : 1.0)
                    .opacity(pulse ? 0.7 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
                    .onChange(of: viewModel.mode) { _, _ in pulse = false }
            case .transcribing:
                ProgressView()
                    .controlSize(.small)
            case .toast:
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .frame(width: 36, height: 36)
        .background(.thickMaterial, in: Circle())
        .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    }
}
