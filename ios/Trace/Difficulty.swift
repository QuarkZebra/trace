import CoreGraphics
import Foundation

// Adaptive difficulty, built around Wilson, Shenhav, Straccia & Cohen (2019),
// "The Eighty Five Percent Rule for optimal learning" (Nat. Commun. 10:4646).
//
// Their result: for a learner whose accuracy follows a sigmoid in the difficulty
// parameter, learning is fastest when training error is held near 15.87% — i.e.
// accuracy near 85%. So we don't make the task as easy as possible, and we don't
// push to failure; we steer the corridor width to the point where the child gets
// roughly 85% of trials right.
//
// Two things regulate difficulty, on different timescales:
//
//  1. A weighted up/down staircase on `w85`, the corridor width we believe sits
//     at the 85% point. Steps are multiplicative because width is a scale
//     parameter, and asymmetric in the Kaernbach sense: to converge on
//     P(correct) = p, an up-step must be worth p/(1-p) down-steps, which at
//     p = 0.85 is about 5.7. Step sizes are further shaded by whether the trial
//     was meant to be easy, so an unexpected failure on an easy trial moves us
//     much more than an expected failure on a probe.
//
//  2. A slow regulator over the last dozen trials. If observed accuracy drifts
//     away from 85% for a sustained stretch, nudge the width — and at the rails,
//     move the child up or down a shape-complexity level.
//
// The 85% is a property of the *set*, not of every trial. Most trials are served
// comfortably above threshold; a minority are probes at or below it. Averaged
// over a session that lands near 85% while keeping nearly every individual trial
// feeling winnable.

struct TrialRecord: Codable {
    var win: Bool
    var probe: Bool
    var width: CGFloat
    var level: Int
    var shapeId: String
}

struct TrialPlan {
    var probe: Bool
    var level: Int
    var width: CGFloat
}

enum Limits {
    static let target: CGFloat = 0.85
    static let minWidth: CGFloat = 4.5
    static let maxWidth: CGFloat = 34
    static let startWidth: CGFloat = 19
    static let maxLevel = 5

    /// Once the corridor is this tight, further narrowing only tests fine motor
    /// control the child has already shown. Promote them instead.
    static let levelUpWidth: CGFloat = 13

    /// Sustained accuracy this high promotes regardless of width. Without it a
    /// child who misses now and then can sit at the same level indefinitely —
    /// the staircase stays honest, but nothing visibly progresses, which reads
    /// as "the game isn't doing anything".
    static let levelUpAccuracy: CGFloat = 0.95
}

// The Kaernbach ratio has to be preserved for the staircase to converge on 85%,
// which means an up-step is ~5.7 down-steps. That makes the base step size the
// only real dial, and it can't be large: at 0.055 a single miss moved the width
// 40% in one trial, which both looked erratic and overshot the target. Speed of
// visible progress comes from the slow regulator instead, which moves on
// evidence from a dozen trials rather than one.
private let baseStep: CGFloat = 0.04

/// No single trial may move the estimate more than this, in either direction.
private let maxStepFactor: CGFloat = 1.25
private let upRatio = Limits.target / (1 - Limits.target)  // ≈ 5.67
private let window = 12

final class Learner: Codable {
    var w85: CGFloat = Limits.startWidth
    var level: Int = 1
    var history: [TrialRecord] = []
    var sinceProbe: Int = 0
    var lastWasProbe: Bool = false
    var recentShapes: [String] = []
    var creativeSeed: UInt32 = 1
    var totalTrials: Int = 0
    var totalWins: Int = 0

    /// Corridor width remembered per shape level. Difficulty is really the pair
    /// (how complex a shape, how wide the track), so moving up a level and back
    /// down shouldn't throw away what we already learned about each band —
    /// otherwise every level change restarts the search and the width stops
    /// looking like it responds to anything.
    var widthByLevel: [Int: CGFloat] = [:]

    /// Trials since the level last changed. Steps start large and settle, so a
    /// new band is found in a few goes instead of a few dozen.
    var sinceLevelChange: Int = 0

    /// Direction changes since arriving at this level. Until the width has
    /// over- and under-shot a couple of times we're still bracketing, and big
    /// symmetric steps get there far faster than the converged rule: the 5.7-to-1
    /// asymmetry that makes the estimate settle on 85% also makes it crawl
    /// downwards, which took 40-odd trials to reach a genuinely tight corridor.
    var reversalsAtLevel: Int = 0
    var lastMoveWasDown: Bool? = nil

    init() {}

    // Decoded field-by-field so a save written by an older build still loads
    // instead of silently resetting a child's progress.
    private enum CodingKeys: String, CodingKey {
        case w85, level, history, sinceProbe, lastWasProbe, recentShapes
        case creativeSeed, totalTrials, totalWins, widthByLevel, sinceLevelChange
        case reversalsAtLevel, lastMoveWasDown
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        w85 = try c.decodeIfPresent(CGFloat.self, forKey: .w85) ?? Limits.startWidth
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 1
        history = try c.decodeIfPresent([TrialRecord].self, forKey: .history) ?? []
        sinceProbe = try c.decodeIfPresent(Int.self, forKey: .sinceProbe) ?? 0
        lastWasProbe = try c.decodeIfPresent(Bool.self, forKey: .lastWasProbe) ?? false
        recentShapes = try c.decodeIfPresent([String].self, forKey: .recentShapes) ?? []
        creativeSeed = try c.decodeIfPresent(UInt32.self, forKey: .creativeSeed) ?? 1
        totalTrials = try c.decodeIfPresent(Int.self, forKey: .totalTrials) ?? 0
        totalWins = try c.decodeIfPresent(Int.self, forKey: .totalWins) ?? 0
        widthByLevel = try c.decodeIfPresent([Int: CGFloat].self, forKey: .widthByLevel) ?? [:]
        sinceLevelChange = try c.decodeIfPresent(Int.self, forKey: .sinceLevelChange) ?? 0
        reversalsAtLevel = try c.decodeIfPresent(Int.self, forKey: .reversalsAtLevel) ?? 0
        lastMoveWasDown = try c.decodeIfPresent(Bool.self, forKey: .lastMoveWasDown)
    }

    /// Move to a different shape level, keeping each level's own width estimate.
    private func changeLevel(to newLevel: Int) {
        widthByLevel[level] = w85
        level = newLevel
        // A harder band needs a wider track to start from; an easier one we've
        // seen before starts wherever we left it. Capped at the opening width so
        // promotions can't ratchet the corridor out to the maximum, which had it
        // bouncing between levels.
        w85 = clamp(widthByLevel[newLevel] ?? min(Limits.startWidth, w85 * 1.4))
        sinceLevelChange = 0
        reversalsAtLevel = 0
        lastMoveWasDown = nil
        history.removeAll()
    }

    /// Observed accuracy over the last `n` trials, or nil if there are too few.
    func recentAccuracy(_ n: Int = window) -> CGFloat? {
        let h = history.suffix(n)
        guard h.count >= min(6, n) else { return nil }
        return CGFloat(h.filter(\.win).count) / CGFloat(h.count)
    }

    /// Should the next trial be a probe — the one we expect them to miss?
    ///
    /// Base rate is one in six. Two rules keep it unpredictable in both
    /// directions: never two in a row (that reads as "the game got hard"), and
    /// forced if nine trials pass without one (that reads as "the game got
    /// boring"). Probes are also skipped right after two misses, so a struggling
    /// child gets a run of wins first.
    func shouldProbe() -> Bool {
        if lastWasProbe { return false }
        let lastTwo = history.suffix(2)
        if lastTwo.count == 2 && lastTwo.allSatisfy({ !$0.win }) { return false }
        // Already at the widest corridor and the easiest shapes: the task can't
        // get any easier, so there's no headroom above threshold for a probe to
        // sit below. Spending one trial in six on a near-certain miss would just
        // drag a struggling child further under 85% for no information.
        if w85 >= Limits.maxWidth * 0.95 && level == 1 { return false }
        if sinceProbe >= 9 { return true }
        return CGFloat.random(in: 0..<1) < 1.0 / 6.0
    }

    /// Choose the difficulty of the next trial.
    ///
    /// Easy trials sit 22–40% wider than the 85% point, well up the child's
    /// psychometric curve. Probes sit at or below it, and half the time a probe
    /// spends its difficulty on a harder *shape* rather than a narrower
    /// corridor — variety matters as much as the number does.
    func planTrial() -> TrialPlan {
        let probe = shouldProbe()
        let jitter = CGFloat.random(in: 0.93...1.07)  // so widths never look quantised
        var width: CGFloat
        var lvl = level

        if probe {
            if Bool.random() && level < Limits.maxLevel {
                lvl = level + 1
                width = w85 * 1.05 * jitter
            } else {
                width = w85 * 0.82 * jitter
            }
        } else {
            width = w85 * CGFloat.random(in: 1.18...1.32) * jitter
            // Occasionally reach down a level for a confidence builder.
            if level > 1 && CGFloat.random(in: 0..<1) < 0.18 { lvl = level - 1 }
        }

        return TrialPlan(
            probe: probe, level: lvl,
            width: min(Limits.maxWidth, max(Limits.minWidth, width)))
    }

    /// Fold a finished trial back into the estimate.
    func record(_ r: TrialRecord) {
        history.append(r)
        if history.count > 60 { history.removeFirst() }
        totalTrials += 1
        if r.win { totalWins += 1 }

        lastWasProbe = r.probe
        sinceProbe = r.probe ? 0 : sinceProbe + 1
        recentShapes.append(r.shapeId)
        if recentShapes.count > 8 { recentShapes.removeFirst() }

        // Fast staircase. Weights: an easy win is weak evidence, an easy loss is
        // loud, a probe win says we're too generous, a probe loss says nothing.
        let (dir, k): (CGFloat, CGFloat)
        switch (r.probe, r.win) {
        case (false, true): (dir, k) = (-1, 0.35)
        case (false, false): (dir, k) = (1, upRatio)
        case (true, true): (dir, k) = (-1, 1.0)
        case (true, false): (dir, k) = (1, 0.15 * upRatio)
        }
        sinceLevelChange += 1

        // Two phases. While still bracketing — before the width has over- and
        // under-shot twice — take big, near-symmetric steps to find the right
        // neighbourhood fast. Once bracketed, switch to the Kaernbach-weighted
        // rule that actually converges on 85%. Using the converged rule from the
        // start is what made the width look inert.
        let factor: CGFloat
        if reversalsAtLevel < 2 {
            factor = dir < 0 ? 0.86 : 1.28
        } else {
            let eagerness = 1 + 1.0 * exp(-CGFloat(sinceLevelChange) / 8)
            factor = min(
                maxStepFactor, max(1 / maxStepFactor, 1 + dir * baseStep * eagerness * k))
        }

        let movingDown = dir < 0
        if let previous = lastMoveWasDown, previous != movingDown { reversalsAtLevel += 1 }
        lastMoveWasDown = movingDown

        w85 = clamp(w85 * factor)

        regulate()
    }

    private func regulate() {
        guard let acc = recentAccuracy() else { return }
        // Give a new level time to settle before considering another move, or a
        // capable child ping-pongs between bands instead of progressing.
        let mayChangeLevel = sinceLevelChange >= 8

        if acc > Limits.target + 0.03 {
            // Too easy for a sustained stretch. Tighten — and once the corridor
            // is already tight, promote to harder shapes and hand back some
            // width rather than narrowing further.
            if mayChangeLevel && (w85 <= Limits.levelUpWidth || acc >= Limits.levelUpAccuracy)
                && level < Limits.maxLevel
            {
                changeLevel(to: level + 1)
            } else {
                w85 = clamp(w85 * 0.94)
            }
        } else if acc < Limits.target - 0.08 {
            // Missing too often. Widen; if we're already at the ceiling, the
            // shapes themselves are the problem, so step back down a level.
            if mayChangeLevel && w85 >= Limits.maxWidth * 0.92 && level > 1 {
                changeLevel(to: level - 1)
            } else {
                w85 = clamp(w85 * 1.05)
            }
        }
    }

    private func clamp(_ v: CGFloat) -> CGFloat {
        min(Limits.maxWidth, max(Limits.minWidth, v))
    }
}

// MARK: - Persistence

struct Settings: Codable {
    enum Focus: String, Codable, CaseIterable {
        case mix, shapes, letters, numbers
    }
    var voice = true
    var sound = true
    var rate: Float = 0.52  // AVSpeechUtterance rate; ~0.5 is the system default
    var focus: Focus = .mix
    var penId: String = "blueberry"
}

enum Store {
    private static let learnerKey = "trace.learner.v1"
    private static let settingsKey = "trace.settings.v1"

    static func loadLearner() -> Learner {
        guard let data = UserDefaults.standard.data(forKey: learnerKey),
            let l = try? JSONDecoder().decode(Learner.self, from: data)
        else { return Learner() }
        return l
    }

    static func save(_ learner: Learner, _ settings: Settings) {
        if let d = try? JSONEncoder().encode(learner) {
            UserDefaults.standard.set(d, forKey: learnerKey)
        }
        if let d = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(d, forKey: settingsKey)
        }
    }

    static func loadSettings() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
            let s = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return s
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: learnerKey)
    }
}
