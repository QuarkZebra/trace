import UIKit

// The trial loop: present a shape, demonstrate it, wait for the child, judge,
// celebrate or coach, adapt, repeat.

private enum AttemptOutcome { case done, settled, panel }

#if DEBUG
private nonisolated(unsafe) var selfTestKey: UInt8 = 0
#endif

// Celebration cadence: one big one in about every four wins, never twice
// running, guaranteed if it's been a while.
private let bigChance: CGFloat = 0.25
private let bigForceAfter = 6

/// How many trials get an unprompted demonstration at the start of a session.
/// After that she's shown she knows the game, and the demo becomes something
/// she asks for via the button rather than something imposed on every shape.
private let autoDemoTrials = 3

private let idleDelay: Double = 4.5  // no touch after the prompt -> offer the replay button
private let settleDelay: Double = 2.6  // pen up on an unfinished shape -> judge what we have

@MainActor
final class GameViewController: UIViewController {

    private let board = BoardView()
    private let fx = CelebrationView()
    private let helpButton = UIButton(type: .custom)
    private let startOverlay = UIView()

    private var learner = Store.loadLearner()
    private var settings = Store.loadSettings()
    private let voice = Voice()
    private let sfx = Sfx()

    private let penBar = PenBarView()
    private var pen = Pens.default

    private var loopTask: Task<Void, Never>?
    private var abort = false
    private var demoedThisSession = Set<String>()
    private var trialsThisSession = 0
    private var sinceBig = 99
    private var lastWasBig = false
    private var lastBigKind: BigCelebration?
    private var helpSticky = false
    private var lastFailedShape: String?

    /// Set by the self-test: the demo is a multi-second animation and there's no
    /// point waiting on it when nobody's watching.
    var skipDemoForTest = false

    private var attemptCont: CheckedContinuation<AttemptOutcome, Never>?
    private var idleTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var onHelp: (() async -> Void)?

    // MARK: - Setup

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.051, green: 0.063, blue: 0.188, alpha: 1)

        board.frame = view.bounds
        board.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(board)

        fx.frame = view.bounds
        fx.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(fx)

        setUpHelpButton()
        setUpPenBar()
        setUpStartOverlay()

        // Grown-up settings sit behind a long press in the corner, where a child
        // won't wander into them.
        let corner = UIView(frame: CGRect(x: 0, y: 0, width: 90, height: 90))
        corner.backgroundColor = .clear
        view.addSubview(corner)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(cornerHeld))
        press.minimumPressDuration = 1.2
        corner.addGestureRecognizer(press)

        voice.enabled = settings.voice
        voice.rate = settings.rate
        sfx.enabled = settings.sound
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        guard !selfTestStarted else { return }
        selfTestStarted = true
        if SelfTest.isEnabled {
            Task { await runSelfTest() }
        } else if ProcessInfo.processInfo.arguments.contains("-autoplay") {
            // Lets a screenshot run reach real gameplay without a tap.
            startTapped()
        } else if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-showshape"),
            i + 1 < ProcessInfo.processInfo.arguments.count,
            let shape = ShapeLibrary.byId(ProcessInfo.processInfo.arguments[i + 1])
        {
            // Park a named shape on screen so a screenshot can check its look.
            startOverlay.isHidden = true
            if ProcessInfo.processInfo.arguments.contains("-unlockall") {
                learner.totalWins = 80
                learner.totalTrials = 90
                learner.level = Limits.maxLevel
                for i in 0..<12 {
                    learner.history.append(
                        TrialRecord(win: i != 0, probe: false, width: 12, level: 5, shapeId: "s"))
                }
                let all = Pens.unlocked(for: learner)
                pen = all.last ?? Pens.default
                board.pen = pen
                penBar.setPens(all, selected: pen, animated: false)
                layoutPenBar()
            }
            board.setTrial(shape: shape, corridorUnits: 16)
            if ProcessInfo.processInfo.arguments.contains("-traced") {
                board.simulateTrace(wobble: 0.34)
                let j = board.judge()
                print("SELFTEST traced \(shape.id): win=\(j.win) reason=\(j.reason.rawValue)")
            }
            // Trace one shape then move to the next, to prove the previous
            // child's line doesn't linger on the new shape.
            if let k = ProcessInfo.processInfo.arguments.firstIndex(of: "-thenshape"),
                k + 1 < ProcessInfo.processInfo.arguments.count,
                let next = ShapeLibrary.byId(ProcessInfo.processInfo.arguments[k + 1])
            {
                board.setTrial(shape: next, corridorUnits: 16)
                print("SELFTEST advanced to \(next.id), drawnLen=\(Int(board.drawnLen))")
            }
        }
        #endif
    }

    #if DEBUG
    private var selfTestStarted: Bool {
        get { objc_getAssociatedObject(self, &selfTestKey) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &selfTestKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    private func runSelfTest() async {
        startOverlay.isHidden = true
        settings.voice = false
        settings.sound = false
        voice.enabled = false
        sfx.enabled = false
        skipDemoForTest = true
        learner = Learner()

        SelfTest.checkProgression()
        SelfTest.checkPens()
        SelfTest.checkStartArrows(board: board)
        SelfTest.checkShapes()
        SelfTest.checkAdaptation()
        SelfTest.checkJudging(board: board)

        board.onStrokeEnd = nil
        startLoop()
        await SelfTest.playTrials(30, board: board, learner: { self.learner })
        exit(0)
    }
    #endif

    private func setUpHelpButton() {
        helpButton.frame = CGRect(x: 0, y: 0, width: 96, height: 96)
        helpButton.backgroundColor = UIColor(red: 1, green: 0.82, blue: 0.35, alpha: 1)
        helpButton.layer.cornerRadius = 48
        helpButton.tintColor = UIColor(red: 0.29, green: 0.17, blue: 0, alpha: 1)
        helpButton.setImage(
            UIImage(
                systemName: "arrow.clockwise",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 42, weight: .bold)),
            for: .normal)
        helpButton.layer.shadowColor = UIColor.black.cgColor
        helpButton.layer.shadowOpacity = 0.45
        helpButton.layer.shadowRadius = 14
        helpButton.layer.shadowOffset = CGSize(width: 0, height: 8)
        helpButton.isHidden = true
        helpButton.addTarget(self, action: #selector(helpTapped), for: .touchUpInside)
        helpButton.accessibilityLabel = "Show me again"
        view.addSubview(helpButton)
    }

    private func setUpPenBar() {
        pen = Pens.byId(settings.penId)
        let available = Pens.unlocked(for: learner)
        if !available.contains(pen) { pen = Pens.default }
        board.pen = pen
        penBar.setPens(available, selected: pen, animated: false)
        penBar.onSelect = { [weak self] chosen in
            guard let self else { return }
            pen = chosen
            board.pen = chosen
            settings.penId = chosen.id
            Store.save(learner, settings)
            sfx.pop()
        }
        view.addSubview(penBar)
    }

    private func layoutPenBar() {
        let inset = view.safeAreaInsets
        penBar.frame.origin = CGPoint(
            x: 24 + inset.left,
            y: view.bounds.height - penBar.bounds.height - 16 - inset.bottom)
    }

    private func setUpStartOverlay() {
        startOverlay.frame = view.bounds
        startOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        startOverlay.backgroundColor = UIColor(red: 0.075, green: 0.09, blue: 0.24, alpha: 1)

        let title = UILabel()
        title.text = "Trace"
        title.font = .systemFont(ofSize: 110, weight: .heavy)
        title.textColor = UIColor(red: 1, green: 0.86, blue: 0.55, alpha: 1)
        title.textAlignment = .center

        let sub = UILabel()
        sub.text = "Stay inside the lines!"
        sub.font = .systemFont(ofSize: 30, weight: .medium)
        sub.textColor = UIColor(red: 0.72, green: 0.76, blue: 1, alpha: 1)
        sub.textAlignment = .center

        let play = UIButton(type: .custom)
        play.setTitle("Play", for: .normal)
        play.titleLabel?.font = .systemFont(ofSize: 44, weight: .bold)
        play.setTitleColor(UIColor(red: 0.02, green: 0.2, blue: 0.1, alpha: 1), for: .normal)
        play.backgroundColor = UIColor(red: 0.42, green: 0.87, blue: 0.55, alpha: 1)
        play.layer.cornerRadius = 46
        play.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

        let hint = UILabel()
        hint.text = "Press and hold the top-left corner for grown-up settings."
        hint.font = .systemFont(ofSize: 15)
        hint.textColor = UIColor(white: 1, alpha: 0.4)
        hint.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [title, sub, play, hint])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 28
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(56, after: play)
        startOverlay.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: startOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: startOverlay.centerYAnchor),
            play.widthAnchor.constraint(equalToConstant: 300),
            play.heightAnchor.constraint(equalToConstant: 92),
        ])
        view.addSubview(startOverlay)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let inset = view.safeAreaInsets
        helpButton.frame = CGRect(
            x: view.bounds.width - 96 - 24 - inset.right,
            y: view.bounds.height - 96 - 24 - inset.bottom,
            width: 96, height: 96)
        layoutPenBar()
    }

    // MARK: - Session

    @objc private func startTapped() {
        sfx.start()
        UIView.animate(withDuration: 0.25) { self.startOverlay.alpha = 0 } completion: { _ in
            self.startOverlay.isHidden = true
        }
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            await voice.say(Lines.welcome())
            startLoop()
        }
    }

    private func startLoop() {
        guard loopTask == nil else { return }
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                let outcome = await runTrial()
                // The panel can open during a celebration, after the last abort
                // check in runTrial — stop here rather than presenting the next
                // shape behind the dialog.
                if outcome == .panel || abort { break }
            }
            loopTask = nil
        }
    }

    /// Can this shape host a corridor of `width` without its channels fusing?
    private func fits(_ shape: Shape, _ width: CGFloat) -> Bool {
        (shape.maxWidth ?? Limits.maxWidth) >= width * 0.92
    }

    /// Pick a shape for the planned difficulty.
    ///
    /// `width` matters here as well as in the trial: a shape with a corridor cap
    /// can't host a wide track, and quietly narrowing one would turn a trial we
    /// planned as easy into a hard one — which is exactly what the 85%
    /// accounting relies on not happening.
    private func chooseShape(level: Int, width: CGFloat) -> Shape {
        var pool = ShapeLibrary.forLevel(level)
        switch settings.focus {
        case .shapes: pool = pool.filter { $0.kind == nil }
        case .letters: pool = pool.filter { $0.kind == .letterGlyph }
        case .numbers: pool = pool.filter { $0.kind == .digitGlyph }
        case .mix: break
        }
        if pool.isEmpty { pool = ShapeLibrary.forLevel(level) }

        // Novel generated designs once the basics are landing, so the library
        // never feels exhausted.
        if settings.focus == .mix && level >= 3 {
            let chance: CGFloat = level >= 4 ? 0.18 : 0.1
            if CGFloat.random(in: 0..<1) < chance {
                let made = makeCreativeShape(seed: learner.creativeSeed, level: level)
                learner.creativeSeed &+= 1
                if fits(made, width) { return made }
            }
        }

        let roomy = pool.filter { fits($0, width) }
        if !roomy.isEmpty { pool = roomy }

        // Avoid repeats — but a small pool can't honour a long memory. At level
        // one there are only five shapes and the recent list holds eight, so
        // filtering by all of them left nothing and fell back to the whole pool,
        // which is how the same shape came up twice in a row. Keep the window
        // strictly smaller than the pool so there's always a fresh option.
        let avoid = max(0, min(learner.recentShapes.count, pool.count - 1))
        let recent = Set(avoid > 0 ? learner.recentShapes.suffix(avoid) : [])
        let fresh = pool.filter { !recent.contains($0.id) }
        return (fresh.isEmpty ? pool : fresh).randomElement() ?? pool[0]
    }

    private func runTrial() async -> AttemptOutcome {
        abort = false
        trialsThisSession += 1
        var plan = learner.planTrial()
        let shape = chooseShape(level: plan.level, width: plan.width)
        // Honour the shape's cap even when nothing in the pool could take the
        // full planned width, and record the width actually shown.
        plan.width = min(plan.width, shape.maxWidth ?? Limits.maxWidth)

        board.setTrial(shape: shape, corridorUnits: plan.width)
        fx.clear()

        // Only the opening few trials get an unprompted demonstration. After
        // that it's on request — the yellow button appears if she stalls, and
        // the voice offers rather than just launching into it.
        let needsDemo = trialsThisSession < autoDemoTrials

        await voice.say(Lines.challenge(shape))
        if abort { return .panel }

        // If they cut the demonstration short by starting to trace, don't talk
        // over them with "now you try" — they already are.
        let demoFinished = needsDemo ? await showDemo(shape) : true
        if abort { return .panel }
        if demoFinished { await voice.say(Lines.yourTurn()) }
        if abort { return .panel }

        let outcome = await awaitAttempt(shape: shape)
        if outcome == .panel { return .panel }

        let verdict = board.judge()

        // The measurement is the first attempt at a shape — that's what feeds
        // the 85% estimate. The retry below is practice, not data.
        learner.record(
            TrialRecord(
                win: verdict.win, probe: plan.probe, width: plan.width, level: plan.level,
                shapeId: shape.id))
        Store.save(learner, settings)

        if verdict.win {
            lastFailedShape = nil
            await reward()
            return .done
        }

        lastFailedShape = shape.id
        sfx.nearMiss()
        await voice.say(Lines.encourage(verdict.reason))
        if abort { return .panel }

        await retry(shape: shape, plan: plan)
        return .done
    }

    /// Returns false if the child cut the demonstration short.
    @discardableResult
    private func showDemo(_ shape: Shape) async -> Bool {
        if skipDemoForTest { return true }
        demoedThisSession.insert(shape.id)
        await voice.say(Lines.demoIntro())
        if abort { return false }
        let finished = await board.runDemo { [weak self] i, n in
            guard let self else { return }
            if let line = Lines.strokePart(i, of: n) { Task { await self.voice.say(line) } }
            self.sfx.tick()
        }
        if !finished { voice.stop() }
        return finished
    }

    private func retry(shape: Shape, plan: TrialPlan) async {
        await voice.say(Lines.tryAgain())
        if abort { return }
        let wider = min(Limits.maxWidth, shape.maxWidth ?? Limits.maxWidth, plan.width * 1.22)
        board.setTrial(shape: shape, corridorUnits: wider)
        let demoFinished = await showDemo(shape)
        if abort { return }
        if demoFinished { await voice.say(Lines.yourTurn()) }
        let outcome = await awaitAttempt(shape: shape)
        if outcome == .panel { return }
        if board.judge().win {
            lastFailedShape = nil
            await reward(forceSmall: true)
        } else {
            sfx.nearMiss()
            await voice.say(Lines.movingOn)
        }
    }

    // MARK: - Waiting for the child

    private func awaitAttempt(shape: Shape) async -> AttemptOutcome {
        await withCheckedContinuation { (cont: CheckedContinuation<AttemptOutcome, Never>) in
            attemptCont = cont

            if helpSticky { helpButton.isHidden = false }

            idleTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(idleDelay * 1_000_000_000))
                guard !Task.isCancelled, attemptCont != nil else { return }
                showHelpButton()
                await voice.say(Lines.idleNudge())
            }

            onHelp = { [weak self] in
                guard let self else { return }
                settleTask?.cancel()
                idleTask?.cancel()
                board.clearInk()
                let complete = await showDemo(shape)
                if attemptCont != nil, complete { await voice.say(Lines.yourTurn()) }
            }

            board.onFirstTouch = { [weak self] in
                self?.idleTask?.cancel()
                self?.voice.stop()
            }

            board.onLeave = { [weak self] in self?.sfx.bump() }

            board.onStrokeEnd = { [weak self] in
                guard let self else { return }
                settleTask?.cancel()
                if board.looksFinished() {
                    finishAttempt(.done)
                } else {
                    settleTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(settleDelay * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        self?.finishAttempt(.settled)
                    }
                }
            }

            // An eager child may have traced the whole thing during the demo,
            // before any of the handlers above existed. Pick that attempt up
            // rather than waiting for a stroke that already happened.
            if !board.isDrawing && board.drawnLen > 0 {
                idleTask?.cancel()
                if board.looksFinished() {
                    finishAttempt(.done)
                } else {
                    settleTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(settleDelay * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        self?.finishAttempt(.settled)
                    }
                }
            }
        }
    }

    private func finishAttempt(_ outcome: AttemptOutcome) {
        guard let cont = attemptCont else { return }
        attemptCont = nil
        idleTask?.cancel()
        settleTask?.cancel()
        board.onStrokeEnd = nil
        board.onFirstTouch = nil
        board.onLeave = nil
        onHelp = nil
        cont.resume(returning: outcome)
    }

    private func showHelpButton() {
        helpSticky = true
        guard helpButton.isHidden else { return }
        helpButton.isHidden = false
        helpButton.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.6) {
            self.helpButton.transform = .identity
        }
    }

    @objc private func helpTapped() {
        guard let handler = onHelp else { return }
        Task { await handler() }
    }

    // MARK: - Reward

    private func reward(forceSmall: Bool = false) async {
        sinceBig += 1
        let big =
            !forceSmall && !lastWasBig && (sinceBig >= bigForceAfter || CGFloat.random(in: 0..<1) < bigChance)
        lastWasBig = big
        if big { sinceBig = 0 }

        board.freeze(true)
        fx.traceGlow(board.allCheckpoints())

        if big {
            // Never the same big one twice running — the variety is what makes
            // it register as special rather than as the usual noise.
            let kind = BigCelebration.allCases.filter { $0 != lastBigKind }.randomElement()!
            lastBigKind = kind
            sfx.bigWin()
            fx.big(kind)
            await voice.say(kind.line)
            try? await Task.sleep(nanoseconds: UInt64(kind.duration * 1_000_000_000))
        } else {
            sfx.smallWin()
            fx.small(at: board.boardCentre)
            await voice.say(Lines.praise())
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        fx.clear()
        await announceUnlocks()
        board.freeze(abort)
    }

    /// Hand over any pens her progress has just earned.
    private func announceUnlocks() async {
        let available = Pens.unlocked(for: learner)
        let known = Set(penBar.pens.map(\.id))
        let fresh = available.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }

        penBar.setPens(available, selected: pen, animated: true)
        layoutPenBar()

        sfx.bigWin()
        fx.big(.fireworks)
        // Several pens can arrive together; one sentence covers the batch.
        for line in Set(fresh.map { $0.unlock.announcement }).sorted() where !line.isEmpty {
            await voice.say(line)
        }
        try? await Task.sleep(nanoseconds: 900_000_000)
        fx.clear()

        // Switch her onto the newest pen so the reward is immediately visible.
        if let newest = fresh.last {
            pen = newest
            board.pen = newest
            penBar.select(newest)
            settings.penId = newest.id
            Store.save(learner, settings)
        }
    }

    // MARK: - Grown-up panel

    @objc private func cornerHeld(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, presentedViewController == nil else { return }
        openPanel()
    }

    private func openPanel() {
        abort = true
        voice.stop()
        board.stopDemo()
        board.freeze(true)
        finishAttempt(.panel)
        loopTask?.cancel()
        loopTask = nil

        let panel = ParentPanelViewController(
            learner: learner, settings: settings,
            onChange: { [weak self] s in
                guard let self else { return }
                settings = s
                voice.enabled = s.voice
                voice.rate = s.rate
                sfx.enabled = s.sound
                Store.save(learner, settings)
            },
            onReset: { [weak self] in
                guard let self else { return }
                learner = Learner()
                demoedThisSession.removeAll()
                Store.save(learner, settings)
            },
            onClose: { [weak self] in
                self?.dismiss(animated: true) { [weak self] in
                    guard let self else { return }
                    self.abort = false
                    self.board.freeze(false)
                    self.startLoop()
                }
            })
        let nav = UINavigationController(rootViewController: panel)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }
}
