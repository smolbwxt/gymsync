const { test } = require('node:test');
const assert = require('node:assert');
const { stripId } = require('../rename_app_shots.js');

test('stripId strips the xcresulttool _<N>_<UUID>.png suffix', () => {
  assert.equal(
    stripId('app-tab-library_0_ABCD-1234.png'),
    'app-tab-library'
  );
});

test('stripId handles a full-length UUID suffix', () => {
  assert.equal(
    stripId('app-you-appearance_0_279838C6-1234-4E56-9ABC-DEF012345678.png'),
    'app-you-appearance'
  );
});

test('a non-app- name is skipped (does not pass the app- filter used by main())', () => {
  const id = stripId('debug-catalog-thumbnail_2_1234ABCD-5678-90EF-1234-567890ABCDEF.png');
  assert.ok(!id.startsWith('app-'), `expected a non-app- id, got ${id}`);
});
