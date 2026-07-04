/*
 * 場の「勢い」判定ロジック（純粋関数）— 会話内容は一切解析しない。
 * ブラウザ (window.NagomiClassify) と Node (require) の両方から使える単一の真実源。
 */
(function (root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.NagomiClassify = api;
})(typeof window !== 'undefined' ? window : globalThis, function () {
  'use strict';

  // ---- パラメータ ----
  const PARAMS = {
    SAMPLE_MS: 1000,       // 音量サンプリング間隔（要件: 1秒ごと）
    BASELINE_WINDOW: 3,    // 過去3サンプル = 過去3秒の移動平均
    COOLDOWN_MS: 3000,     // 反応クールダウン（要件: 3秒）
    SMOOTHING: 0.25,       // 瞬時レベルの指数移動平均係数
    QUIET_DB: -55,         // これ以下は「静か」
    LOUD_ABS_DB: -22,      // これ以上は絶対的に「賑やか」
    SURGE_DELTA_DB: 8,     // 直近が基準より +8dB 以上急上昇したら「賑やか」
  };

  /**
   * 現在音量(db)と過去3秒の基準音量(baseline)から状態を判定する。
   * @param {number} db       平滑化した現在音量 (負のdB)
   * @param {number} baseline 過去3サンプルの移動平均 (負のdB)
   * @returns {'quiet'|'normal'|'lively'}
   */
  function classify(db, baseline) {
    if (db <= PARAMS.QUIET_DB) return 'quiet';
    if (db >= PARAMS.LOUD_ABS_DB || db - baseline >= PARAMS.SURGE_DELTA_DB) return 'lively';
    return 'normal';
  }

  return { classify, PARAMS };
});
