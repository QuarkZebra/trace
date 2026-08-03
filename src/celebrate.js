// Particle celebrations on a dedicated overlay canvas.
//
// Two tiers: a small sparkle-and-stamp for every win, and an occasional big one
// (confetti + balloons + starburst) so the big ones stay special.

const COLORS = [
  '#ff5d8f', '#ffd166', '#06d6a0', '#4cc9f0', '#b892ff',
  '#ff924c', '#f9f871', '#7ee8fa', '#ff6392',
];

const rand = (a, b) => a + Math.random() * (b - a);
const pick = (arr) => arr[(Math.random() * arr.length) | 0];

class Confetti {
  constructor(x, y) {
    const a = rand(-Math.PI, 0);
    const sp = rand(7, 20);
    this.x = x;
    this.y = y;
    this.vx = Math.cos(a) * sp * rand(0.6, 1.4);
    this.vy = Math.sin(a) * sp;
    this.w = rand(7, 15);
    this.h = rand(9, 20);
    this.rot = rand(0, Math.PI * 2);
    this.spin = rand(-0.28, 0.28);
    this.color = pick(COLORS);
    this.life = rand(2.2, 3.6);
    this.age = 0;
    this.wobble = rand(0, 6.28);
  }
  step(dt) {
    this.age += dt;
    this.vy += 26 * dt;
    this.vx *= 0.995;
    this.wobble += dt * 7;
    this.x += (this.vx + Math.sin(this.wobble) * 1.6) * dt * 60 * 0.35;
    this.y += this.vy * dt * 60 * 0.35;
    this.rot += this.spin;
    return this.age < this.life;
  }
  draw(ctx) {
    const fade = Math.min(1, (this.life - this.age) / 0.6);
    ctx.save();
    ctx.globalAlpha = fade;
    ctx.translate(this.x, this.y);
    ctx.rotate(this.rot);
    ctx.fillStyle = this.color;
    // Squash on the spin so flat pieces read as tumbling paper.
    ctx.fillRect(-this.w / 2, -this.h / 2, this.w, this.h * Math.abs(Math.cos(this.rot * 1.4)));
    ctx.restore();
  }
}

class Balloon {
  constructor(x, y) {
    this.x = x;
    this.y = y;
    this.r = rand(28, 46);
    this.vy = rand(-2.6, -1.5);
    this.color = pick(COLORS);
    this.sway = rand(0, 6.28);
    this.swaySpeed = rand(1.1, 2.1);
    this.life = rand(4, 6);
    this.age = 0;
  }
  step(dt) {
    this.age += dt;
    this.sway += dt * this.swaySpeed;
    this.y += this.vy * dt * 60;
    this.x += Math.sin(this.sway) * 0.9;
    return this.age < this.life && this.y > -160;
  }
  draw(ctx) {
    ctx.save();
    ctx.globalAlpha = Math.min(1, (this.life - this.age) / 0.8);
    ctx.strokeStyle = 'rgba(255,255,255,0.5)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(this.x, this.y + this.r * 1.15);
    ctx.quadraticCurveTo(
      this.x + Math.sin(this.sway * 1.6) * 16,
      this.y + this.r * 1.15 + 44,
      this.x + Math.sin(this.sway) * 8,
      this.y + this.r * 1.15 + 88,
    );
    ctx.stroke();

    ctx.fillStyle = this.color;
    ctx.beginPath();
    ctx.ellipse(this.x, this.y, this.r * 0.85, this.r, 0, 0, Math.PI * 2);
    ctx.fill();
    // knot
    ctx.beginPath();
    ctx.moveTo(this.x - 7, this.y + this.r * 0.99);
    ctx.lineTo(this.x + 7, this.y + this.r * 0.99);
    ctx.lineTo(this.x, this.y + this.r * 1.2);
    ctx.closePath();
    ctx.fill();
    // highlight
    ctx.fillStyle = 'rgba(255,255,255,0.42)';
    ctx.beginPath();
    ctx.ellipse(this.x - this.r * 0.28, this.y - this.r * 0.34, this.r * 0.2, this.r * 0.28, -0.5, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }
}

class Sparkle {
  constructor(x, y) {
    const a = rand(0, Math.PI * 2);
    const sp = rand(1.5, 7);
    this.x = x;
    this.y = y;
    this.vx = Math.cos(a) * sp;
    this.vy = Math.sin(a) * sp;
    this.r = rand(3, 8);
    this.color = pick(COLORS);
    this.life = rand(0.6, 1.3);
    this.age = 0;
  }
  step(dt) {
    this.age += dt;
    this.x += this.vx * dt * 60 * 0.5;
    this.y += this.vy * dt * 60 * 0.5;
    this.vy += 8 * dt;
    this.vx *= 0.97;
    this.vy *= 0.97;
    return this.age < this.life;
  }
  draw(ctx) {
    const t = 1 - this.age / this.life;
    ctx.save();
    ctx.globalAlpha = t;
    ctx.fillStyle = this.color;
    ctx.translate(this.x, this.y);
    ctx.rotate(this.age * 4);
    const r = this.r * (0.5 + t * 0.9);
    ctx.beginPath();
    for (let i = 0; i < 8; i++) {
      const rr = i % 2 ? r * 0.42 : r;
      const a = (i / 8) * Math.PI * 2;
      ctx[i ? 'lineTo' : 'moveTo'](Math.cos(a) * rr, Math.sin(a) * rr);
    }
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }
}

class Ring {
  constructor(x, y) {
    this.x = x;
    this.y = y;
    this.age = 0;
    this.life = 0.85;
  }
  step(dt) {
    this.age += dt;
    return this.age < this.life;
  }
  draw(ctx) {
    const t = this.age / this.life;
    ctx.save();
    ctx.globalAlpha = (1 - t) * 0.7;
    ctx.strokeStyle = '#ffd166';
    ctx.lineWidth = 14 * (1 - t) + 2;
    ctx.beginPath();
    ctx.arc(this.x, this.y, 40 + t * 260, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  }
}

export class Celebration {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.parts = [];
    this.raf = null;
    this.last = 0;
  }

  get width() {
    return this.canvas.clientWidth;
  }

  get height() {
    return this.canvas.clientHeight;
  }

  small(x, y) {
    for (let i = 0; i < 26; i++) this.parts.push(new Sparkle(x, y));
    this.parts.push(new Ring(x, y));
    this.#run();
  }

  /** Sparkle trail along the shape the child just finished. */
  traceGlow(points) {
    const step = Math.max(1, Math.floor(points.length / 26));
    for (let i = 0; i < points.length; i += step) {
      const p = points[i];
      this.parts.push(new Sparkle(p.x, p.y));
    }
    this.#run();
  }

  big() {
    const W = this.width;
    const H = this.height;
    for (let i = 0; i < 110; i++) {
      this.parts.push(new Confetti(rand(W * 0.15, W * 0.85), rand(H * 0.35, H * 0.6)));
    }
    for (let i = 0; i < 9; i++) {
      this.parts.push(new Balloon(rand(W * 0.08, W * 0.92), H + rand(40, 320)));
    }
    this.parts.push(new Ring(W / 2, H / 2));
    for (let i = 0; i < 40; i++) this.parts.push(new Sparkle(W / 2, H / 2));
    this.#run();
  }

  clear() {
    this.parts.length = 0;
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    if (this.raf) cancelAnimationFrame(this.raf);
    this.raf = null;
  }

  #run() {
    if (this.raf) return;
    this.last = performance.now();
    const loop = (now) => {
      const dt = Math.min(0.05, (now - this.last) / 1000);
      this.last = now;
      const ctx = this.ctx;
      ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
      this.parts = this.parts.filter((p) => p.step(dt));
      for (const p of this.parts) p.draw(ctx);
      if (this.parts.length) {
        this.raf = requestAnimationFrame(loop);
      } else {
        this.raf = null;
        ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
      }
    };
    this.raf = requestAnimationFrame(loop);
  }
}
