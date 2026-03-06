import AppKit
import Combine
import SwiftUI

/// Floating status panel showing recording/transcribing state.
///
/// Uses `.nonactivatingPanel` so it never steals focus from the active app.
/// Positioned at the bottom-centre of the main screen and auto-dismisses
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
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 56),
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
        panel.contentViewController = NSHostingController(rootView: OverlayView(viewModel: viewModel))
        return panel
    }

    private func subscribeToState(of coordinator: AppCoordinator) {
        coordinator.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self else { return }
                switch newState {
                case .recording:
                    self.present(text: "Recording...")
                case .transcribing:
                    self.present(text: "Transcribing...")
                case .idle:
                    // If coming from recording (not transcribing), dismiss immediately.
                    // Transcribing→idle is handled by the toast subscription below.
                    if self.previousState != .transcribing {
                        self.dismiss()
                    }
                }
                self.previousState = newState
            }
            .store(in: &cancellables)
    }

    private func subscribeToToasts(of coordinator: AppCoordinator) {
        // showToast delivers synchronously from @MainActor, so ordering is preserved:
        // coordinator fires showToast BEFORE setting state = .idle, so the toast is
        // shown first. The state → .idle delivery (async via receive(on:)) arrives later
        // but is ignored for the transcribing→idle path.
        coordinator.showToast
            .sink { [weak self] message in
                guard let self else { return }
                if message.isEmpty {
                    self.dismiss()
                } else {
                    self.present(text: message)
                    self.scheduleDismiss()
                }
            }
            .store(in: &cancellables)
    }

    private func present(text: String) {
        dismissTask?.cancel()
        dismissTask = nil
        viewModel.text = text
        guard let panel else { return }
        positionAtBottomCenter(panel)
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

    private func positionAtBottomCenter(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let pw: CGFloat = 320
        let ph: CGFloat = 56
        panel.setFrame(
            NSRect(x: visible.midX - pw / 2, y: visible.minY + 40, width: pw, height: ph),
            display: false
        )
    }
}

// MARK: - ViewModel

private final class OverlayViewModel: ObservableObject {
    @Published var text: String = ""
}

// MARK: - View

private struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        HStack(spacing: 8) {
            if viewModel.text == "Recording..." {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
            }
            Text(viewModel.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        )
        .padding(8)
    }
}
