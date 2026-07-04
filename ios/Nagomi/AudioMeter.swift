import AVFoundation
import Combine
import Foundation

/// マイクの音量(dB)だけを計測し、場の状態（静か/普通/賑やか）を判定する。
///
/// 会話内容は一切解析せず、音声は保存せず、すべて端末内で完結する。
/// マイクの生波形はタップ内で即座に RMS→dB の1数値に変換され、破棄される。
/// Web版 `app.js`（measureDb / loop / sampleAndClassify / applyState）と同じ設計。
@MainActor
final class AudioMeter: ObservableObject {

    /// 現在の場の状態（状態変化かつクールダウン経過時のみ更新）。
    @Published private(set) var state: FieldState = .normal
    /// メーター表示用のレベル（0.0〜1.0）。
    @Published private(set) var level: Double = 0
    /// 計測中かどうか。
    @Published private(set) var isRunning = false
    /// マイク権限が拒否された、または開始に失敗したか。
    @Published private(set) var permissionDenied = false

    private let engine = AVAudioEngine()
    private var sampleTimer: Timer?
    private var meterTimer: Timer?

    // 音声スレッド（タップ）と主スレッド（タイマー）で共有する平滑化 dB。
    private let lock = NSLock()
    private var smoothedDb = -100.0

    private var recentDbs: [Double] = []
    private var lastReactAt = Date.distantPast

    // MARK: - 制御

    func toggle() { isRunning ? stop() : start() }

    func start() {
        requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.permissionDenied = true
                return
            }
            self.permissionDenied = false
            self.beginCapture()
        }
    }

    func stop() {
        sampleTimer?.invalidate(); sampleTimer = nil
        meterTimer?.invalidate(); meterTimer = nil
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        // マイクを解放（音声は保存しない）。
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRunning = false
        level = 0
    }

    // MARK: - 権限

    private func requestPermission(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    // MARK: - 計測

    private func beginCapture() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
        } catch {
            permissionDenied = true
            return
        }

        lock.lock(); smoothedDb = -100; lock.unlock()
        recentDbs = []
        lastReactAt = .distantPast
        state = .normal

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // タップ（音声スレッド）: 生波形を dB に変換して平滑化するだけ。保存も送信もしない。
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let db = Self.measureDb(buffer)
            self.lock.lock()
            let s = Classifier.Params.smoothing
            self.smoothedDb = s * db + (1 - s) * self.smoothedDb
            self.lock.unlock()
        }

        do {
            engine.prepare()
            try engine.start()
            isRunning = true
        } catch {
            permissionDenied = true
            stop()
            return
        }

        // メーター描画（~30fps・低遅延）。
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMeter() }
        }
        // 1秒ごとに状態判定。
        sampleTimer = Timer.scheduledTimer(withTimeInterval: Classifier.Params.sampleMs / 1000.0,
                                           repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleAndClassify() }
        }
    }

    private func currentSmoothedDb() -> Double {
        lock.lock(); defer { lock.unlock() }
        return smoothedDb
    }

    /// dB(-80..0) をメーター(0..1) に写像。
    private func updateMeter() {
        level = max(0, min(1, (currentSmoothedDb() + 80) / 80))
    }

    /// 1秒ごと: サンプルを蓄積し、過去3秒平均と比較して状態判定。
    private func sampleAndClassify() {
        let db = currentSmoothedDb()
        recentDbs.append(db)
        if recentDbs.count > Classifier.Params.baselineWindow { recentDbs.removeFirst() }
        let baseline = recentDbs.reduce(0, +) / Double(recentDbs.count)
        applyState(Classifier.classify(db: db, baseline: baseline))
    }

    /// 状態変化時のみ・3秒クールダウンを考慮して反応する。
    private func applyState(_ next: FieldState) {
        guard next != state else { return }
        let now = Date()
        guard now.timeIntervalSince(lastReactAt) * 1000 >= Classifier.Params.cooldownMs else { return }
        lastReactAt = now
        state = next
    }

    /// 時間領域データから RMS を計算し dB に変換（Web版 `measureDb` と同じ式）。
    private static func measureDb(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return -100 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return -100 }
        var sumSq: Double = 0
        for i in 0..<n {
            let v = Double(channel[i])
            sumSq += v * v
        }
        let rms = (sumSq / Double(n)).squareRoot()
        // 無音での -Infinity を避けるため下限を設ける。
        return 20 * log10(max(rms, 1e-5)) // 約 -100 .. 0
    }
}
