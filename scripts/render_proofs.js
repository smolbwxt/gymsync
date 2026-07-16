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
  '.svg': 'image/svg+xml',
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
    if (!el) {
      throw new Error(`frame ${p.idx} (${p.title}): '.gs-theme' not found — refusing to substitute a full-page crop`);
    }
    const nn = String(p.idx).padStart(2, '0');
    const file = `proof-frame-${nn}.png`;
    await el.screenshot({ path: path.join(outDir, file) });
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
