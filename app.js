/*
 * コミュニケーション心理的安全性低減アプリ (MVP)
 * ------------------------------------------------------------------
 * 音声の「勢い」(音量・変化) だけを検出し、3状態 (静か / 普通 / 賑やか) を判定して
 * キャラクターが表情・モーションのみで反応する。会話内容は一切解析しない。
 *
 * 設計（要件対応）:
 *  - マイクからリアルタイムで音量(dB)を取得           → Web Audio API AnalyserNode + RMS→dB
 *  - 1秒ごとにサンプリング / 過去3秒平均と比較して判定  → SAMPLE_MS=1000, 3サンプルの移動平均
 *  - 状態変化時のみ反応 / クールダウン3秒              → lastReactAt + COOLDOWN_MS=3000
 *  - 音量検出遅延<=200ms                            → 計測ループは ~60fps (rAF) の平滑値
 *  - アニメ切替<=100ms                              → CSS クラス切替で即時
 *  - 音声保存なし / 会話解析なし / オンデバイス完結     → 生データはメモリ内のみ・送信/保存しない
 */

(() => {
  'use strict';

  // ---- パラメータ & 判定ロジック（classify.js が単一の真実源） ----
  const { classify, PARAMS } = window.NagomiClassify;
  const { SAMPLE_MS, BASELINE_WINDOW, COOLDOWN_MS, SMOOTHING } = PARAMS;

  // ---- 状態定義 ----
  const STATES = {
    quiet:  { label: '静か 🤫' },
    normal: { label: '普通 🙂' },
    lively: { label: '賑やか 🎉' },
  };

  // ---- DOM ----
  const stage = document.getElementById('stage');
  const character = document.getElementById('character');
  const statePill = document.getElementById('statePill');
  const meterFill = document.getElementById('meterFill');
  const startBtn = document.getElementById('startBtn');

  // ---- ランタイム状態 ----
  let audioCtx = null;
  let analyser = null;
  let mediaStream = null;
  let sampleBuffer = null;          // 時間領域波形の作業バッファ
  let running = false;
  let rafId = null;
  let sampleTimer = null;

  let smoothedDb = -100;            // 平滑化した瞬時音量(dB)
  let recentDbs = [];               // 過去サンプルの移動平均用
  let currentState = 'idle';
  let lastReactAt = 0;

  // dB(-100..0) をメーター(0..100%) に写像
  const dbToPercent = (db) => Math.max(0, Math.min(100, (db + 80) / 0.8));

  /** 時間領域データから RMS を計算し dB に変換 */
  function measureDb() {
    analyser.getFloatTimeDomainData(sampleBuffer);
    let sumSq = 0;
    for (let i = 0; i < sampleBuffer.length; i++) {
      const v = sampleBuffer[i];
      sumSq += v * v;
    }
    const rms = Math.sqrt(sumSq / sampleBuffer.length);
    // 無音での -Infinity を避けるため下限を設ける
    const db = 20 * Math.log10(Math.max(rms, 1e-5));
    return db; // 約 -100 .. 0
  }

  /** 描画ループ: 瞬時音量を平滑化してメーターへ（低遅延・軽量） */
  function loop() {
    if (!running) return;
    const db = measureDb();
    smoothedDb = SMOOTHING * db + (1 - SMOOTHING) * smoothedDb;
    meterFill.style.width = dbToPercent(smoothedDb) + '%';
    rafId = requestAnimationFrame(loop);
  }

  /** 1秒ごと: サンプルを蓄積し、過去3秒平均と比較して状態判定 */
  function sampleAndClassify() {
    if (!running) return;

    recentDbs.push(smoothedDb);
    if (recentDbs.length > BASELINE_WINDOW) recentDbs.shift();
    const baseline = recentDbs.reduce((a, b) => a + b, 0) / recentDbs.length;

    applyState(classify(smoothedDb, baseline));
  }

  /** 状態変化時のみ・クールダウン考慮でキャラクターを反応させる */
  function applyState(next) {
    if (next === currentState) return;              // 変化した時のみ
    const now = performance.now();
    if (now - lastReactAt < COOLDOWN_MS) return;    // 連続反応を防ぐ（3秒クールダウン）

    currentState = next;
    lastReactAt = now;

    stage.dataset.state = next;                     // CSS が即時に表情/モーション切替
    statePill.textContent = STATES[next].label;

    // 反応の瞬間の小さな pop（一度だけ）
    character.classList.remove('react');
    void character.offsetWidth;                     // reflow でアニメ再起動
    character.classList.add('react');
  }

  async function start() {
    try {
      mediaStream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: false },
        video: false,
      });
    } catch (err) {
      statePill.textContent = 'マイクを許可してね';
      console.warn('getUserMedia failed:', err);
      return;
    }

    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    const source = audioCtx.createMediaStreamSource(mediaStream);
    analyser = audioCtx.createAnalyser();
    analyser.fftSize = 1024;                         // 軽量な窓サイズ
    analyser.smoothingTimeConstant = 0.2;
    source.connect(analyser);
    // 注意: analyser を destination に繋がない = 自分の声のハウリングを防ぐ

    sampleBuffer = new Float32Array(analyser.fftSize);
    smoothedDb = -100;
    recentDbs = [];
    currentState = 'idle';
    lastReactAt = 0;
    running = true;

    stage.dataset.state = 'normal';
    statePill.textContent = STATES.normal.label;
    startBtn.textContent = 'とめる';
    startBtn.classList.add('running');

    loop();
    sampleTimer = setInterval(sampleAndClassify, SAMPLE_MS);
  }

  function stop() {
    running = false;
    if (rafId) cancelAnimationFrame(rafId);
    if (sampleTimer) clearInterval(sampleTimer);
    if (mediaStream) mediaStream.getTracks().forEach((t) => t.stop());  // マイク解放（音声は保存しない）
    if (audioCtx) audioCtx.close();
    audioCtx = analyser = mediaStream = null;

    stage.dataset.state = 'idle';
    statePill.textContent = '待機中';
    meterFill.style.width = '0%';
    startBtn.textContent = 'はじめる';
    startBtn.classList.remove('running');
  }

  startBtn.addEventListener('click', () => (running ? stop() : start()));
})();
