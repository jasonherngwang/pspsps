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
        let pw: CGFloat = 220
        let ph: CGFloat = 80
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

// MARK: - Pixel Art Drawing Helpers

/// A single filled pixel-block in the grid.
private struct Pixel: View {
    let color: Color
    let px: Int
    let py: Int
    let size: CGFloat

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: size, height: size)
            .position(x: CGFloat(px) * size + size / 2,
                      y: CGFloat(py) * size + size / 2)
    }
}

/// Draw a filled rectangle of pixels from (x1,y1) to (x2,y2) inclusive.
private struct PixelRect: View {
    let color: Color
    let x1, y1, x2, y2: Int
    let s: CGFloat

    var body: some View {
        let w = CGFloat(x2 - x1 + 1) * s
        let h = CGFloat(y2 - y1 + 1) * s
        Rectangle()
            .fill(color)
            .frame(width: w, height: h)
            .position(x: CGFloat(x1) * s + w / 2,
                      y: CGFloat(y1) * s + h / 2)
    }
}

// MARK: - Nyan Cat Pixel Art

struct NyanCatView: View {
    let isRecording: Bool
    @State private var peaks: [CGFloat] = Array(repeating: 0.5, count: 9)
    @State private var phase: CGFloat = 0
    private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    // Pixel unit size (each "pixel" = s × s points)
    private let s: CGFloat = 3

    // Colors matching the reference image
    private let black       = Color.black
    private let crustColor  = Color(red: 1.0, green: 0.82, blue: 0.62)   // tan crust
    private let icingColor  = Color(red: 1.0, green: 0.68, blue: 0.84)   // pink icing
    private let sprinkleColor = Color(red: 1.0, green: 0.55, blue: 0.72) // darker pink sprinkles
    private let waveColor   = Color(red: 0.86, green: 0.15, blue: 0.53)  // dark pink waveform
    private let catGray     = Color(red: 0.55, green: 0.55, blue: 0.55)  // gray body
    private let catLightGray = Color(red: 0.70, green: 0.70, blue: 0.70) // lighter gray
    private let catDarkGray = Color(red: 0.35, green: 0.35, blue: 0.35)  // dark feet
    private let cheekPink   = Color(red: 1.0, green: 0.6, blue: 0.65)    // cheek
    private let nosePink    = Color(red: 1.0, green: 0.55, blue: 0.6)    // nose

    // Body dimensions in pixels
    private let bodyW = 22   // pop-tart width in pixels
    private let bodyH = 14   // pop-tart height in pixels

    var body: some View {
        let legBounce = Int(phase * 4) % 2 == 0
        let bodyBob = sin(phase * .pi * 4) * 2

        HStack(spacing: 0) {
            // Rainbow Trail
            RainbowTrail()
                .frame(width: 40, height: CGFloat(bodyH - 2) * s)
                .mask(
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(y: CGFloat(bodyBob))

            // Cat Body Assembly
            ZStack(alignment: .topLeading) {
                // Tail – pixel stub
                tailPixels

                // Back legs
                PixelRect(color: catDarkGray, x1: 3, y1: bodyH, x2: 4, y2: bodyH + 2, s: s)
                    .offset(y: legBounce ? 0 : -s)
                PixelRect(color: catDarkGray, x1: 6, y1: bodyH, x2: 7, y2: bodyH + 2, s: s)
                    .offset(y: legBounce ? -s : 0)

                // Front legs
                PixelRect(color: catDarkGray, x1: bodyW - 5, y1: bodyH, x2: bodyW - 4, y2: bodyH + 2, s: s)
                    .offset(y: legBounce ? -s : 0)
                PixelRect(color: catDarkGray, x1: bodyW - 2, y1: bodyH, x2: bodyW - 1, y2: bodyH + 2, s: s)
                    .offset(y: legBounce ? 0 : -s)

                // Pop-Tart outline (black border)
                PixelRect(color: black, x1: 1, y1: 0, x2: bodyW, y2: bodyH - 1, s: s)

                // Pop-Tart crust fill
                PixelRect(color: crustColor, x1: 2, y1: 1, x2: bodyW - 1, y2: bodyH - 2, s: s)

                // Pop-Tart icing fill (inset)
                PixelRect(color: icingColor, x1: 3, y1: 2, x2: bodyW - 2, y2: bodyH - 3, s: s)

                // Sprinkles
                sprinklePixels

                // Waveform or spinner
                if isRecording {
                    waveformView
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(waveColor)
                        .frame(
                            width: CGFloat(bodyW - 6) * s,
                            height: CGFloat(bodyH - 6) * s
                        )
                        .offset(
                            x: 4 * s,
                            y: 3 * s
                        )
                }

                // Cat Head
                PixelCatHead(s: s, catGray: catGray, catLightGray: catLightGray,
                             catDarkGray: catDarkGray, cheekPink: cheekPink, nosePink: nosePink)
                    .offset(x: CGFloat(bodyW - 1) * s, y: 1 * s)
            }
            .frame(width: CGFloat(bodyW + 10) * s, height: CGFloat(bodyH + 3) * s)
            .offset(y: CGFloat(bodyBob))
        }
        .onReceive(timer) { _ in
            if isRecording {
                for i in 0..<peaks.count {
                    peaks[i] = CGFloat.random(in: 0.15...1.0)
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }

    // MARK: - Sub-views

    private var tailPixels: some View {
        let tailY = 5
        return ZStack(alignment: .topLeading) {
            // Gray tail stub - three pixels going left
            PixelRect(color: catGray, x1: 0, y1: tailY, x2: 0, y2: tailY + 2, s: s)
            PixelRect(color: catGray, x1: 1, y1: tailY, x2: 1, y2: tailY + 3, s: s)
        }
    }

    private var sprinklePixels: some View {
        // Scattered darker-pink sprinkle dots on the icing
        let positions: [(Int, Int)] = [
            (5, 3), (8, 4), (11, 3), (14, 5), (17, 3),
            (6, 7), (9, 8), (13, 7), (16, 8), (19, 6),
            (5, 10), (10, 10), (15, 10), (18, 4), (7, 5),
            (12, 9), (4, 6), (17, 9)
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(0..<positions.count, id: \.self) { i in
                Pixel(color: sprinkleColor, px: positions[i].0, py: positions[i].1, size: s)
            }
        }
    }

    private var waveformView: some View {
        // Pixelated waveform bars inside the icing area
        let barAreaX = 4    // start x in pixels
        let barAreaY = 3    // top of bar area
        let maxBarH = bodyH - 6  // max bar height in pixels

        return ZStack(alignment: .topLeading) {
            ForEach(0..<peaks.count, id: \.self) { i in
                let barH = max(1, Int(CGFloat(maxBarH) * peaks[i]))
                let x = barAreaX + i * 2
                let y = barAreaY + (maxBarH - barH)
                PixelRect(color: waveColor, x1: x, y1: y, x2: x, y2: y + barH - 1, s: s)
                    .animation(.easeOut(duration: 0.12), value: peaks[i])
            }
        }
    }
}

// MARK: - Rainbow Trail

struct RainbowTrail: View {
    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<colors.count, id: \.self) { i in
                Rectangle()
                    .fill(colors[i])
            }
        }
    }
}

// MARK: - Pixel Cat Head

private struct PixelCatHead: View {
    let s: CGFloat
    let catGray: Color
    let catLightGray: Color
    let catDarkGray: Color
    let cheekPink: Color
    let nosePink: Color

    // Head is 10×10 pixel grid; ears extend above
    private let headW = 10
    private let headH = 10

    var body: some View {
        ZStack(alignment: .topLeading) {
            // -- Ears (above head) --
            // Left ear outline + fill
            PixelRect(color: .black, x1: 1, y1: 0, x2: 2, y2: 0, s: s)   // top
            PixelRect(color: .black, x1: 0, y1: 1, x2: 0, y2: 2, s: s)   // left edge
            PixelRect(color: .black, x1: 3, y1: 1, x2: 3, y2: 2, s: s)   // right edge
            PixelRect(color: catGray, x1: 1, y1: 1, x2: 2, y2: 2, s: s)  // fill

            // Right ear outline + fill
            PixelRect(color: .black, x1: 7, y1: 0, x2: 8, y2: 0, s: s)
            PixelRect(color: .black, x1: 6, y1: 1, x2: 6, y2: 2, s: s)
            PixelRect(color: .black, x1: 9, y1: 1, x2: 9, y2: 2, s: s)
            PixelRect(color: catGray, x1: 7, y1: 1, x2: 8, y2: 2, s: s)

            // -- Head body --
            // Black outline
            PixelRect(color: .black, x1: 0, y1: 3, x2: headW - 1, y2: 3, s: s)      // top
            PixelRect(color: .black, x1: 0, y1: headH - 1, x2: headW - 1, y2: headH - 1, s: s) // bottom
            PixelRect(color: .black, x1: 0, y1: 3, x2: 0, y2: headH - 1, s: s)      // left
            PixelRect(color: .black, x1: headW - 1, y1: 3, x2: headW - 1, y2: headH - 1, s: s)  // right

            // Gray fill
            PixelRect(color: catGray, x1: 1, y1: 4, x2: headW - 2, y2: headH - 2, s: s)

            // -- Face features --
            // Eyes (2×2 black with 1px white highlight)
            PixelRect(color: .black, x1: 2, y1: 5, x2: 3, y2: 6, s: s)  // left eye
            Pixel(color: .white, px: 2, py: 5, size: s)                   // left highlight

            PixelRect(color: .black, x1: 6, y1: 5, x2: 7, y2: 6, s: s)  // right eye
            Pixel(color: .white, px: 6, py: 5, size: s)                   // right highlight

            // Nose
            Pixel(color: nosePink, px: 5, py: 7, size: s)

            // Mouth – "w" shape
            Pixel(color: .black, px: 4, py: 8, size: s)
            Pixel(color: .black, px: 6, py: 8, size: s)
            Pixel(color: .black, px: 5, py: 7, size: s) // shared with nose bottom

            // Cheeks
            PixelRect(color: cheekPink, x1: 1, y1: 7, x2: 2, y2: 7, s: s)  // left cheek
            PixelRect(color: cheekPink, x1: 7, y1: 7, x2: 8, y2: 7, s: s)  // right cheek
        }
        .frame(width: CGFloat(headW) * s, height: CGFloat(headH) * s)
    }
}
