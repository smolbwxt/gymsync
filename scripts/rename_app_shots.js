#!/usr/bin/env node
/**
 * Renames xcresulttool/xcparse-exported UI test attachments into the
 * `app-<screen-id>.png` files parity_diff.js expects.
 *
 * The `app-screenshots` CI artifact does NOT contain `app-<id>.png` files
 * directly — xcresulttool/xcparse export each XCTAttachment as a
 * UUID-named file (e.g. `279838C6-...png`) plus a manifest.json mapping
 * each `exportedFileName` to a `suggestedHumanReadableName` derived from
 * the attachment's name set via attachScreenshot() in ScreenshotTests.swift,
 * e.g. `app-tab-library_0_<UUID>.png`. This strips the trailing
 * `_<N>_<UUID>.png` suffix to recover the original `app-<id>` name and
 * copies the file under that name into --out-dir, so parity_diff.js's
 * `--app <dir>` can find `app-<screen-id>.png` by simple join.
 *
 * Usage:
 *   node scripts/rename_app_shots.js <artifact-dir> <out-dir>
 */
const fs = require('node:fs');
const path = require('node:path');

/** Strip the trailing xcresulttool `_<N>_<UUID>.png` suffix, recovering the
 *  original attachment name (e.g. `app-tab-library_0_ABCD-1234.png` ->
 *  `app-tab-library`). Names that don't carry this suffix pass through
 *  unchanged. */
function stripId(name) {
  return name.replace(/_\d+_[0-9A-F-]+\.png$/i, '');
}

module.exports = { stripId };

function main() {
  const [inDir, outDir] = process.argv.slice(2);
  if (!inDir || !outDir) {
    console.error('Usage: node scripts/rename_app_shots.js <artifact-dir> <out-dir>');
    process.exit(1);
  }
  const manifest = JSON.parse(fs.readFileSync(path.join(inDir, 'manifest.json'), 'utf8'));
  fs.mkdirSync(outDir, { recursive: true });
  let n = 0;
  for (const t of manifest) {
    for (const a of (t.attachments || [])) {
      const id = stripId(a.suggestedHumanReadableName);
      if (id.startsWith('app-')) {
        fs.copyFileSync(path.join(inDir, a.exportedFileName), path.join(outDir, id + '.png'));
        n++;
      }
    }
  }
  console.log(`renamed ${n} app captures -> ${outDir}`);
}

if (require.main === module) {
  main();
}
