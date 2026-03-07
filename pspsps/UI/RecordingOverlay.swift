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

// MARK: - Nyan Cat Drawing Tools

struct NyanCatView: View {
    let isRecording: Bool
    @State private var peaks: [CGFloat] = [0.3, 0.6, 0.9, 0.5, 0.4, 0.7, 0.8]
    @State private var phase: CGFloat = 0
    private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()
    
    // Nyan Cat colors
    let crustColor = Color(red: 0.98, green: 0.8, blue: 0.6)
    let icingColor = Color(red: 1.0, green: 0.6, blue: 0.8)
    let waveformColor = Color(red: 0.86, green: 0.15, blue: 0.53) // Dark pink
    let catSkin = Color(red: 0.6, green: 0.6, blue: 0.6)
    
    var body: some View {
        HStack(spacing: 0) {
            // Fading Rainbow Trail
            RainbowTrail(phase: phase)
                .frame(width: 80, height: 28)
                .mask(
                    LinearGradient(gradient: Gradient(colors: [.clear, .black]), startPoint: .leading, endPoint: .trailing)
                )
                .offset(y: 2)
            
            // Cat Body
            ZStack(alignment: .leading) {
                // Tail
                Path { path in
                    path.move(to: CGPoint(x: 4, y: 16))
                    path.addLine(to: CGPoint(x: -8, y: 16))
                    path.addLine(to: CGPoint(x: -12, y: 10 + sin(phase * .pi * 2) * 4))
                }
                .stroke(catSkin, style: StrokeStyle(lineWidth: 4, lineCap: .square))
                
                // Back Legs
                Rectangle()
                    .fill(catSkin)
                    .frame(width: 6, height: 8)
                    .offset(x: 10, y: 16 + (Int(phase * 4) % 2 == 0 ? 0 : -2))
                
                // Front Legs
                Rectangle()
                    .fill(catSkin)
                    .frame(width: 6, height: 8)
                    .offset(x: 40, y: 16 + (Int(phase * 4) % 2 == 0 ? -2 : 0))
                
                // Pop Tart Crust
                RoundedRectangle(cornerRadius: 4)
                    .fill(crustColor)
                    .frame(width: 60, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.black, lineWidth: 2)
                    )
                
                // Pop Tart Icing
                RoundedRectangle(cornerRadius: 3)
                    .fill(icingColor)
                    .frame(width: 52, height: 28)
                    .offset(x: 4)
                
                // Pink Waveform inside Pop Tart
                if isRecording {
                    HStack(spacing: 3) {
                        ForEach(0..<peaks.count, id: \.self) { index in
                            Capsule()
                                .fill(waveformColor)
                                .frame(width: 3, height: 20 * peaks[index])
                                .animation(.spring(response: 0.15), value: peaks[index])
                        }
                    }
                    .frame(width: 52, height: 28)
                    .offset(x: 4)
                } else {
                    // Transcribing State
                    ProgressView()
                        .controlSize(.small)
                        .tint(waveformColor)
                        .frame(width: 52, height: 28)
                        .offset(x: 4)
                }
                
                // Cat Head
                CatHead()
                    .offset(x: 48, y: 4)
            }
            .offset(y: sin(phase * .pi * 4) * 2) // Bop up and down
        }
        .onReceive(timer) { _ in
            if isRecording {
                for i in 0..<peaks.count {
                    peaks[i] = CGFloat.random(in: 0.2...1.0)
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

struct RainbowTrail: View {
    var phase: CGFloat
    let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { i in
                let yOffset = sin(phase * .pi * 2 + CGFloat(i) * 0.5) * 2.0
                Rectangle()
                    .fill(colors[i])
                    .frame(height: 28.0 / 6.0)
                    .offset(y: yOffset)
            }
        }
    }
}

struct CatHead: View {
    let catSkin = Color(red: 0.6, green: 0.6, blue: 0.6)
    
    var body: some View {
        ZStack {
            // Ears
            Path { path in
                path.move(to: CGPoint(x: 2, y: 6))
                path.addLine(to: CGPoint(x: 6, y: -2))
                path.addLine(to: CGPoint(x: 10, y: 4))
                
                path.move(to: CGPoint(x: 14, y: 4))
                path.addLine(to: CGPoint(x: 18, y: -2))
                path.addLine(to: CGPoint(x: 22, y: 6))
            }
            .fill(catSkin)
            .overlay(
                Path { path in
                    path.move(to: CGPoint(x: 2, y: 6))
                    path.addLine(to: CGPoint(x: 6, y: -2))
                    path.addLine(to: CGPoint(x: 10, y: 4))
                    
                    path.move(to: CGPoint(x: 14, y: 4))
                    path.addLine(to: CGPoint(x: 18, y: -2))
                    path.addLine(to: CGPoint(x: 22, y: 6))
                }
                .stroke(.black, lineWidth: 2)
            )
            
            // Face Base
            RoundedRectangle(cornerRadius: 3)
                .fill(catSkin)
                .frame(width: 24, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 3).stroke(.black, lineWidth: 2)
                )
            
            // Cheeks
            Circle().fill(.pink).frame(width: 4, height: 4).offset(x: -8, y: 2)
            Circle().fill(.pink).frame(width: 4, height: 4).offset(x: 8, y: 2)
            
            // Eyes
            Circle().fill(.black).frame(width: 4, height: 4).offset(x: -5, y: -2)
            Circle().fill(.black).frame(width: 4, height: 4).offset(x: 5, y: -2)
            Circle().fill(.white).frame(width: 1.5, height: 1.5).offset(x: -5.5, y: -2.5) // sparkle
            Circle().fill(.white).frame(width: 1.5, height: 1.5).offset(x: 4.5, y: -2.5) // sparkle
            
            // Mouth
            Path { path in
                path.move(to: CGPoint(x: -2, y: 2))
                path.addLine(to: CGPoint(x: -1, y: 4))
                path.addLine(to: CGPoint(x: 0, y: 2))
                path.addLine(to: CGPoint(x: 1, y: 4))
                path.addLine(to: CGPoint(x: 2, y: 2))
            }
            .stroke(.black, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .offset(y: 2)
        }
        .frame(width: 24, height: 24)
    }
}
