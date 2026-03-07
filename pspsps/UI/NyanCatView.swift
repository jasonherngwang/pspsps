import SwiftUI

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
                Rectangle()
                    .fill(colors[i])
                    .frame(height: 28.0 / 6.0)
                    .offset(y: sin(phase * .pi * 2 + Double(i) * 0.5) * 2)
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
