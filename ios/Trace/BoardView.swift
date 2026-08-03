import UIKit

// The tracing surface: draws the corridor, takes pencil/finger input, tracks how
// much of the path got covered and how far outside the lines the child strayed.
//
// Latency is the whole point of this being native. Nothing here redraws the
// screen on a timer:
//
//  * the corridor is rendered once per trial into an image and parked on a layer
//  * committed ink lives in a bitmap that's only re-uploaded when a stroke ends
//  * the stroke in progress is a CAShapeLayer path, rasterised by the GPU
//  * predicted touches are drawn ahead of the pencil and thrown away next batch
//  * the demo dot and the pulsing start markers are Core Animation, not code
//
// So the per-touch work is: hit-test against a byte grid, mark checkpoints,
// append to a path. That's what keeps up with a 120 Hz Pencil.

struct Judgement {
    enum Reason: String { case win, outside, almost, unfinished, scribble }
    var win: Bool
    var reason: Reason
    var coverage: CGFloat
    var meanCoverage: CGFloat
    var leakRatio: CGFloat
}

private enum Ink {
    static let track = UIColor(red: 0.992, green: 0.984, blue: 0.953, alpha: 1)
    static let edge = UIColor(red: 0.576, green: 0.682, blue: 0.878, alpha: 1)
    static let inside = UIColor(red: 0.169, green: 0.184, blue: 0.478, alpha: 1)
    static let outside = UIColor(red: 0.898, green: 0.282, blue: 0.302, alpha: 1)
    static let start = UIColor(red: 0.086, green: 0.639, blue: 0.290, alpha: 1)
    static let demo = UIColor(red: 0.976, green: 0.451, blue: 0.086, alpha: 1)
    static let skyTop = UIColor(red: 0.086, green: 0.102, blue: 0.239, alpha: 1)
    static let skyBottom = UIColor(red: 0.051, green: 0.063, blue: 0.188, alpha: 1)
}

// A trial is won when every stroke is essentially covered and the total amount
// of drawing outside the corridor stays under a small allowance. The allowance
// has an absolute floor as well as a proportional part, so a small shape isn't
// unfairly strict about a single wobble at a corner.
private let coverageToWin: CGFloat = 0.9
private let leakFraction: CGFloat = 0.07
private let leakFloorCorridors: CGFloat = 0.9
private let scribbleLimit: CGFloat = 2.6

final class BoardView: UIView {

    // MARK: Callbacks
    var onFirstTouch: (() -> Void)?
    var onStrokeEnd: (() -> Void)?
    var onLeave: (() -> Void)?

    // MARK: State
    private(set) var trial: Trial?
    private var corridorMask: CorridorMask?
    private var covered: [[Bool]] = []
    private(set) var insideLen: CGFloat = 0
    private(set) var outsideLen: CGFloat = 0
    private(set) var drawnLen: CGFloat = 0
    private(set) var isDrawing = false

    private var penSeen = false
    private var activeTouch: UITouch?
    private var lastPoint: CGPoint?
    private var lastInside = true
    var frozen = false

    // MARK: Layers
    private let corridorLayer = CALayer()
    private let bakedInkLayer = CALayer()
    private let liveInLayer = CAShapeLayer()
    private let liveOutLayer = CAShapeLayer()
    private let predictLayer = CAShapeLayer()
    private let trailLayer = CAShapeLayer()
    private let demoDotLayer = CALayer()
    private var markerLayers: [CALayer] = []

    private var liveIn = CGMutablePath()
    private var liveOut = CGMutablePath()
    private var livePointCount = 0

    private var inkCtx: CGContext?
    private var demoTask: Task<Bool, Never>?

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = UIColor(red: 0.051, green: 0.063, blue: 0.188, alpha: 1)
        isMultipleTouchEnabled = false
        isExclusiveTouch = true

        for l in [corridorLayer, bakedInkLayer] {
            l.contentsGravity = .resize
            layer.addSublayer(l)
        }
        for l in [liveOutLayer, liveInLayer, predictLayer, trailLayer] {
            l.fillColor = nil
            l.lineCap = .round
            l.lineJoin = .round
            layer.addSublayer(l)
        }
        liveInLayer.strokeColor = Ink.inside.cgColor
        predictLayer.strokeColor = Ink.inside.cgColor
        liveOutLayer.strokeColor = Ink.outside.cgColor
        trailLayer.strokeColor = Ink.demo.withAlphaComponent(0.45).cgColor

        demoDotLayer.isHidden = true
        layer.addSublayer(demoDotLayer)
        trailLayer.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for l in [corridorLayer, bakedInkLayer, liveInLayer, liveOutLayer, predictLayer, trailLayer] {
            l.frame = bounds
            l.contentsScale = window?.screen.scale ?? 2
        }
        if let t = trial, inkCtx == nil || CGFloat(inkCtx!.width) != bounds.width * contentScaleFactor {
            setTrial(shape: t.shape, corridorUnits: t.corridorUnits)
        }
    }

    private var boardRect: CGRect {
        let m = min(bounds.width, bounds.height) * 0.06
        let size = min(bounds.width - m * 2, bounds.height - m * 2)
        return CGRect(
            x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size)
    }

    // MARK: - Trial setup

    func setTrial(shape: Shape, corridorUnits: CGFloat) {
        guard bounds.width > 40, bounds.height > 40 else { return }
        stopDemo()

        let t = buildTrial(shape: shape, corridorUnits: corridorUnits, view: boardRect)
        trial = t
        corridorMask = CorridorMask(trial: t, size: bounds.size)
        covered = t.strokes.map { [Bool](repeating: false, count: $0.checkpoints.count) }
        insideLen = 0
        outsideLen = 0
        drawnLen = 0
        isDrawing = false
        activeTouch = nil
        lastPoint = nil
        lastInside = true
        frozen = false

        let lw = min(26, max(7, t.corridorPx * 0.3))
        for l in [liveInLayer, liveOutLayer, predictLayer] { l.lineWidth = lw }
        trailLayer.lineWidth = t.corridorPx * 0.42

        makeInkContext()
        clearLivePaths()
        corridorLayer.contents = renderCorridor(t)?.cgImage
        buildMarkers(t)
    }

    func clearInk() {
        guard let t = trial else { return }
        covered = t.strokes.map { [Bool](repeating: false, count: $0.checkpoints.count) }
        insideLen = 0
        outsideLen = 0
        drawnLen = 0
        lastPoint = nil
        makeInkContext()
        bakedInkLayer.contents = nil
        clearLivePaths()
        refreshMarkers()
    }

    private func makeInkContext() {
        let scale = contentScaleFactor
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard w > 0, h > 0,
            let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        // Draw in UIKit coordinates (origin top-left).
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        inkCtx = ctx
    }

    private func clearLivePaths() {
        liveIn = CGMutablePath()
        liveOut = CGMutablePath()
        livePointCount = 0
        liveInLayer.path = nil
        liveOutLayer.path = nil
        predictLayer.path = nil
    }

    // MARK: - Corridor rendering

    private func renderCorridor(_ t: Trial) -> UIImage? {
        let r = UIGraphicsImageRenderer(bounds: bounds)
        return r.image { c in
            let ctx = c.cgContext

            // Night-sky backdrop. Blacking out everything that isn't the shape
            // makes the corridor unmistakable, which is the whole point.
            let colors = [Ink.skyTop.cgColor, Ink.skyBottom.cgColor] as CFArray
            if let g = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
            {
                ctx.drawLinearGradient(
                    g, start: .zero, end: CGPoint(x: 0, y: bounds.height), options: [])
            }

            // Deterministic star field, so repaints don't shimmer.
            ctx.setFillColor(UIColor(white: 1, alpha: 0.35).cgColor)
            for i in 0..<70 {
                let x = CGFloat((i &* 9301 &+ 49297) % 233_280) / 233_280 * bounds.width
                let y = CGFloat((i &* 4931 &+ 7919) % 65521) / 65521 * bounds.height
                let rad = CGFloat((i % 3) + 1) * 0.6
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: rad, height: rad))
            }

            func strokeAll(_ width: CGFloat, _ color: UIColor) {
                ctx.setStrokeColor(color.cgColor)
                ctx.setLineWidth(width)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                for st in t.strokes {
                    ctx.addPath(st.cgPath)
                    ctx.strokePath()
                }
            }

            let w = t.corridorPx

            // A soft halo lifts the track off the background.
            ctx.saveGState()
            ctx.setShadow(
                offset: .zero, blur: 26,
                color: UIColor(red: 0.486, green: 0.839, blue: 1, alpha: 0.55).cgColor)
            strokeAll(w + 12, UIColor(red: 0.486, green: 0.839, blue: 1, alpha: 0.16))
            ctx.restoreGState()

            // Laying a wider band down first and then the track on top leaves a
            // strip of band showing either side — those strips are the two lines
            // the child has to stay between.
            strokeAll(w + 11, Ink.edge)
            strokeAll(w, Ink.track)

            // Faint dashed guide down the middle of the track.
            ctx.saveGState()
            ctx.setLineDash(phase: 0, lengths: [5, 16])
            ctx.setLineWidth(2)
            ctx.setStrokeColor(UIColor(red: 0.47, green: 0.52, blue: 0.75, alpha: 0.5).cgColor)
            for st in t.strokes {
                ctx.addPath(st.cgPath)
                ctx.strokePath()
            }
            ctx.restoreGState()
        }
    }

    // MARK: - Start markers

    private func buildMarkers(_ t: Trial) {
        markerLayers.forEach { $0.removeFromSuperlayer() }
        markerLayers = []

        for st in t.strokes {
            guard let p = st.pts.first else { continue }
            let q = st.pts[min(st.pts.count - 1, 14)]
            let r = max(11, t.corridorPx * 0.26)

            let group = CALayer()
            group.frame = CGRect(x: p.x - r * 3, y: p.y - r * 3, width: r * 6, height: r * 6)
            let mid = CGPoint(x: r * 3, y: r * 3)

            let ring = CAShapeLayer()
            ring.path = CGPath(
                ellipseIn: CGRect(x: mid.x - r - 8, y: mid.y - r - 8, width: (r + 8) * 2, height: (r + 8) * 2),
                transform: nil)
            ring.fillColor = nil
            ring.strokeColor = Ink.start.cgColor
            ring.lineWidth = 3
            ring.opacity = 0.5
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.88
            pulse.toValue = 1.22
            pulse.duration = 0.85
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            ring.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            ring.frame = group.bounds
            ring.add(pulse, forKey: "pulse")
            group.addSublayer(ring)

            let dot = CAShapeLayer()
            dot.path = CGPath(
                ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: r * 2, height: r * 2),
                transform: nil)
            dot.fillColor = Ink.start.cgColor
            group.addSublayer(dot)

            // Arrow pointing the way the stroke travels. The rotation is baked
            // into the path rather than applied as a layer transform: the points
            // are placed directly along the stroke's own direction vector, so
            // there's no anchor-point or coordinate-flip subtlety to get wrong.
            let dx = q.x - p.x, dy = q.y - p.y
            let len = max(hypot(dx, dy), 0.0001)
            let ax = dx / len, ay = dy / len  // along the stroke
            let bx = -ay, by = ax  // across it
            func corner(along: CGFloat, across: CGFloat) -> CGPoint {
                CGPoint(x: mid.x + ax * along + bx * across, y: mid.y + ay * along + by * across)
            }

            // Clearly longer than it is wide — at near-equilateral proportions
            // it's genuinely ambiguous which vertex is the point.
            let arrow = CAShapeLayer()
            let tri = CGMutablePath()
            tri.move(to: corner(along: r * 0.78, across: 0))
            tri.addLine(to: corner(along: -r * 0.46, across: -r * 0.40))
            tri.addLine(to: corner(along: -r * 0.20, across: 0))
            tri.addLine(to: corner(along: -r * 0.46, across: r * 0.40))
            tri.closeSubpath()
            arrow.path = tri
            arrow.fillColor = Ink.track.cgColor
            arrow.frame = group.bounds
            group.addSublayer(arrow)

            layer.addSublayer(group)
            markerLayers.append(group)
        }
        refreshMarkers()
    }

    /// Hide a stroke's start marker once they've begun tracing that stroke.
    private func refreshMarkers() {
        for (i, l) in markerLayers.enumerated() {
            l.isHidden = strokeCoverage(i) > 0.15
        }
    }

    // MARK: - Demo

    /// Animate a dot along each stroke in teaching order. Returns false if the
    /// child cut it short by starting to draw.
    @discardableResult
    func runDemo(onStroke: @escaping (Int, Int) -> Void) async -> Bool {
        guard let t = trial else { return false }
        stopDemo()

        let task = Task { () -> Bool in
            for (i, st) in t.strokes.enumerated() {
                if Task.isCancelled { return false }
                onStroke(i, t.strokes.count)
                // Slow enough for a 4-year-old to follow, never a slog.
                let dur = min(4.2, max(1.9, Double(st.len) * 0.0055))
                animateDemoStroke(st, duration: dur)
                do {
                    try await Task.sleep(nanoseconds: UInt64((dur + 0.55) * 1_000_000_000))
                } catch {
                    return false
                }
            }
            if Task.isCancelled { return false }
            hideDemo()
            return true
        }
        demoTask = task
        let finished = await task.value
        demoTask = nil
        return finished
    }

    func stopDemo() {
        demoTask?.cancel()
        demoTask = nil
        hideDemo()
    }

    private func hideDemo() {
        trailLayer.removeAllAnimations()
        demoDotLayer.removeAllAnimations()
        trailLayer.isHidden = true
        demoDotLayer.isHidden = true
        trailLayer.path = nil
    }

    private func animateDemoStroke(_ st: StrokeGeometry, duration: Double) {
        guard let t = trial, let first = st.pts.first else { return }
        let path = st.cgPath

        trailLayer.path = path
        trailLayer.isHidden = false
        trailLayer.strokeStart = 1
        trailLayer.strokeEnd = 1

        let end = CABasicAnimation(keyPath: "strokeEnd")
        end.fromValue = 0
        end.toValue = 1
        end.duration = duration

        // The tail lags the head by a fifth of the stroke, so it reads as a
        // comet rather than the whole path filling in.
        let start = CABasicAnimation(keyPath: "strokeStart")
        start.fromValue = 0
        start.toValue = 1
        start.beginTime = duration * 0.2
        start.duration = duration * 0.8

        let group = CAAnimationGroup()
        group.animations = [end, start]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        trailLayer.add(group, forKey: "comet")

        let r = max(13, t.corridorPx * 0.3)
        demoDotLayer.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
        demoDotLayer.cornerRadius = r
        demoDotLayer.backgroundColor = Ink.demo.cgColor
        demoDotLayer.shadowColor = Ink.demo.cgColor
        demoDotLayer.shadowOpacity = 0.9
        demoDotLayer.shadowRadius = 12
        demoDotLayer.shadowOffset = .zero
        demoDotLayer.position = CGPoint(x: first.x, y: first.y)
        demoDotLayer.isHidden = false

        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.duration = duration
        move.calculationMode = .paced
        move.fillMode = .forwards
        move.isRemovedOnCompletion = false
        demoDotLayer.add(move, forKey: "travel")
    }

    // MARK: - Touch input

    /// Palm rejection: once we've seen an Apple Pencil, ignore finger contacts.
    /// A resting hand otherwise draws wild lines all over the shape.
    private func accepts(_ touch: UITouch) -> Bool {
        if frozen || trial == nil { return false }
        if touch.type == .pencil {
            penSeen = true
            return true
        }
        return !penSeen
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first(where: accepts) else { return }
        stopDemo()
        activeTouch = touch
        isDrawing = true
        let p = touch.preciseLocation(in: self)
        lastPoint = p
        lastInside = corridorMask?.contains(p.x, p.y) ?? false
        liveIn.move(to: p)
        liveOut.move(to: p)
        markCoverage(p)
        refreshMarkers()
        onFirstTouch?()
        onFirstTouch = nil
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }

        // Coalesced touches give the Pencil's full sample rate rather than one
        // point per frame — this is most of the difference in how the line feels.
        for t in event?.coalescedTouches(for: touch) ?? [touch] {
            extend(to: t.preciseLocation(in: self))
        }
        commitLive()

        // Predicted touches draw slightly ahead of where the pencil actually is,
        // which hides most of the remaining latency. They're never committed and
        // never counted — the next batch replaces them.
        if let predicted = event?.predictedTouches(for: touch), !predicted.isEmpty,
            let from = lastPoint
        {
            let p = CGMutablePath()
            p.move(to: from)
            for t in predicted { p.addLine(to: t.preciseLocation(in: self)) }
            predictLayer.path = p
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { endStroke(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { endStroke(touches) }

    private func endStroke(_ touches: Set<UITouch>) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        isDrawing = false
        lastPoint = nil
        predictLayer.path = nil
        bakeLive()
        refreshMarkers()
        onStrokeEnd?()
    }

    private func extend(to p: CGPoint) {
        guard let t = trial, let a = lastPoint else {
            lastPoint = p
            return
        }
        let seg = hypot(p.x - a.x, p.y - a.y)
        if seg < 0.7 { return }

        // Walk the segment in small steps so a fast flick can't tunnel across
        // the corridor wall without being counted as an excursion.
        let steps = max(1, Int(ceil(seg / 3)))
        var prev = a
        for s in 1...steps {
            let f = CGFloat(s) / CGFloat(steps)
            let q = CGPoint(x: a.x + (p.x - a.x) * f, y: a.y + (p.y - a.y) * f)
            let inside = corridorMask?.contains(q.x, q.y) ?? false
            let d = hypot(q.x - prev.x, q.y - prev.y)

            drawnLen += d
            if inside {
                insideLen += d
                markCoverage(q)
            } else {
                outsideLen += d
            }

            if inside {
                liveIn.move(to: prev)
                liveIn.addLine(to: q)
            } else {
                liveOut.move(to: prev)
                liveOut.addLine(to: q)
            }
            livePointCount += 1

            if lastInside && !inside { onLeave?() }
            lastInside = inside
            prev = q
        }
        lastPoint = p
        _ = t
    }

    private func commitLive() {
        liveInLayer.path = liveIn
        liveOutLayer.path = liveOut
        // A path that grows without bound gets slower to rasterise every frame,
        // so fold it into the bitmap periodically and start a fresh one.
        if livePointCount > 400 { bakeLive() }
    }

    /// Fold the live stroke into the committed bitmap and reset the live paths.
    private func bakeLive() {
        guard let ctx = inkCtx, livePointCount > 0 else { return }
        let lw = min(26, max(7, (trial?.corridorPx ?? 30) * 0.3))
        ctx.setLineWidth(lw)
        ctx.setStrokeColor(Ink.inside.cgColor)
        ctx.addPath(liveIn)
        ctx.strokePath()
        ctx.setStrokeColor(Ink.outside.cgColor)
        ctx.addPath(liveOut)
        ctx.strokePath()

        bakedInkLayer.contents = ctx.makeImage()
        clearLivePaths()
    }

    // MARK: - Coverage and judging

    /// Any checkpoint near an in-corridor sample counts as traced.
    private func markCoverage(_ p: CGPoint) {
        guard let t = trial else { return }
        let reach = max(t.corridorPx * 0.62, 16)
        let reach2 = reach * reach
        for s in 0..<t.strokes.count {
            let cps = t.strokes[s].checkpoints
            for i in 0..<cps.count where !covered[s][i] {
                let dx = cps[i].x - p.x, dy = cps[i].y - p.y
                if dx * dx + dy * dy <= reach2 { covered[s][i] = true }
            }
        }
    }

    private func strokeCoverage(_ i: Int) -> CGFloat {
        guard i < covered.count, !covered[i].isEmpty else { return 0 }
        return CGFloat(covered[i].filter { $0 }.count) / CGFloat(covered[i].count)
    }

    func coverage() -> (per: [CGFloat], min: CGFloat, mean: CGFloat) {
        guard let t = trial, !t.strokes.isEmpty else { return ([0], 0, 0) }
        let per = (0..<t.strokes.count).map { strokeCoverage($0) }
        return (per, per.min() ?? 0, per.reduce(0, +) / CGFloat(per.count))
    }

    /// True once every stroke is covered — used to judge the moment they lift.
    func looksFinished() -> Bool { coverage().min >= coverageToWin }

    func judge() -> Judgement {
        guard let t = trial else {
            return Judgement(win: false, reason: .unfinished, coverage: 0, meanCoverage: 0, leakRatio: 0)
        }
        let cov = coverage()
        let allowance = max(t.totalLen * leakFraction, t.corridorPx * leakFloorCorridors)
        let leaked = outsideLen > allowance
        let scribbled = drawnLen > t.totalLen * scribbleLimit
        let incomplete = cov.min < coverageToWin

        // Order matters: straying outside is the most useful thing to coach on,
        // so it wins over "you didn't finish" even when the stray is what cut
        // the coverage short.
        var reason: Judgement.Reason = .win
        if scribbled {
            reason = .scribble
        } else if leaked {
            reason = .outside
        } else if incomplete && cov.mean < 0.55 {
            reason = .unfinished
        } else if incomplete {
            reason = .almost
        }

        return Judgement(
            win: reason == .win, reason: reason, coverage: cov.min, meanCoverage: cov.mean,
            leakRatio: t.totalLen > 0 ? outsideLen / t.totalLen : 0)
    }

    /// Every checkpoint, for the celebration sparkle trail.
    func allCheckpoints() -> [CGPoint] {
        (trial?.strokes.flatMap { $0.checkpoints } ?? []).map { CGPoint(x: $0.x, y: $0.y) }
    }

    var boardCentre: CGPoint { CGPoint(x: boardRect.midX, y: boardRect.midY) }

    func freeze(_ on: Bool) {
        frozen = on
        if on {
            isDrawing = false
            activeTouch = nil
            lastPoint = nil
        }
    }

    #if DEBUG
    /// Test hook: drive a synthetic stroke along the current shape, since the
    /// simulator can't be sent real pencil input. This runs the same machinery
    /// a real touch does — hit-testing, coverage, leak accounting and judging.
    ///
    /// - Parameters:
    ///   - wobble: perpendicular wander, as a fraction of corridor width
    ///   - offset: constant perpendicular bias, as a fraction of corridor width
    ///   - skipEnd: fraction of each stroke left untraced
    func simulateTrace(wobble: CGFloat = 0, offset: CGFloat = 0, skipEnd: CGFloat = 0) {
        guard let t = trial else { return }
        let w = t.corridorPx
        for st in t.strokes {
            let pts = st.pts
            let stop = max(2, Int(CGFloat(pts.count) * (1 - skipEnd)))
            for i in 0..<stop {
                let p = pts[i]
                let q = pts[min(pts.count - 1, i + 1)]
                let nx = -(q.y - p.y), ny = q.x - p.x
                let nl = max(hypot(nx, ny), 0.0001)
                let amp = offset * w + (wobble == 0 ? 0 : sin(CGFloat(i) / 6) * w * wobble)
                let pt = CGPoint(x: p.x + (nx / nl) * amp, y: p.y + (ny / nl) * amp)
                if i == 0 {
                    lastPoint = pt
                    lastInside = corridorMask?.contains(pt.x, pt.y) ?? false
                    liveIn.move(to: pt)
                    liveOut.move(to: pt)
                    markCoverage(pt)
                } else {
                    extend(to: pt)
                    // Mirror what touchesMoved does, so this exercises the
                    // display path and not just the judging.
                    if i % 12 == 0 { commitLive() }
                }
            }
            commitLive()
            bakeLive()
            lastPoint = nil
            onStrokeEnd?()
        }
    }
    #endif
}

private func CGColorSpaceDeviceRGB() -> CGColorSpace { CGColorSpaceCreateDeviceRGB() }

