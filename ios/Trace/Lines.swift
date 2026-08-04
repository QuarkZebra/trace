import Foundation

// Everything the app says out loud, in one place so it's easy to reword.
//
// Rules of thumb: short sentences, concrete verbs, no praise for being "smart"
// (praise the effort or the action), and coaching that names one physical thing
// to change rather than a general "try harder".

enum Lines {
    private static var lastPicked: [String: String] = [:]

    /// Pick from a bank without repeating the previous pick from that bank.
    private static func pick(_ key: String, _ bank: [String]) -> String {
        let prev = lastPicked[key]
        let options = bank.count > 1 ? bank.filter { $0 != prev } : bank
        let choice = options.randomElement() ?? bank[0]
        lastPicked[key] = choice
        return choice
    }

    static func welcome() -> String {
        pick(
            "welcome",
            [
                "Hi! Let's trace some shapes. Stay inside the lines!",
                "Ready to trace? Try to keep your line inside the track.",
            ])
    }

    static func challenge(_ shape: Shape) -> String {
        let n = shape.name
        return pick(
            "challenge",
            [
                "Can you trace this \(n) without going outside the lines?",
                "Here's a \(n). Try to stay inside the lines.",
                "Let's trace a \(n). Keep your line in the middle.",
                "A \(n)! See if you can stay inside the track.",
            ])
    }

    static func yourTurn() -> String {
        pick(
            "turn",
            [
                "Now you try. Start on the green dot.",
                "Your turn! Start on the green dot.",
                "Okay, you go. Begin at the green dot.",
            ])
    }

    static func demoIntro() -> String {
        pick("demoIntro", ["Watch me first.", "I'll show you.", "Watch how it goes."])
    }

    static func strokePart(_ i: Int, of total: Int) -> String? {
        guard total > 1 else { return nil }
        if i == 0 { return "First, this part." }
        if i == total - 1 { return "And the last part." }
        return "Now the next part."
    }

    /// Offered only when she's stalled — after the first few trials we stop
    /// demonstrating unprompted and ask instead.
    static func idleNudge() -> String {
        pick(
            "idle",
            [
                "Would you like me to show you? Tap the yellow button.",
                "Want to see it first? Tap the yellow button.",
                "Shall I show you how? Tap the yellow button.",
            ])
    }

    static func praise() -> String {
        pick(
            "praise",
            [
                "You did it!", "Nice tracing!", "You stayed inside the lines!",
                "That was great!", "Wow, right down the middle!", "Beautiful line!",
                "You kept it steady!",
            ])
    }


    /// Near-miss coaching: a warm opener, then exactly one short physical
    /// instruction. Long explanations lose a four-year-old.
    static func encourage(_ reason: Judgement.Reason) -> String {
        let opener = pick("opener", ["Ooh, so close!", "Almost!", "So close!", "Nearly had it!"])
        let tips: [String]
        switch reason {
        case .outside, .win:
            tips = [
                "Go slowly, like a turtle.",
                "Hold your pencil close to the tip.",
                "Rest your hand on the screen.",
                "Keep your eyes right on the line.",
                "Pinch the pencil with two fingers and your thumb.",
                "Little bit slower this time.",
            ]
        case .almost:
            tips = [
                "Keep going all the way to the end.",
                "Follow the track right to the finish.",
                "Trace the whole thing this time.",
            ]
        case .unfinished:
            tips = [
                "Start on the green dot and follow the track.",
                "Try tracing the whole shape.",
                "Watch the orange dot, then copy it.",
            ]
        case .scribble:
            tips = [
                "One smooth line, all the way around.",
                "Try one slow line instead of back and forth.",
            ]
        }
        return "\(opener) \(pick("tip-\(reason)", tips))"
    }

    static func tryAgain() -> String {
        pick(
            "again",
            ["Let's try that one again.", "One more go at this one.", "Try it again."])
    }

    static let movingOn = "Good trying! Let's do a different one."
}
