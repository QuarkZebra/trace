import CoreGraphics
import Foundation

// Path sampling and corridor geometry — the Swift counterpart of the web
// version's geometry module.
//
// Shapes are authored in a 0..100 square (y down). A shape is a list of
// strokes, each a mini-SVG-ish string sampled into a polyline:
//
//   M x y            move to
//   L x y            line to
//   Q cx cy x y      quadratic bezier
//   C c1x c1y c2x c2y x y   cubic bezier
//   E cx cy rx ry a0 a1     elliptical arc, degrees, y down
//   S cx cy r0 r1 a0 a1     spiral, radius eased from r0 to r1
//
// Everything downstream works on the sampled polyline, so we never have to do
// real path offsetting.

struct Pt: Equatable {
    var x: CGFloat
    var y: CGFloat
}

@inline(__always) private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

@inline(__always) private func ellipsePoint(
    _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ deg: CGFloat
) -> Pt {
    let a = deg * .pi / 180
    return Pt(x: cx + rx * cos(a), y: cy + ry * sin(a))
}

enum PathDSL {
    static let defaultStep: CGFloat = 0.7

    static func sample(_ d: String, step: CGFloat = defaultStep) -> [Pt] {
        let tokens = d.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" })
        var pts: [Pt] = []
        var cx: CGFloat = 0
        var cy: CGFloat = 0
        var i = 0

        func num() -> CGFloat {
            defer { i += 1 }
            guard i < tokens.count, let v = Double(tokens[i]) else { return 0 }
            return CGFloat(v)
        }
        func push(_ x: CGFloat, _ y: CGFloat) {
            if let last = pts.last, hypot(x - last.x, y - last.y) <= 1e-6 { return }
            pts.append(Pt(x: x, y: y))
        }

        while i < tokens.count {
            let cmd = tokens[i]
            i += 1
            switch cmd {
            case "M":
                cx = num(); cy = num()
                push(cx, cy)

            case "L":
                let x = num(), y = num()
                let n = max(2, Int(ceil(hypot(x - cx, y - cy) / step)))
                for k in 1...n {
                    let t = CGFloat(k) / CGFloat(n)
                    push(lerp(cx, x, t), lerp(cy, y, t))
                }
                cx = x; cy = y

            case "Q":
                let qx = num(), qy = num(), x = num(), y = num()
                let approx = hypot(qx - cx, qy - cy) + hypot(x - qx, y - qy)
                let n = max(4, Int(ceil(approx / step)))
                for k in 1...n {
                    let t = CGFloat(k) / CGFloat(n), mt = 1 - t
                    push(
                        mt * mt * cx + 2 * mt * t * qx + t * t * x,
                        mt * mt * cy + 2 * mt * t * qy + t * t * y)
                }
                cx = x; cy = y

            case "C":
                let c1x = num(), c1y = num(), c2x = num(), c2y = num(), x = num(), y = num()
                let approx = hypot(c1x - cx, c1y - cy) + hypot(c2x - c1x, c2y - c1y) + hypot(x - c2x, y - c2y)
                let n = max(6, Int(ceil(approx / step)))
                for k in 1...n {
                    let t = CGFloat(k) / CGFloat(n), mt = 1 - t
                    push(
                        mt * mt * mt * cx + 3 * mt * mt * t * c1x + 3 * mt * t * t * c2x + t * t * t * x,
                        mt * mt * mt * cy + 3 * mt * mt * t * c1y + 3 * mt * t * t * c2y + t * t * t * y)
                }
                cx = x; cy = y

            case "E":
                let ecx = num(), ecy = num(), rx = num(), ry = num(), a0 = num(), a1 = num()
                let arcLen = abs(a1 - a0) * .pi / 180 * ((rx + ry) / 2)
                let n = max(12, Int(ceil(arcLen / step)))
                for k in 0...n {
                    let p = ellipsePoint(ecx, ecy, rx, ry, lerp(a0, a1, CGFloat(k) / CGFloat(n)))
                    push(p.x, p.y)
                    cx = p.x; cy = p.y
                }

            case "S":
                let scx = num(), scy = num(), r0 = num(), r1 = num(), a0 = num(), a1 = num()
                let arcLen = abs(a1 - a0) * .pi / 180 * ((r0 + r1) / 2)
                let n = max(24, Int(ceil(arcLen / step)))
                for k in 0...n {
                    let t = CGFloat(k) / CGFloat(n)
                    let r = lerp(r0, r1, t)
                    let p = ellipsePoint(scx, scy, r, r, lerp(a0, a1, t))
                    push(p.x, p.y)
                    cx = p.x; cy = p.y
                }

            default:
                assertionFailure("Unknown path command \"\(cmd)\" in: \(d)")
            }
        }
        return pts
    }
}

func polylineLength(_ pts: [Pt]) -> CGFloat {
    guard pts.count > 1 else { return 0 }
    var total: CGFloat = 0
    for i in 1..<pts.count { total += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) }
    return total
}

/// Re-space a polyline so consecutive points sit `spacing` apart.
func resample(_ pts: [Pt], spacing: CGFloat) -> [Pt] {
    guard pts.count > 1, spacing > 0 else { return pts }
    var out = [pts[0]]
    var carry: CGFloat = 0
    for i in 1..<pts.count {
        let a = pts[i - 1], b = pts[i]
        let seg = hypot(b.x - a.x, b.y - a.y)
        if seg == 0 { continue }
        var t = spacing - carry
        while t <= seg {
            out.append(Pt(x: lerp(a.x, b.x, t / seg), y: lerp(a.y, b.y, t / seg)))
            t += spacing
        }
        carry = (carry + seg).truncatingRemainder(dividingBy: spacing)
    }
    if let last = pts.last, let tail = out.last, hypot(tail.x - last.x, tail.y - last.y) > spacing * 0.4 {
        out.append(last)
    }
    return out
}

func boundingBox(_ strokes: [[Pt]]) -> CGRect {
    var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
    var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
    for pts in strokes {
        for p in pts {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
    }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

// MARK: - Trial

struct StrokeGeometry {
    var pts: [Pt]
    var len: CGFloat
    var checkpoints: [Pt]

    var cgPath: CGPath {
        let p = CGMutablePath()
        guard let first = pts.first else { return p }
        p.move(to: CGPoint(x: first.x, y: first.y))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.x, y: q.y)) }
        return p
    }
}

struct Trial {
    let shape: Shape
    let strokes: [StrokeGeometry]
    let corridorPx: CGFloat
    let corridorUnits: CGFloat
    let totalLen: CGFloat
}

/// Build everything the game needs from a shape definition, in view points.
///
/// `corridorUnits` is the full corridor width in shape units, so 18 means the
/// gap between the two lines is 18% of the shape box.
func buildTrial(shape: Shape, corridorUnits: CGFloat, view: CGRect) -> Trial {
    let raw = shape.strokes.map { PathDSL.sample($0) }
    let box = boundingBox(raw)

    // Fit the shape plus half a corridor of breathing room into the view.
    let pad = corridorUnits / 2 + 3
    let scale = min(view.width / (box.width + pad * 2), view.height / (box.height + pad * 2))
    let ox = view.minX + (view.width - box.width * scale) / 2 - box.minX * scale
    let oy = view.minY + (view.height - box.height * scale) / 2 - box.minY * scale

    let corridorPx = corridorUnits * scale
    let strokes: [StrokeGeometry] = raw.map { pts in
        let screen = pts.map { Pt(x: $0.x * scale + ox, y: $0.y * scale + oy) }
        let len = polylineLength(screen)
        // One checkpoint about every third of a corridor width, clamped so short
        // strokes still get a usable number and long ones don't explode.
        let spacing = min(max(corridorPx * 0.34, 10), max(len / 12, 12))
        return StrokeGeometry(pts: screen, len: len, checkpoints: resample(screen, spacing: spacing))
    }

    return Trial(
        shape: shape,
        strokes: strokes,
        corridorPx: corridorPx,
        corridorUnits: corridorUnits,
        totalLen: strokes.reduce(0) { $0 + $1.len })
}

// MARK: - Corridor mask

/// The corridor rasterised once into a byte grid, so asking "is this point
/// inside the lines?" costs one array lookup instead of a distance-to-path scan
/// on every pencil sample — and the pencil delivers a lot of samples.
final class CorridorMask {
    let width: Int
    let height: Int
    private let grid: [UInt8]

    init?(trial: Trial, size: CGSize) {
        width = max(1, Int(size.width.rounded()))
        height = max(1, Int(size.height.rounded()))
        let bytes = width * height
        guard
            let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }

        // Flip so the mask shares the view's top-left origin.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setLineWidth(trial.corridorPx)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for st in trial.strokes {
            ctx.addPath(st.cgPath)
            ctx.strokePath()
        }

        guard let data = ctx.data else { return nil }
        let buf = data.bindMemory(to: UInt8.self, capacity: bytes)
        var g = [UInt8](repeating: 0, count: bytes)
        for i in 0..<bytes { g[i] = buf[i] > 120 ? 1 : 0 }
        grid = g
    }

    @inline(__always) func contains(_ x: CGFloat, _ y: CGFloat) -> Bool {
        let ix = Int(x), iy = Int(y)
        guard ix >= 0, iy >= 0, ix < width, iy < height else { return false }
        return grid[iy * width + ix] == 1
    }
}
