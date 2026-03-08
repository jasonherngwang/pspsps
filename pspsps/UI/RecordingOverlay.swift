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
        let pw: CGFloat = 210
        let ph: CGFloat = 70
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
    }
}

// MARK: - Nyan Cat (PNG asset + dynamic waveform overlay)

struct NyanCatView: View {
    let isRecording: Bool
    @State private var peaks: [CGFloat] = Array(repeating: 0.5, count: 16)
    private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    /// Display size in points.
    private let displayWidth: CGFloat = 200
    private let displayHeight: CGFloat = 60

    /// Icing region as fraction of the image (for waveform/spinner placement).
    private let icingX: CGFloat = 0.13
    private let icingY: CGFloat = 0.20
    private let icingW: CGFloat = 0.70
    private let icingH: CGFloat = 0.55

    /// Waveform bar color (darker pink, matching original sprinkle color).
    private let barColor = Color(red: 0.90, green: 0.35, blue: 0.55)

    var body: some View {
        ZStack {
            Image("NyanCat")
                .interpolation(.none)
                .resizable()
                .frame(width: displayWidth, height: displayHeight)

            if isRecording {
                Canvas { ctx, size in
                    let region = CGRect(
                        x: icingX * size.width,
                        y: icingY * size.height,
                        width: icingW * size.width,
                        height: icingH * size.height
                    )
                    let barCount = peaks.count
                    let gap: CGFloat = 1.5
                    let barWidth: CGFloat = 3
                    let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
                    let insetX = (region.width - totalWidth) / 2

                    for (i, peak) in peaks.enumerated() {
                        let barH = max(2, region.height * peak)
                        let x = region.minX + insetX + CGFloat(i) * (barWidth + gap)
                        let y = region.midY - barH / 2
                        ctx.fill(
                            Path(CGRect(x: x, y: y, width: barWidth, height: barH)),
                            with: .color(barColor)
                        )
                    }
                }
                .frame(width: displayWidth, height: displayHeight)
                .allowsHitTesting(false)
            } else {
                ProgressView()
                    .controlSize(.regular)
                    .scaleEffect(1.17)
                    .colorMultiply(Color(red: 0.85, green: 0.15, blue: 0.45))
                    .position(
                        x: displayWidth * (icingX + icingW / 2),
                        y: displayHeight * (icingY + icingH / 2)
                    )
                    .frame(width: displayWidth, height: displayHeight)
            }
        }
        .frame(width: displayWidth, height: displayHeight)
        .onReceive(timer) { _ in
            if isRecording {
                for i in 0..<peaks.count {
                    peaks[i] = CGFloat.random(in: 0.15...1.0)
                }
            }
        }
    }
}
