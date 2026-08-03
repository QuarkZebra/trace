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
    static let levelUpWidth: CGFloat = 11
}

private let baseStep: CGFloat = 0.035
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

    init() {}

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
            width = w85 * CGFloat.random(in: 1.22...1.40) * jitter
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
        case (false, false): (dir, k) = (1, 1.3 * upRatio)
        case (true, true): (dir, k) = (-1, 1.0)
        case (true, false): (dir, k) = (1, 0.15 * upRatio)
        }
        w85 = clamp(w85 * (1 + dir * baseStep * k))

        regulate()
    }

    private func regulate() {
        guard let acc = recentAccuracy() else { return }

        if acc > Limits.target + 0.03 {
            // Too easy for a sustained stretch. Tighten — and once the corridor
            // is already tight, promote to harder shapes and hand back some
            // width rather than narrowing further.
            if w85 <= Limits.levelUpWidth && level < Limits.maxLevel {
                level += 1
                w85 = clamp(Limits.startWidth * 0.85)
                history.removeAll()
            } else {
                w85 = clamp(w85 * 0.97)
            }
        } else if acc < Limits.target - 0.08 {
            // Missing too often. Widen; if we're already at the ceiling, the
            // shapes themselves are the problem, so step back down a level.
            if w85 >= Limits.maxWidth * 0.92 && level > 1 {
                level -= 1
                w85 = clamp(Limits.startWidth)
                history.removeAll()
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
    var rate: Float = 0.44  // AVSpeechUtterance rate; ~0.5 is the system default
    var focus: Focus = .mix
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
