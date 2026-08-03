import CoreGraphics
import Foundation

// The shape library, authored in a 0..100 box with y pointing down.
//
// `level` is the complexity band the adaptive engine draws from:
//   1  single straight strokes
//   2  simple closed shapes and gentle curves
//   3  corners, points, multi-segment shapes; easy letters/digits
//   4  most letters and digits, two-part shapes
//   5  fiddly letters, tight curves, three-part shapes, generated designs
//
// `name` is spoken aloud, so it has to be a word a four-year-old has.
//
// `maxWidth` caps the corridor for shapes with narrow channels or small
// enclosed holes. Widen a spiral past its turn spacing and the turns fuse into
// one white blob — no lines left to stay inside, and a scribble "wins".
// Corners round off harmlessly, so only shapes with stretches running close and
// parallel, or with small holes, need a cap.

struct Shape {
    enum Kind { case letterGlyph, digitGlyph, creative }

    let id: String
    let name: String
    let level: Int
    let strokes: [String]
    var kind: Kind? = nil
    var maxWidth: CGFloat? = nil
}

private func S(
    _ id: String, _ name: String, _ level: Int, _ strokes: [String],
    kind: Shape.Kind? = nil, maxWidth: CGFloat? = nil
) -> Shape {
    Shape(id: id, name: name, level: level, strokes: strokes, kind: kind, maxWidth: maxWidth)
}

enum ShapeLibrary {

    static let basics: [Shape] = [
        S("line-h", "straight line", 1, ["M 10 50 L 90 50"]),
        S("line-v", "down line", 1, ["M 50 8 L 50 92"]),
        S("line-diag", "slanty line", 1, ["M 12 88 L 88 12"]),
        S("hill", "hill", 1, ["M 8 78 Q 50 6 92 78"]),
        S("valley", "smile", 1, ["M 8 24 Q 50 94 92 24"]),

        S("circle", "circle", 2, ["E 50 50 40 40 -90 270"]),
        S("oval", "egg", 2, ["E 50 50 28 42 -90 270"]),
        S("square", "square", 2, ["M 14 14 L 86 14 L 86 86 L 14 86 L 14 14"]),
        S("rectangle", "rectangle", 2, ["M 8 24 L 92 24 L 92 76 L 8 76 L 8 24"]),
        S("wave", "wave", 2, ["M 6 50 Q 22 16 38 50 Q 54 84 70 50 Q 86 16 96 40"]),
        S("arch", "rainbow", 2, ["M 10 84 Q 10 14 50 14 Q 90 14 90 84"]),

        S("triangle", "triangle", 3, ["M 50 10 L 92 86 L 8 86 L 50 10"]),
        S("diamond", "diamond", 3, ["M 50 8 L 92 50 L 50 92 L 8 50 L 50 8"]),
        S("zigzag", "zigzag", 3, ["M 6 76 L 28 24 L 50 76 L 72 24 L 94 76"]),
        S("cross", "plus", 3, ["M 50 10 L 50 90", "M 10 50 L 90 50"]),
        S("staircase", "steps", 3, ["M 8 88 L 8 62 L 36 62 L 36 40 L 64 40 L 64 18 L 92 18"]),
        S(
            "teardrop", "raindrop", 3,
            ["M 50 8 Q 88 52 88 62 Q 88 92 50 92 Q 12 92 12 62 Q 12 52 50 8"], maxWidth: 22),

        S(
            "star", "star", 4,
            ["M 50 6 L 62 38 L 96 38 L 68 58 L 79 92 L 50 71 L 21 92 L 32 58 L 4 38 L 38 38 L 50 6"],
            maxWidth: 16),
        S(
            "heart", "heart", 4,
            ["M 50 92 C 4 58 10 18 32 18 C 44 18 50 30 50 34 C 50 30 56 18 68 18 C 90 18 96 58 50 92"]),
        S(
            "moon", "moon", 4, ["M 66 10 Q 22 26 22 52 Q 22 80 66 92 Q 34 66 34 50 Q 34 32 66 10"],
            maxWidth: 13),
        S("spiral", "swirl", 5, ["M 90 50 S 50 50 40 6 0 880"], maxWidth: 10),
        S(
            "flower", "flower", 5,
            [
                "M 50 50 Q 22 34 34 20 Q 46 6 50 28 Q 54 6 66 20 Q 78 34 50 50",
                "M 50 50 Q 78 66 66 80 Q 54 94 50 72 Q 46 94 34 80 Q 22 66 50 50",
            ], maxWidth: 15),
    ]

    // MARK: Digits — (level, strokes, maxWidth)

    static let digits: [Shape] = {
        let defs: [(String, Int, [String], CGFloat?)] = [
            ("0", 3, ["E 50 50 26 40 -90 270"], 26),
            ("1", 3, ["M 32 26 L 50 12 L 50 90"], nil),
            ("2", 4, ["M 26 28 Q 26 10 50 10 Q 74 10 74 32 Q 74 48 26 88 L 76 88"], 20),
            ("3", 5, ["M 28 22 Q 32 10 52 10 Q 74 10 74 28 Q 74 46 48 48 Q 76 50 76 70 Q 76 90 50 90 Q 30 90 26 78"], 20),
            ("4", 4, ["M 62 12 L 20 64 L 78 64", "M 62 12 L 62 90"], 20),
            ("5", 4, ["M 74 12 L 34 12 L 30 46 Q 52 38 64 47 Q 78 56 78 70 Q 78 90 50 90 Q 30 90 26 80"], 20),
            ("6", 5, ["M 66 14 Q 38 22 30 52 Q 26 70 34 82 Q 44 94 56 88 Q 72 80 70 64 Q 68 48 50 48 Q 36 48 31 60"], 20),
            ("7", 3, ["M 24 12 L 76 12 L 44 90"], nil),
            ("8", 5, ["E 50 30 20 22 -90 270", "E 50 70 24 20 -90 270"], 18),
            ("9", 5, ["M 34 86 Q 62 78 70 48 Q 74 30 66 18 Q 56 6 44 12 Q 28 20 30 36 Q 32 52 50 52 Q 64 52 69 40"], 20),
        ]
        return defs.map {
            S("digit-\($0.0)", "number \($0.0)", $0.1, $0.2, kind: .digitGlyph, maxWidth: $0.3)
        }
    }()

    // MARK: Uppercase letters — capitals first, that's what preschools teach

    static let letters: [Shape] = {
        let defs: [(String, Int, [String], CGFloat?)] = [
            ("A", 4, ["M 20 90 L 50 10 L 80 90", "M 32 62 L 68 62"], 20),
            ("B", 5, ["M 26 10 L 26 90", "M 26 10 Q 66 10 66 30 Q 66 50 26 50 Q 72 50 72 70 Q 72 90 26 90"], 17),
            ("C", 3, ["E 50 50 35 40 -62 -298"], nil),
            ("D", 4, ["M 28 10 L 28 90", "M 28 10 Q 76 10 76 50 Q 76 90 28 90"], 24),
            ("E", 4, ["M 72 12 L 28 12 L 28 88 L 72 88", "M 28 50 L 64 50"], nil),
            ("F", 4, ["M 72 12 L 28 12 L 28 90", "M 28 50 L 64 50"], nil),
            ("G", 5, ["E 50 50 35 40 -62 -298 L 85 50 L 60 50"], 20),
            ("H", 3, ["M 26 10 L 26 90", "M 74 10 L 74 90", "M 26 50 L 74 50"], nil),
            ("I", 3, ["M 50 12 L 50 88", "M 30 12 L 70 12", "M 30 88 L 70 88"], nil),
            ("J", 4, ["M 58 12 L 58 66 Q 58 90 38 90 Q 22 90 22 74"], nil),
            ("K", 4, ["M 28 10 L 28 90", "M 74 12 L 30 50", "M 30 50 L 74 90"], nil),
            ("L", 2, ["M 30 10 L 30 88 L 74 88"], nil),
            ("M", 4, ["M 22 90 L 22 12 L 50 56 L 78 12 L 78 90"], nil),
            ("N", 3, ["M 24 90 L 24 12 L 76 88 L 76 10"], nil),
            ("O", 2, ["E 50 50 36 40 -90 270"], 30),
            ("P", 4, ["M 28 10 L 28 90", "M 28 10 Q 72 10 72 32 Q 72 54 28 54"], 20),
            ("Q", 5, ["E 50 50 36 40 -90 270", "M 60 66 L 84 92"], 26),
            ("R", 5, ["M 28 10 L 28 90", "M 28 10 Q 72 10 72 32 Q 72 54 28 54 L 74 90"], 18),
            ("S", 5, ["M 72 24 Q 68 10 50 10 Q 28 10 28 28 Q 28 45 50 50 Q 74 55 74 72 Q 74 90 50 90 Q 31 90 28 78"], nil),
            ("T", 2, ["M 24 12 L 76 12", "M 50 12 L 50 90"], nil),
            ("U", 3, ["M 26 10 L 26 62 Q 26 90 50 90 Q 74 90 74 62 L 74 10"], nil),
            ("V", 3, ["M 24 10 L 50 90 L 76 10"], nil),
            ("W", 4, ["M 18 10 L 34 90 L 50 38 L 66 90 L 82 10"], nil),
            ("X", 3, ["M 26 10 L 74 90", "M 74 10 L 26 90"], nil),
            ("Y", 4, ["M 26 10 L 50 48 L 74 10", "M 50 48 L 50 90"], nil),
            ("Z", 3, ["M 26 12 L 74 12 L 26 88 L 74 88"], nil),
        ]
        return defs.map {
            S("letter-\($0.0)", "letter \($0.0)", $0.1, $0.2, kind: .letterGlyph, maxWidth: $0.3)
        }
    }()

    static let all: [Shape] = basics + digits + letters

    /// Every fixed shape at or below `level`, biased toward the top of the band.
    static func forLevel(_ level: Int) -> [Shape] {
        let at = all.filter { $0.level == level }
        let below = all.filter { $0.level == level - 1 }
        return at.count >= 4 ? at + below : all.filter { $0.level <= level }
    }

    static func byId(_ id: String) -> Shape? { all.first { $0.id == id } }
}

// MARK: - Creative shapes

/// Random designs stitched from primitive pieces. Each piece starts where the
/// last one ended, so the result is one continuous squiggle that has never
/// existed before — useful once the fixed library starts feeling familiar.
private let creativeNames = [
    "squiggle", "wiggly path", "roller coaster", "silly snake", "loop-de-loop",
    "mountain road", "twisty tail", "bumpy track", "zoomy line", "curly whirly",
]

/// Deterministic RNG so a design is reproducible from its integer seed.
struct Mulberry32 {
    private var a: UInt32
    init(seed: UInt32) { a = seed }

    mutating func next() -> CGFloat {
        a = a &+ 0x6D2B_79F5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ (t ^ (t >> 7)) &* (t | 61)
        return CGFloat((t ^ (t >> 14)) & 0xFFFF_FFFF) / CGFloat(UInt32.max)
    }

    mutating func range(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { lo + next() * (hi - lo) }
}

private func clampInside(_ p: Pt) -> Pt {
    Pt(x: min(92, max(8, p.x)), y: min(92, max(8, p.y)))
}

func makeCreativeShape(seed: UInt32, level: Int) -> Shape {
    var rng = Mulberry32(seed: seed)
    let pieces = level >= 5 ? 5 : 4
    var cur = clampInside(Pt(x: rng.range(10, 34), y: rng.range(20, 80)))
    var d = "M \(f(cur.x)) \(f(cur.y))"
    var tightestLoop = CGFloat.greatestFiniteMagnitude

    // Bias motion left-to-right so the design reads like handwriting.
    let stride = (76 - cur.x) / CGFloat(pieces)

    for _ in 0..<pieces {
        let next = clampInside(Pt(x: cur.x + stride * rng.range(0.7, 1.3), y: rng.range(14, 86)))
        let kind = rng.next()

        if kind < 0.3 {
            d += " L \(f(next.x)) \(f(next.y))"
        } else if kind < 0.62 {
            let ctrl = clampInside(
                Pt(
                    x: (cur.x + next.x) / 2 + rng.range(-18, 18),
                    y: (cur.y + next.y) / 2 + rng.range(-34, 34)))
            d += " Q \(f(ctrl.x)) \(f(ctrl.y)) \(f(next.x)) \(f(next.y))"
        } else if kind < 0.85 {
            let bumps = 2 + Int(rng.next() * 2)
            for b in 1...bumps {
                let t = CGFloat(b) / CGFloat(bumps)
                let p = clampInside(
                    Pt(
                        x: cur.x + (next.x - cur.x) * t,
                        y: cur.y + (next.y - cur.y) * t + (b % 2 == 1 ? -1 : 1) * rng.range(12, 24)))
                d += " L \(f(p.x)) \(f(p.y))"
            }
            d += " L \(f(next.x)) \(f(next.y))"
        } else {
            // A full loop. The circle has to be placed so its start angle lands
            // exactly on the current point, otherwise the path teleports and
            // the corridor gets a visible seam.
            let r = rng.range(9, 14)
            let above = cur.y - r >= 12 + r
            let below = cur.y + r <= 88 - r
            let inX = cur.x - r >= 6 && cur.x + r <= 94
            if inX && (above || below) {
                let cyy = above ? cur.y - r : cur.y + r
                let a0: CGFloat = above ? 90 : -90
                d += " S \(f(cur.x)) \(f(cyy)) \(f(r)) \(f(r)) \(f(a0)) \(f(a0 + 360))"
                tightestLoop = min(tightestLoop, r)
            }
            d += " L \(f(next.x)) \(f(next.y))"
        }
        cur = next
    }

    let name = creativeNames[Int(rng.next() * CGFloat(creativeNames.count)) % creativeNames.count]
    // A loop of radius r has a hole 2r across; the corridor has to stay
    // narrower than that or the hole fills in and the loop stops being a loop.
    let cap = tightestLoop == .greatestFiniteMagnitude ? nil : (tightestLoop * 1.3).rounded()
    return S("creative-\(seed)", name, level, [d], kind: .creative, maxWidth: cap)
}

private func f(_ v: CGFloat) -> String { String(format: "%.1f", v) }
