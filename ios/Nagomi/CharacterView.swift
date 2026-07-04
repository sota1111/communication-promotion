import SwiftUI

/// 言葉を発さず、表情とモーションのみで反応するキャラクター。
///
/// - 静か   → 首をかしげる（傾き）+ 控えめな口
/// - 普通   → ニコニコ（笑顔の弧）+ ゆっくり呼吸
/// - 賑やか → ぴょんぴょん跳ねる（上下）+ 口を開ける
struct CharacterView: View {
    let state: FieldState

    @State private var breathe = false   // 常時の呼吸アニメーション
    @State private var blink = false     // まばたき
    @State private var hop = false       // 賑やか時の跳ね

    private let skin = Color(red: 1.0, green: 0.86, blue: 0.72)
    private let cheekColor = Color(red: 1.0, green: 0.66, blue: 0.66)
    private let inkColor = Color(red: 0.36, green: 0.26, blue: 0.20)

    var body: some View {
        face
            .scaleEffect(breathe ? 1.03 : 0.99)                     // 呼吸
            .rotationEffect(.degrees(state == .quiet ? -14 : 0))    // 静か = 首かしげ
            .offset(y: hop ? -30 : 0)                               // 賑やか = 跳ね
            .animation(.easeInOut(duration: 0.35), value: state)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                    breathe = true
                }
                withAnimation(.easeInOut(duration: 0.14).delay(2.4).repeatForever(autoreverses: true)) {
                    blink = true
                }
            }
            .onChange(of: state) { _, newValue in
                if newValue == .lively {
                    withAnimation(.interpolatingSpring(stiffness: 240, damping: 6)
                        .repeatCount(4, autoreverses: true)) {
                        hop = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.25)) { hop = false }
                }
            }
    }

    private var face: some View {
        ZStack {
            Circle()
                .fill(skin)
                .frame(width: 200, height: 200)
                .shadow(color: .black.opacity(0.12), radius: 14, y: 8)

            HStack(spacing: 44) { eye; eye }
                .offset(y: -14)

            HStack(spacing: 108) { cheek; cheek }
                .offset(y: 26)

            mouth
                .offset(y: 44)
        }
        .frame(width: 240, height: 240)
    }

    private var eye: some View {
        Capsule()
            .fill(inkColor)
            .frame(width: 18, height: blink ? 4 : 22) // まばたき
    }

    private var cheek: some View {
        Circle()
            .fill(cheekColor.opacity(0.6))
            .frame(width: 30, height: 30)
    }

    @ViewBuilder private var mouth: some View {
        switch state {
        case .quiet:
            // 控えめな一直線の口
            Capsule()
                .fill(inkColor)
                .frame(width: 28, height: 6)
        case .normal:
            // ニコニコの弧
            Smile()
                .stroke(inkColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 64, height: 30)
        case .lively:
            // 開いた口（跳ねながら）
            Ellipse()
                .fill(inkColor)
                .frame(width: 46, height: 40)
        }
    }
}

/// 笑顔の弧（下向きの弧）。
private struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.midX, y: rect.maxY * 1.7))
        return p
    }
}
