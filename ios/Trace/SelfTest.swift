#if DEBUG
import UIKit

// A headless run-through, launched with `-selftest`. The simulator can't be
// sent real pencil input, so this drives the board with synthetic strokes to
// check that judging, adaptation and the trial loop all behave — the same
// checks the web version got, against the real Swift code paths.

@MainActor
enum SelfTest {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-selftest")
    }

    private static func log(_ s: String) { print("SELFTEST \(s)") }

    /// Judging: does a clean trace win and a sloppy one lose, for the right reason?
    static func checkJudging(board: BoardView) {
        log("--- judging ---")
        guard let shape = ShapeLibrary.byId("letter-P") else { return }

        let cases: [(String, CGFloat, CGFloat, CGFloat)] = [
            // label, wobble, offset, skipEnd
            ("perfect", 0, 0, 0),
            ("wobble 30%", 0.30, 0, 0),
            ("wobble 45%", 0.45, 0, 0),
            ("offset 40%", 0, 0.40, 0),
            ("offset 60%", 0, 0.60, 0),
            ("stops at 65%", 0, 0, 0.35),
            ("stops at 95%", 0, 0, 0.05),
        ]
        for (label, wobble, offset, skipEnd) in cases {
            board.setTrial(shape: shape, corridorUnits: 14)
            board.onStrokeEnd = nil
            board.simulateTrace(wobble: wobble, offset: offset, skipEnd: skipEnd)
            let j = board.judge()
            log(
                String(
                    format: "%-14@ win=%@ reason=%-10@ cov=%.2f leak=%.1f%%", label as NSString,
                    j.win ? "Y" : "n", j.reason.rawValue as NSString, j.coverage, j.leakRatio * 100))
        }
    }

    /// The start marker's arrow must point the way the stroke actually travels.
    static func checkStartArrows(board: BoardView) {
        log("--- start arrows ---")
        for id in ["valley", "line-diag", "letter-P", "circle"] {
            guard let shape = ShapeLibrary.byId(id) else { continue }
            board.setTrial(shape: shape, corridorUnits: 16)
            guard let t = board.trial, let st = t.strokes.first else { continue }
            let p = st.pts[0]
            let q = st.pts[min(st.pts.count - 1, 14)]
            let deg = atan2(q.y - p.y, q.x - p.x) * 180 / .pi
            log(
                String(
                    format: "%-10@ start=(%.0f,%.0f) next=(%.0f,%.0f) angle=%.0f deg",
                    id as NSString, p.x, p.y, q.x, q.y, deg))
        }
    }

    /// Every shape in the library samples cleanly and sits inside its box.
    static func checkShapes() {
        log("--- shapes ---")
        var problems = 0
        var checked = 0
        var shapes = ShapeLibrary.all
        for seed in UInt32(1)...60 { shapes.append(makeCreativeShape(seed: seed, level: 5)) }

        for s in shapes {
            checked += 1
            let strokes = s.strokes.map { PathDSL.sample($0) }
            for (i, pts) in strokes.enumerated() {
                if pts.count < 4 {
                    log("  \(s.id)[\(i)]: only \(pts.count) points")
                    problems += 1
                }
                for k in 1..<max(1, pts.count) {
                    let d = hypot(pts[k].x - pts[k - 1].x, pts[k].y - pts[k - 1].y)
                    if d > 4 {
                        log(String(format: "  %@[%d]: %.1f-unit jump", s.id, i, d))
                        problems += 1
                        break
                    }
                }
            }
            let b = boundingBox(strokes)
            if b.minX < -1 || b.minY < -1 || b.maxX > 101 || b.maxY > 101 {
                log("  \(s.id): outside the 0..100 box")
                problems += 1
            }
            if s.strokes.count > 3 {
                log("  \(s.id): \(s.strokes.count) strokes")
                problems += 1
            }
        }
        log("checked \(checked) shapes, \(problems) problem(s)")
    }

    /// Does a child who's doing well actually SEE it get harder? The controller
    /// can be statistically correct and still feel inert, which is what the
    /// first round of testing on device reported.
    static func checkProgression() {
        log("--- progression (a child winning ~95% of the time) ---")
        let learner = Learner()
        var line = ""
        for t in 1...30 {
            let plan = learner.planTrial()
            let win = CGFloat.random(in: 0..<1) < 0.95
            learner.record(
                TrialRecord(
                    win: win, probe: plan.probe, width: plan.width, level: plan.level,
                    shapeId: "s"))
            if t % 5 == 0 {
                line += String(format: "  t%02d: gap=%.1f level=%d", t, learner.w85, learner.level)
                log(line)
                line = ""
            }
        }
        log(
            String(
                format: "after 30 trials: gap %.1f (from %.1f), level %d, pens %d",
                learner.w85, Limits.startWidth, learner.level,
                Pens.unlocked(for: learner).count))
    }

    /// How many trials before the corridor width finds a child's real level?
    /// "It adapts eventually" is not the same as "it feels responsive".
    static func checkResponsiveness() {
        log("--- responsiveness (trials to reach the child's true width) ---")
        for trueWidth in [CGFloat(9), 16, 26] {
            var totalToConverge = 0
            var runs = 0
            for _ in 0..<40 {
                let l = Learner()
                var settled: Int?
                for t in 1...60 {
                    let plan = l.planTrial()
                    // Sharp psychometric curve around the child's true width.
                    let p = 1 / (1 + exp(-(plan.width - trueWidth) / 2.0))
                    l.record(
                        TrialRecord(
                            win: CGFloat.random(in: 0..<1) < p, probe: plan.probe,
                            width: plan.width, level: plan.level, shapeId: "s"))
                    if settled == nil, abs(l.w85 - trueWidth) / trueWidth < 0.20 { settled = t }
                }
                if let s = settled {
                    totalToConverge += s
                    runs += 1
                }
            }
            log(
                String(
                    format: "  true width %.0f: reached within 20%% in %@ trials (%d/40 runs)",
                    trueWidth,
                    runs > 0 ? String(format: "%.0f", Double(totalToConverge) / Double(runs)) : "—",
                    runs))
        }
    }

    /// No two pens may arrive at the same moment — each needs its own
    /// celebration, and "you're at level purple now" only works if purple is the
    /// only thing that just happened.
    static func checkUnlockSpacing() {
        log("--- unlock spacing ---")
        var previous = Set<String>()
        var clashes = 0
        // Walk a plausible career: wins climbing, level rising with them.
        for step in 0...80 {
            let l = Learner()
            l.totalWins = step
            l.totalTrials = step + step / 6
            l.level = min(Limits.maxLevel, 1 + step / 16)
            for i in 0..<12 {
                l.history.append(
                    TrialRecord(win: i != 0, probe: false, width: 12, level: l.level, shapeId: "s"))
            }
            let now = Set(Pens.unlocked(for: l).map(\.id))
            let fresh = now.subtracting(previous)
            if fresh.count > 1 {
                log("  CLASH at wins=\(step): \(fresh.sorted().joined(separator: ", "))")
                clashes += 1
            } else if fresh.count == 1 {
                log("  wins=\(String(format: "%2d", step)) level=\(l.level) -> \(fresh.first!)")
            }
            previous = now
        }
        log(clashes == 0 ? "  no two pens ever arrive together" : "  \(clashes) clash(es)")
    }

    /// The unlock ladder, at the milestones it's meant to fire on.
    static func checkPens() {
        log("--- pen unlocks ---")
        let stages: [(String, Int, Int, Int)] = [
            // label, totalWins, totalTrials, level
            ("fresh start", 0, 0, 1),
            ("8 wins", 8, 10, 1),
            ("standard shapes", 14, 16, 2),
            ("letters", 40, 46, 4),
            ("letters mastered", 60, 66, 5),
        ]
        for (label, wins, trials, level) in stages {
            let l = Learner()
            l.totalWins = wins
            l.totalTrials = trials
            l.level = level
            // Recent history so lettersMastered can evaluate accuracy.
            for i in 0..<12 {
                l.history.append(
                    TrialRecord(win: i != 0, probe: false, width: 10, level: level, shapeId: "s"))
            }
            let names = Pens.unlocked(for: l).map(\.name).joined(separator: ", ")
            log("  \(label.padding(toLength: 18, withPad: " ", startingAt: 0)) \(names)")
        }
    }

    /// The 85% controller against a simulated child whose skill is fixed.
    static func checkAdaptation() {
        log("--- adaptation ---")
        for (label, startSkill, learnRate) in [
            ("typical", CGFloat(16), CGFloat(0.004)),
            ("struggling", CGFloat(30), CGFloat(0.002)),
            ("skilled", CGFloat(6), CGFloat(0.006)),
        ] {
            let learner = Learner()
            var skill = startSkill
            var log2: [(win: Bool, probe: Bool)] = []
            var gaps: [Int] = []
            var since = 0
            var worstRun = 0
            var run = 0

            for _ in 0..<400 {
                let plan = learner.planTrial()
                let need = skill + CGFloat(plan.level - 1) * 2.6
                let p = 1 / (1 + exp(-(plan.width - need) / 2.2))
                let win = CGFloat.random(in: 0..<1) < p
                learner.record(
                    TrialRecord(
                        win: win, probe: plan.probe, width: plan.width, level: plan.level,
                        shapeId: "s"))
                if win { skill = max(3, skill - learnRate * 12) }
                log2.append((win, plan.probe))
                if plan.probe {
                    gaps.append(since)
                    since = 0
                } else {
                    since += 1
                }
                run = win ? 0 : run + 1
                worstRun = max(worstRun, run)
            }

            let tail = log2.suffix(200)
            let acc = CGFloat(tail.filter(\.win).count) / CGFloat(tail.count)
            let probeRate = CGFloat(log2.filter(\.probe).count) / CGFloat(log2.count)
            log(
                String(
                    format: "%-11@ acc=%.1f%%  probeRate=1/%.1f  gaps=%d..%d  worstLossRun=%d  level=%d  width=%.1f",
                    label as NSString, acc * 100, 1 / probeRate, gaps.min() ?? 0, gaps.max() ?? 0,
                    worstRun, learner.level, learner.w85))
        }
    }

    /// Play the real trial loop, tracing each shape as it comes up.
    static func playTrials(_ n: Int, board: BoardView, learner: () -> Learner) async {
        log("--- trial loop ---")
        var capViolations = 0
        var seen = Set<String>()
        var repeats = 0
        var previousShape = ""
        var widths: [CGFloat] = []

        for i in 0..<n {
            var guardCount = 0
            while board.trial == nil && guardCount < 200 {
                try? await Task.sleep(nanoseconds: 25_000_000)
                guardCount += 1
            }
            guard let t = board.trial else { break }
            let before = learner().totalTrials
            seen.insert(t.shape.id)
            widths.append(t.corridorUnits)
            if let cap = t.shape.maxWidth, t.corridorUnits > cap + 0.01 {
                log("  CAP VIOLATION \(t.shape.id) at \(t.corridorUnits) > \(cap)")
                capViolations += 1
            }
            if i < 6 {
                log(
                    String(
                        format: "  %2d %-16@ width=%.1f", i + 1, t.shape.id as NSString,
                        t.corridorUnits))
            }
            board.simulateTrace(wobble: 0.3)

            var settle = 0
            while learner().totalTrials == before && settle < 200 {
                try? await Task.sleep(nanoseconds: 25_000_000)
                settle += 1
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        let l = learner()
        log(
            String(
                format: "played %d trials, %d distinct shapes, %d cap violations, acc=%.0f%%, level=%d, width=%.1f",
                l.totalTrials, seen.count, capViolations,
                l.totalTrials > 0 ? Double(l.totalWins) / Double(l.totalTrials) * 100 : 0,
                l.level, l.w85))
        // Count repeats from what was actually *recorded*, not from whatever was
        // on the board when this loop looked — the tracer runs faster than the
        // game advances, so polling the board double-counts a single trial.
        for (a, b) in zip(l.history, l.history.dropFirst()) where a.shapeId == b.shapeId {
            repeats += 1
        }
        _ = previousShape
        log(
            String(
                format: "back-to-back repeats: %d of %d   gap first->last: %.1f -> %.1f", repeats,
                max(0, l.history.count - 1), widths.first ?? 0, widths.last ?? 0))
        log("DONE")
    }
}
#endif
