import Foundation

/// 場の状態（3状態）。Web版 `classify.js` の 'quiet' / 'normal' / 'lively' に対応。
enum FieldState: String {
    case quiet
    case normal
    case lively
}

/// 場の「勢い」判定ロジック（純粋関数）— 会話内容は一切解析しない。
///
/// Web版 `classify.js` の忠実な移植（定数・分岐順を一致させた単一の真実源）。
/// アルゴリズムの単体テストはリポジトリ直下 `test/classify.test.mjs`（Node）が正典。
enum Classifier {

    /// 判定パラメータ（`classify.js` の PARAMS と同値）。
    enum Params {
        static let sampleMs: Double = 1000       // 音量サンプリング間隔（1秒ごと）
        static let baselineWindow = 3            // 過去3サンプル = 過去3秒の移動平均
        static let cooldownMs: Double = 3000     // 反応クールダウン（3秒）
        static let smoothing = 0.25              // 瞬時レベルの指数移動平均係数
        static let quietDb = -55.0               // これ以下は「静か」
        static let loudAbsDb = -22.0             // これ以上は絶対的に「賑やか」
        static let surgeDeltaDb = 8.0            // 基準より +8dB 以上急上昇したら「賑やか」
    }

    /// 現在音量(db)と過去3秒の基準音量(baseline)から状態を判定する。
    /// - Parameters:
    ///   - db: 平滑化した現在音量（負のdB）
    ///   - baseline: 過去3サンプルの移動平均（負のdB）
    static func classify(db: Double, baseline: Double) -> FieldState {
        if db <= Params.quietDb { return .quiet }
        if db >= Params.loudAbsDb || db - baseline >= Params.surgeDeltaDb { return .lively }
        return .normal
    }
}
