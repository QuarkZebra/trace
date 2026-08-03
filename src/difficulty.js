// Adaptive difficulty, built around Wilson, Shenhav, Straccia & Cohen (2019),
// "The Eighty Five Percent Rule for optimal learning" (Nat. Commun. 10:4646).
//
// Their result: for a learner whose accuracy follows a sigmoid in the difficulty
// parameter, learning is fastest when training error is held near 15.87% — i.e.
// accuracy near 85%. So we don't make the task as easy as possible, and we don't
// push to failure; we steer the corridor width to the point where the child gets
// roughly 85% of trials right.
//
// Two things regulate the difficulty, on different timescales:
//
//  1. A weighted up/down staircase on `w85`, the corridor width we believe sits
//     at the 85% point. Steps are multiplicative because width is a scale
//     parameter. Step sizes are asymmetric in the Kaernbach sense: to converge
//     on P(correct) = p, an up-step must be worth p/(1-p) down-steps, which at
//     p = 0.85 is a ratio of about 5.7. The step weights are further shaded by
//     whether the trial was meant to be easy or hard, so an unexpected failure
//     on an easy trial moves us much more than an expected failure on a probe.
//
//  2. A slow regulator on the last dozen trials. If observed accuracy drifts
//     away from 85% for a sustained stretch, nudge width — and, at the rails,
//     move the child up or down a shape-complexity level.
//
// The 85% is a *set* property, not a per-trial one. Matt's framing — five or six
// you expect them to get, one you expect them to miss — is what actually gets
// presented: most trials are served comfortably above threshold, and a minority
// are served as probes at or below it. Averaged over a session that lands near
// 85% while keeping nearly every individual trial feeling winnable.

const TARGET = 0.85;

// Corridor widths, in shape units (the shape lives in a 0..100 box).
const MIN_W = 4.5;
const MAX_W = 34;
const START_W = 19;

const BASE_STEP = 0.035; // ~3.5% width change per trial at the reference weight
const UP_RATIO = TARGET / (1 - TARGET); // ≈ 5.67

// How much a trial of each kind moves the estimate, relative to BASE_STEP.
const WEIGHTS = {
  // We expected a win. Getting one is weak evidence; missing one is loud.
  easyWin: { dir: -1, k: 0.35 },
  easyLoss: { dir: +1, k: 1.3 * UP_RATIO },
  // We expected a miss. Winning is real evidence we're too generous.
  probeWin: { dir: -1, k: 1.0 },
  probeLoss: { dir: +1, k: 0.15 * UP_RATIO },
};

const WINDOW = 12; // trials in the slow regulator
const MAX_LEVEL = 5;

// Once the corridor is this tight, further narrowing is testing fine motor
// control the child has already demonstrated. Move them up a shape level and
// give the width back instead.
const LEVEL_UP_W = 11;

export class Learner {
  constructor(saved) {
    this.w85 = START_W;
    this.level = 1;
    this.history = []; // { win, probe, width, level, shapeId }
    this.sinceProbe = 0;
    this.lastWasProbe = false;
    this.recentShapes = [];
    this.creativeSeed = 1;
    this.totalTrials = 0;
    this.totalWins = 0;
    if (saved) Object.assign(this, saved);
  }

  toJSON() {
    return {
      w85: this.w85,
      level: this.level,
      history: this.history.slice(-40),
      sinceProbe: this.sinceProbe,
      lastWasProbe: this.lastWasProbe,
      recentShapes: this.recentShapes.slice(-8),
      creativeSeed: this.creativeSeed,
      totalTrials: this.totalTrials,
      totalWins: this.totalWins,
    };
  }

  /** Observed accuracy over the last `n` trials, or null if too few. */
  recentAccuracy(n = WINDOW) {
    const h = this.history.slice(-n);
    if (h.length < Math.min(6, n)) return null;
    return h.filter((t) => t.win).length / h.length;
  }

  /**
   * Should the next trial be a probe — the one we expect them to miss?
   *
   * Base rate is 1 in 6. Two rules keep it from being predictable in either
   * direction: never two probes back to back (that reads as "the game got
   * hard"), and force one if nine trials have gone by without any (that reads
   * as "the game got boring"). We also skip a probe right after two losses, so
   * a struggling child gets a run of wins first.
   */
  shouldProbe(rng) {
    if (this.lastWasProbe) return false;
    const lastTwo = this.history.slice(-2);
    if (lastTwo.length === 2 && lastTwo.every((t) => !t.win)) return false;
    if (this.sinceProbe >= 9) return true;
    return rng() < 1 / 6;
  }

  /**
   * Choose the difficulty of the next trial.
   *
   * Easy trials sit ~30-50% wider than the 85% point, which puts them well up
   * the child's psychometric curve. Probes sit at or below it, and half the time
   * a probe spends its difficulty on a harder *shape* rather than a narrower
   * corridor — variety matters as much as the number does.
   */
  planTrial(rng) {
    const probe = this.shouldProbe(rng);
    const jitter = 0.93 + rng() * 0.14; // so widths never look quantised
    let width;
    let level = this.level;

    if (probe) {
      if (rng() < 0.5 && this.level < MAX_LEVEL) {
        level = this.level + 1;
        width = this.w85 * 1.05 * jitter;
      } else {
        width = this.w85 * 0.82 * jitter;
      }
    } else {
      width = this.w85 * (1.22 + rng() * 0.18) * jitter;
      // Occasionally reach *down* a level for a confidence builder.
      if (this.level > 1 && rng() < 0.18) level = this.level - 1;
    }

    return {
      probe,
      level,
      width: clamp(width, MIN_W, MAX_W),
    };
  }

  /** Fold a finished trial back into the estimate. */
  record({ win, probe, width, level, shapeId }) {
    this.history.push({ win, probe, width, level, shapeId });
    if (this.history.length > 60) this.history.shift();
    this.totalTrials += 1;
    if (win) this.totalWins += 1;

    this.lastWasProbe = probe;
    this.sinceProbe = probe ? 0 : this.sinceProbe + 1;
    if (shapeId) {
      this.recentShapes.push(shapeId);
      if (this.recentShapes.length > 8) this.recentShapes.shift();
    }

    // --- fast staircase ---
    const key = probe ? (win ? 'probeWin' : 'probeLoss') : win ? 'easyWin' : 'easyLoss';
    const { dir, k } = WEIGHTS[key];
    this.w85 = clamp(this.w85 * (1 + dir * BASE_STEP * k), MIN_W, MAX_W);

    // --- slow regulator ---
    this.#regulate();
  }

  #regulate() {
    const acc = this.recentAccuracy();
    if (acc === null) return;

    if (acc > TARGET + 0.03) {
      // Too easy for a sustained stretch. Tighten — and once the corridor is
      // already tight, more narrowing just tests fine motor control they've
      // clearly got, so promote them to harder shapes and hand back some width
      // to work with instead.
      if (this.w85 <= LEVEL_UP_W && this.level < MAX_LEVEL) {
        this.level += 1;
        this.w85 = clamp(START_W * 0.85, MIN_W, MAX_W);
        this.history.length = 0;
      } else {
        this.w85 = clamp(this.w85 * 0.97, MIN_W, MAX_W);
      }
    } else if (acc < TARGET - 0.08) {
      // Missing too often. Widen; if we're already at the ceiling, the shapes
      // themselves are the problem, so step back down a level.
      if (this.w85 >= MAX_W * 0.92 && this.level > 1) {
        this.level -= 1;
        this.w85 = clamp(START_W, MIN_W, MAX_W);
        this.history.length = 0;
      } else {
        this.w85 = clamp(this.w85 * 1.05, MIN_W, MAX_W);
      }
    }
  }

  /** For the grown-up panel. */
  stats() {
    return {
      trials: this.totalTrials,
      wins: this.totalWins,
      allTime: this.totalTrials ? this.totalWins / this.totalTrials : 0,
      recent: this.recentAccuracy(),
      width: this.w85,
      level: this.level,
    };
  }
}

function clamp(v, lo, hi) {
  return Math.min(hi, Math.max(lo, v));
}

export const LIMITS = { MIN_W, MAX_W, START_W, TARGET, MAX_LEVEL };
