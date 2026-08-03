// Path sampling + corridor geometry.
//
// Shapes are authored in a 0..100 square ("shape units"). A shape is a list of
// strokes; each stroke is a mini-SVG-ish string that we sample into a polyline:
//
//   M x y            move to
//   L x y            line to
//   Q cx cy x y      quadratic bezier
//   C c1x c1y c2x c2y x y   cubic bezier
//   E cx cy rx ry a0 a1     elliptical arc, angles in degrees, y down
//   S cx cy r0 r1 a0 a1     spiral arc, radius eased from r0 to r1 over the sweep
//
// Everything downstream (corridor mask, coverage checkpoints, the demo dot)
// works on the sampled polyline, so we never have to do real path offsetting.

const DEFAULT_STEP = 0.7; // shape units between samples

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function ellipsePoint(cx, cy, rx, ry, deg) {
  const a = (deg * Math.PI) / 180;
  return [cx + rx * Math.cos(a), cy + ry * Math.sin(a)];
}

function dist(ax, ay, bx, by) {
  return Math.hypot(bx - ax, by - ay);
}

/** Sample a path string into a flat polyline: [{x, y}, ...] */
export function samplePath(d, step = DEFAULT_STEP) {
  const tok = d.trim().split(/[\s,]+/);
  const pts = [];
  let cx = 0;
  let cy = 0;
  let i = 0;

  const num = () => parseFloat(tok[i++]);
  const push = (x, y) => {
    const last = pts[pts.length - 1];
    if (!last || dist(last.x, last.y, x, y) > 1e-6) pts.push({ x, y });
  };

  while (i < tok.length) {
    const cmd = tok[i++];
    switch (cmd) {
      case 'M': {
        cx = num();
        cy = num();
        push(cx, cy);
        break;
      }
      case 'L': {
        const x = num();
        const y = num();
        const n = Math.max(2, Math.ceil(dist(cx, cy, x, y) / step));
        for (let k = 1; k <= n; k++) push(lerp(cx, x, k / n), lerp(cy, y, k / n));
        cx = x;
        cy = y;
        break;
      }
      case 'Q': {
        const qx = num();
        const qy = num();
        const x = num();
        const y = num();
        const approx = dist(cx, cy, qx, qy) + dist(qx, qy, x, y);
        const n = Math.max(4, Math.ceil(approx / step));
        for (let k = 1; k <= n; k++) {
          const t = k / n;
          const mt = 1 - t;
          push(
            mt * mt * cx + 2 * mt * t * qx + t * t * x,
            mt * mt * cy + 2 * mt * t * qy + t * t * y,
          );
        }
        cx = x;
        cy = y;
        break;
      }
      case 'C': {
        const c1x = num();
        const c1y = num();
        const c2x = num();
        const c2y = num();
        const x = num();
        const y = num();
        const approx =
          dist(cx, cy, c1x, c1y) + dist(c1x, c1y, c2x, c2y) + dist(c2x, c2y, x, y);
        const n = Math.max(6, Math.ceil(approx / step));
        for (let k = 1; k <= n; k++) {
          const t = k / n;
          const mt = 1 - t;
          push(
            mt * mt * mt * cx + 3 * mt * mt * t * c1x + 3 * mt * t * t * c2x + t * t * t * x,
            mt * mt * mt * cy + 3 * mt * mt * t * c1y + 3 * mt * t * t * c2y + t * t * t * y,
          );
        }
        cx = x;
        cy = y;
        break;
      }
      case 'E': {
        const ecx = num();
        const ecy = num();
        const rx = num();
        const ry = num();
        const a0 = num();
        const a1 = num();
        const sweep = Math.abs(a1 - a0);
        const arcLen = ((sweep * Math.PI) / 180) * ((rx + ry) / 2);
        const n = Math.max(12, Math.ceil(arcLen / step));
        for (let k = 0; k <= n; k++) {
          const [x, y] = ellipsePoint(ecx, ecy, rx, ry, lerp(a0, a1, k / n));
          push(x, y);
          cx = x;
          cy = y;
        }
        break;
      }
      case 'S': {
        const scx = num();
        const scy = num();
        const r0 = num();
        const r1 = num();
        const a0 = num();
        const a1 = num();
        const sweep = Math.abs(a1 - a0);
        const arcLen = ((sweep * Math.PI) / 180) * ((r0 + r1) / 2);
        const n = Math.max(24, Math.ceil(arcLen / step));
        for (let k = 0; k <= n; k++) {
          const t = k / n;
          const r = lerp(r0, r1, t);
          const [x, y] = ellipsePoint(scx, scy, r, r, lerp(a0, a1, t));
          push(x, y);
          cx = x;
          cy = y;
        }
        break;
      }
      default:
        throw new Error(`Unknown path command "${cmd}" in: ${d}`);
    }
  }
  return pts;
}

export function polylineLength(pts) {
  let L = 0;
  for (let i = 1; i < pts.length; i++) L += dist(pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y);
  return L;
}

/** Re-space a polyline so consecutive points are `spacing` apart. */
export function resample(pts, spacing) {
  if (pts.length < 2) return pts.slice();
  const out = [pts[0]];
  let carry = 0;
  for (let i = 1; i < pts.length; i++) {
    const a = pts[i - 1];
    const b = pts[i];
    const seg = dist(a.x, a.y, b.x, b.y);
    if (seg === 0) continue;
    let t = spacing - carry;
    while (t <= seg) {
      out.push({ x: lerp(a.x, b.x, t / seg), y: lerp(a.y, b.y, t / seg) });
      t += spacing;
    }
    carry = (carry + seg) % spacing;
  }
  const last = pts[pts.length - 1];
  const tail = out[out.length - 1];
  if (dist(tail.x, tail.y, last.x, last.y) > spacing * 0.4) out.push(last);
  return out;
}

/** Bounding box of every stroke together. */
export function bboxOf(strokes) {
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const pts of strokes) {
    for (const p of pts) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
  }
  return { minX, minY, maxX, maxY, w: maxX - minX, h: maxY - minY };
}

/**
 * Build everything the game needs from a shape definition, in screen pixels.
 *
 * `corridorUnits` is the full corridor width in shape units (0..100 box), so a
 * value of 18 means the gap between the two lines is 18% of the shape box.
 */
export function buildTrial(shape, corridorUnits, view) {
  const raw = shape.strokes.map((d) => samplePath(d));
  const box = bboxOf(raw);

  // Fit the shape (plus half a corridor of breathing room) into the view.
  const pad = corridorUnits / 2 + 3;
  const spanX = box.w + pad * 2;
  const spanY = box.h + pad * 2;
  const scale = Math.min(view.w / spanX, view.h / spanY);
  const ox = view.x + (view.w - box.w * scale) / 2 - box.minX * scale;
  const oy = view.y + (view.h - box.h * scale) / 2 - box.minY * scale;
  const toScreen = (p) => ({ x: p.x * scale + ox, y: p.y * scale + oy });

  const corridorPx = corridorUnits * scale;
  const strokes = raw.map((pts) => {
    const screen = pts.map(toScreen);
    const len = polylineLength(screen);
    // One checkpoint roughly every third of a corridor width, clamped so short
    // strokes still get a usable number and long ones don't explode.
    const spacing = Math.min(Math.max(corridorPx * 0.34, 10), Math.max(len / 12, 12));
    return { pts: screen, len, checkpoints: resample(screen, spacing) };
  });

  return {
    shape,
    strokes,
    corridorPx,
    scale,
    totalLen: strokes.reduce((s, st) => s + st.len, 0),
  };
}

/**
 * Rasterise the corridor once into a byte grid. Hit-testing a finger position
 * then costs one array lookup instead of a distance-to-polyline scan.
 */
export function buildCorridorMask(trial, w, h) {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const ctx = c.getContext('2d', { willReadFrequently: true });
  ctx.strokeStyle = '#fff';
  ctx.lineWidth = trial.corridorPx;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  for (const st of trial.strokes) {
    ctx.beginPath();
    ctx.moveTo(st.pts[0].x, st.pts[0].y);
    for (let i = 1; i < st.pts.length; i++) ctx.lineTo(st.pts[i].x, st.pts[i].y);
    ctx.stroke();
  }
  const src = ctx.getImageData(0, 0, w, h).data;
  const grid = new Uint8Array(w * h);
  for (let i = 0, p = 3; i < grid.length; i++, p += 4) grid[i] = src[p] > 120 ? 1 : 0;
  return { grid, w, h };
}

export function maskContains(mask, x, y) {
  const ix = x | 0;
  const iy = y | 0;
  if (ix < 0 || iy < 0 || ix >= mask.w || iy >= mask.h) return false;
  return mask.grid[iy * mask.w + ix] === 1;
}
