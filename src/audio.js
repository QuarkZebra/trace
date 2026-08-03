// Voice and sound. The child can't read, so speech carries every instruction —
// nothing important in this app is text-only.

const PREFERRED_VOICES = [
  'Samantha', 'Karen', 'Moira', 'Tessa', 'Serena', 'Allison', 'Ava',
  'Google UK English Female', 'Microsoft Aria Online (Natural) - English (United States)',
];

export class Voice {
  constructor() {
    this.enabled = true;
    this.voice = null;
    this.rate = 0.92; // a shade slower than default; 4-year-old ears
    this.pitch = 1.12;
    this.ready = false;
    if ('speechSynthesis' in window) {
      const load = () => this.#pickVoice();
      load();
      speechSynthesis.addEventListener('voiceschanged', load);
    }
  }

  #pickVoice() {
    const all = speechSynthesis.getVoices();
    if (!all.length) return;
    for (const want of PREFERRED_VOICES) {
      const v = all.find((x) => x.name === want);
      if (v) {
        this.voice = v;
        this.ready = true;
        return;
      }
    }
    this.voice = all.find((v) => v.lang && v.lang.startsWith('en')) || all[0];
    this.ready = true;
  }

  /** iOS won't speak until synthesis is touched inside a user gesture. */
  unlock() {
    if (!('speechSynthesis' in window)) return;
    const u = new SpeechSynthesisUtterance(' ');
    u.volume = 0;
    speechSynthesis.speak(u);
    this.#pickVoice();
  }

  /** Speak, cancelling anything mid-sentence. Resolves when done (or skipped). */
  say(text, { interrupt = true } = {}) {
    if (!this.enabled || !('speechSynthesis' in window)) return Promise.resolve();
    if (interrupt) speechSynthesis.cancel();
    return new Promise((resolve) => {
      const u = new SpeechSynthesisUtterance(text);
      if (this.voice) u.voice = this.voice;
      u.rate = this.rate;
      u.pitch = this.pitch;
      u.onend = () => resolve();
      u.onerror = () => resolve();
      // Safari occasionally drops onend; don't let the state machine wedge.
      const guard = setTimeout(resolve, 1200 + text.length * 90);
      const clear = () => clearTimeout(guard);
      u.addEventListener('end', clear);
      u.addEventListener('error', clear);
      speechSynthesis.speak(u);
    });
  }

  stop() {
    if ('speechSynthesis' in window) speechSynthesis.cancel();
  }
}

// ---------------------------------------------------------------------------
// Sound effects, synthesised so there are no audio files to ship or preload.
// ---------------------------------------------------------------------------

export class Sfx {
  constructor() {
    this.enabled = true;
    this.ctx = null;
  }

  unlock() {
    if (!this.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (AC) this.ctx = new AC();
    }
    if (this.ctx && this.ctx.state === 'suspended') this.ctx.resume();
  }

  #tone(freq, start, dur, { type = 'sine', gain = 0.18 } = {}) {
    if (!this.ctx || !this.enabled) return;
    const t0 = this.ctx.currentTime + start;
    const osc = this.ctx.createOscillator();
    const env = this.ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, t0);
    env.gain.setValueAtTime(0, t0);
    env.gain.linearRampToValueAtTime(gain, t0 + 0.015);
    env.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    osc.connect(env).connect(this.ctx.destination);
    osc.start(t0);
    osc.stop(t0 + dur + 0.05);
  }

  #noise(start, dur, gain = 0.1) {
    if (!this.ctx || !this.enabled) return;
    const t0 = this.ctx.currentTime + start;
    const frames = Math.floor(this.ctx.sampleRate * dur);
    const buf = this.ctx.createBuffer(1, frames, this.ctx.sampleRate);
    const data = buf.getChannelData(0);
    for (let i = 0; i < frames; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / frames);
    const src = this.ctx.createBufferSource();
    const env = this.ctx.createGain();
    src.buffer = buf;
    env.gain.setValueAtTime(gain, t0);
    src.connect(env).connect(this.ctx.destination);
    src.start(t0);
  }

  smallWin() {
    [523.25, 659.25, 783.99].forEach((f, i) => this.#tone(f, i * 0.09, 0.28, { type: 'triangle' }));
  }

  bigWin() {
    const notes = [523.25, 659.25, 783.99, 1046.5, 1318.5];
    notes.forEach((f, i) => this.#tone(f, i * 0.075, 0.5, { type: 'triangle', gain: 0.2 }));
    this.#tone(261.63, 0.4, 0.9, { type: 'sine', gain: 0.12 });
    this.#noise(0.38, 0.5, 0.07);
  }

  nearMiss() {
    this.#tone(392, 0, 0.2, { type: 'sine', gain: 0.14 });
    this.#tone(349.23, 0.16, 0.3, { type: 'sine', gain: 0.12 });
  }

  /** Soft click when the pen strays outside the corridor. */
  bump() {
    this.#tone(180, 0, 0.07, { type: 'sine', gain: 0.07 });
  }

  pop() {
    this.#tone(880, 0, 0.09, { type: 'square', gain: 0.06 });
  }

  tick() {
    this.#tone(1200, 0, 0.05, { type: 'sine', gain: 0.04 });
  }
}
