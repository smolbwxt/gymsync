const { test } = require('node:test');
const assert = require('node:assert');
const { normalizeName, slugify, scoreMatch, bestMatch, validatePack } = require('../lib/exercise_match.js');

test('normalizeName strips parentheticals and case', () => {
  assert.equal(normalizeName('Bench Press (Barbell)'), 'bench press');
  assert.equal(normalizeName('  DB  Shoulder-Press '), 'db shoulder press');
});

test('slugify produces kebab', () => {
  assert.equal(slugify('Incline Bench Press'), 'incline-bench-press');
});

test('scoreMatch rewards exact name+equipment+muscle', () => {
  const s = scoreMatch(
    { name: 'bench press', equipment: 'barbell', primaryMuscle: 'chest' },
    { name: 'bench press', equipment: 'barbell', target: 'pectorals' }
  );
  assert.ok(s > 0.95, `expected ~1, got ${s}`);
});

test('bestMatch returns null below threshold', () => {
  const r = bestMatch(
    { name: 'back squat', equipment: 'barbell', primaryMuscle: 'quads' },
    [{ name: 'bicep curl', equipment: 'dumbbell', target: 'biceps' }]
  );
  assert.equal(r, null);
});

test('validatePack catches duplicate slugs and bad category', () => {
  const errs = validatePack([
    { slug: 'a-b', name: 'A', category: 'compound', primary_muscle: 'chest', equipment: 'barbell', match_key: 'x' },
    { slug: 'a-b', name: 'B', category: 'weird', primary_muscle: 'back', equipment: 'cable', match_key: 'y' },
  ]);
  assert.ok(errs.some(e => e.includes('duplicate slug')));
  assert.ok(errs.some(e => e.includes('category')));
});
