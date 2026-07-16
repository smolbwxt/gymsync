'use strict';

// Pure matching/validation helpers for mapping our exercise catalog onto the
// ExerciseDB dataset (GymSync Phase E). No I/O — node builtins only.

/**
 * Lowercase, strip parentheticals and punctuation, collapse whitespace.
 * e.g. 'Bench Press (Barbell)' -> 'bench press'
 *      '  DB  Shoulder-Press ' -> 'db shoulder press'
 */
function normalizeName(s) {
  return String(s == null ? '' : s)
    .replace(/\([^)]*\)/g, ' ')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/** Kebab-case slug derived from a name. e.g. 'Incline Bench Press' -> 'incline-bench-press' */
function slugify(s) {
  const normalized = normalizeName(s);
  return normalized ? normalized.replace(/\s+/g, '-') : '';
}

function tokenize(s) {
  const normalized = normalizeName(s);
  return normalized ? normalized.split(' ') : [];
}

/** Jaccard overlap of the token sets of two names, in [0,1]. */
function nameTokenOverlap(a, b) {
  const setA = new Set(tokenize(a));
  const setB = new Set(tokenize(b));
  if (setA.size === 0 && setB.size === 0) return 1;
  if (setA.size === 0 || setB.size === 0) return 0;
  let intersection = 0;
  for (const token of setA) {
    if (setB.has(token)) intersection++;
  }
  const union = new Set([...setA, ...setB]).size;
  return union === 0 ? 0 : intersection / union;
}

// Canonical muscle groups — small alias map so e.g. 'chest' and 'pectorals'
// (ExerciseDB's term) are treated as equivalent.
const MUSCLE_ALIASES = {
  chest: 'chest',
  pectorals: 'chest',
  back: 'back',
  lats: 'back',
  'upper back': 'back',
  quads: 'quads',
  quadriceps: 'quads',
  hamstrings: 'hamstrings',
  glutes: 'glutes',
  shoulders: 'shoulders',
  delts: 'shoulders',
  deltoids: 'shoulders',
  biceps: 'biceps',
  triceps: 'triceps',
  calves: 'calves',
  abs: 'abs',
  abdominals: 'abs',
  core: 'abs',
};

function muscleGroup(m) {
  const normalized = normalizeName(m);
  return MUSCLE_ALIASES[normalized] || normalized;
}

function equipmentEquals(a, b) {
  return normalizeName(a) === normalizeName(b);
}

/**
 * Score a candidate ExerciseDB entry against our catalog entry, in [0,1].
 * Weights: 0.6 name token overlap, 0.2 equipment equality, 0.2 target-muscle
 * equality (after the alias map above).
 */
function scoreMatch(ours, theirs) {
  const nameScore = nameTokenOverlap(ours.name, theirs.name);
  const equipmentScore = equipmentEquals(ours.equipment, theirs.equipment) ? 1 : 0;
  const muscleScore = muscleGroup(ours.primaryMuscle) === muscleGroup(theirs.target) ? 1 : 0;
  return 0.6 * nameScore + 0.2 * equipmentScore + 0.2 * muscleScore;
}

/**
 * Best-scoring candidate for `ours`, or null if nothing clears `threshold`.
 */
function bestMatch(ours, candidates, threshold = 0.75) {
  let best = null;
  let bestScore = -Infinity;
  for (const candidate of candidates || []) {
    const score = scoreMatch(ours, candidate);
    if (score > bestScore) {
      bestScore = score;
      best = candidate;
    }
  }
  if (best === null || bestScore < threshold) return null;
  return { candidate: best, score: bestScore };
}

const REQUIRED_PACK_FIELDS = ['slug', 'name', 'category', 'primary_muscle', 'equipment', 'match_key'];
const VALID_CATEGORIES = new Set(['compound', 'isolation']);
const SLUG_RE = /^[a-z0-9-]+$/;

/**
 * Validate an expansion pack (array of exercise entries). Returns an array
 * of human-readable error strings; empty array means the pack is valid.
 * Entries carrying a `_meta` key are pack-level metadata (Task 3 convention)
 * and are skipped entirely.
 */
function validatePack(pack) {
  if (!Array.isArray(pack)) return ['pack must be an array'];

  const errors = [];
  const seenSlugs = new Set();

  pack.forEach((entry, idx) => {
    if (entry && typeof entry === 'object' && Object.prototype.hasOwnProperty.call(entry, '_meta')) {
      return; // skip pack metadata entries
    }

    const label = entry && entry.slug ? entry.slug : `entry #${idx}`;

    if (entry == null || typeof entry !== 'object') {
      errors.push(`${label}: entry is not an object`);
      return;
    }

    for (const field of REQUIRED_PACK_FIELDS) {
      if (entry[field] === undefined || entry[field] === null || entry[field] === '') {
        errors.push(`${label}: missing required field '${field}'`);
      }
    }

    if (entry.slug) {
      if (!SLUG_RE.test(entry.slug)) {
        errors.push(`${label}: invalid slug format '${entry.slug}' (expected ^[a-z0-9-]+$)`);
      }
      if (seenSlugs.has(entry.slug)) {
        errors.push(`${label}: duplicate slug '${entry.slug}'`);
      } else {
        seenSlugs.add(entry.slug);
      }
    }

    if (entry.category !== undefined && entry.category !== null && !VALID_CATEGORIES.has(entry.category)) {
      errors.push(`${label}: invalid category '${entry.category}' (must be one of: compound, isolation)`);
    }
  });

  return errors;
}

module.exports = {
  normalizeName,
  slugify,
  scoreMatch,
  bestMatch,
  validatePack,
};
