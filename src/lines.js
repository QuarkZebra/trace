// Everything the app says out loud, in one place so it's easy to reword.
//
// Rules of thumb used here: short sentences, concrete verbs, no praise for
// being "smart" (praise the effort or the action), and coaching that names one
// physical thing to change rather than a general "try harder".

let lastPicked = new Map();

/** Pick from a bank without repeating the previous pick from that bank. */
function pick(key, bank) {
  const prev = lastPicked.get(key);
  const options = bank.length > 1 ? bank.filter((x) => x !== prev) : bank;
  const choice = options[Math.floor(Math.random() * options.length)];
  lastPicked.set(key, choice);
  return choice;
}

export const WELCOME = [
  "Hi! Let's trace some shapes. Stay inside the lines!",
  "Ready to trace? Try to keep your line inside the track.",
];

export function challenge(shape) {
  const n = shape.name;
  return pick('challenge', [
    `Can you trace this ${n} without going outside the lines?`,
    `Here's a ${n}. Try to stay inside the lines.`,
    `Let's trace a ${n}. Keep your line in the middle.`,
    `A ${n}! See if you can stay inside the track.`,
  ]);
}

export function yourTurn() {
  return pick('turn', [
    'Now you try. Start on the green dot.',
    'Your turn! Start on the green dot.',
    'Okay, you go. Begin at the green dot.',
  ]);
}

export function demoIntro() {
  return pick('demoIntro', ['Watch me first.', "I'll show you.", 'Watch how it goes.']);
}

export function strokePart(i, total) {
  if (total <= 1) return null;
  if (i === 0) return 'First, this part.';
  if (i === total - 1) return 'And the last part.';
  return 'Now the next part.';
}

export function idleNudge() {
  return pick('idle', [
    "Tap the yellow button if you'd like me to show you again.",
    'Need to see it again? Tap the yellow button.',
  ]);
}

export function praise() {
  return pick('praise', [
    'You did it!',
    'Nice tracing!',
    'You stayed inside the lines!',
    'That was great!',
    'Wow, right down the middle!',
    'Beautiful line!',
    'You kept it steady!',
  ]);
}

export function bigPraise() {
  return pick('bigPraise', [
    'Amazing! Look at that!',
    'Fantastic tracing! Balloons for you!',
    'Superstar! That was so smooth!',
    'Incredible! Confetti time!',
  ]);
}

/**
 * Near-miss coaching. Always the same shape: a warm opener, then exactly one
 * short, physical instruction. Long explanations lose a four-year-old.
 */
const OPENERS = ['Ooh, so close!', 'Almost!', 'So close!', 'Nearly had it!'];

const TIPS = {
  outside: [
    'Go slowly, like a turtle.',
    'Hold your pencil close to the tip.',
    'Rest your hand on the screen.',
    'Keep your eyes right on the line.',
    'Pinch the pencil with two fingers and your thumb.',
    'Little bit slower this time.',
  ],
  almost: [
    'Keep going all the way to the end.',
    'Follow the track right to the finish.',
    'Trace the whole thing this time.',
  ],
  unfinished: [
    'Start on the green dot and follow the track.',
    'Try tracing the whole shape.',
    'Watch the yellow dot, then copy it.',
  ],
  scribble: [
    'One smooth line, all the way around.',
    'Try one slow line instead of back and forth.',
  ],
};

export function encourage(reason) {
  const opener = pick('opener', OPENERS);
  const tip = pick(`tip-${reason}`, TIPS[reason] || TIPS.outside);
  return `${opener} ${tip}`;
}

export function tryAgain() {
  return pick('again', ["Let's try that one again.", 'One more go at this one.', 'Try it again.']);
}
