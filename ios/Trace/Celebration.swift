import UIKit

// Two tiers of celebration.
//
// Small ones fire on every win and vary a little so they don't go stale. Big
// ones fire about one win in four, and each is a *combination* of the small
// effects — the point is that it visibly escalates, not that it's merely
// different. Each big one carries its own line, so the words always describe
// what's actually on screen.
//
// All Core Animation, so none of it competes with the pencil for CPU.

private let partyColors: [UIColor] = [
    UIColor(red: 1.00, green: 0.36, blue: 0.56, alpha: 1),
    UIColor(red: 1.00, green: 0.82, blue: 0.40, alpha: 1),
    UIColor(red: 0.02, green: 0.84, blue: 0.63, alpha: 1),
    UIColor(red: 0.30, green: 0.79, blue: 0.94, alpha: 1),
    UIColor(red: 0.72, green: 0.57, blue: 1.00, alpha: 1),
    UIColor(red: 1.00, green: 0.57, blue: 0.30, alpha: 1),
    UIColor(red: 0.98, green: 0.97, blue: 0.44, alpha: 1),
]

/// The big ones. Praise names the effort, not the child — she can control how
/// hard she tries, and that's what we want her repeating.
enum BigCelebration: CaseIterable {
    case balloonBubbleConfetti
    case sillyFoam
    case fireworks
    case ribbons
    case bubbleStorm

    var line: String {
        switch self {
        case .balloonBubbleConfetti:
            return "Oh wow! That was sooooo awesome. You get balloons, filled with bubbles, filled with confetti!"
        case .sillyFoam:
            return "Great work! You're working so hard, you got super silly foam."
        case .fireworks:
            return "Look how steady your hand is getting! That earned fireworks."
        case .ribbons:
            return "You kept going and it's paying off. Ribbons everywhere!"
        case .bubbleStorm:
            return "Your careful tracing is really working. Here comes a bubble storm!"
        }
    }

    var duration: Double {
        switch self {
        case .balloonBubbleConfetti: return 3.4
        case .sillyFoam: return 2.8
        case .fireworks: return 2.6
        case .ribbons: return 3.0
        case .bubbleStorm: return 2.8
        }
    }
}

final class CelebrationView: UIView {

    private var live: [CALayer] = []
    private var pending: [DispatchWorkItem] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    func clear() {
        pending.forEach { $0.cancel() }
        pending.removeAll()
        live.forEach { $0.removeAllAnimations(); $0.removeFromSuperlayer() }
        live.removeAll()
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    private func after(_ delay: Double, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        pending.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: Small wins

    /// Every win gets one of these. Cheap, quick, and varied enough not to blur
    /// into wallpaper.
    func small(at point: CGPoint) {
        switch Int.random(in: 0..<3) {
        case 0:
            ring(at: point)
            sparkles(at: point, count: 26)
        case 1:
            sparkles(at: point, count: 18)
            confettiPuff(at: point)
        default:
            ring(at: point)
            starPop(at: point)
        }
    }

    /// Sparkles running along the shape she just finished.
    func traceGlow(_ points: [CGPoint]) {
        guard !points.isEmpty else { return }
        let step = max(1, points.count / 24)
        for i in stride(from: 0, to: points.count, by: step) {
            sparkles(at: points[i], count: 1)
        }
    }

    // MARK: Big wins

    func big(_ kind: BigCelebration) {
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        switch kind {
        case .balloonBubbleConfetti:
            // Balloons go up, and as they reach the top they burst into bubbles
            // and then confetti — the escalation is the whole idea.
            balloons(count: 9)
            after(1.1) { self.bubbles(count: 26, from: 0.55) }
            after(2.0) { self.confetti() }
            ring(at: centre)
        case .sillyFoam:
            foam()
            after(0.8) { self.bubbles(count: 18, from: 0.9) }
        case .fireworks:
            for i in 0..<5 {
                let p = CGPoint(
                    x: bounds.width * CGFloat.random(in: 0.2...0.8),
                    y: bounds.height * CGFloat.random(in: 0.2...0.55))
                after(Double(i) * 0.28) {
                    self.ring(at: p)
                    self.sparkles(at: p, count: 34)
                }
            }
        case .ribbons:
            ribbons()
            after(0.7) { self.sparkles(at: centre, count: 30) }
        case .bubbleStorm:
            bubbles(count: 44, from: 1.0)
            after(0.9) { self.sparkles(at: centre, count: 24) }
            ring(at: centre)
        }
    }

    // MARK: Unlocks

    /// Paint thrown at the screen a few times until it's entirely the new
    /// colour, then wiped away. The splats deliberately overlap and grow, so the
    /// last one is what finally covers everything — it reads as the colour
    /// arriving rather than a slideshow of blobs.
    func paintSplatter(color: UIColor, then done: @escaping () -> Void) {
        let splats = 6
        let spread: [CGPoint] = [
            CGPoint(x: 0.30, y: 0.35), CGPoint(x: 0.72, y: 0.28),
            CGPoint(x: 0.22, y: 0.70), CGPoint(x: 0.78, y: 0.68),
            CGPoint(x: 0.50, y: 0.48), CGPoint(x: 0.50, y: 0.50),
        ]

        for i in 0..<splats {
            let at = CGPoint(
                x: bounds.width * spread[i].x, y: bounds.height * spread[i].y)
            // Each throw is bigger than the last; the final one is oversized so
            // it fills whatever the others missed.
            let reach = max(bounds.width, bounds.height)
            let size = reach * (i == splats - 1 ? 2.6 : 0.55 + CGFloat(i) * 0.22)

            after(Double(i) * 0.26) {
                let l = CALayer()
                l.contents = Self.splatImage.cgImage
                l.bounds = CGRect(x: 0, y: 0, width: size, height: size)
                l.position = at
                l.backgroundColor = UIColor.clear.cgColor
                // Tint the greyscale splat with the pen's colour.
                l.compositingFilter = nil
                let tint = CALayer()
                tint.frame = l.bounds
                tint.backgroundColor = color.cgColor
                tint.mask = {
                    let m = CALayer()
                    m.frame = l.bounds
                    m.contents = Self.splatImage.cgImage
                    return m
                }()
                l.addSublayer(tint)
                l.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(i) * 1.1))
                self.layer.addSublayer(l)
                self.live.append(l)

                let pop = CABasicAnimation(keyPath: "transform.scale")
                pop.fromValue = 0.05
                pop.toValue = 1.0
                pop.duration = 0.34
                pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
                pop.fillMode = .forwards
                pop.isRemovedOnCompletion = false
                l.add(pop, forKey: "splat")
                self.sfxTick?()
            }
        }

        // Hold the full colour for a beat, then clear so the game reappears.
        after(Double(splats) * 0.26 + 0.9) {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.45
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            self.live.forEach { $0.add(fade, forKey: "wipe") }
            self.after(0.5) {
                self.clear()
                done()
            }
        }
    }

    /// The fine point pen draws itself in: a symmetrical burst of thin strokes,
    /// because the thing being rewarded here is precision, not exuberance.
    func drawnLines(color: UIColor, then done: @escaping () -> Void) {
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let reach = max(bounds.width, bounds.height) * 0.62
        let spokes = 24

        let path = CGMutablePath()
        for i in 0..<spokes {
            let a = CGFloat(i) / CGFloat(spokes) * .pi * 2
            path.move(to: centre)
            path.addLine(to: CGPoint(x: centre.x + cos(a) * reach, y: centre.y + sin(a) * reach))
        }
        for ring in 1...4 {
            let r = reach * CGFloat(ring) / 4.6
            path.addEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
        }

        let l = CAShapeLayer()
        l.path = path
        l.fillColor = nil
        l.strokeColor = UIColor(white: 0.95, alpha: 0.9).cgColor
        l.lineWidth = 2  // thin, to show off what the pen is for
        l.lineCap = .round
        layer.addSublayer(l)
        live.append(l)

        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 1.5
        draw.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        draw.fillMode = .forwards
        draw.isRemovedOnCompletion = false
        l.add(draw, forKey: "draw")

        sparkles(at: centre, count: 24)
        after(2.1) {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.5
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            l.add(fade, forKey: "wipe")
            self.after(0.55) {
                self.clear()
                done()
            }
        }
    }

    /// Called as each splat lands, so the view doesn't need to own a synthesiser.
    var sfxTick: (() -> Void)?

    // MARK: Pieces

    private func ring(at p: CGPoint) {
        let l = CAShapeLayer()
        let r: CGFloat = 40
        l.path = CGPath(
            ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2), transform: nil)
        l.fillColor = nil
        l.strokeColor = UIColor(red: 1, green: 0.82, blue: 0.4, alpha: 1).cgColor
        l.lineWidth = 14
        l.opacity = 0
        layer.addSublayer(l)
        live.append(l)

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.2
        grow.toValue = 5.5
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.7
        fade.toValue = 0
        let thin = CABasicAnimation(keyPath: "lineWidth")
        thin.fromValue = 16
        thin.toValue = 2
        let g = CAAnimationGroup()
        g.animations = [grow, fade, thin]
        g.duration = 0.85
        g.isRemovedOnCompletion = false
        g.fillMode = .forwards
        l.add(g, forKey: "ring")
    }

    private func burst(
        at p: CGPoint, image: UIImage, cells: Int, configure: (CAEmitterCell) -> Void,
        window: Double = 0.03
    ) {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = p
        emitter.emitterShape = .point
        emitter.emitterMode = .outline
        emitter.beginTime = CACurrentMediaTime()

        let cell = CAEmitterCell()
        cell.contents = image.cgImage
        cell.birthRate = Float(cells) * 40
        cell.color = partyColors.randomElement()!.cgColor
        configure(cell)
        emitter.emitterCells = [cell]

        layer.addSublayer(emitter)
        live.append(emitter)
        after(window) { emitter.birthRate = 0 }
    }

    private func sparkles(at p: CGPoint, count: Int) {
        burst(at: p, image: Self.starImage, cells: count) { c in
            c.lifetime = 1.1
            c.lifetimeRange = 0.4
            c.velocity = 210
            c.velocityRange = 130
            c.emissionRange = .pi * 2
            c.yAcceleration = 220
            c.scale = 0.35
            c.scaleRange = 0.25
            c.scaleSpeed = -0.22
            c.alphaSpeed = -0.9
            c.spin = 3
            c.spinRange = 4
        }
    }

    private func starPop(at p: CGPoint) {
        burst(at: p, image: Self.starImage, cells: 14) { c in
            c.lifetime = 1.3
            c.velocity = 90
            c.velocityRange = 50
            c.emissionRange = .pi * 2
            c.yAcceleration = -40
            c.scale = 0.6
            c.scaleRange = 0.3
            c.scaleSpeed = -0.3
            c.alphaSpeed = -0.7
            c.spin = 2
        }
    }

    private func confettiPuff(at p: CGPoint) {
        burst(at: p, image: Self.confettiImage, cells: 16) { c in
            c.lifetime = 1.6
            c.velocity = 260
            c.velocityRange = 140
            c.emissionRange = .pi * 2
            c.yAcceleration = 520
            c.scale = 0.4
            c.scaleRange = 0.2
            c.spin = 5
            c.spinRange = 6
            c.alphaSpeed = -0.5
        }
    }

    private func confetti() {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.height * 0.35)
        emitter.emitterSize = CGSize(width: bounds.width * 0.8, height: 1)
        emitter.emitterShape = .line
        emitter.beginTime = CACurrentMediaTime()

        emitter.emitterCells = partyColors.map { color in
            let cell = CAEmitterCell()
            cell.contents = Self.confettiImage.cgImage
            cell.color = color.cgColor
            cell.birthRate = 700
            cell.lifetime = 3.4
            cell.velocity = 420
            cell.velocityRange = 240
            cell.emissionLongitude = -.pi / 2
            cell.emissionRange = .pi / 2.6
            cell.yAcceleration = 600
            cell.scale = 0.55
            cell.scaleRange = 0.3
            cell.spin = 5
            cell.spinRange = 7
            cell.alphaSpeed = -0.28
            return cell
        }
        layer.addSublayer(emitter)
        live.append(emitter)
        after(0.22) { emitter.birthRate = 0 }
    }

    /// Translucent bubbles drifting up. `from` is where they start, as a
    /// fraction of the screen height.
    private func bubbles(count: Int, from: CGFloat) {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.height * from)
        emitter.emitterSize = CGSize(width: bounds.width * 0.85, height: 1)
        emitter.emitterShape = .line
        emitter.beginTime = CACurrentMediaTime()

        let cell = CAEmitterCell()
        cell.contents = Self.bubbleImage.cgImage
        cell.birthRate = Float(count) * 12
        cell.lifetime = 3.2
        cell.lifetimeRange = 0.8
        cell.velocity = 190
        cell.velocityRange = 90
        cell.emissionLongitude = -.pi / 2
        cell.emissionRange = .pi / 7
        cell.yAcceleration = -30
        cell.xAcceleration = 12
        cell.scale = 0.5
        cell.scaleRange = 0.35
        cell.alphaSpeed = -0.22
        cell.color = UIColor.white.withAlphaComponent(0.9).cgColor
        emitter.emitterCells = [cell]

        layer.addSublayer(emitter)
        live.append(emitter)
        after(0.5) { emitter.birthRate = 0 }
    }

    /// Big soft blobs piling up from the bottom of the screen.
    private func foam() {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.height + 40)
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        emitter.emitterShape = .line
        emitter.beginTime = CACurrentMediaTime()

        emitter.emitterCells = partyColors.prefix(4).map { colour in
            let cell = CAEmitterCell()
            cell.contents = Self.blobImage.cgImage
            cell.color = colour.withAlphaComponent(0.75).cgColor
            cell.birthRate = 90
            cell.lifetime = 3.0
            cell.velocity = 300
            cell.velocityRange = 160
            cell.emissionLongitude = -.pi / 2
            cell.emissionRange = .pi / 4
            cell.yAcceleration = 90  // slows and settles, like foam piling up
            cell.scale = 1.0
            cell.scaleRange = 0.7
            cell.scaleSpeed = 0.25
            cell.alphaSpeed = -0.32
            cell.spin = 1.2
            cell.spinRange = 2
            return cell
        }
        layer.addSublayer(emitter)
        live.append(emitter)
        after(0.9) { emitter.birthRate = 0 }
    }

    /// Long streamers tumbling down.
    private func ribbons() {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: -40)
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        emitter.emitterShape = .line
        emitter.beginTime = CACurrentMediaTime()

        emitter.emitterCells = partyColors.map { colour in
            let cell = CAEmitterCell()
            cell.contents = Self.ribbonImage.cgImage
            cell.color = colour.cgColor
            cell.birthRate = 26
            cell.lifetime = 4.0
            cell.velocity = 150
            cell.velocityRange = 70
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = .pi / 10
            cell.yAcceleration = 120
            cell.scale = 0.8
            cell.scaleRange = 0.4
            cell.spin = 2.2
            cell.spinRange = 3
            cell.alphaSpeed = -0.2
            return cell
        }
        layer.addSublayer(emitter)
        live.append(emitter)
        after(1.4) { emitter.birthRate = 0 }
    }

    private func balloons(count: Int) {
        for i in 0..<count {
            let r = CGFloat.random(in: 30...48)
            let l = CALayer()
            l.contents = Self.balloonImage(color: partyColors[i % partyColors.count]).cgImage
            l.bounds = CGRect(x: 0, y: 0, width: r * 1.8, height: r * 2.9)
            let x = bounds.width * CGFloat.random(in: 0.08...0.92)
            l.position = CGPoint(x: x, y: bounds.height + r * 2 + CGFloat.random(in: 0...260))
            layer.addSublayer(l)
            live.append(l)

            let rise = CABasicAnimation(keyPath: "position.y")
            rise.fromValue = l.position.y
            rise.toValue = -r * 3
            rise.duration = Double.random(in: 2.6...3.8)
            rise.isRemovedOnCompletion = false
            rise.fillMode = .forwards

            // A little side-to-side so they don't look like they're on rails.
            let sway = CAKeyframeAnimation(keyPath: "position.x")
            sway.values = [x, x + 26, x - 22, x + 14, x]
            sway.duration = Double.random(in: 2.2...3.2)
            sway.repeatCount = .infinity

            l.add(rise, forKey: "rise")
            l.add(sway, forKey: "sway")
        }
    }

    // MARK: Particle textures, drawn once

    private static let starImage: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { c in
            let path = CGMutablePath()
            for i in 0..<8 {
                let r: CGFloat = i % 2 == 0 ? 13 : 5.5
                let a = CGFloat(i) / 8 * .pi * 2 - .pi / 2
                let p = CGPoint(x: 14 + cos(a) * r, y: 14 + sin(a) * r)
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            path.closeSubpath()
            c.cgContext.setFillColor(UIColor.white.cgColor)
            c.cgContext.addPath(path)
            c.cgContext.fillPath()
        }
    }()

    private static let confettiImage: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 16, height: 24)).image { c in
            c.cgContext.setFillColor(UIColor.white.cgColor)
            c.cgContext.fill(CGRect(x: 0, y: 0, width: 16, height: 24))
        }
    }()

    private static let ribbonImage: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 12, height: 64)).image { c in
            c.cgContext.setFillColor(UIColor.white.cgColor)
            c.cgContext.fill(CGRect(x: 0, y: 0, width: 12, height: 64))
        }
    }()

    /// An irregular paint splat: a lumpy centre plus a few flung droplets.
    private static let splatImage: UIImage = {
        let size = CGSize(width: 300, height: 300)
        return UIGraphicsImageRenderer(size: size).image { c in
            let ctx = c.cgContext
            ctx.setFillColor(UIColor.white.cgColor)
            let mid = CGPoint(x: 150, y: 150)

            // Lumpy body — radius wobbles around the circle.
            let path = CGMutablePath()
            let lobes = 13
            for i in 0...lobes {
                let a = CGFloat(i) / CGFloat(lobes) * .pi * 2
                let wobble = 1 + 0.26 * sin(a * 3.1) + 0.16 * cos(a * 5.7)
                let r = 96 * wobble
                let p = CGPoint(x: mid.x + cos(a) * r, y: mid.y + sin(a) * r)
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()

            // Droplets, deterministic so every splat isn't identical but none
            // depends on a random seed at draw time.
            let drops: [(CGFloat, CGFloat, CGFloat)] = [
                (0.4, 132, 15), (1.5, 120, 10), (2.4, 140, 18), (3.3, 126, 9),
                (4.1, 145, 13), (5.0, 118, 16), (5.8, 138, 11),
            ]
            for (angle, dist, r) in drops {
                ctx.fillEllipse(
                    in: CGRect(
                        x: mid.x + cos(angle) * dist - r, y: mid.y + sin(angle) * dist - r,
                        width: r * 2, height: r * 2))
            }
        }
    }()

    private static let blobImage: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 72, height: 72)).image { c in
            c.cgContext.setFillColor(UIColor.white.cgColor)
            c.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 72, height: 72))
        }
    }()

    private static let bubbleImage: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { c in
            let ctx = c.cgContext
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.95).cgColor)
            ctx.setLineWidth(4)
            ctx.strokeEllipse(in: CGRect(x: 4, y: 4, width: 56, height: 56))
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.18).cgColor)
            ctx.fillEllipse(in: CGRect(x: 4, y: 4, width: 56, height: 56))
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
            ctx.fillEllipse(in: CGRect(x: 17, y: 14, width: 12, height: 9))
        }
    }()

    private static func balloonImage(color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 90, height: 145)).image { c in
            let ctx = c.cgContext
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.5).cgColor)
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: 45, y: 96))
            ctx.addQuadCurve(to: CGPoint(x: 45, y: 143), control: CGPoint(x: 62, y: 120))
            ctx.strokePath()

            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: 6, y: 2, width: 78, height: 94))
            ctx.move(to: CGPoint(x: 38, y: 94))
            ctx.addLine(to: CGPoint(x: 52, y: 94))
            ctx.addLine(to: CGPoint(x: 45, y: 106))
            ctx.closePath()
            ctx.fillPath()

            ctx.setFillColor(UIColor(white: 1, alpha: 0.42).cgColor)
            ctx.fillEllipse(in: CGRect(x: 22, y: 18, width: 18, height: 26))
        }
    }
}
