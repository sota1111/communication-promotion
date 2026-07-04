// 場の勢い判定ロジックの単体テスト（node --test で実行）
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { classify, PARAMS } = require('../classify.js');

test('要件のパラメータが仕様どおり', () => {
  assert.equal(PARAMS.SAMPLE_MS, 1000);      // 1秒ごとにサンプリング
  assert.equal(PARAMS.BASELINE_WINDOW, 3);   // 過去3秒平均
  assert.equal(PARAMS.COOLDOWN_MS, 3000);    // クールダウン3秒
});

test('静か: 音量が閾値以下', () => {
  assert.equal(classify(-70, -70), 'quiet');
  assert.equal(classify(PARAMS.QUIET_DB, -60), 'quiet'); // 境界: 閾値ちょうども静か
});

test('普通: 通常会話レベル（基準からの急上昇なし）', () => {
  assert.equal(classify(-35, -37), 'normal');
  assert.equal(classify(-30, -33), 'normal');
});

test('賑やか: 絶対的に大きい音量', () => {
  assert.equal(classify(-18, -30), 'lively');            // LOUD_ABS 超え
  assert.equal(classify(PARAMS.LOUD_ABS_DB, -50), 'lively'); // 境界
});

test('賑やか: 基準から+8dB以上の急上昇（笑い声・盛り上がり）', () => {
  assert.equal(classify(-32, -42), 'lively');  // +10dB の急上昇
  assert.equal(classify(-34, -42), 'lively');  // ちょうど +8dB
});

test('急上昇が閾値未満なら普通のまま', () => {
  assert.equal(classify(-36, -42), 'normal');  // +6dB は普通
});

test('状態は3種類のいずれかに必ず収まる', () => {
  for (let db = -90; db <= -5; db += 1) {
    const s = classify(db, -45);
    assert.ok(['quiet', 'normal', 'lively'].includes(s), `unexpected state ${s} for ${db}dB`);
  }
});
