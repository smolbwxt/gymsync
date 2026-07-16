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
