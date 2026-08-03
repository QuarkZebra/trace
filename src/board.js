// The tracing surface: draws the corridor, takes pen/finger input, tracks how
// much of the path got covered and how far outside the lines the child strayed.

import { buildTrial, buildCorridorMask, maskContains } from './geometry.js';

// A trial is won when every stroke is essentially covered and the total amount
// of drawing outside the corridor stays under a small allowance. The allowance
// has an absolute floor as well as a proportional part, so a small shape isn't
// unfairly strict about a single wobble at a corner.
const COVERAGE_TO_WIN = 0.9;
const LEAK_FRACTION = 0.07;
const LEAK_FLOOR_CORRIDORS = 0.9;
const SCRIBBLE_LIMIT = 2.6; // drawn length vs. path length, guards against scribble-farming

// Paper-coloured track on a near-black surround, so "inside the lines" is the
// lit part and everything else is blacked out. Ink reads like pencil on paper,
// and turns red the instant it crosses an edge.
const TRACK = '#fdfbf3';
const EDGE = '#93aee0';
const INK_COLOR = '#2b2f7a';
const INK_OUT_COLOR = '#e5484d';

export class Board {
  constructor(canvas, fxCanvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.fxCanvas = fxCanvas;

    this.scene = document.createElement('canvas');
    this.ink = document.createElement('canvas');
    this.dpr = 1;
    this.W = 0;
    this.H = 0;

    this.trial = null;
    this.mask = null;
    this.covered = [];
    this.insideLen = 0;
    this.outsideLen = 0;
    this.drawnLen = 0;
    this.drawing = false;
    this.activePointer = null;
    this.penSeen = false;
    this.lastPoint = null;
    this.lastInside = true;

    this.demo = null; // { strokeIndex, t, startedAt }
    this.showStartHint = true;
    this.frozen = false; // set between trials so stray touches do nothing

    this.onFirstTouch = null;
    this.onStrokeEnd = null;
    this.onLeave = null; // fired once when the pen exits the corridor

    this.#bindInput();
    this.resize();
  }

  // -------------------------------------------------------------------------
  // Layout
  // -------------------------------------------------------------------------

  resize() {
    const rect = this.canvas.getBoundingClientRect();
    const w = Math.round(rect.width);
    const h = Math.round(rect.height);
    const dpr = Math.min(window.devicePixelRatio || 1, 2.5);

    // A backgrounded or hidden tab reports a zero-sized viewport. Rebuilding at
    // that size would collapse the trial to nothing, so keep the last good
    // layout and wait for a real measurement.
    if (w < 40 || h < 40) return;
    if (w === this.W && h === this.H && dpr === this.dpr) return;

    this.W = w;
    this.H = h;
    this.dpr = dpr;

    for (const c of [this.canvas, this.fxCanvas]) {
      c.width = Math.round(this.W * this.dpr);
      c.height = Math.round(this.H * this.dpr);
    }
    this.canvas.getContext('2d').setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    this.fxCanvas.getContext('2d').setTransform(this.dpr, 0, 0, this.dpr, 0, 0);

    // Scene and ink live at logical resolution — the mask lookup is indexed in
    // logical pixels, and keeping them all in one space avoids conversions.
    for (const c of [this.scene, this.ink]) {
      c.width = this.W;
      c.height = this.H;
    }
    const again =
      this.pending ||
      (this.trial ? { shape: this.trial.shape, corridorUnits: this.trial.corridorUnits } : null);
    this.pending = null;
    if (again) this.setShape(again.shape, again.corridorUnits);
  }

  #view() {
    const m = Math.min(this.W, this.H) * 0.06;
    const size = Math.min(this.W - m * 2, this.H - m * 2);
    return { x: (this.W - size) / 2, y: (this.H - size) / 2, w: size, h: size };
  }

  // -------------------------------------------------------------------------
  // Trial setup
  // -------------------------------------------------------------------------

  setShape(shape, corridorUnits) {
    // Nothing sensible to build against a zero-sized viewport — hold it until
    // we get a real measurement back.
    if (this.W < 40 || this.H < 40) {
      this.pending = { shape, corridorUnits };
      return;
    }
    this.trial = buildTrial(shape, corridorUnits, this.#view());
    this.trial.corridorUnits = corridorUnits;
    this.mask = buildCorridorMask(this.trial, this.W, this.H);
    this.covered = this.trial.strokes.map((st) => new Uint8Array(st.checkpoints.length));
    this.insideLen = 0;
    this.outsideLen = 0;
    this.drawnLen = 0;
    this.drawing = false;
    this.activePointer = null;
    this.lastPoint = null;
    this.lastInside = true;
    this.showStartHint = true;
    this.demo = null;
    this.frozen = false;

    this.ink.getContext('2d').clearRect(0, 0, this.W, this.H);
    this.#paintScene();
    this.render();
  }

  clearInk() {
    this.ink.getContext('2d').clearRect(0, 0, this.W, this.H);
    this.covered = this.trial.strokes.map((st) => new Uint8Array(st.checkpoints.length));
    this.insideLen = 0;
    this.outsideLen = 0;
    this.drawnLen = 0;
    this.lastPoint = null;
    this.render();
  }

  // -------------------------------------------------------------------------
  // Drawing the board
  // -------------------------------------------------------------------------

  #paintScene() {
    const ctx = this.scene.getContext('2d');
    const { W, H } = this;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, W, H);

    // Night-sky backdrop. Blacking out everything that isn't the shape makes
    // the corridor unmistakable, which is the whole point.
    const g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#161a3d');
    g.addColorStop(1, '#0d1030');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);

    ctx.fillStyle = 'rgba(255,255,255,0.35)';
    for (let i = 0; i < 60; i++) {
      // Deterministic star field — no flicker between repaints.
      const x = ((i * 9301 + 49297) % 233280) / 233280 * W;
      const y = ((i * 4931 + 7919) % 65521) / 65521 * H;
      const r = ((i % 3) + 1) * 0.6;
      ctx.beginPath();
      ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.fill();
    }

    const path = (lw, style) => {
      ctx.strokeStyle = style;
      ctx.lineWidth = lw;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      for (const st of this.trial.strokes) {
        ctx.beginPath();
        ctx.moveTo(st.pts[0].x, st.pts[0].y);
        for (let i = 1; i < st.pts.length; i++) ctx.lineTo(st.pts[i].x, st.pts[i].y);
        ctx.stroke();
      }
    };

    const w = this.trial.corridorPx;

    // A soft halo lifts the track off the background.
    ctx.save();
    ctx.shadowColor = 'rgba(124, 214, 255, 0.55)';
    ctx.shadowBlur = 26;
    path(w + 12, 'rgba(124, 214, 255, 0.16)');
    ctx.restore();

    // Laying a wider band down first and then the track on top leaves a strip
    // of band showing on each side — those strips are the two lines the child
    // has to stay between.
    path(w + 11, EDGE);
    path(w, TRACK);

    // Faint dashed guide down the middle of the track.
    ctx.save();
    ctx.setLineDash([5, 16]);
    ctx.lineWidth = 2;
    ctx.strokeStyle = 'rgba(120, 132, 190, 0.5)';
    for (const st of this.trial.strokes) {
      ctx.beginPath();
      ctx.moveTo(st.pts[0].x, st.pts[0].y);
      for (let i = 1; i < st.pts.length; i++) ctx.lineTo(st.pts[i].x, st.pts[i].y);
      ctx.stroke();
    }
    ctx.restore();
  }

  #drawStartMarkers(ctx, pulse) {
    if (!this.showStartHint) return;
    for (let i = 0; i < this.trial.strokes.length; i++) {
      const st = this.trial.strokes[i];
      if (this.#strokeCoverage(i) > 0.15) continue;
      const p = st.pts[0];
      const q = st.pts[Math.min(st.pts.length - 1, 14)];
      const r = Math.max(11, this.trial.corridorPx * 0.26);

      ctx.save();
      ctx.globalAlpha = 0.4 + 0.4 * pulse;
      ctx.strokeStyle = '#16a34a';
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(p.x, p.y, r + 8 + pulse * 8, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();

      ctx.save();
      ctx.fillStyle = '#16a34a';
      ctx.beginPath();
      ctx.arc(p.x, p.y, r, 0, Math.PI * 2);
      ctx.fill();

      // Direction arrow, pointing the way the stroke travels.
      const a = Math.atan2(q.y - p.y, q.x - p.x);
      ctx.translate(p.x, p.y);
      ctx.rotate(a);
      ctx.fillStyle = '#fdfbf3';
      ctx.beginPath();
      ctx.moveTo(r * 0.55, 0);
      ctx.lineTo(-r * 0.3, -r * 0.45);
      ctx.lineTo(-r * 0.3, r * 0.45);
      ctx.closePath();
      ctx.fill();
      ctx.restore();
    }
  }

  render(now = performance.now()) {
    if (!this.trial) return;
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.W, this.H);
    ctx.drawImage(this.scene, 0, 0, this.W, this.H);
    ctx.drawImage(this.ink, 0, 0, this.W, this.H);

    const pulse = (Math.sin(now / 380) + 1) / 2;
    this.#drawStartMarkers(ctx, pulse);

    if (this.demo) this.#drawDemoDot(ctx, now);
  }

  // -------------------------------------------------------------------------
  // "Watch me" demonstration
  // -------------------------------------------------------------------------

  /**
   * Animate a dot along each stroke in teaching order.
   * `onStroke(i)` fires as each stroke begins so the voice can narrate parts.
   */
  runDemo({ onStroke } = {}) {
    if (!this.trial) return Promise.resolve('skipped');
    this.stopDemo();
    return new Promise((resolve) => {
      const strokes = this.trial.strokes;
      let i = 0;
      let started = 0;

      // Held on the instance so stopDemo can settle the promise: a child who
      // starts drawing part-way through the demonstration must not leave the
      // trial loop waiting on an animation that will never finish.
      this.demoResolve = resolve;
      this.demo = { strokeIndex: 0, t: 0, raf: null, timer: null };
      if (onStroke) onStroke(0, strokes.length);

      const finish = () => {
        this.demo = null;
        this.demoResolve = null;
        this.render();
        resolve('complete');
      };

      const tick = (now) => {
        if (!this.demo) return;
        if (!started) started = now;
        const st = strokes[i];
        // Slow enough for a 4-year-old to follow, but never a slog.
        const dur = Math.min(4200, Math.max(1900, st.len * 5.5));
        const t = Math.min(1, (now - started) / dur);
        this.demo.strokeIndex = i;
        this.demo.t = t;
        this.render(now);

        if (t < 1) {
          this.demo.raf = requestAnimationFrame(tick);
        } else if (i < strokes.length - 1) {
          i += 1;
          started = 0;
          if (onStroke) onStroke(i, strokes.length);
          this.demo.timer = setTimeout(() => {
            if (this.demo) this.demo.raf = requestAnimationFrame(tick);
          }, 620);
        } else {
          this.demo.timer = setTimeout(finish, 380);
        }
      };
      this.demo.raf = requestAnimationFrame(tick);
    });
  }

  /** Cancel a running demo, resolving its promise as interrupted. */
  stopDemo() {
    if (this.demo) {
      if (this.demo.raf) cancelAnimationFrame(this.demo.raf);
      if (this.demo.timer) clearTimeout(this.demo.timer);
      this.demo = null;
      this.render();
    }
    const resolve = this.demoResolve;
    this.demoResolve = null;
    if (resolve) resolve('interrupted');
  }

  #drawDemoDot(ctx, now) {
    const st = this.trial.strokes[this.demo.strokeIndex];
    const pts = st.pts;
    const idx = Math.min(pts.length - 1, Math.floor(this.demo.t * (pts.length - 1)));
    const p = pts[idx];

    // Fading trail behind the dot.
    ctx.save();
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    const tail = Math.max(2, Math.floor(pts.length * 0.22));
    for (let k = Math.max(0, idx - tail); k < idx; k++) {
      const a = (k - (idx - tail)) / tail;
      ctx.strokeStyle = `rgba(249, 115, 22, ${a * 0.45})`;
      ctx.lineWidth = this.trial.corridorPx * 0.45 * a + 3;
      ctx.beginPath();
      ctx.moveTo(pts[k].x, pts[k].y);
      ctx.lineTo(pts[k + 1].x, pts[k + 1].y);
      ctx.stroke();
    }
    ctx.restore();

    const r = Math.max(13, this.trial.corridorPx * 0.3);
    ctx.save();
    ctx.shadowColor = 'rgba(249,115,22,0.9)';
    ctx.shadowBlur = 20;
    ctx.fillStyle = '#f97316';
    ctx.beginPath();
    ctx.arc(p.x, p.y, r, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#ffd8a8';
    ctx.beginPath();
    ctx.arc(p.x - r * 0.25, p.y - r * 0.28, r * 0.34, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  // -------------------------------------------------------------------------
  // Input
  // -------------------------------------------------------------------------

  #bindInput() {
    const c = this.canvas;
    c.addEventListener('pointerdown', (e) => this.#down(e));
    c.addEventListener('pointermove', (e) => this.#move(e));
    c.addEventListener('pointerup', (e) => this.#up(e));
    c.addEventListener('pointercancel', (e) => this.#up(e));
    c.addEventListener('pointerleave', (e) => this.#up(e));
    c.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  #pos(e) {
    const r = this.canvas.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  }

  /**
   * Palm rejection: once we've seen an Apple Pencil, ignore finger contacts.
   * A resting hand generates a stream of touch pointers that would otherwise
   * count as wild strokes outside the lines.
   */
  #accepts(e) {
    if (this.frozen || !this.trial) return false;
    if (e.pointerType === 'pen') {
      this.penSeen = true;
      return true;
    }
    return !this.penSeen;
  }

  #down(e) {
    if (!this.#accepts(e)) return;
    if (this.activePointer !== null) return; // one contact at a time
    e.preventDefault();
    this.stopDemo();
    this.activePointer = e.pointerId;
    try {
      this.canvas.setPointerCapture(e.pointerId);
    } catch {
      /* capture is an optimisation, not a requirement */
    }
    this.drawing = true;
    this.lastPoint = this.#pos(e);
    this.lastInside = maskContains(this.mask, this.lastPoint.x, this.lastPoint.y);
    this.#markCoverage(this.lastPoint);
    if (this.onFirstTouch) {
      this.onFirstTouch();
      this.onFirstTouch = null;
    }
    this.render();
  }

  #move(e) {
    if (!this.drawing || e.pointerId !== this.activePointer) return;
    e.preventDefault();
    // Coalesced events give the Pencil's full sample rate; some browsers hand
    // back an empty list, in which case the event itself is all we get.
    const co = e.getCoalescedEvents ? e.getCoalescedEvents() : null;
    for (const ev of co && co.length ? co : [e]) this.#extend(this.#pos(ev));
    this.render();
  }

  #up(e) {
    if (!this.drawing || e.pointerId !== this.activePointer) return;
    this.drawing = false;
    this.activePointer = null;
    this.lastPoint = null;
    this.showStartHint = true;
    if (this.onStrokeEnd) this.onStrokeEnd();
    this.render();
  }

  #extend(p) {
    const a = this.lastPoint;
    if (!a) {
      this.lastPoint = p;
      return;
    }
    const seg = Math.hypot(p.x - a.x, p.y - a.y);
    if (seg < 0.7) return;

    // Walk the segment in small steps so a fast flick can't tunnel across the
    // corridor wall without being counted as an excursion.
    const steps = Math.max(1, Math.ceil(seg / 3));
    const ctx = this.ink.getContext('2d');
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.lineWidth = Math.min(26, Math.max(7, this.trial.corridorPx * 0.3));

    let prev = a;
    for (let s = 1; s <= steps; s++) {
      const t = s / steps;
      const q = { x: a.x + (p.x - a.x) * t, y: a.y + (p.y - a.y) * t };
      const inside = maskContains(this.mask, q.x, q.y);
      const d = Math.hypot(q.x - prev.x, q.y - prev.y);

      this.drawnLen += d;
      if (inside) {
        this.insideLen += d;
        this.#markCoverage(q);
      } else {
        this.outsideLen += d;
      }

      ctx.strokeStyle = inside ? INK_COLOR : INK_OUT_COLOR;
      ctx.beginPath();
      ctx.moveTo(prev.x, prev.y);
      ctx.lineTo(q.x, q.y);
      ctx.stroke();

      if (this.lastInside && !inside && this.onLeave) this.onLeave();
      this.lastInside = inside;
      prev = q;
    }
    this.lastPoint = p;
  }

  /** Any checkpoint near an in-corridor sample counts as traced. */
  #markCoverage(p) {
    const reach = Math.max(this.trial.corridorPx * 0.62, 16);
    const reach2 = reach * reach;
    for (let s = 0; s < this.trial.strokes.length; s++) {
      const cps = this.trial.strokes[s].checkpoints;
      const cov = this.covered[s];
      for (let i = 0; i < cps.length; i++) {
        if (cov[i]) continue;
        const dx = cps[i].x - p.x;
        const dy = cps[i].y - p.y;
        if (dx * dx + dy * dy <= reach2) cov[i] = 1;
      }
    }
  }

  #strokeCoverage(i) {
    const cov = this.covered[i];
    if (!cov || !cov.length) return 0;
    let n = 0;
    for (let k = 0; k < cov.length; k++) n += cov[k];
    return n / cov.length;
  }

  // -------------------------------------------------------------------------
  // Judging
  // -------------------------------------------------------------------------

  coverage() {
    if (!this.trial) return { per: [0], min: 0, mean: 0 };
    const per = this.trial.strokes.map((_, i) => this.#strokeCoverage(i));
    return { per, min: Math.min(...per), mean: per.reduce((a, b) => a + b, 0) / per.length };
  }

  /** True once every stroke is covered — used to judge the moment they lift. */
  looksFinished() {
    return this.coverage().min >= COVERAGE_TO_WIN;
  }

  judge() {
    if (!this.trial) return { win: false, reason: 'unfinished', coverage: 0, meanCoverage: 0 };
    const cov = this.coverage();
    const allowance = Math.max(
      this.trial.totalLen * LEAK_FRACTION,
      this.trial.corridorPx * LEAK_FLOOR_CORRIDORS,
    );
    const leaked = this.outsideLen > allowance;
    const scribbled = this.drawnLen > this.trial.totalLen * SCRIBBLE_LIMIT;
    const incomplete = cov.min < COVERAGE_TO_WIN;

    // Order matters: straying outside is the most useful thing to coach on, so
    // it wins over "you didn't finish" even when the stray is what cut the
    // coverage short.
    let reason = 'win';
    if (scribbled) reason = 'scribble';
    else if (leaked) reason = 'outside';
    else if (incomplete && cov.mean < 0.55) reason = 'unfinished';
    else if (incomplete) reason = 'almost';

    return {
      win: reason === 'win',
      reason,
      coverage: cov.min,
      meanCoverage: cov.mean,
      outsideLen: this.outsideLen,
      allowance,
      leakRatio: this.trial.totalLen ? this.outsideLen / this.trial.totalLen : 0,
    };
  }

  /** Every path point, for the celebration sparkle trail. */
  allPoints() {
    return this.trial.strokes.flatMap((st) => st.checkpoints);
  }

  center() {
    const v = this.#view();
    return { x: v.x + v.w / 2, y: v.y + v.h / 2 };
  }

  freeze(on) {
    this.frozen = on;
    if (on) {
      this.drawing = false;
      this.activePointer = null;
      this.lastPoint = null;
    }
  }
}
