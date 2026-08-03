// The shape library. Everything is authored in a 0..100 box (y points down).
//
// `level` is the complexity band the adaptive engine draws from:
//   1  single straight strokes
//   2  simple closed shapes and gentle curves
//   3  corners, points, multi-segment shapes; easy letters/digits
//   4  most letters and digits, two-part shapes
//   5  fiddly letters, tight curves, three-part shapes, generated designs
//
// `name` is what the app says out loud, so it has to be a 4-year-old's word.
//
// `maxWidth` caps the corridor for shapes with narrow channels or small
// enclosed holes. Widen a spiral past its turn spacing and the turns fuse into
// one white blob — there are no lines left to stay inside, and the child can
// scribble anywhere and "win". Corners are fine to round off, so only shapes
// with stretches running close and parallel, or with small holes, need a cap.
// Values are the full corridor width in the 0..100 shape box.

import { mulberry32, range } from './rng.js';

const S = (id, name, level, strokes, opts = {}) => ({ id, name, level, strokes, ...opts });

export const BASIC = [
  S('line-h', 'straight line', 1, ['M 10 50 L 90 50']),
  S('line-v', 'down line', 1, ['M 50 8 L 50 92']),
  S('line-diag', 'slanty line', 1, ['M 12 88 L 88 12']),
  S('hill', 'hill', 1, ['M 8 78 Q 50 6 92 78']),
  S('valley', 'smile', 1, ['M 8 24 Q 50 94 92 24']),

  S('circle', 'circle', 2, ['E 50 50 40 40 -90 270']),
  S('oval', 'egg', 2, ['E 50 50 28 42 -90 270']),
  S('square', 'square', 2, ['M 14 14 L 86 14 L 86 86 L 14 86 L 14 14']),
  S('rectangle', 'rectangle', 2, ['M 8 24 L 92 24 L 92 76 L 8 76 L 8 24']),
  S('wave', 'wave', 2, ['M 6 50 Q 22 16 38 50 Q 54 84 70 50 Q 86 16 96 40']),
  S('arch', 'rainbow', 2, ['M 10 84 Q 10 14 50 14 Q 90 14 90 84']),

  S('triangle', 'triangle', 3, ['M 50 10 L 92 86 L 8 86 L 50 10']),
  S('diamond', 'diamond', 3, ['M 50 8 L 92 50 L 50 92 L 8 50 L 50 8']),
  S('zigzag', 'zigzag', 3, ['M 6 76 L 28 24 L 50 76 L 72 24 L 94 76']),
  S('cross', 'plus', 3, ['M 50 10 L 50 90', 'M 10 50 L 90 50']),
  S('staircase', 'steps', 3, ['M 8 88 L 8 62 L 36 62 L 36 40 L 64 40 L 64 18 L 92 18']),
  S('teardrop', 'raindrop', 3, ['M 50 8 Q 88 52 88 62 Q 88 92 50 92 Q 12 92 12 62 Q 12 52 50 8'], {
    maxWidth: 22,
  }),

  S(
    'star',
    'star',
    4,
    ['M 50 6 L 62 38 L 96 38 L 68 58 L 79 92 L 50 71 L 21 92 L 32 58 L 4 38 L 38 38 L 50 6'],
    { maxWidth: 16 },
  ),
  S('heart', 'heart', 4, ['M 50 92 C 4 58 10 18 32 18 C 44 18 50 30 50 34 C 50 30 56 18 68 18 C 90 18 96 58 50 92']),
  S('moon', 'moon', 4, ['M 66 10 Q 22 26 22 52 Q 22 80 66 92 Q 34 66 34 50 Q 34 32 66 10'], {
    maxWidth: 13,
  }),
  S('spiral', 'swirl', 5, ['M 90 50 S 50 50 40 6 0 880'], { maxWidth: 10 }),
  S(
    'flower',
    'flower',
    5,
    [
      'M 50 50 Q 22 34 34 20 Q 46 6 50 28 Q 54 6 66 20 Q 78 34 50 50',
      'M 50 50 Q 78 66 66 80 Q 54 94 50 72 Q 46 94 34 80 Q 22 66 50 50',
    ],
    { maxWidth: 15 },
  ),
];

// ---------------------------------------------------------------------------
// Digits
// ---------------------------------------------------------------------------

// [level, strokes, maxWidth?]
const DIGIT_DEFS = {
  0: [3, ['E 50 50 26 40 -90 270'], 26],
  1: [3, ['M 32 26 L 50 12 L 50 90']],
  2: [4, ['M 26 28 Q 26 10 50 10 Q 74 10 74 32 Q 74 48 26 88 L 76 88'], 20],
  3: [5, ['M 28 22 Q 32 10 52 10 Q 74 10 74 28 Q 74 46 48 48 Q 76 50 76 70 Q 76 90 50 90 Q 30 90 26 78'], 20],
  4: [4, ['M 62 12 L 20 64 L 78 64', 'M 62 12 L 62 90'], 20],
  5: [4, ['M 74 12 L 34 12 L 30 46 Q 52 38 64 47 Q 78 56 78 70 Q 78 90 50 90 Q 30 90 26 80'], 20],
  6: [5, ['M 66 14 Q 38 22 30 52 Q 26 70 34 82 Q 44 94 56 88 Q 72 80 70 64 Q 68 48 50 48 Q 36 48 31 60'], 20],
  7: [3, ['M 24 12 L 76 12 L 44 90']],
  8: [5, ['E 50 30 20 22 -90 270', 'E 50 70 24 20 -90 270'], 18],
  9: [5, ['M 34 86 Q 62 78 70 48 Q 74 30 66 18 Q 56 6 44 12 Q 28 20 30 36 Q 32 52 50 52 Q 64 52 69 40'], 20],
};

export const DIGITS = Object.entries(DIGIT_DEFS).map(([d, [level, strokes, maxWidth]]) =>
  S(`digit-${d}`, `number ${d}`, level, strokes, { kind: 'digit', glyph: d, maxWidth }),
);

// ---------------------------------------------------------------------------
// Uppercase letters (capitals first — that's what preschools teach)
// ---------------------------------------------------------------------------

// [level, strokes, maxWidth?]
const LETTER_DEFS = {
  A: [4, ['M 20 90 L 50 10 L 80 90', 'M 32 62 L 68 62'], 20],
  B: [5, ['M 26 10 L 26 90', 'M 26 10 Q 66 10 66 30 Q 66 50 26 50 Q 72 50 72 70 Q 72 90 26 90'], 17],
  C: [3, ['E 50 50 35 40 -62 -298']],
  D: [4, ['M 28 10 L 28 90', 'M 28 10 Q 76 10 76 50 Q 76 90 28 90'], 24],
  E: [4, ['M 72 12 L 28 12 L 28 88 L 72 88', 'M 28 50 L 64 50']],
  F: [4, ['M 72 12 L 28 12 L 28 90', 'M 28 50 L 64 50']],
  G: [5, ['E 50 50 35 40 -62 -298 L 85 50 L 60 50'], 20],
  H: [3, ['M 26 10 L 26 90', 'M 74 10 L 74 90', 'M 26 50 L 74 50']],
  I: [3, ['M 50 12 L 50 88', 'M 30 12 L 70 12', 'M 30 88 L 70 88']],
  J: [4, ['M 58 12 L 58 66 Q 58 90 38 90 Q 22 90 22 74']],
  K: [4, ['M 28 10 L 28 90', 'M 74 12 L 30 50', 'M 30 50 L 74 90']],
  L: [2, ['M 30 10 L 30 88 L 74 88']],
  M: [4, ['M 22 90 L 22 12 L 50 56 L 78 12 L 78 90']],
  N: [3, ['M 24 90 L 24 12 L 76 88 L 76 10']],
  O: [2, ['E 50 50 36 40 -90 270'], 30],
  P: [4, ['M 28 10 L 28 90', 'M 28 10 Q 72 10 72 32 Q 72 54 28 54'], 20],
  Q: [5, ['E 50 50 36 40 -90 270', 'M 60 66 L 84 92'], 26],
  R: [5, ['M 28 10 L 28 90', 'M 28 10 Q 72 10 72 32 Q 72 54 28 54 L 74 90'], 18],
  S: [5, ['M 72 24 Q 68 10 50 10 Q 28 10 28 28 Q 28 45 50 50 Q 74 55 74 72 Q 74 90 50 90 Q 31 90 28 78']],
  T: [2, ['M 24 12 L 76 12', 'M 50 12 L 50 90']],
  U: [3, ['M 26 10 L 26 62 Q 26 90 50 90 Q 74 90 74 62 L 74 10']],
  V: [3, ['M 24 10 L 50 90 L 76 10']],
  W: [4, ['M 18 10 L 34 90 L 50 38 L 66 90 L 82 10']],
  X: [3, ['M 26 10 L 74 90', 'M 74 10 L 26 90']],
  Y: [4, ['M 26 10 L 50 48 L 74 10', 'M 50 48 L 50 90']],
  Z: [3, ['M 26 12 L 74 12 L 26 88 L 74 88']],
};

export const LETTERS = Object.entries(LETTER_DEFS).map(([ch, [level, strokes, maxWidth]]) =>
  S(`letter-${ch}`, `letter ${ch}`, level, strokes, { kind: 'letter', glyph: ch, maxWidth }),
);

// ---------------------------------------------------------------------------
// Creative shapes — random designs stitched from primitive pieces.
//
// Each piece starts where the last one ended, so the result is one continuous
// squiggle that has never existed before. Handy for keeping a kid curious once
// the fixed library starts feeling familiar.
// ---------------------------------------------------------------------------

const CREATIVE_NAMES = [
  'squiggle', 'wiggly path', 'roller coaster', 'silly snake', 'loop-de-loop',
  'mountain road', 'twisty tail', 'bumpy track', 'zoomy line', 'curly whirly',
];

function clampInside(p) {
  return { x: Math.min(92, Math.max(8, p.x)), y: Math.min(92, Math.max(8, p.y)) };
}

export function makeCreativeShape(seed, level) {
  const rng = mulberry32(seed);
  const pieces = level >= 5 ? 5 : 4;
  let cur = clampInside({ x: range(rng, 10, 34), y: range(rng, 20, 80) });
  let d = `M ${cur.x.toFixed(1)} ${cur.y.toFixed(1)}`;
  let tightestLoop = Infinity;

  // Bias motion left-to-right so the design reads like handwriting.
  const stride = (76 - cur.x) / pieces;

  for (let i = 0; i < pieces; i++) {
    const next = clampInside({
      x: cur.x + stride * range(rng, 0.7, 1.3),
      y: range(rng, 14, 86),
    });
    const kind = rng();

    if (kind < 0.3) {
      d += ` L ${next.x.toFixed(1)} ${next.y.toFixed(1)}`;
    } else if (kind < 0.62) {
      const ctrl = clampInside({
        x: (cur.x + next.x) / 2 + range(rng, -18, 18),
        y: (cur.y + next.y) / 2 + range(rng, -34, 34),
      });
      d += ` Q ${ctrl.x.toFixed(1)} ${ctrl.y.toFixed(1)} ${next.x.toFixed(1)} ${next.y.toFixed(1)}`;
    } else if (kind < 0.85) {
      // Little zigzag between the two points.
      const bumps = 2 + Math.floor(rng() * 2);
      for (let b = 1; b <= bumps; b++) {
        const t = b / bumps;
        const p = clampInside({
          x: cur.x + (next.x - cur.x) * t,
          y: cur.y + (next.y - cur.y) * t + (b % 2 ? -1 : 1) * range(rng, 12, 24),
        });
        d += ` L ${p.x.toFixed(1)} ${p.y.toFixed(1)}`;
      }
      d += ` L ${next.x.toFixed(1)} ${next.y.toFixed(1)}`;
    } else {
      // A full loop. The circle has to be placed so its start angle lands
      // exactly on the current point, otherwise the path teleports and the
      // corridor gets a visible seam. Above the cursor if there's room for it,
      // below if not, and skip the loop entirely if neither fits.
      const r = range(rng, 9, 14);
      const above = cur.y - r >= 12 + r;
      const below = cur.y + r <= 88 - r;
      const inX = cur.x - r >= 6 && cur.x + r <= 94;
      if (inX && (above || below)) {
        const cyy = above ? cur.y - r : cur.y + r;
        const a0 = above ? 90 : -90;
        d += ` S ${cur.x.toFixed(1)} ${cyy.toFixed(1)} ${r.toFixed(1)} ${r.toFixed(1)} ${a0} ${a0 + 360}`;
        tightestLoop = Math.min(tightestLoop, r);
      }
      d += ` L ${next.x.toFixed(1)} ${next.y.toFixed(1)}`;
    }
    cur = next;
  }

  const name = CREATIVE_NAMES[Math.floor(rng() * CREATIVE_NAMES.length)];
  // A loop of radius r has a hole 2r across; the corridor has to stay narrower
  // than that or the hole fills in and the loop stops being a loop.
  const maxWidth = tightestLoop === Infinity ? undefined : Math.round(tightestLoop * 1.3);
  return S(`creative-${seed}`, name, level, [d], { kind: 'creative', seed, maxWidth });
}

// ---------------------------------------------------------------------------

export const LIBRARY = [...BASIC, ...DIGITS, ...LETTERS];

/** Every fixed shape at or below `level`, biased toward the top of the band. */
export function shapesForLevel(level) {
  const at = LIBRARY.filter((s) => s.level === level);
  const below = LIBRARY.filter((s) => s.level === level - 1);
  return at.length >= 4 ? [...at, ...below] : LIBRARY.filter((s) => s.level <= level);
}

export function shapeById(id) {
  return LIBRARY.find((s) => s.id === id) || null;
}
