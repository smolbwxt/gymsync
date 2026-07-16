#!/usr/bin/env node
/**
 * Diff engine for the design-parity harness. Pairs each app screenshot
 * (app-<screen-id>.png) with its authoritative proof frame (via
 * frame-map.json), computes a coarse structural score, renders a heatmap,
 * and emits one self-contained worst-first parity-report.html.
 *
 * The score is deliberately coarse: web-rendered proofs and iOS screenshots
 * never pixel-match, so both images are downscaled hard before comparison,
 * which suppresses sub-pixel font noise while still catching missing
 * sections, wrong layout, and wrong components (a map where search belongs).
 *
 * Usage:
 *   node scripts/parity_diff.js --app <dir> --proofs <dir> \
 *     --map docs/design/frame-map.json \
 *     --accepted docs/design/accepted-deviations.json \
 *     --out .superpowers/parity/report
 */
const fs = require('node:fs');
const path = require('node:path');
const { parseArgs } = require('node:util');
const { PNG } = require('pngjs');
const pixelmatch = require('pixelmatch');

const NORM_W = 300, NORM_H = 650; // common canvas for heatmap + scoring source
const SCORE_W = 64;               // downscale width for the coarse score

/** Nearest-neighbor resize of a PNG to exactly w x h (opaque output). */
function normalize(src, w, h) {
  const dst = new PNG({ width: w, height: h });
  for (let y = 0; y < h; y++) {
    const sy = Math.min(src.height - 1, Math.floor((y * src.height) / h));
    for (let x = 0; x < w; x++) {
      const sx = Math.min(src.width - 1, Math.floor((x * src.width) / w));
      const si = (sy * src.width + sx) << 2;
      const di = (y * w + x) << 2;
      dst.data[di] = src.data[si];
      dst.data[di + 1] = src.data[si + 1];
      dst.data[di + 2] = src.data[si + 2];
      dst.data[di + 3] = 255;
    }
  }
  return dst;
}

/** Coarse structural difference in [0,1]: mean luminance delta on a
 *  hard-downscaled pair. 0 = identical, 1 = maximally different. */
function scorePair(a, b) {
  const h = Math.round((SCORE_W * NORM_H) / NORM_W);
  const da = normalize(a, SCORE_W, h);
  const db = normalize(b, SCORE_W, h);
  const n = SCORE_W * h;
  let sum = 0;
  for (let i = 0; i < n; i++) {
    const j = i << 2;
    const la = 0.299 * da.data[j] + 0.587 * da.data[j + 1] + 0.114 * da.data[j + 2];
    const lb = 0.299 * db.data[j] + 0.587 * db.data[j + 1] + 0.114 * db.data[j + 2];
    sum += Math.abs(la - lb);
  }
  return sum / n / 255;
}

/** Full-res (NORM) difference visualization for the report. */
function heatmap(a, b) {
  const na = normalize(a, NORM_W, NORM_H);
  const nb = normalize(b, NORM_W, NORM_H);
  const out = new PNG({ width: NORM_W, height: NORM_H });
  pixelmatch(na.data, nb.data, out.data, NORM_W, NORM_H, { threshold: 0.12, includeAA: false });
  return out;
}

function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/** Self-contained report. Rows sorted worst-first; accepted rows carry an
 *  `accepted` class so the template can separate known-OK divergence.
 *  `unmapped` lists screen-ids captured by the app but absent from the
 *  frame map (no authoritative proof to diff against) — rendered as a
 *  small footer so they aren't silently dropped from the report. */
function buildReportHtml(rows, unmapped = []) {
  const sorted = [...rows].sort((x, y) => y.score - x.score);
  const pct = (s) => (s * 100).toFixed(1) + '%';
  const cards = sorted.map((r) => `
  <article class="pair${r.accepted ? ' accepted' : ''}">
    <header>
      <span class="frame">${esc(r.screenId)} · ${esc(r.frameTitle)}</span>
      <span class="score">${pct(r.score)}</span>
      ${r.accepted ? `<span class="chip">accepted</span>` : ''}
    </header>
    <div class="shots">
      <figure><img loading="lazy" src="${r.proofB64}" alt="proof"><figcaption>Proof</figcaption></figure>
      <figure><img loading="lazy" src="${r.appB64}" alt="app"><figcaption>App</figcaption></figure>
      <figure><img loading="lazy" src="${r.heatB64}" alt="diff"><figcaption>Diff</figcaption></figure>
    </div>
    ${r.accepted ? `<p class="reason">${esc(r.acceptedReason)}</p>` : ''}
  </article>`).join('');
  const unmappedSection = unmapped.length ? `
<footer class="unmapped">
  <h2>Unmapped captures — no authoritative frame</h2>
  <ul>${unmapped.map((id) => `<li>${esc(id)}</li>`).join('')}</ul>
</footer>` : '';
  return `<!DOCTYPE html><html><head><meta charset="utf-8">
<title>GymSync Design Parity</title>
<style>
:root{--bg:#f3efe6;--card:#efe9dd;--ink:#1b2540;--muted:#6b6455;--line:rgba(27,37,64,.18);--warn:#b06a1e;--ok:#3f7d5c;}
@media(prefers-color-scheme:dark){:root{--bg:#13161c;--card:#1a1f27;--ink:#eef2f7;--muted:#9aa2ae;--line:rgba(255,255,255,.12);--warn:#e0a256;--ok:#6cc79a;}}
:root[data-theme="light"]{--bg:#f3efe6;--card:#efe9dd;--ink:#1b2540;--muted:#6b6455;--line:rgba(27,37,64,.18);--warn:#b06a1e;--ok:#3f7d5c;}
:root[data-theme="dark"]{--bg:#13161c;--card:#1a1f27;--ink:#eef2f7;--muted:#9aa2ae;--line:rgba(255,255,255,.12);--warn:#e0a256;--ok:#6cc79a;}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font-family:ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;line-height:1.5}
.wrap{max-width:1040px;margin:0 auto;padding:40px 24px 72px}
h1{font-size:32px;font-weight:800;letter-spacing:-.02em;margin:0 0 8px}
.lede{color:var(--muted);margin:0 0 28px;max-width:70ch}
.pairs{display:grid;gap:20px}
.pair{background:var(--card);border:1px solid var(--line);border-left:4px solid var(--warn);padding:14px}
.pair.accepted{border-left-color:var(--ok);opacity:.72}
.pair header{display:flex;align-items:center;gap:12px;margin-bottom:12px;flex-wrap:wrap}
.frame{font-weight:700;font-size:14px;color:var(--muted)}
.score{font-variant-numeric:tabular-nums;font-weight:800;font-size:15px}
.chip{font-size:11px;font-weight:800;text-transform:uppercase;letter-spacing:.05em;padding:2px 8px;background:var(--ok);color:#fff}
.shots{display:flex;gap:10px;overflow-x:auto}
.shots figure{margin:0;flex:1;min-width:0}
.shots img{width:100%;display:block;border:1px solid var(--line)}
figcaption{font-size:11px;color:var(--muted);text-align:center;margin-top:5px}
.reason{font-size:13px;color:var(--muted);margin:12px 2px 2px}
.unmapped{margin-top:32px;padding-top:16px;border-top:1px solid var(--line)}
.unmapped h2{font-size:15px;font-weight:700;color:var(--muted);margin:0 0 8px}
.unmapped ul{margin:0;padding-left:20px;color:var(--muted);font-size:13px}
</style></head>
<body><div class="wrap">
<h1>GymSync Design Parity</h1>
<p class="lede">Every captured app screen vs. its authoritative Ink-palette proof, sorted worst-divergence first. Score is a coarse structural delta — high means "look at this," not "failed." Accepted deviations are dimmed and sorted with their score but flagged.</p>
<div class="pairs">${cards}</div>
${unmappedSection}
</div></body></html>`;
}

module.exports = { normalize, scorePair, heatmap, buildReportHtml, findUnmappedCaptures };

function readPng(fp) {
  return PNG.sync.read(fs.readFileSync(fp));
}
function b64Png(png) {
  return 'data:image/png;base64,' + PNG.sync.write(png).toString('base64');
}

/** Screen-ids captured under `app-<screen-id>.png` in `appDir` that have no
 *  corresponding entry in the frame map — i.e. no authoritative proof frame
 *  to diff against. These would otherwise be silently skipped. */
function findUnmappedCaptures(appDir, frameMap) {
  const mapped = new Set(Object.keys(frameMap));
  return fs.readdirSync(appDir)
    .filter((f) => f.startsWith('app-') && f.endsWith('.png'))
    .map((f) => f.slice('app-'.length, -'.png'.length))
    .filter((screenId) => !mapped.has(screenId))
    .sort();
}

function main() {
  const { values } = parseArgs({ options: {
    app: { type: 'string' }, proofs: { type: 'string' }, map: { type: 'string' },
    accepted: { type: 'string' }, out: { type: 'string' },
  }});
  const outDir = path.resolve(values.out);
  fs.mkdirSync(outDir, { recursive: true });

  const frameMap = JSON.parse(fs.readFileSync(values.map, 'utf8'));
  const accepted = values.accepted && fs.existsSync(values.accepted)
    ? JSON.parse(fs.readFileSync(values.accepted, 'utf8')) : [];
  const acceptedById = Object.fromEntries(accepted.map((a) => [a.screenId, a.reason]));

  const rows = [];
  for (const [screenId, entry] of Object.entries(frameMap)) {
    const appFile = path.join(values.app, `app-${screenId}.png`);
    const nn = String(entry.frame).padStart(2, '0');
    const proofFile = path.join(values.proofs, `proof-frame-${nn}.png`);
    if (!fs.existsSync(appFile)) { console.warn(`  skip ${screenId}: no app capture`); continue; }
    if (!fs.existsSync(proofFile)) { console.warn(`  skip ${screenId}: no proof frame ${nn}`); continue; }

    const appPng = readPng(appFile);
    const proofPng = readPng(proofFile);
    const score = scorePair(proofPng, appPng);
    const heat = heatmap(proofPng, appPng);
    fs.writeFileSync(path.join(outDir, `heat-${screenId}.png`), PNG.sync.write(heat));

    rows.push({
      screenId, frameTitle: entry.title, score,
      accepted: screenId in acceptedById,
      acceptedReason: acceptedById[screenId] || '',
      proofB64: b64Png(normalize(proofPng, NORM_W, NORM_H)),
      appB64: b64Png(normalize(appPng, NORM_W, NORM_H)),
      heatB64: b64Png(heat),
    });
    console.log(`  ${screenId}: ${(score * 100).toFixed(1)}%${screenId in acceptedById ? ' (accepted)' : ''}`);
  }

  const unmapped = findUnmappedCaptures(values.app, frameMap);
  for (const screenId of unmapped) {
    console.warn(`unmapped capture (no frame-map entry): ${screenId}`);
  }

  fs.writeFileSync(path.join(outDir, 'parity-report.html'), buildReportHtml(rows, unmapped));
  console.log(`\ndone — ${rows.length} pairs -> ${path.join(outDir, 'parity-report.html')}`);
}

if (require.main === module) {
  try { main(); } catch (e) { console.error(e); process.exit(1); }
}
