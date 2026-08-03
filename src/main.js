// Trace — app shell and trial loop.

import { Board } from './board.js';
import { Celebration } from './celebrate.js';
import { Voice, Sfx } from './audio.js';
import { Learner, LIMITS } from './difficulty.js';
import { shapesForLevel, makeCreativeShape } from './shapes.js';
import * as say from './lines.js';

const STORE_KEY = 'trace.save.v1';

const DEFAULT_SETTINGS = {
  voice: true,
  sound: true,
  rate: 0.92,
  focus: 'mix', // mix | shapes | letters | numbers
};

// Celebration cadence: roughly one big one in every three or four wins, never
// twice running, and guaranteed if it's been a while.
const BIG_CHANCE = 0.29;
const BIG_FORCE_AFTER = 5;

const IDLE_MS = 4500; // no touch after the prompt -> offer the replay button
const SETTLE_MS = 2600; // pen up on an unfinished shape -> judge what we have

class Game {
  constructor() {
    this.board = new Board(document.getElementById('board'), document.getElementById('fx'));
    this.fx = new Celebration(document.getElementById('fx'));
    this.voice = new Voice();
    this.sfx = new Sfx();

    const saved = load();
    this.learner = new Learner(saved?.learner);
    this.settings = { ...DEFAULT_SETTINGS, ...(saved?.settings || {}) };
    this.applySettings();

    this.demoedThisSession = new Set();
    this.sinceBig = 99;
    this.lastWasBig = false;
    this.helpSticky = false;
    this.abort = false;
    this.running = false;

    this.helpBtn = document.getElementById('help');
    this.startScreen = document.getElementById('start');
    this.panel = document.getElementById('panel');

    this.#wireUi();
    window.addEventListener('resize', () => this.#onResize());
    window.addEventListener('orientationchange', () => setTimeout(() => this.#onResize(), 250));
    // Coming back from the background is when a stale zero-size layout shows up.
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') setTimeout(() => this.#onResize(), 60);
    });
  }

  // -------------------------------------------------------------------------
  // UI wiring
  // -------------------------------------------------------------------------

  #wireUi() {
    document.getElementById('playBtn').addEventListener('click', () => this.begin());

    this.helpBtn.addEventListener('click', () => {
      if (this.onHelp) this.onHelp();
    });

    // Grown-up panel, behind a long press in the corner so a child can't wander
    // into it by accident.
    const tap = document.getElementById('parentTap');
    let timer = null;
    const cancel = () => {
      clearTimeout(timer);
      timer = null;
    };
    tap.addEventListener('pointerdown', () => {
      timer = setTimeout(() => this.openPanel(), 1200);
    });
    ['pointerup', 'pointerleave', 'pointercancel'].forEach((ev) =>
      tap.addEventListener(ev, cancel),
    );

    document.getElementById('panelClose').addEventListener('click', () => this.closePanel());
    document.getElementById('optVoice').addEventListener('change', (e) => {
      this.settings.voice = e.target.checked;
      this.applySettings();
      this.save();
    });
    document.getElementById('optSound').addEventListener('change', (e) => {
      this.settings.sound = e.target.checked;
      this.applySettings();
      this.save();
    });
    document.getElementById('optRate').addEventListener('input', (e) => {
      this.settings.rate = parseFloat(e.target.value);
      this.applySettings();
    });
    document.getElementById('optRate').addEventListener('change', () => {
      this.save();
      this.voice.say('This is how fast I will talk.');
    });
    document.getElementById('optFocus').addEventListener('change', (e) => {
      this.settings.focus = e.target.value;
      this.save();
    });
    document.getElementById('resetBtn').addEventListener('click', () => {
      if (!confirm('Reset all progress and start difficulty from scratch?')) return;
      this.learner = new Learner();
      this.demoedThisSession.clear();
      this.save();
      this.refreshPanel();
    });
  }

  applySettings() {
    this.voice.enabled = this.settings.voice;
    this.voice.rate = this.settings.rate;
    this.sfx.enabled = this.settings.sound;
  }

  save() {
    try {
      localStorage.setItem(
        STORE_KEY,
        JSON.stringify({ learner: this.learner.toJSON(), settings: this.settings }),
      );
    } catch {
      /* private browsing — progress just won't persist */
    }
  }

  #onResize() {
    this.board.resize();
    this.fx.canvas.getContext('2d').setTransform(
      this.board.dpr, 0, 0, this.board.dpr, 0, 0,
    );
  }

  // -------------------------------------------------------------------------
  // Grown-up panel
  // -------------------------------------------------------------------------

  openPanel() {
    this.abort = true;
    this.voice.stop();
    this.board.stopDemo();
    this.board.freeze(true);
    this.refreshPanel();
    this.panel.hidden = false;
  }

  closePanel() {
    this.panel.hidden = true;
    this.board.freeze(false);
    if (!this.running) this.loop();
  }

  refreshPanel() {
    const s = this.learner.stats();
    const pct = (v) => (v === null ? '—' : `${Math.round(v * 100)}%`);
    document.getElementById('statTrials').textContent = s.trials;
    document.getElementById('statAll').textContent = pct(s.allTime);
    document.getElementById('statRecent').textContent = pct(s.recent);
    document.getElementById('statLevel').textContent = `${s.level} of ${LIMITS.MAX_LEVEL}`;
    document.getElementById('statWidth').textContent = `${s.width.toFixed(1)} / 100`;

    document.getElementById('optVoice').checked = this.settings.voice;
    document.getElementById('optSound').checked = this.settings.sound;
    document.getElementById('optRate').value = this.settings.rate;
    document.getElementById('optFocus').value = this.settings.focus;

    // A little bar of the last dozen results, newest on the right.
    const strip = document.getElementById('statStrip');
    strip.innerHTML = '';
    for (const t of this.learner.history.slice(-14)) {
      const d = document.createElement('i');
      d.className = `pip ${t.win ? 'win' : 'miss'}${t.probe ? ' probe' : ''}`;
      d.title = `${t.probe ? 'challenge' : 'regular'} · width ${t.width.toFixed(1)}`;
      strip.appendChild(d);
    }
  }

  // -------------------------------------------------------------------------
  // Session
  // -------------------------------------------------------------------------

  async begin() {
    this.voice.unlock();
    this.sfx.unlock();
    this.startScreen.hidden = true;
    requestWakeLock();
    await this.voice.say(say.WELCOME[Math.floor(Math.random() * say.WELCOME.length)]);
    this.loop();
  }

  async loop() {
    if (this.running) return;
    this.running = true;
    try {
      // eslint-disable-next-line no-constant-condition
      while (true) {
        const done = await this.runTrial();
        // The panel can open during a celebration, after the last abort check
        // in runTrial — stop here rather than presenting the next shape behind
        // the dialog (setShape would also quietly un-freeze the board).
        if (done === 'panel' || this.abort) break;
      }
    } finally {
      this.running = false;
    }
  }

  /**
   * Pick a shape for the planned difficulty.
   *
   * `width` matters here as well as in the trial: shapes with a corridor cap
   * can't host a wide track, and quietly narrowing one would turn a trial we
   * planned as easy into a hard one — which is exactly what the 85% accounting
   * relies on not happening. So prefer shapes that can take the planned width.
   */
  chooseShape(level, width) {
    const focus = this.settings.focus;
    let pool = shapesForLevel(level);
    if (focus === 'shapes') pool = pool.filter((s) => !s.kind);
    else if (focus === 'letters') pool = pool.filter((s) => s.kind === 'letter');
    else if (focus === 'numbers') pool = pool.filter((s) => s.kind === 'digit');
    if (!pool.length) pool = shapesForLevel(level);

    // Novel generated designs once the basics are landing, so the library never
    // feels exhausted.
    if (focus === 'mix' && level >= 3) {
      const chance = level >= 4 ? 0.18 : 0.1;
      if (Math.random() < chance) {
        const made = makeCreativeShape(this.learner.creativeSeed++, level);
        if (fits(made, width)) return made;
      }
    }

    const roomy = pool.filter((s) => fits(s, width));
    if (roomy.length) pool = roomy;
    const fresh = pool.filter((s) => !this.learner.recentShapes.includes(s.id));
    const from = fresh.length ? fresh : pool;
    return from[Math.floor(Math.random() * from.length)];
  }

  async runTrial() {
    this.abort = false;
    const plan = this.learner.planTrial(Math.random);
    const shape = this.chooseShape(plan.level, plan.width);
    // Honour the shape's cap even when nothing in the pool could take the full
    // planned width, and record the width actually shown.
    plan.width = Math.min(plan.width, shape.maxWidth ?? LIMITS.MAX_W);

    this.board.setShape(shape, plan.width);
    this.fx.clear();

    // Demonstrate when the shape is new to this session, when we're just
    // starting out, or when the last go at it didn't land.
    const needsDemo =
      this.learner.totalTrials < 3 ||
      !this.demoedThisSession.has(shape.id) ||
      this.lastFailedShape === shape.id;

    await this.voice.say(say.challenge(shape));
    if (this.abort) return 'panel';

    // If they cut the demonstration short by starting to trace, don't talk over
    // them with "now you try" — they already are.
    const demoFinished = needsDemo ? await this.showDemo(shape) : true;
    if (this.abort) return 'panel';
    if (demoFinished) await this.voice.say(say.yourTurn());
    if (this.abort) return 'panel';

    const outcome = await this.awaitAttempt(shape);
    if (outcome === 'panel') return 'panel';

    const verdict = this.board.judge();

    // The measurement is the first attempt at a shape — that's what feeds the
    // 85% estimate. The optional retry below is practice, not data.
    this.learner.record({
      win: verdict.win,
      probe: plan.probe,
      width: plan.width,
      level: plan.level,
      shapeId: shape.id,
    });
    this.save();

    if (verdict.win) {
      this.lastFailedShape = null;
      await this.reward();
      return 'next';
    }

    this.lastFailedShape = shape.id;
    this.sfx.nearMiss();
    await this.voice.say(say.encourage(verdict.reason));
    if (this.abort) return 'panel';

    // One immediate second go at the same shape, a little wider, so the trial
    // ends on a success as often as possible.
    await this.retry(shape, plan);
    return 'next';
  }

  /** Returns false if the child cut the demonstration short by starting to draw. */
  async showDemo(shape) {
    this.demoedThisSession.add(shape.id);
    await this.voice.say(say.demoIntro());
    if (this.abort) return false;
    const how = await this.board.runDemo({
      onStroke: (i, n) => {
        const line = say.strokePart(i, n);
        if (line) this.voice.say(line);
        this.sfx.tick();
      },
    });
    if (how === 'interrupted') this.voice.stop();
    return how === 'complete';
  }

  /**
   * Wait for the child to have a go. Resolves when they've either covered the
   * whole shape or stopped drawing long enough that they're clearly done.
   */
  awaitAttempt(shape) {
    return new Promise((resolve) => {
      let settleTimer = null;
      let idleTimer = null;
      let finished = false;

      const cleanup = () => {
        clearTimeout(settleTimer);
        clearTimeout(idleTimer);
        this.board.onStrokeEnd = null;
        this.board.onFirstTouch = null;
        this.board.onLeave = null;
        this.onHelp = null;
      };

      const finish = (why) => {
        if (finished) return;
        finished = true;
        cleanup();
        resolve(why);
      };

      // Opening the grown-up panel abandons the trial rather than letting a
      // timer fire behind the dialog.
      this.abortCheck = setInterval(() => {
        if (this.abort) {
          clearInterval(this.abortCheck);
          finish('panel');
        }
      }, 200);

      const showHelp = () => {
        this.helpSticky = true;
        this.helpBtn.hidden = false;
        this.helpBtn.classList.add('pop');
      };
      if (this.helpSticky) this.helpBtn.hidden = false;

      idleTimer = setTimeout(async () => {
        showHelp();
        await this.voice.say(say.idleNudge());
      }, IDLE_MS);

      this.onHelp = async () => {
        clearTimeout(settleTimer);
        clearTimeout(idleTimer);
        this.board.clearInk();
        const complete = await this.showDemo(shape);
        if (!finished && complete) await this.voice.say(say.yourTurn());
      };

      this.board.onFirstTouch = () => {
        clearTimeout(idleTimer);
        this.voice.stop();
      };

      this.board.onLeave = () => this.sfx.bump();

      this.board.onStrokeEnd = () => {
        clearTimeout(settleTimer);
        if (this.board.looksFinished()) {
          finish('done');
        } else {
          settleTimer = setTimeout(() => finish('settled'), SETTLE_MS);
        }
      };

      // An eager child may have traced the whole thing during the demo, before
      // any of the handlers above existed. Pick that attempt up rather than
      // waiting for a stroke that already happened.
      if (!this.board.drawing && this.board.drawnLen > 0) {
        clearTimeout(idleTimer);
        if (this.board.looksFinished()) finish('done');
        else settleTimer = setTimeout(() => finish('settled'), SETTLE_MS);
      }
    }).finally(() => clearInterval(this.abortCheck));
  }

  async retry(shape, plan) {
    await this.voice.say(say.tryAgain());
    if (this.abort) return;
    const wider = Math.min(LIMITS.MAX_W, shape.maxWidth ?? LIMITS.MAX_W, plan.width * 1.22);
    this.board.setShape(shape, wider);
    const demoFinished = await this.showDemo(shape);
    if (this.abort) return;
    if (demoFinished) await this.voice.say(say.yourTurn());
    const outcome = await this.awaitAttempt(shape);
    if (outcome === 'panel') return;
    const verdict = this.board.judge();
    if (verdict.win) {
      this.lastFailedShape = null;
      await this.reward({ forceSmall: true });
    } else {
      this.sfx.nearMiss();
      await this.voice.say('Good trying! Let’s do a different one.');
    }
  }

  async reward({ forceSmall = false } = {}) {
    this.sinceBig += 1;
    const big =
      !forceSmall &&
      !this.lastWasBig &&
      (this.sinceBig >= BIG_FORCE_AFTER || Math.random() < BIG_CHANCE);
    this.lastWasBig = big;
    if (big) this.sinceBig = 0;

    this.board.freeze(true);
    this.fx.traceGlow(this.board.allPoints());

    if (big) {
      this.sfx.bigWin();
      this.fx.big();
      await this.voice.say(say.bigPraise());
      await wait(1900);
    } else {
      const c = this.board.center();
      this.sfx.smallWin();
      this.fx.small(c.x, c.y);
      await this.voice.say(say.praise());
      await wait(500);
    }
    this.fx.clear();
    this.board.freeze(this.abort);
  }
}

// ---------------------------------------------------------------------------

/** Can this shape host a corridor of `width` without its channels fusing? */
function fits(shape, width) {
  return (shape.maxWidth ?? LIMITS.MAX_W) >= width * 0.92;
}

function wait(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function load() {
  try {
    return JSON.parse(localStorage.getItem(STORE_KEY) || 'null');
  } catch {
    return null;
  }
}

async function requestWakeLock() {
  try {
    if ('wakeLock' in navigator) await navigator.wakeLock.request('screen');
  } catch {
    /* not fatal — the screen may just dim */
  }
}

// Keep the page itself from scrolling, pinching or bouncing under a small hand.
['gesturestart', 'gesturechange', 'gestureend'].forEach((ev) =>
  document.addEventListener(ev, (e) => e.preventDefault()),
);
document.addEventListener('touchmove', (e) => e.preventDefault(), { passive: false });
document.addEventListener('dblclick', (e) => e.preventDefault());

window.trace = new Game();

if ('serviceWorker' in navigator && location.protocol === 'https:') {
  navigator.serviceWorker.register('./sw.js').catch(() => {});
}
