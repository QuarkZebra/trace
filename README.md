# Trace

A tracing game for a four-year-old. A shape is shown as a bright track between
two lines on a blacked-out background; the child traces it with a finger or an
Apple Pencil and has to stay inside. How far apart the lines are adapts to keep
them succeeding about 85% of the time.

It talks. Nothing important is text-only, because the intended player can't read.

---

## Running it

```bash
node /Users/matthewbrown/Projects/Trace/serve.js
```

That prints two addresses — a `localhost` one for the Mac and a LAN one
(`http://192.168.x.x:4173`) to open in Safari on the iPad, as long as both are on
the same wifi. No build step, no dependencies.

### Putting it on the iPad's home screen

In Safari on the iPad: **Share → Add to Home Screen**. It then launches
full-screen with no browser chrome, keeps the screen awake while playing, and
remembers progress between sessions.

One caveat: the offline cache (service worker) only registers over HTTPS, so over
plain wifi the app needs the Mac's server running. If you want it fully offline,
host the folder anywhere with HTTPS — GitHub Pages, Netlify drop, anything static
— and add *that* to the home screen instead.

There's no Xcode on this machine, so this is a web app rather than a native one.
If you later want it in the App Store, the whole thing drops into a WKWebView
essentially unchanged.

---

## How the difficulty works

Based on Wilson, Shenhav, Straccia & Cohen (2019), *The Eighty Five Percent Rule
for optimal learning*, Nature Communications 10:4646 —
https://www.nature.com/articles/s41467-019-12552-4

Their result is that for a learner whose accuracy follows a sigmoid in task
difficulty, learning is fastest when training error sits near 15.87%. So the app
doesn't make things as easy as possible, and it doesn't push to failure. It
steers toward roughly 85% success.

Two things do the steering, on different timescales
([src/difficulty.js](src/difficulty.js)):

1. **A weighted staircase** on `w85` — the corridor width believed to sit at the
   85% point. Steps are multiplicative, since width is a scale parameter. Up and
   down steps are asymmetric in the Kaernbach sense: converging on p = 0.85 needs
   an up-step worth p/(1−p) ≈ 5.7 down-steps. Step size is further weighted by
   whether the trial was *meant* to be easy, so an unexpected miss on an easy
   shape moves the estimate far more than an expected miss on a hard one.

2. **A slow regulator** over the last dozen trials. If observed accuracy drifts
   off 85% for a sustained stretch it nudges the width, and at the rails it moves
   the child between shape-complexity levels instead.

### The one-in-six

The 85% is a property of the *set*, not of every trial — which is what you asked
for. Most trials are served 22–40% wider than the 85% point, comfortably
winnable. About one in six is a **probe**, served at or below threshold, and half
of those spend their difficulty on a harder *shape* rather than a narrower track.

Three rules stop the probes being predictable, which matters because a child who
can spot "this is the hard one" has already half-lost it:

- never two probes in a row,
- forced if nine trials pass without one,
- suppressed right after two misses, so a struggling child gets a run of wins
  first.

In simulation across five different learner profiles, observed accuracy lands
between 83% and 88%, probes arrive anywhere from 1 to 10 trials apart, and the
longest run of consecutive misses is 2.

### Shape levels

1. single straight strokes
2. simple closed shapes, gentle curves
3. corners and points, easy letters and digits
4. most letters and digits, two-part shapes
5. fiddly letters, tight curves, three-part shapes, generated designs

Levels advance when the corridor is already tight and accuracy is still high —
narrowing further would just test fine motor control the child has clearly got.

---

## What happens in a trial

1. Speaks the challenge: *"Can you trace this triangle without going outside the
   lines?"*
2. Demonstrates with a dot travelling the path, narrating multi-part shapes
   (*"First, this part." … "And the last part."*). Skipped for shapes already
   seen this session, unless the last go at it missed.
3. Waits. A green dot with an arrow marks where to start and which way to go.
   After 4.5 seconds of nothing, the yellow replay button appears and it offers
   it out loud. Once shown, the button stays.
4. The child traces. Ink is indigo inside the lines and turns red the instant it
   crosses one, with a soft click — feedback without a penalty.
5. Judged when the shape is covered, or 2.6 seconds after they stop.

**A win** needs every stroke ~90% covered and total out-of-corridor drawing under
a small allowance (7% of path length, with an absolute floor so one wobble at a
corner isn't fatal). Roughly one win in three or four gets a big celebration —
confetti, balloons, fanfare — never two in a row, guaranteed if it's been five.
The rest get sparkles and a chime.

**A miss** gets warmth plus exactly one short physical instruction, chosen from
what actually went wrong: *"Ooh, so close! Hold your pencil close to the tip."*
Then one immediate retry of the same shape, slightly wider, so the trial usually
ends on a success. **That retry isn't recorded** — the first attempt is the
measurement, the retry is practice. Keeps the 85% accounting honest.

---

## Grown-up settings

Press and hold the **top-left corner for about a second**. You get:

- shapes tried, all-time and last-12 accuracy, current level and line gap
- a strip of the last 14 results — filled pips are wins, ringed pips are probes
- talking and sound-effect toggles, and talking speed
- what to practise: everything / shapes / letters / numbers
- reset progress

---

## Adding your own shapes

Shapes live in [src/shapes.js](src/shapes.js), authored in a 0–100 box with y
pointing down. The path mini-language:

```
M x y                    move to
L x y                    line to
Q cx cy x y              quadratic curve
C c1x c1y c2x c2y x y    cubic curve
E cx cy rx ry a0 a1      elliptical arc, degrees
S cx cy r0 r1 a0 a1      spiral, radius eased from r0 to r1
```

A shape is a list of strokes, and the list order is the teaching order the demo
dot follows. So the letter P is the stem first, then the bowl:

```js
S('letter-P', 'letter P', 4, [
  'M 28 10 L 28 90',
  'M 28 10 Q 72 10 72 32 Q 72 54 28 54',
], { maxWidth: 20 })
```

`name` is spoken aloud, so use a word a four-year-old has. `maxWidth` caps the
corridor for shapes with narrow channels or small holes — widen a spiral past its
turn spacing and the turns fuse into one white blob with no lines left to stay
inside. Corners round off harmlessly, so only shapes with stretches running close
and *parallel*, or with small enclosed holes, need one.

Spoken lines are all in [src/lines.js](src/lines.js) if you want to reword the
praise or the coaching tips.

---

## Layout

| file | what it does |
| --- | --- |
| [src/main.js](src/main.js) | app shell, the trial loop, settings, saving |
| [src/difficulty.js](src/difficulty.js) | the 85% rule — staircase, probes, levels |
| [src/board.js](src/board.js) | canvas, corridor drawing, pen input, judging |
| [src/geometry.js](src/geometry.js) | path sampling, corridor mask, checkpoints |
| [src/shapes.js](src/shapes.js) | shape library and the generator for new designs |
| [src/celebrate.js](src/celebrate.js) | confetti, balloons, sparkles |
| [src/audio.js](src/audio.js) | speech, and synthesised sound effects |
| [src/lines.js](src/lines.js) | every spoken line |

Hit-testing rasterises the corridor once into a byte grid, so checking whether a
finger is inside costs one array lookup rather than a distance-to-path scan on
every pointer sample. Fast strokes are walked in ~3px steps so a quick flick
can't tunnel through a wall uncounted. Once an Apple Pencil has been seen, finger
contacts are ignored — otherwise a resting palm draws wild lines all over the
shape.
