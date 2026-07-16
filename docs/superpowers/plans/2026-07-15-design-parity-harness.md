# Design-Parity Verification Harness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every build, render every app screen and its authoritative design proof side-by-side with a coarse mechanical divergence score, so a proof-vs-implementation discrepancy can't ship unseen.

**Architecture:** Two capture halves that meet in a diff engine. The **proof half** (`render_proofs.js`) extracts each phone-frame block from the design canvas, renders it through the canvas's own dc-runtime in the Ink palette via headless Chromium, and emits one PNG per frame. The **app half** (extended `ScreenshotTests.swift` + a seeded fixture world + a `#if DEBUG` screen catalog) captures one PNG per app screen/state in CI. The **diff engine** (`parity_diff.js`) joins them through a hand-authored `frame-map.json`, computes a downscaled structural score, renders a heatmap, and emits one self-contained, worst-first `parity-report.html`. It is report-only — never a build gate.

**Tech Stack:** Node ≥ 18 (built-in `node:test`, `node:http`, `util.parseArgs`), `puppeteer` (bundled Chromium), `pngjs` + `pixelmatch` (pure-JS image ops, no native compile), Swift/XCUITest, GitHub Actions (`macos-15` for the app half, `ubuntu-latest` for the parity job), Supabase REST (service-role seed).

## Global Constraints

- **Report-only, never a build gate.** The parity CI job is `continue-on-error: true`. A hard gate is explicitly deferred until a clean baseline exists.
- **Coarse/structural diff, not pixel-exact.** Web-rendered proofs and iOS-rasterized screenshots can never pixel-match; the score exists to rank divergence, not to pass/fail.
- **All proof renders use the Ink palette** — `data-palette="ink"` on the `.gs-theme` wrapper (matches the CI test user's palette).
- **Proof crop = the `.gs-theme` content element** (the phone-frame content, below the drawn status bar and above the home indicator).
- **Additive only — no app-architecture refactor.** The debug catalog is compiled out of release entirely (`#if DEBUG`). No production view is restructured.
- **Screen-id naming is the join key.** App captures are named `app-<screen-id>.png`; proof renders are `proof-frame-<NN>.png` (NN = zero-padded frame index); `docs/design/frame-map.json` binds each `<screen-id>` to a frame index.
- **Credentials only from gitignored `.env.local`.** The seed uses `SUPABASE_URL` + `SUPABASE_SECRET_KEY` (service role), same as `scripts/seed_routines.js`. Never hardcode secrets.
- **Never `git add -A`.** Stage explicit paths in every commit. Never commit to `master`; all work happens on the feature branch this plan is executed on.
- **JS deps stay minimal.** Tests use Node's built-in `node:test` runner (no Jest/Mocha). Image math uses `pngjs` + `pixelmatch` (pure JS). Only `puppeteer` pulls a binary (Chromium), and only the render script needs it.

---

## File Structure

**New JavaScript (repo root `scripts/`):**
- `scripts/render_proofs.js` — proof half: canvas → per-frame Ink PNGs + `manifest.json`. Exports `buildFramePages(canvasHtml)` and `slug(s)` for testing.
- `scripts/parity_diff.js` — diff engine: pairs app↔proof PNGs, scores, heatmaps, emits report. Exports `normalize`, `scorePair`, `heatmap`, `buildReportHtml`.
- `scripts/seed_qa_fixtures.js` — idempotent CI-account fixture world.
- `scripts/tests/render_proofs.test.js` — unit tests for frame extraction.
- `scripts/tests/parity_diff.test.js` — unit tests for scoring + report.
- `scripts/tests/fixtures/mini-canvas.html` — tiny synthetic canvas (2 frames) for extraction tests.

**New checked-in config (`docs/design/`):**
- `docs/design/frame-map.json` — `{ "<screen-id>": { "frame": <idx>, "title": "<title>" } }`. Hand-authored; the authoritative binding of app screens to canvas frames.
- `docs/design/accepted-deviations.json` — `[{ "screenId": "<id>", "reason": "<text>" }]`. Known-OK divergences.

**New Swift (`GymSyncApp/GymSync/`):**
- `GymSyncApp/GymSync/App/CatalogHostView.swift` — `#if DEBUG` screen catalog: maps a `UITEST_CATALOG` id to a force-presented view with hand-built fixture state.

**Modified:**
- `GymSyncApp/GymSync/App/GymSyncApp.swift:14-19` — under `#if DEBUG`, route to `CatalogHostView` when `UITEST_CATALOG` is set.
- `GymSyncApp/GymSyncUITests/ScreenshotTests.swift` — walk every seeded-reachable screen + every catalog state, attach `app-<screen-id>.png`.
- `.github/workflows/ios.yml` — seed step before app capture; new `parity` job (needs `screenshots`).
- `package.json` — add `puppeteer`, `pngjs`, `pixelmatch` to `devDependencies`; add `test:parity` script.
- `GymSyncApp/GymSyncTests/` — one new test file for the catalog enum exhaustiveness (Task 4).

---

## Task 1: Proof render script

**Files:**
- Create: `scripts/render_proofs.js`
- Create: `scripts/tests/render_proofs.test.js`
- Create: `scripts/tests/fixtures/mini-canvas.html`
- Create: `docs/design/frame-map.json`
- Modify: `package.json` (add `puppeteer` devDependency + `test:parity` script)

**Interfaces:**
- Produces: `buildFramePages(canvasHtml: string) => Array<{ idx: number, title: string, name: string, html: string }>` — pure. `slug(s: string) => string`.
- Produces (CLI): `node scripts/render_proofs.js --canvas <path> --design-dir <dir> --out <dir>` writes `proof-frame-<NN>.png` (NN = `String(idx).padStart(2,'0')`) for every frame, plus `manifest.json` = `[{ idx, title, name, file }]`.
- Produces (artifact): `docs/design/frame-map.json` consumed by Task 2.

- [ ] **Step 1: Add the render dependency and test script to package.json**

Edit `package.json` `devDependencies` to add (keep existing `pg`, `supabase`):

```json
  "devDependencies": {
    "pg": "^8.22.0",
    "pixelmatch": "^5.3.0",
    "pngjs": "^7.0.0",
    "puppeteer": "^23.0.0",
    "supabase": "^2.109.1"
  },
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1",
    "test:parity": "node --test scripts/tests/"
  }
```

Then install:

```bash
cd /g/Projects/GymSync && npm install
```

Expected: `puppeteer` downloads a Chromium build; `node_modules/puppeteer`, `node_modules/pngjs`, `node_modules/pixelmatch` exist.

- [ ] **Step 2: Write the fixture canvas**

Create `scripts/tests/fixtures/mini-canvas.html` — a minimal stand-in for the real canvas: a `<style>` block plus two `<h5>`-titled `<x-import>` frames.

```html
<!DOCTYPE html>
<html><head><style>.demo{color:red}</style></head>
<body>
<h5>Home · Overview</h5>
<x-import component-from-global-scope="IOSDevice" from="./ios-frame.jsx" width="{{ 380 }}" height="{{ 824 }}"><div>home</div></x-import>
<h5>Library &amp; Packs</h5>
<x-import component-from-global-scope="IOSDevice" from="./ios-frame.jsx" width="{{ 380 }}" height="{{ 824 }}"><div>library</div></x-import>
</body></html>
```

- [ ] **Step 3: Write the failing test for frame extraction**

Create `scripts/tests/render_proofs.test.js`:

```js
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { buildFramePages, slug } = require('../render_proofs.js');

const canvas = fs.readFileSync(
  path.join(__dirname, 'fixtures', 'mini-canvas.html'), 'utf8'
);

test('slug normalizes titles', () => {
  assert.equal(slug('Home · Overview'), 'home-overview');
  assert.equal(slug('Library & Packs'), 'library-packs');
});

test('buildFramePages returns one page per x-import block', () => {
  const pages = buildFramePages(canvas);
  assert.equal(pages.length, 2);
});

test('each page takes its title from the nearest preceding h5', () => {
  const pages = buildFramePages(canvas);
  assert.equal(pages[0].title, 'Home - Overview'); // · replaced with -
  assert.equal(pages[0].name, '00-home-overview');
  assert.equal(pages[1].title, 'Library & Packs'); // &amp; decoded
  assert.equal(pages[1].name, '01-library-packs');
});

test('generated page rewrites the ios-frame import to an absolute path and sets Ink palette', () => {
  const pages = buildFramePages(canvas);
  assert.ok(pages[0].html.includes('from="/ios-frame.jsx"'));
  assert.ok(!pages[0].html.includes('from="./ios-frame.jsx"'));
  assert.ok(pages[0].html.includes('data-palette="ink"'));
  assert.ok(pages[0].html.includes('src="/support.js"'));
});
```

- [ ] **Step 4: Run the test to verify it fails**

```bash
cd /g/Projects/GymSync && node --test scripts/tests/render_proofs.test.js
```

Expected: FAIL — `Cannot find module '../render_proofs.js'`.

- [ ] **Step 5: Implement render_proofs.js**

Create `scripts/render_proofs.js`:

```js
#!/usr/bin/env node
/**
 * Proof half of the design-parity harness. Extracts every phone-frame
 * <x-import> block from the design canvas, wraps each in a standalone
 * dc-runtime page rendered in the Ink palette, and screenshots the phone
 * content via headless Chromium — one PNG per canvas frame.
 *
 * Usage:
 *   node scripts/render_proofs.js --canvas "docs/design/Gym Sync App Designs.dc.html" \
 *     --design-dir docs/design --out .superpowers/parity/proofs
 *
 * The static server is rooted at --design-dir so the canvas's own runtime
 * assets (/support.js, /_ds/..., /ios-frame.jsx) resolve by absolute path;
 * each generated frame page is served from memory at /__frame.html.
 */
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { parseArgs } = require('node:util');

// The design system id embedded in the canvas's <x-import>/_ds asset paths.
const DS_ID = 'modernist-91f0e407-441d-4fe1-9229-e6d9255276ee';

function slug(s) {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

/**
 * Pure: canvas HTML -> [{ idx, title, name, html }], one entry per
 * phone-frame <x-import> block. Title is the nearest preceding <h5>.
 */
function buildFramePages(canvasHtml) {
  const styleStart = canvasHtml.indexOf('<style>');
  const styleBlock = styleStart === -1 ? '' : canvasHtml.slice(
    styleStart + '<style>'.length, canvasHtml.indexOf('</style>')
  );
  const reImport = /<x-import\b[\s\S]*?<\/x-import>/g;
  const pages = [];
  let m, idx = 0;
  while ((m = reImport.exec(canvasHtml))) {
    const block = m[0].split('from="./ios-frame.jsx"').join('from="/ios-frame.jsx"');
    const before = canvasHtml.slice(0, m.index);
    const h5s = [...before.matchAll(/<h5[^>]*>([^<]+)<\/h5>/g)];
    const title = (h5s.length ? h5s[h5s.length - 1][1] : 'frame' + idx)
      .replace(/&amp;/g, '&').replace(/·/g, '-').trim();
    const nn = String(idx).padStart(2, '0');
    const name = nn + '-' + slug(title);
    const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><script src="/support.js"></script></head><body>
<x-dc><helmet><link rel="stylesheet" href="/_ds/${DS_ID}/styles.css"><script src="/_ds/${DS_ID}/_ds_bundle.js"></script><style>${styleBlock}
html,body{margin:0;padding:0;background:#b8b2a8} .gs-theme{padding:14px;display:inline-block}</style></helmet>
<div class="gs-theme" data-palette="ink">
${block}
</div></x-dc>
<script type="text/x-dc" data-dc-script data-props="{&quot;palette&quot;:{&quot;editor&quot;:&quot;enum&quot;,&quot;default&quot;:&quot;ink&quot;,&quot;options&quot;:[&quot;midnight&quot;,&quot;arena&quot;,&quot;ink&quot;,&quot;modernist&quot;],&quot;tsType&quot;:&quot;string&quot;}}"></script>
</body></html>`;
    pages.push({ idx, title, name, html });
    idx++;
  }
  return pages;
}

module.exports = { buildFramePages, slug };

const MIME = {
  '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.json': 'application/json',
  '.jsx': 'text/javascript', '.woff2': 'font/woff2', '.woff': 'font/woff',
};

async function main() {
  const { values } = parseArgs({ options: {
    canvas: { type: 'string' },
    'design-dir': { type: 'string' },
    out: { type: 'string' },
  }});
  const canvasHtml = fs.readFileSync(values.canvas, 'utf8');
  const designDir = path.resolve(values['design-dir']);
  const outDir = path.resolve(values.out);
  fs.mkdirSync(outDir, { recursive: true });

  const pages = buildFramePages(canvasHtml);

  let currentHtml = '';
  const server = http.createServer((req, res) => {
    const url = req.url.split('?')[0];
    if (url === '/__frame.html') {
      res.setHeader('content-type', 'text/html');
      res.end(currentHtml);
      return;
    }
    const fp = path.join(designDir, decodeURIComponent(url));
    if (fp.startsWith(designDir) && fs.existsSync(fp) && fs.statSync(fp).isFile()) {
      res.setHeader('content-type', MIME[path.extname(fp)] || 'application/octet-stream');
      fs.createReadStream(fp).pipe(res);
      return;
    }
    res.statusCode = 404;
    res.end('not found');
  });
  await new Promise((r) => server.listen(0, r));
  const port = server.address().port;

  // Lazy-require so the pure exports (and their tests) never need Chromium.
  const puppeteer = require('puppeteer');
  const browser = await puppeteer.launch({ args: ['--no-sandbox', '--disable-setuid-sandbox'] });
  const page = await browser.newPage();
  await page.setViewport({ width: 460, height: 940, deviceScaleFactor: 2 });

  const manifest = [];
  for (const p of pages) {
    currentHtml = p.html;
    await page.goto(`http://localhost:${port}/__frame.html`, { waitUntil: 'networkidle0' });
    await new Promise((r) => setTimeout(r, 500)); // settle dc-runtime paint
    const el = await page.$('.gs-theme');
    const nn = String(p.idx).padStart(2, '0');
    const file = `proof-frame-${nn}.png`;
    if (el) {
      await el.screenshot({ path: path.join(outDir, file) });
    } else {
      await page.screenshot({ path: path.join(outDir, file) });
    }
    manifest.push({ idx: p.idx, title: p.title, name: p.name, file });
    console.log(`  rendered ${file}  ·  ${p.title}`);
  }
  fs.writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));
  await browser.close();
  server.close();
  console.log(`\ndone — ${manifest.length} proof frames -> ${outDir}`);
}

if (require.main === module) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
cd /g/Projects/GymSync && node --test scripts/tests/render_proofs.test.js
```

Expected: PASS — all four tests green.

- [ ] **Step 7: Smoke-render the real canvas and eyeball one frame**

```bash
cd /g/Projects/GymSync && node scripts/render_proofs.js \
  --canvas "docs/design/Gym Sync App Designs.dc.html" \
  --design-dir docs/design \
  --out .superpowers/parity/proofs
```

Expected: prints `rendered proof-frame-00.png · Home` … and `done — ~50 proof frames`. Open `.superpowers/parity/proofs/proof-frame-00.png` and confirm it shows the Home screen in the bone/navy Ink palette (not midnight/dark). `.superpowers/` is git-ignored scratch — these PNGs are not committed.

- [ ] **Step 8: Author frame-map.json**

Read `manifest.json` to see each frame's index + title, then create `docs/design/frame-map.json` binding each app screen-id to its authoritative frame. Start with the six screenshot-verified screens plus the You/Appearance pair, using the frame indices the manifest reports (titles shown are the expected canvas labels — confirm the index against the manifest):

```json
{
  "tab-home": { "frame": 0, "title": "Home" },
  "tab-library": { "frame": 1, "title": "Library" },
  "tab-social": { "frame": 2, "title": "Social" },
  "tab-stats": { "frame": 3, "title": "Stats" },
  "tab-you": { "frame": 35, "title": "Settings Hub" },
  "you-appearance": { "frame": 33, "title": "Theme Picker" }
}
```

This file grows in Tasks 4-5 as catalog states and seeded-reachable screens gain captures. A `<screen-id>` with no entry here is simply not diffed yet (the diff engine skips unmapped app captures and logs them).

- [ ] **Step 9: Commit**

```bash
cd /g/Projects/GymSync
git add scripts/render_proofs.js scripts/tests/render_proofs.test.js \
  scripts/tests/fixtures/mini-canvas.html docs/design/frame-map.json \
  package.json package-lock.json
git commit -m "feat(parity): proof render script + frame map"
```

---

## Task 2: Diff + report engine

**Files:**
- Create: `scripts/parity_diff.js`
- Create: `scripts/tests/parity_diff.test.js`
- Modify: `package.json` (deps already added in Task 1 — no change if Task 1 done; otherwise add `pngjs`, `pixelmatch`)

**Interfaces:**
- Consumes: `proof-frame-<NN>.png` + `manifest.json` (Task 1), `docs/design/frame-map.json` (Task 1), `app-<screen-id>.png` (Task 5), `docs/design/accepted-deviations.json` (Task 6; treated as `[]` if absent).
- Produces: `normalize(src: PNG, w: number, h: number) => PNG` (nearest-neighbor resize), `scorePair(a: PNG, b: PNG) => number` in `[0,1]`, `heatmap(a: PNG, b: PNG) => PNG`, `buildReportHtml(rows) => string` where each row is `{ screenId, frameTitle, score, accepted, acceptedReason, proofB64, appB64, heatB64 }`.
- Produces (CLI): `node scripts/parity_diff.js --app <dir> --proofs <dir> --map docs/design/frame-map.json --accepted docs/design/accepted-deviations.json --out <dir>` writes `parity-report.html` (self-contained, base64-embedded, worst-first) + per-screen `heat-<screenId>.png`.

- [ ] **Step 1: Write the failing test for the pure image ops**

Create `scripts/tests/parity_diff.test.js`:

```js
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
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /g/Projects/GymSync && node --test scripts/tests/parity_diff.test.js
```

Expected: FAIL — `Cannot find module '../parity_diff.js'`.

- [ ] **Step 3: Implement parity_diff.js**

Create `scripts/parity_diff.js`:

```js
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
 *  `accepted` class so the template can separate known-OK divergence. */
function buildReportHtml(rows) {
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
</style></head>
<body><div class="wrap">
<h1>GymSync Design Parity</h1>
<p class="lede">Every captured app screen vs. its authoritative Ink-palette proof, sorted worst-divergence first. Score is a coarse structural delta — high means "look at this," not "failed." Accepted deviations are dimmed and sorted with their score but flagged.</p>
<div class="pairs">${cards}</div>
</div></body></html>`;
}

module.exports = { normalize, scorePair, heatmap, buildReportHtml };

function readPng(fp) {
  return PNG.sync.read(fs.readFileSync(fp));
}
function b64Png(png) {
  return 'data:image/png;base64,' + PNG.sync.write(png).toString('base64');
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

  fs.writeFileSync(path.join(outDir, 'parity-report.html'), buildReportHtml(rows));
  console.log(`\ndone — ${rows.length} pairs -> ${path.join(outDir, 'parity-report.html')}`);
}

if (require.main === module) {
  try { main(); } catch (e) { console.error(e); process.exit(1); }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /g/Projects/GymSync && node --test scripts/tests/parity_diff.test.js
```

Expected: PASS — all four tests green.

- [ ] **Step 5: Prove the pipeline end-to-end against the 6 existing app screenshots**

Download the `app-screenshots` artifact from the most recent `iOS` workflow run that produced it, into a local dir. The current pipeline names them `tab-*.png` / `you-appearance.png`, not `app-*.png`, so copy them to the harness naming for this one proof run:

```bash
cd /g/Projects/GymSync
RUN=$(gh run list --workflow=iOS.yml --json databaseId,conclusion \
  --jq 'map(select(.conclusion=="success"))[0].databaseId' -L 20)
gh run download "$RUN" -n app-screenshots -D .superpowers/parity/app-raw
mkdir -p .superpowers/parity/app
for f in home library social stats you; do
  [ -f ".superpowers/parity/app-raw/tab-$f.png" ] && cp ".superpowers/parity/app-raw/tab-$f.png" ".superpowers/parity/app/app-tab-$f.png"
done
[ -f .superpowers/parity/app-raw/you-appearance.png ] && cp .superpowers/parity/app-raw/you-appearance.png .superpowers/parity/app/app-you-appearance.png
node scripts/parity_diff.js \
  --app .superpowers/parity/app \
  --proofs .superpowers/parity/proofs \
  --map docs/design/frame-map.json \
  --out .superpowers/parity/report
```

Expected: prints a score line per mapped screen and writes `.superpowers/parity/report/parity-report.html`. Open it: three columns (Proof · App · Diff) per screen, sorted worst-first. Confirm the Library and You rows (the known systematic divergences) score meaningfully higher than Home/Stats. This validates the full join → score → report path before any app-side work exists. (If `gh` can't find a run with the artifact, use the 6 PNGs already captured in the scratchpad under `app-shots3/` with the same rename.)

- [ ] **Step 6: Commit**

```bash
cd /g/Projects/GymSync
git add scripts/parity_diff.js scripts/tests/parity_diff.test.js
git commit -m "feat(parity): diff + report engine"
```

---

## Task 3: Fixture seed script

**Files:**
- Create: `scripts/seed_qa_fixtures.js`

**Interfaces:**
- Consumes: `SUPABASE_URL` + `SUPABASE_SECRET_KEY` from `.env.local`; a `--username <ci_test_user>` arg naming the CI test account.
- Produces: an idempotent deterministic world for that account — a group with the user as member, sessions in each state, a chat thread with mixed messages, friends (accepted + pending), 2-3 routines with exercises, personal records, a published featured routine. Re-runnable without duplication.

- [ ] **Step 1: Confirm the schema for the tables the seed touches**

```bash
cd /g/Projects/GymSync && node scripts/db_query.js "select table_name from information_schema.tables where table_schema='public' order by table_name" 2>/dev/null || node -e "console.log('use mcp list_tables or scripts/db_query.js to enumerate columns for: groups, group_members, sessions, messages, friendships, routines, routine_exercises, personal_records')"
```

Expected: a table list. Note the exact column names + enum values for `sessions.status` (scheduled / lobby_open / voting / locked / in_progress / completed), `friendships` (status: accepted / pending), `messages` (kind: text / soundboard / voice), and the group-membership join table. These drive the insert payloads below — adjust field names to match the live schema before writing inserts.

- [ ] **Step 2: Write the seed script**

Create `scripts/seed_qa_fixtures.js`. It mirrors `scripts/seed_routines.js`'s env-loading + `rest()` helper exactly, and makes every insert idempotent by first deleting the fixture's own prior rows (keyed on a stable marker — a `[QA]` name prefix or a fixed UUID namespace) then re-inserting, so re-runs converge:

```js
#!/usr/bin/env node
/**
 * Seeds a deterministic, screenshot-stable world for the CI test account so
 * the app's real internal fetches return known data on every screen. Idempotent:
 * every fixture row is namespaced with a stable marker and deleted-then-reinserted,
 * so re-running converges to the same state (no duplication).
 *
 * Usage:  node scripts/seed_qa_fixtures.js --username <ci_test_user>
 * Requires SUPABASE_URL + SUPABASE_SECRET_KEY in .env.local (service role).
 */
const fs = require('node:fs');
const path = require('node:path');
const { parseArgs } = require('node:util');

const env = fs.readFileSync(path.join(__dirname, '..', '.env.local'), 'utf8');
const get = (k) => { const m = new RegExp(`${k}=(.+)`).exec(env); return m && m[1].trim(); };
const SUPABASE_URL = get('SUPABASE_URL');
const SUPABASE_SECRET_KEY = get('SUPABASE_SECRET_KEY');
if (!SUPABASE_URL || !SUPABASE_SECRET_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SECRET_KEY in .env.local'); process.exit(1);
}
const headers = {
  apikey: SUPABASE_SECRET_KEY, Authorization: `Bearer ${SUPABASE_SECRET_KEY}`,
  'Content-Type': 'application/json',
};
async function rest(pathAndQuery, opts = {}) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${pathAndQuery}`, {
    ...opts, headers: { ...headers, ...(opts.headers || {}) },
  });
  if (!res.ok) throw new Error(`${pathAndQuery}: ${res.status} ${await res.text()}`);
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}
const rep = { Prefer: 'return=representation' };
const MARK = '[QA]'; // stable marker: name-prefix for fixture rows we own

async function main() {
  const { values } = parseArgs({ options: { username: { type: 'string' } } });
  if (!values.username) { console.error('Usage: --username <ci_test_user>'); process.exit(1); }

  const [me] = await rest(`profiles?select=id,username&username=ilike.${encodeURIComponent(values.username)}`);
  if (!me) { console.error(`No profile for "${values.username}"`); process.exit(1); }
  console.log(`Seeding QA world for @${me.username} (${me.id})`);

  // --- groups + membership (idempotent: drop this account's [QA] groups first) ---
  await rest(`groups?owner_id=eq.${me.id}&name=ilike.${encodeURIComponent(MARK + '%')}`, { method: 'DELETE' });
  const [group] = await rest('groups', { method: 'POST', headers: rep,
    body: JSON.stringify({ owner_id: me.id, name: `${MARK} Push Crew` }) });
  await rest('group_members', { method: 'POST',
    body: JSON.stringify({ group_id: group.id, user_id: me.id, role: 'member' }) });
  console.log(`  group ${group.id}`);

  // --- sessions in each state (deleted by group_id, then reinserted) ---
  await rest(`sessions?group_id=eq.${group.id}`, { method: 'DELETE' });
  const states = ['scheduled', 'lobby_open', 'voting', 'locked', 'in_progress', 'completed'];
  for (const status of states) {
    await rest('sessions', { method: 'POST',
      body: JSON.stringify({ group_id: group.id, host_id: me.id, status,
        title: `${MARK} ${status}`, scheduled_at: new Date().toISOString() }) });
  }
  console.log(`  sessions: ${states.join(', ')}`);

  // --- chat thread: text + soundboard echo + voice-note row ---
  // (Insert into the group's message table; kinds per the messages.kind enum.)
  // --- friends: one accepted, one pending (requires two more test profiles) ---
  // --- routines (2-3) with exercises via the seed_routines pattern ---
  // --- personal_records for the Stats hero + Recent PRs table ---
  // --- one published/featured routine for the Library Featured shelf ---
  // Each block: DELETE this account's [QA]-marked rows, then POST fresh.
  // Fill these in against the exact columns confirmed in Step 1.

  console.log('\ndone — QA fixture world seeded (idempotent).');
}
main().catch((e) => { console.error('Fatal:', e.message); process.exit(1); });
```

Complete the commented blocks (chat, friends, routines, PRs, featured) using the exact columns from Step 1, each following the same delete-marked-then-insert idempotency shape shown for groups and sessions.

- [ ] **Step 3: Run once and verify the world appears**

```bash
cd /g/Projects/GymSync && node scripts/seed_qa_fixtures.js --username ci_test_user_2
```

Expected: prints each seeded block; exits 0. Spot-check with a query, e.g.:

```bash
node scripts/db_query.js "select status, count(*) from sessions s join groups g on g.id=s.group_id where g.name like '[QA]%' group by status"
```

Expected: one row per session state, count 1 each.

- [ ] **Step 4: Run a SECOND time and verify idempotency (the load-bearing property)**

```bash
cd /g/Projects/GymSync && node scripts/seed_qa_fixtures.js --username ci_test_user_2
node scripts/db_query.js "select count(*) from groups where owner_id=(select id from profiles where username ilike 'ci_test_user_2') and name like '[QA]%'"
```

Expected: the group count is still exactly 1 (not 2). Same for sessions/messages/friends/routines — the second run replaced rather than duplicated. If any count doubled, the delete-marker for that block is wrong; fix before committing.

- [ ] **Step 5: Commit**

```bash
cd /g/Projects/GymSync
git add scripts/seed_qa_fixtures.js
git commit -m "feat(parity): idempotent CI fixture seed"
```

---

## Task 4: Debug screen catalog + launch hook

**Files:**
- Create: `GymSyncApp/GymSync/App/CatalogHostView.swift`
- Modify: `GymSyncApp/GymSync/App/GymSyncApp.swift:14-19`
- Create: `GymSyncApp/GymSyncTests/CatalogScreenTests.swift`

**Interfaces:**
- Consumes: `UITEST_CATALOG=<screen-id>` launch environment (set by `ScreenshotTests` in Task 5), read under `#if DEBUG` in `GymSyncApp.body`.
- Produces: `enum CatalogScreen: String, CaseIterable` whose raw values are the catalog screen-ids, and `CatalogHostView(screen:)` mapping each to a force-presented view with hand-built fixture state. Compiled out of release.

- [ ] **Step 1: Write the failing enum-exhaustiveness test**

Create `GymSyncApp/GymSyncTests/CatalogScreenTests.swift`:

```swift
import XCTest
@testable import GymSync

/// The catalog is the only way the parity harness reaches states that
/// navigation + seeding can't (overlays, voice-dock states, onboarding steps).
/// This guards the contract Task 5's UI test relies on: every id it drives
/// resolves to a real case, and the documented set is present.
final class CatalogScreenTests: XCTestCase {
    func testEveryDocumentedIdRoundTrips() {
        let ids = [
            "pr-celebration",
            "voice-idle", "voice-connecting", "voice-transmitting",
            "voice-mic-denied", "voice-unavailable",
            "onboarding-signin", "onboarding-username", "onboarding-homegym",
            "onboarding-homegym-searching", "onboarding-done",
            "onboarding-push-priming", "onboarding-push-denied",
            "stattile-loading", "stattile-error", "stattile-empty",
        ]
        for id in ids {
            XCTAssertNotNil(CatalogScreen(rawValue: id), "missing catalog case: \(id)")
        }
    }

    func testAllCasesHaveUniqueRawValues() {
        let raws = CatalogScreen.allCases.map(\.rawValue)
        XCTAssertEqual(raws.count, Set(raws).count, "duplicate catalog raw values")
    }
}
```

- [ ] **Step 2: Verify it fails to compile**

Note: on the Windows dev box, Swift can't be compiled locally — this test runs in the `build-test` CI job. Locally, verify by inspection that `CatalogScreen` does not yet exist. In CI it fails with "cannot find 'CatalogScreen' in scope". Proceed to implement.

- [ ] **Step 3: Implement CatalogHostView.swift**

Create `GymSyncApp/GymSync/App/CatalogHostView.swift`. Wrap the whole file in `#if DEBUG` so it never enters a release build:

```swift
#if DEBUG
import SwiftUI

/// Debug-only screen catalog. The parity harness sets `UITEST_CATALOG=<id>`
/// as a launch env var; `GymSyncApp` then presents `CatalogHostView` instead
/// of the normal `RootView`, force-rendering a single target view with
/// hand-built fixture state so the harness can screenshot states that
/// navigation + seeded data can't reach (overlays, voice-dock states,
/// onboarding steps). Compiled out of release entirely.
enum CatalogScreen: String, CaseIterable {
    case prCelebration = "pr-celebration"
    case voiceIdle = "voice-idle"
    case voiceConnecting = "voice-connecting"
    case voiceTransmitting = "voice-transmitting"
    case voiceMicDenied = "voice-mic-denied"
    case voiceUnavailable = "voice-unavailable"
    case onboardingSignIn = "onboarding-signin"
    case onboardingUsername = "onboarding-username"
    case onboardingHomeGym = "onboarding-homegym"
    case onboardingHomeGymSearching = "onboarding-homegym-searching"
    case onboardingDone = "onboarding-done"
    case onboardingPushPriming = "onboarding-push-priming"
    case onboardingPushDenied = "onboarding-push-denied"
    case statTileLoading = "stattile-loading"
    case statTileError = "stattile-error"
    case statTileEmpty = "stattile-empty"
}

struct CatalogHostView: View {
    let screen: CatalogScreen
    @Environment(\.gsTheme) private var theme

    var body: some View {
        Group {
            switch screen {
            case .prCelebration:            content_prCelebration
            case .voiceIdle:                content_voice(.idle)
            case .voiceConnecting:          content_voice(.connecting)
            case .voiceTransmitting:        content_voice(.transmitting)
            case .voiceMicDenied:           content_voice(.micDenied)
            case .voiceUnavailable:         content_voice(.unavailable)
            case .onboardingSignIn:         SignInView()
            case .onboardingUsername:       content_onboardingUsername
            case .onboardingHomeGym:        content_homeGym(searching: false)
            case .onboardingHomeGymSearching: content_homeGym(searching: true)
            case .onboardingDone:           content_onboardingDone
            case .onboardingPushPriming:    content_pushPriming
            case .onboardingPushDenied:     content_pushDenied
            case .statTileLoading:          content_statTile(.loading)
            case .statTileError:            content_statTile(.error)
            case .statTileEmpty:            content_statTile(.empty)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
    }

    // Each `content_*` builder force-constructs its target view with fixture
    // state. Implement against the real view initializers — reuse the same
    // fixture models the views' own #Preview/tests use where they exist, and
    // stub the minimum otherwise. Keep them presentational only (no live
    // network / LiveKit) so the render is deterministic in CI.
}
#endif
```

Implement each `content_*` builder against the real view initializers (`VoiceDock`, `HomeGymSetupView`, `PushPrimingView`, `GSStatTile`, the PR overlay, `UsernameView`, etc.), passing fixture state. If a view's state type isn't yet expressible from outside, add the smallest `#if DEBUG` convenience initializer to that view rather than restructuring it.

- [ ] **Step 4: Wire the launch hook in GymSyncApp.swift**

Modify `GymSyncApp.swift` body (lines 14-19) to route to the catalog under DEBUG when the env var is set:

```swift
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let id = ProcessInfo.processInfo.environment["UITEST_CATALOG"],
               let screen = CatalogScreen(rawValue: id) {
                CatalogHostView(screen: screen)
                    .environment(\.gsTheme, ThemeStore.shared.current)
            } else {
                RootView()
                    .environment(AuthService.shared)
            }
            #else
            RootView()
                .environment(AuthService.shared)
            #endif
        }
    }
```

- [ ] **Step 5: Regenerate the project and confirm it builds (CI)**

The new file must exist before `xcodegen generate` (the generated project only includes files present at generate time — see `ios.yml:23`). Locally, verify the file is on disk and syntactically consistent by inspection. In CI, the `build-test` job compiles it and runs `CatalogScreenTests`.

```bash
cd /g/Projects/GymSync && git add GymSyncApp/GymSync/App/CatalogHostView.swift \
  GymSyncApp/GymSync/App/GymSyncApp.swift GymSyncApp/GymSyncTests/CatalogScreenTests.swift
git commit -m "feat(parity): debug screen catalog + launch hook"
git push
```

Expected: the `iOS / build-test` job goes green, including `CatalogScreenTests` (2 tests). If a `content_*` builder fails to compile against a view's real initializer, fix the builder (or add a `#if DEBUG` convenience init to that view) — do not restructure the production view.

---

## Task 5: Extend the UITest capture

**Files:**
- Modify: `GymSyncApp/GymSyncUITests/ScreenshotTests.swift`
- Modify: `docs/design/frame-map.json` (add entries for the newly captured screen-ids)

**Interfaces:**
- Consumes: the seeded world (Task 3), the catalog hook (Task 4), the existing autologin (`UITEST_EMAIL`/`UITEST_PASSWORD`).
- Produces: `app-<screen-id>.png` attachments for every reachable screen + every catalog state, exported by the existing `screenshots` CI job.

- [ ] **Step 1: Rename the existing tab captures to the harness convention**

The current captures use `tab-home.png` etc.; the diff engine joins on `app-<screen-id>.png`. Update the six existing `attachScreenshot` calls in `ScreenshotTests.swift` (lines 112, 120, 128, 136, 144, 167) to the new names:

```swift
attachScreenshot(app, named: "app-tab-home.png")
attachScreenshot(app, named: "app-tab-library.png")
attachScreenshot(app, named: "app-tab-social.png")
attachScreenshot(app, named: "app-tab-stats.png")
attachScreenshot(app, named: "app-tab-you.png")
attachScreenshot(app, named: "app-you-appearance.png")
```

- [ ] **Step 2: Add a catalog-driven capture helper**

Add a helper that launches the app straight into a catalog screen (no autologin needed — the catalog bypasses auth) and screenshots it. Insert into `ScreenshotTests`:

```swift
    /// Launches directly into a debug catalog screen (bypasses auth entirely)
    /// and captures it. One test method per state so a single failure doesn't
    /// swallow the rest (same rationale as the per-tab methods).
    private func captureCatalog(_ id: String) {
        let app = XCUIApplication()
        var env = app.launchEnvironment
        env["UITEST_CATALOG"] = id
        app.launchEnvironment = env
        app.launch()
        settle()
        settle()
        attachScreenshot(app, named: "app-\(id).png")
    }

    func testCatalogPRCelebration()      { captureCatalog("pr-celebration") }
    func testCatalogVoiceIdle()          { captureCatalog("voice-idle") }
    func testCatalogVoiceConnecting()    { captureCatalog("voice-connecting") }
    func testCatalogVoiceTransmitting()  { captureCatalog("voice-transmitting") }
    func testCatalogVoiceMicDenied()     { captureCatalog("voice-mic-denied") }
    func testCatalogVoiceUnavailable()   { captureCatalog("voice-unavailable") }
    func testCatalogOnboardingSignIn()   { captureCatalog("onboarding-signin") }
    func testCatalogOnboardingUsername() { captureCatalog("onboarding-username") }
    func testCatalogOnboardingHomeGym()  { captureCatalog("onboarding-homegym") }
    func testCatalogOnboardingHomeGymSearching() { captureCatalog("onboarding-homegym-searching") }
    func testCatalogOnboardingDone()     { captureCatalog("onboarding-done") }
    func testCatalogPushPriming()        { captureCatalog("onboarding-push-priming") }
    func testCatalogPushDenied()         { captureCatalog("onboarding-push-denied") }
    func testCatalogStatTileLoading()    { captureCatalog("stattile-loading") }
    func testCatalogStatTileError()      { captureCatalog("stattile-error") }
    func testCatalogStatTileEmpty()      { captureCatalog("stattile-empty") }
```

- [ ] **Step 3: Add seeded-reachable deep-screen captures**

For screens reachable by navigation once the fixture world exists (lobby, chat, session recap, friends, routine detail), add methods that autologin, navigate, and capture. Example for the Social → Friends list and a group lobby (adjust the queries to the real accessibility labels — reuse the `BEGINSWITH` predicate idiom from `testYouAppearance`):

```swift
    func testFriendsList() {
        let app = launchApp()
        guard waitForTabBar(app) else { return }
        selectTab(app, label: "Social")
        settle()
        // Seeded world puts a crew + friends here; tap into the crew.
        let crew = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '[QA] Push Crew'")).firstMatch
        if crew.waitForExistence(timeout: 10) { crew.tap(); settle() }
        attachScreenshot(app, named: "app-lobby.png")
    }
```

Add analogous methods for `app-chat.png`, `app-session-recap.png`, `app-routine-detail.png`. Keep each defensive (guard `waitForExistence`) so a navigation miss attaches whatever's on screen rather than hard-failing the job (the job is `continue-on-error` anyway).

- [ ] **Step 4: Extend frame-map.json for the new screen-ids**

Add a `frame-map.json` entry for each new `app-<screen-id>.png` that has an authoritative canvas frame, using the frame index from Task 1's `manifest.json`. For example (indices are illustrative — read them from the manifest):

```json
{
  "pr-celebration": { "frame": 12, "title": "PR Moment" },
  "voice-transmitting": { "frame": 8, "title": "Live Session · voice" },
  "onboarding-homegym-searching": { "frame": 42, "title": "Gym Setup · searching" },
  "onboarding-username": { "frame": 40, "title": "Onboarding · Username" },
  "lobby": { "frame": 5, "title": "Lobby" },
  "chat": { "frame": 22, "title": "Chat" }
}
```

Note `onboarding-homegym-searching → frame 42` (`docs/design/unbuilt-frames/42-gym-setup-searching.png`): this is precisely the screen whose divergence the harness exists to catch — its presence in the map is the regression guard.

- [ ] **Step 5: Push and confirm the screenshots job attaches the new PNGs (CI)**

```bash
cd /g/Projects/GymSync
git add GymSyncApp/GymSyncUITests/ScreenshotTests.swift docs/design/frame-map.json
git commit -m "feat(parity): capture all screens + catalog states"
git push
```

Expected: the `iOS / screenshots` job runs; download its `app-screenshots` artifact and confirm it now contains `app-tab-*.png`, `app-you-appearance.png`, and one `app-<id>.png` per catalog state and seeded screen. Some deep-navigation captures may show a fallback screen if a label query missed — that's acceptable for a `continue-on-error` job and refined iteratively; the catalog and tab captures are the reliable core.

---

## Task 6: CI wiring + accepted-deviations baseline

**Files:**
- Modify: `.github/workflows/ios.yml` (seed step in `screenshots` job; new `parity` job)
- Create: `docs/design/accepted-deviations.json`

**Interfaces:**
- Consumes: `app-screenshots` artifact (from `screenshots` job), `render_proofs.js` + `parity_diff.js` + `frame-map.json` + `accepted-deviations.json`.
- Produces: a `parity-report` CI artifact each build. Report-only (`continue-on-error`).

- [ ] **Step 1: Seed the fixture world before app capture**

In `ios.yml`, add a step to the `screenshots` job (after "Generate Xcode project", before "Run screenshot UI tests") that seeds the CI account. It needs `SUPABASE_SECRET_KEY` in the environment written to a temporary `.env.local`:

```yaml
      - name: Seed QA fixture world
        env:
          SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
          SUPABASE_SECRET_KEY: ${{ secrets.SUPABASE_SECRET_KEY }}
          CI_TEST_USERNAME: ${{ secrets.CI_TEST_USERNAME }}
        run: |
          if [ -n "$SUPABASE_SECRET_KEY" ]; then
            printf 'SUPABASE_URL=%s\nSUPABASE_SECRET_KEY=%s\n' "$SUPABASE_URL" "$SUPABASE_SECRET_KEY" > .env.local
            npm ci
            node scripts/seed_qa_fixtures.js --username "$CI_TEST_USERNAME"
            rm -f .env.local
          else
            echo "No SUPABASE_SECRET_KEY (fork PR) — skipping seed; captures will show empty states."
          fi
```

Add `CI_TEST_USERNAME` (the `ci_test_user_2` handle) as a repo secret if not already present.

- [ ] **Step 2: Add the parity job**

Append a new job to `ios.yml` after the `screenshots` job. It runs on Linux (Chrome/Node are cheap there), downloads the app screenshots, renders proofs, diffs, and uploads the report. `continue-on-error` keeps it report-only:

```yaml
  parity:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    needs: screenshots
    continue-on-error: true
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 20

      - name: Install harness deps
        run: npm ci

      - name: Download app screenshots
        uses: actions/download-artifact@v4
        with:
          name: app-screenshots
          path: app-shots

      - name: Render proofs
        run: |
          node scripts/render_proofs.js \
            --canvas "docs/design/Gym Sync App Designs.dc.html" \
            --design-dir docs/design \
            --out proofs

      - name: Diff and report
        run: |
          node scripts/parity_diff.js \
            --app app-shots \
            --proofs proofs \
            --map docs/design/frame-map.json \
            --accepted docs/design/accepted-deviations.json \
            --out parity-out

      - name: Upload parity report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: parity-report
          path: parity-out
          if-no-files-found: warn
```

Note: `puppeteer`'s `npm ci` downloads Chromium on the runner. If the postinstall Chromium fetch is skipped by the environment, add `npx puppeteer browsers install chrome` before "Render proofs".

- [ ] **Step 3: Create the accepted-deviations baseline**

Create `docs/design/accepted-deviations.json` with the deviations already signed off during the manual QA (the You-tab stat tiles + Apple Health row are recorded deviations ahead of the superseded frame; Social shows an empty state by design for the solo test user):

```json
[
  {
    "screenId": "tab-you",
    "reason": "You tab implements the newer Settings Hub with added stat tiles + Apple Health row — a recorded deviation ahead of the superseded canvas 'You' frame, awaiting design sign-off."
  },
  {
    "screenId": "tab-social",
    "reason": "The CI test user is solo, so Social renders the 'No crew yet' empty state (canvas frame 30) rather than the populated Friends list (frame 19). Both are correct for their state; seeded fixtures will populate this in a later pass."
  }
]
```

As the seed populates screens and the two systematic PR-#22 fixes land, prune entries here so the report's signal stays high.

- [ ] **Step 4: Push and confirm the parity artifact is produced (CI)**

```bash
cd /g/Projects/GymSync
git add .github/workflows/ios.yml docs/design/accepted-deviations.json
git commit -m "ci(parity): seed + parity job + accepted-deviations baseline"
git push
```

Expected: on the resulting `iOS` run, `build-test` → `screenshots` → `parity` run in order; `parity` uploads a `parity-report` artifact. Download it, open `parity-report.html`, and confirm: every mapped app screen shows a Proof · App · Diff row, sorted worst-first, with `tab-you` and `tab-social` dimmed/flagged as accepted. This is the success criterion — a complete side-by-side gallery, generated automatically, that would have floated the gym-setup search divergence to the top.

- [ ] **Step 5: Verify the success criterion against the four device-QA findings**

Confirm the report would have surfaced all four findings that manual QA missed: `onboarding-homegym-searching` (map vs search) should score high and sit near the top; the Library scroll, Social void, and top dead-space screens should each appear with a visible Proof↔App structural difference. Record the observation in the PR description. If any of the four does not surface, the frame-map binding or the capture for that screen is wrong — fix it before finishing.

---

## Self-Review

**1. Spec coverage:**
- Component 1 (Fixture seed `seed_qa_fixtures.js`) → Task 3. ✓
- Component 2 (Debug catalog, `UITEST_CATALOG`, `#if DEBUG`) → Task 4. ✓
- Component 3 (App capture extends `ScreenshotTests.swift`, `app-<id>.png`) → Task 5. ✓
- Component 4 (Proof render `render_proofs.js`, Ink palette, frame→screen map, content crop) → Task 1. ✓
- Component 5 (Diff + report `parity_diff.js`, align/score/heatmap/report, accepted flagged) → Task 2. ✓
- CI integration (seed step, `parity` job needs `screenshots`, `continue-on-error`) → Task 6. ✓
- Accepted-deviations mechanism (`accepted-deviations.json`) → Task 6 Step 3. ✓
- Build phases 1-6 → Tasks 1-6 respectively. ✓
- Success criteria (every screen paired; would surface the four findings; additive; CI report-only) → Task 6 Steps 4-5. ✓
- Load-bearing constraint (coarse/structural, report-only, side-by-side gallery) → Global Constraints + Task 2. ✓

**2. Placeholder scan:** The Task 3 seed script leaves the chat/friends/PRs/featured insert bodies as guided commented blocks — this is deliberate and bounded: the exact columns can't be written blind and Step 1 forces confirming them first, with the idempotency shape fully shown for two blocks to copy. The Task 4 `content_*` builders are described against real initializers rather than stubbed. No "TBD"/"handle edge cases"/"add validation" placeholders; every code step shows real code with real run commands + expected output.

**3. Type consistency:** `buildFramePages`/`slug` (Task 1) match their test imports (Task 1) and are not re-exported elsewhere. `normalize`/`scorePair`/`heatmap`/`buildReportHtml` (Task 2) match their test imports and the CLI's internal calls. `NORM_W`/`NORM_H`/`SCORE_W` are consistent within Task 2. The join key `app-<screen-id>.png` ↔ `frame-map.json` `<screen-id>` ↔ `proof-frame-<NN>.png` (NN from `frame.padStart(2,'0')`) is consistent across Tasks 1, 2, 5, 6. `CatalogScreen` raw values (Task 4) equal the `UITEST_CATALOG` ids driven by `captureCatalog` (Task 5) and the screen-ids in `frame-map.json`. The `settle()`/`attachScreenshot`/`launchApp`/`waitForTabBar` helpers referenced in Task 5 exist in the current `ScreenshotTests.swift`.
