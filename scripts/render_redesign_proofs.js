#!/usr/bin/env node
// render_redesign_proofs.js — renders the 2026-07-20 redesign's proof phones
// (docs/design/mockups/*.template.html) as numbered parity frames, joining the
// existing render_proofs.js output in the same --out dir so parity_diff.js can
// diff redesigned app captures against their REAL (Onyx) authority instead of
// the superseded Ink canvas frames.
//
// Frame number space (STABLE — frame-map.json points here):
//   60 tab-home · 61 tab-library · 62 tab-social · 63 tab-stats · 64 tab-you
//   65 live-session · 66 solo-workout · 67 exercise-detail · 68 campaign-detail
//
// The templates ship with __ARCHIVO_REGULAR__/__ARCHIVO_BOLD__ placeholders
// (fonts stripped for the repo); this script inlines the real TTFs from the
// app bundle so the rendered frames use the actual Archivo.
//
// Usage: node scripts/render_redesign_proofs.js --out proofs

const fs = require('fs');
const os = require('os');
const path = require('path');
const puppeteer = require('puppeteer');

const args = require('util').parseArgs({
  options: { out: { type: 'string', default: 'proofs' } },
}).values;

const ROOT = path.join(__dirname, '..');
const MOCKUPS = path.join(ROOT, 'docs', 'design', 'mockups');
const FONTS = path.join(ROOT, 'GymSyncApp', 'GymSync', 'DesignSystem', 'Fonts');

// template file → ordered [frameNumber, slug] for its .phone elements
// (order = each template's SCREENS array; single-phone templates have one).
const PLAN = [
  {
    file: 'redesign-proofs.template.html',
    frames: [[60, 'tab-home'], [61, 'tab-library'], [62, 'tab-social'], [63, 'tab-stats'], [64, 'tab-you']],
  },
  {
    file: 'deep-proofs.template.html',
    frames: [[65, 'live-session'], [66, 'solo-workout'], [67, 'exercise-detail'], [68, 'campaign-detail']],
  },
];

function injectFonts(html) {
  const b64 = (f) => fs.readFileSync(path.join(FONTS, f)).toString('base64');
  return html
    .replace('__ARCHIVO_REGULAR__', b64('Archivo-Regular.ttf'))
    .replace('__ARCHIVO_BOLD__', b64('Archivo-Bold.ttf'));
}

(async () => {
  const outDir = path.resolve(args.out);
  fs.mkdirSync(outDir, { recursive: true });
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'onyx-proofs-'));

  const browser = await puppeteer.launch({ args: ['--no-sandbox', '--force-color-profile=srgb'] });
  const page = await browser.newPage();
  await page.setViewport({ width: 1600, height: 1200, deviceScaleFactor: 2 });

  for (const { file, frames } of PLAN) {
    const src = path.join(MOCKUPS, file);
    const html = injectFonts(fs.readFileSync(src, 'utf8'));
    const tmpFile = path.join(tmp, file.replace('.template', ''));
    fs.writeFileSync(tmpFile, html);

    await page.goto('file://' + tmpFile, { waitUntil: 'networkidle0' });
    await page.evaluate(() => document.fonts.ready);
    // The galleries build their phones from a JS SCREENS array on load; give
    // layout a beat to settle after fonts resolve.
    await new Promise((r) => setTimeout(r, 400));

    const phones = await page.$$('.phone');
    if (phones.length < frames.length) {
      throw new Error(`${file}: expected >= ${frames.length} .phone elements, found ${phones.length}`);
    }
    for (let i = 0; i < frames.length; i++) {
      const [num, slug] = frames[i];
      const out = path.join(outDir, `proof-frame-${num}.png`);
      await phones[i].screenshot({ path: out });
      console.log(`proof-frame-${num}.png  (${slug})`);
    }
  }

  await browser.close();
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(`\nRendered redesign frames into ${outDir}`);
})().catch((e) => { console.error(e); process.exit(1); });
