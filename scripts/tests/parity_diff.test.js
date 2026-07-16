const { test } = require('node:test');
const assert = require('node:assert');
const { PNG } = require('pngjs');
const { normalize, scorePair, buildReportHtml } = require('../parity_diff.js');

function solid(w, h, r, g, b) {
  const png = new PNG({ width: w, height: h });
  for (let i = 0; i < w * h; i++) {
    const j = i << 2;
    png.data[j] = r; png.data[j + 1] = g; png.data[j + 2] = b; png.data[j + 3] = 255;
  }
  return png;
}

test('normalize resizes to the requested dimensions', () => {
  const out = normalize(solid(10, 20, 0, 0, 0), 4, 8);
  assert.equal(out.width, 4);
  assert.equal(out.height, 8);
});

test('identical images score ~0', () => {
  const a = solid(120, 260, 30, 40, 60);
  const b = solid(120, 260, 30, 40, 60);
  assert.ok(scorePair(a, b) < 0.01, `expected ~0, got ${scorePair(a, b)}`);
});

test('black vs white scores ~1', () => {
  const a = solid(120, 260, 0, 0, 0);
  const b = solid(120, 260, 255, 255, 255);
  assert.ok(scorePair(a, b) > 0.95, `expected ~1, got ${scorePair(a, b)}`);
});

test('buildReportHtml emits one row per pair, worst-first, flagging accepted', () => {
  const html = buildReportHtml([
    { screenId: 'tab-home', frameTitle: 'Home', score: 0.05, accepted: false,
      acceptedReason: '', proofB64: 'A', appB64: 'B', heatB64: 'C' },
    { screenId: 'tab-you', frameTitle: 'Settings Hub', score: 0.40, accepted: true,
      acceptedReason: 'stat tiles are a recorded deviation', proofB64: 'A', appB64: 'B', heatB64: 'C' },
  ]);
  assert.ok(html.includes('tab-home'));
  assert.ok(html.includes('tab-you'));
  // worst-first: the higher-scoring row appears earlier in the document...
  assert.ok(html.indexOf('tab-you') < html.indexOf('tab-home'));
  // ...unless it's accepted — accepted rows carry a distinct class so the
  // report can visually separate them.
  assert.ok(html.includes('accepted'));
  assert.ok(html.includes('stat tiles are a recorded deviation'));
});
