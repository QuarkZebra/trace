import UIKit

// Pens the child unlocks by making progress.
//
// The point isn't decoration — it's that effort produces something visible she
// keeps. Unlocks are tied to what she's actually managing (steadier lines, then
// real shapes, then letters), so the reward names the achievement rather than
// just marking time.

struct Pen: Equatable {
    let id: String
    /// Spoken aloud, so it has to be a word a four-year-old has.
    let name: String
    /// One colour for a plain pen; several for the rainbow, cycled along the line.
    let colors: [UIColor]
    /// Multiplies the normal line thickness. The precision pen is half.
    let widthScale: CGFloat
    let unlock: Unlock

    static func == (a: Pen, b: Pen) -> Bool { a.id == b.id }

    var isRainbow: Bool { colors.count > 1 }
}

enum Unlock {
    case always
    /// Total correct traces, anywhere.
    case wins(Int)
    /// Reached this shape-complexity level.
    case level(Int)
    /// At the letters, and landing them consistently.
    case lettersMastered

    func isMet(by learner: Learner) -> Bool {
        switch self {
        case .always:
            return true
        case .wins(let n):
            return learner.totalWins >= n
        case .level(let n):
            return learner.level >= n
        case .lettersMastered:
            guard learner.level >= Limits.maxLevel else { return false }
            return learner.totalWins >= 60 && (learner.recentAccuracy() ?? 0) >= 0.8
        }
    }

    /// What the app says when this one opens up.
    var announcement: String {
        switch self {
        case .always:
            return ""
        case .wins:
            return "Look! Your careful tracing earned you a new colour."
        case .level(let n) where n <= 2:
            return "You're doing real shapes now! Here's a new colour, and a skinny pencil for tricky ones."
        case .level:
            return "You're tracing letters! That's big-kid work. Two new colours for you."
        case .lettersMastered:
            return "You worked so hard on your letters. You unlocked the rainbow pen!"
        }
    }
}

enum Pens {
    static let all: [Pen] = [
        Pen(
            id: "blueberry", name: "blueberry",
            colors: [UIColor(red: 0.169, green: 0.184, blue: 0.478, alpha: 1)],
            widthScale: 1, unlock: .always),
        Pen(
            id: "grape", name: "grape",
            colors: [UIColor(red: 0.486, green: 0.227, blue: 0.929, alpha: 1)],
            widthScale: 1, unlock: .wins(8)),
        Pen(
            id: "mint", name: "mint",
            colors: [UIColor(red: 0.059, green: 0.608, blue: 0.557, alpha: 1)],
            widthScale: 1, unlock: .level(2)),
        Pen(
            id: "skinny", name: "skinny pencil",
            colors: [UIColor(red: 0.247, green: 0.247, blue: 0.275, alpha: 1)],
            widthScale: 0.5, unlock: .level(2)),
        Pen(
            id: "bubblegum", name: "bubblegum",
            colors: [UIColor(red: 0.878, green: 0.204, blue: 0.545, alpha: 1)],
            widthScale: 1, unlock: .level(4)),
        Pen(
            id: "mango", name: "mango",
            colors: [UIColor(red: 0.976, green: 0.451, blue: 0.086, alpha: 1)],
            widthScale: 1, unlock: .level(4)),
        Pen(
            id: "rainbow", name: "rainbow",
            colors: [
                UIColor(red: 0.898, green: 0.282, blue: 0.302, alpha: 1),
                UIColor(red: 0.976, green: 0.451, blue: 0.086, alpha: 1),
                UIColor(red: 0.961, green: 0.769, blue: 0.000, alpha: 1),
                UIColor(red: 0.133, green: 0.773, blue: 0.369, alpha: 1),
                UIColor(red: 0.024, green: 0.714, blue: 0.831, alpha: 1),
                UIColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1),
                UIColor(red: 0.545, green: 0.361, blue: 0.965, alpha: 1),
                UIColor(red: 0.925, green: 0.282, blue: 0.600, alpha: 1),
            ],
            widthScale: 1, unlock: .lettersMastered),
    ]

    static let `default` = all[0]

    static func byId(_ id: String) -> Pen { all.first { $0.id == id } ?? `default` }

    static func unlocked(for learner: Learner) -> [Pen] {
        all.filter { $0.unlock.isMet(by: learner) }
    }

    /// Pens that just became available. Grouped by announcement so unlocking two
    /// colours at once is one sentence, not two.
    static func newlyUnlocked(before: Learner, after: Learner) -> [Pen] {
        let had = Set(unlocked(for: before).map(\.id))
        return unlocked(for: after).filter { !had.contains($0.id) }
    }
}

// MARK: - Pen picker

/// A simplified take on the Notes tool strip: one nib per unlocked pen, the
/// selected one standing proud of the others. It grows as she unlocks more.
final class PenBarView: UIView {

    var onSelect: ((Pen) -> Void)?
    private(set) var pens: [Pen] = []
    private(set) var selected: Pen = Pens.default
    private var buttons: [UIButton] = []

    private let nibWidth: CGFloat = 34
    private let nibHeight: CGFloat = 104
    private let gap: CGFloat = 10

    func setPens(_ pens: [Pen], selected: Pen, animated: Bool) {
        self.pens = pens
        self.selected = pens.contains(selected) ? selected : (pens.first ?? Pens.default)
        // Nothing to choose between until she's earned a second pen, and an
        // empty-looking control is just clutter on a child's screen.
        isHidden = pens.count < 2
        rebuild(animated: animated)
    }

    func select(_ pen: Pen) {
        guard pens.contains(pen) else { return }
        selected = pen
        layoutNibs(animated: true)
    }

    private func rebuild(animated: Bool) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = pens.enumerated().map { index, pen in
            let b = UIButton(type: .custom)
            b.tag = index
            b.setImage(Self.nibImage(for: pen, size: CGSize(width: nibWidth, height: nibHeight)), for: .normal)
            b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            b.accessibilityLabel = pen.name
            addSubview(b)
            return b
        }
        bounds.size = CGSize(
            width: CGFloat(pens.count) * (nibWidth + gap), height: nibHeight + 16)
        layoutNibs(animated: false)

        if animated, let last = buttons.last {
            last.transform = CGAffineTransform(translationX: 0, y: 60)
            last.alpha = 0
            UIView.animate(
                withDuration: 0.5, delay: 0.1, usingSpringWithDamping: 0.6,
                initialSpringVelocity: 0.4
            ) {
                last.transform = .identity
                last.alpha = 1
            }
        }
    }

    private func layoutNibs(animated: Bool) {
        let apply = {
            for (i, b) in self.buttons.enumerated() {
                let raised = self.pens[i] == self.selected
                b.frame = CGRect(
                    x: CGFloat(i) * (self.nibWidth + self.gap),
                    y: raised ? 0 : 22,
                    width: self.nibWidth, height: self.nibHeight)
            }
        }
        animated ? UIView.animate(withDuration: 0.18, animations: apply) : apply()
    }

    @objc private func tapped(_ sender: UIButton) {
        let pen = pens[sender.tag]
        selected = pen
        layoutNibs(animated: true)
        onSelect?(pen)
    }

    /// A little pen: pale barrel, coloured nib. The rainbow gets a striped nib,
    /// and the skinny pencil a visibly finer point.
    private static func nibImage(for pen: Pen, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { c in
            let ctx = c.cgContext
            let w = size.width, h = size.height
            let tipH = h * 0.40

            // Barrel
            let barrel = UIBezierPath(
                roundedRect: CGRect(x: 0, y: tipH - 6, width: w, height: h - tipH + 6),
                cornerRadius: 7)
            ctx.setFillColor(UIColor(white: 0.93, alpha: 1).cgColor)
            barrel.fill()

            // Nib, narrower for the precision pen so the difference is visible
            // before she's drawn a single line with it.
            let tipWidth = w * (pen.widthScale < 1 ? 0.34 : 1.0)
            let inset = (w - tipWidth) / 2
            let tip = UIBezierPath()
            tip.move(to: CGPoint(x: w / 2, y: 0))
            tip.addLine(to: CGPoint(x: w - inset, y: tipH))
            tip.addLine(to: CGPoint(x: inset, y: tipH))
            tip.close()

            ctx.saveGState()
            tip.addClip()
            if pen.colors.count > 1 {
                let band = tipH / CGFloat(pen.colors.count)
                for (i, colour) in pen.colors.enumerated() {
                    ctx.setFillColor(colour.cgColor)
                    ctx.fill(CGRect(x: 0, y: CGFloat(i) * band, width: w, height: band + 1))
                }
            } else {
                ctx.setFillColor(pen.colors[0].cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: tipH))
            }
            ctx.restoreGState()

            // A band of the pen's colour on the barrel, so the selected pen is
            // identifiable even when the nib is mostly hidden.
            ctx.setFillColor(pen.colors[0].cgColor)
            ctx.fill(CGRect(x: 0, y: tipH + 4, width: w, height: 10))
        }
    }
}
