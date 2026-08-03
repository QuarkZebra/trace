import UIKit

// Two tiers of celebration: a sparkle-and-ring for every win, and an occasional
// big one — confetti, balloons, a starburst — so the big ones stay special.
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

final class CelebrationView: UIView {

    private var live: [CALayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    func clear() {
        live.forEach { $0.removeAllAnimations(); $0.removeFromSuperlayer() }
        live.removeAll()
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    // MARK: Small win

    func small(at point: CGPoint) {
        ring(at: point)
        sparkles(at: point, count: 26)
    }

    /// Sparkles running along the shape they just traced.
    func traceGlow(_ points: [CGPoint]) {
        guard !points.isEmpty else { return }
        let step = max(1, points.count / 26)
        for i in stride(from: 0, to: points.count, by: step) {
            sparkles(at: points[i], count: 1)
        }
    }

    // MARK: Big win

    func big() {
        confetti()
        balloons()
        ring(at: CGPoint(x: bounds.midX, y: bounds.midY))
        sparkles(at: CGPoint(x: bounds.midX, y: bounds.midY), count: 40)
    }

    // MARK: Pieces

    private func ring(at p: CGPoint) {
        let l = CAShapeLayer()
        let r: CGFloat = 40
        l.path = CGPath(
            ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2), transform: nil)
        l.fillColor = nil
        l.strokeColor = UIColor(red: 1, green: 0.82, blue: 0.4, alpha: 1).cgColor
        l.lineWidth = 14
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
        l.opacity = 0
        l.add(g, forKey: "ring")
    }

    private func sparkles(at p: CGPoint, count: Int) {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = p
        emitter.emitterShape = .point
        emitter.emitterMode = .outline
        emitter.renderMode = .additive
        emitter.beginTime = CACurrentMediaTime()

        let cell = CAEmitterCell()
        cell.contents = Self.starImage.cgImage
        cell.birthRate = Float(count) * 40
        cell.lifetime = 1.1
        cell.lifetimeRange = 0.4
        cell.velocity = 210
        cell.velocityRange = 130
        cell.emissionRange = .pi * 2
        cell.yAcceleration = 220
        cell.scale = 0.35
        cell.scaleRange = 0.25
        cell.scaleSpeed = -0.22
        cell.alphaSpeed = -0.9
        cell.spin = 3
        cell.spinRange = 4
        cell.color = partyColors.randomElement()!.cgColor
        emitter.emitterCells = [cell]

        layer.addSublayer(emitter)
        live.append(emitter)
        // One short burst, not a fountain.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { emitter.birthRate = 0 }
    }

    private func confetti() {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.height * 0.52)
        emitter.emitterSize = CGSize(width: bounds.width * 0.7, height: 1)
        emitter.emitterShape = .line
        emitter.beginTime = CACurrentMediaTime()

        emitter.emitterCells = partyColors.map { color in
            let cell = CAEmitterCell()
            cell.contents = Self.confettiImage.cgImage
            cell.color = color.cgColor
            cell.birthRate = 700
            cell.lifetime = 3.4
            cell.velocity = 620
            cell.velocityRange = 260
            cell.emissionLongitude = -.pi / 2
            cell.emissionRange = .pi / 3.2
            cell.yAcceleration = 620
            cell.xAcceleration = 0
            cell.scale = 0.55
            cell.scaleRange = 0.3
            cell.spin = 5
            cell.spinRange = 7
            cell.alphaSpeed = -0.28
            return cell
        }

        layer.addSublayer(emitter)
        live.append(emitter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { emitter.birthRate = 0 }
    }

    private func balloons() {
        for i in 0..<9 {
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
            rise.duration = Double.random(in: 3.6...5.4)
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
        let size = CGSize(width: 28, height: 28)
        return UIGraphicsImageRenderer(size: size).image { c in
            let ctx = c.cgContext
            let mid = CGPoint(x: 14, y: 14)
            let path = CGMutablePath()
            for i in 0..<8 {
                let r: CGFloat = i % 2 == 0 ? 13 : 5.5
                let a = CGFloat(i) / 8 * .pi * 2 - .pi / 2
                let p = CGPoint(x: mid.x + cos(a) * r, y: mid.y + sin(a) * r)
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            path.closeSubpath()
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        }
    }()

    private static let confettiImage: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 16, height: 24)).image { c in
            c.cgContext.setFillColor(UIColor.white.cgColor)
            c.cgContext.fill(CGRect(x: 0, y: 0, width: 16, height: 24))
        }
    }()

    private static func balloonImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 90, height: 145)
        return UIGraphicsImageRenderer(size: size).image { c in
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
