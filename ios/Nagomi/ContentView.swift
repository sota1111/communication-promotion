import SwiftUI

/// メイン画面。キャラクターを中央に常時表示し、ミニマルな背景・音量メーター・
/// 開始/停止ボタン・プライバシー注記を配置する。
struct ContentView: View {
    @StateObject private var meter = AudioMeter()

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 24) {
                statePill

                Spacer()
                CharacterView(state: meter.isRunning ? meter.state : .normal)
                Spacer()

                meterBar
                startButton

                if meter.permissionDenied {
                    Text("マイクの利用を許可してね")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                privacyNote
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
    }

    // MARK: - 状態表示

    private var stateInfo: (label: String, color: Color) {
        guard meter.isRunning else { return ("待機中", .gray) }
        switch meter.state {
        case .quiet:  return ("静か 🤫", Color(red: 0.35, green: 0.55, blue: 0.85))
        case .normal: return ("普通 🙂", Color(red: 0.35, green: 0.70, blue: 0.45))
        case .lively: return ("賑やか 🎉", Color(red: 0.95, green: 0.55, blue: 0.20))
        }
    }

    private var statePill: some View {
        Text(stateInfo.label)
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Capsule().fill(stateInfo.color))
            .animation(.easeInOut(duration: 0.3), value: meter.state)
    }

    // MARK: - メーター

    private var meterBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.08))
                Capsule()
                    .fill(stateInfo.color.opacity(0.85))
                    .frame(width: geo.size.width * meter.level)
            }
        }
        .frame(height: 12)
        .animation(.linear(duration: 0.08), value: meter.level)
    }

    // MARK: - ボタン

    private var startButton: some View {
        Button(action: meter.toggle) {
            Text(meter.isRunning ? "とめる" : "はじめる")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule().fill(meter.isRunning
                                   ? Color.gray
                                   : Color(red: 0.35, green: 0.70, blue: 0.45))
                )
        }
    }

    // MARK: - 背景・注記

    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.96, green: 0.98, blue: 1.0),
                     Color(red: 0.90, green: 0.95, blue: 0.98)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var privacyNote: some View {
        Text("音声は保存せず・会話内容は解析せず・すべて端末内で処理します")
            .font(.caption2)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    ContentView()
}
