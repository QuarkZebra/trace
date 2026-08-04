import AVFoundation
import Foundation

// Voice and sound. The child can't read, so speech carries every instruction —
// nothing important in this app is text-only.

private let preferredVoiceNames = [
    "Samantha", "Karen", "Moira", "Tessa", "Serena", "Allison", "Ava", "Nicky",
]

final class Voice: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var pending: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]
    private var chosen: AVSpeechSynthesisVoice?

    var enabled = true
    var rate: Float = 0.44

    override init() {
        super.init()
        synth.delegate = self
        chosen = Self.pickVoice()
    }

    private static func pickVoice() -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        for name in preferredVoiceNames {
            if let v = all.first(where: { $0.name == name }) { return v }
        }
        // Prefer a higher-quality voice if the child's iPad has one downloaded.
        return all.first { $0.quality != .default } ?? all.first
    }

    /// Speak, cancelling anything mid-sentence. Returns when the line finishes.
    @discardableResult
    func say(_ text: String) async -> Bool {
        guard enabled, !text.isEmpty else { return false }
        stop()
        let u = AVSpeechUtterance(string: text)
        u.voice = chosen
        u.rate = rate
        u.pitchMultiplier = 1.12
        u.postUtteranceDelay = 0.05

        let key = ObjectIdentifier(u)
        // Speech callbacks are reliable, but a wedged synthesiser would hang the
        // whole trial loop — so back it with a watchdog rather than trusting it.
        let guardTask = Task { [weak self] in
            let seconds = 1.5 + Double(text.count) * 0.09
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await MainActor.run { self?.finish(key) }
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            pending[key] = cont
            synth.speak(u)
        }
        guardTask.cancel()
        return true
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    @MainActor private func finish(_ key: ObjectIdentifier) {
        guard let cont = pending.removeValue(forKey: key) else { return }
        cont.resume()
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in finish(ObjectIdentifier(u)) }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in finish(ObjectIdentifier(u)) }
    }
}

// MARK: - Sound effects
//
// Synthesised at runtime so there are no audio files to ship or keep in sync.

final class Sfx {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var started = false

    var enabled = true

    func start() {
        guard !started else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
            player.play()
            started = true
        } catch {
            // A game that can't make noise is still a game; don't take the app
            // down over it.
            started = false
        }
    }

    private struct Tone {
        var freq: Double
        var start: Double
        var dur: Double
        var gain: Double
        var square = false
    }

    private func play(_ tones: [Tone], noiseAt: (start: Double, dur: Double, gain: Double)? = nil) {
        guard enabled, started else { return }
        let sr = 44100.0
        let end = max(
            tones.map { $0.start + $0.dur }.max() ?? 0,
            noiseAt.map { $0.start + $0.dur } ?? 0)
        let frames = AVAudioFrameCount(max(1, (end + 0.1) * sr))
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buf.frameLength = frames
        guard let ch = buf.floatChannelData?[0] else { return }
        for i in 0..<Int(frames) { ch[i] = 0 }

        for t in tones {
            let s = Int(t.start * sr)
            let n = Int(t.dur * sr)
            for i in 0..<n {
                let idx = s + i
                if idx >= Int(frames) { break }
                let time = Double(i) / sr
                // Quick attack, exponential decay — reads as a struck note.
                let env = min(1, time / 0.012) * exp(-3.2 * time / t.dur)
                let phase = 2 * Double.pi * t.freq * time
                let wave = t.square ? (sin(phase) >= 0 ? 0.6 : -0.6) : sin(phase)
                ch[idx] += Float(wave * env * t.gain)
            }
        }

        if let nz = noiseAt {
            let s = Int(nz.start * sr)
            let n = Int(nz.dur * sr)
            for i in 0..<n {
                let idx = s + i
                if idx >= Int(frames) { break }
                let fade = 1 - Double(i) / Double(n)
                ch[idx] += Float(Double.random(in: -1...1) * fade * nz.gain)
            }
        }

        player.scheduleBuffer(buf, completionHandler: nil)
    }

    func smallWin() {
        play(
            [523.25, 659.25, 783.99].enumerated().map {
                Tone(freq: $0.element, start: Double($0.offset) * 0.09, dur: 0.28, gain: 0.18)
            })
    }

    func bigWin() {
        var tones = [523.25, 659.25, 783.99, 1046.5, 1318.5].enumerated().map {
            Tone(freq: $0.element, start: Double($0.offset) * 0.075, dur: 0.5, gain: 0.16)
        }
        tones.append(Tone(freq: 261.63, start: 0.4, dur: 0.9, gain: 0.12))
        play(tones, noiseAt: (0.38, 0.5, 0.05))
    }

    func nearMiss() {
        play([
            Tone(freq: 392, start: 0, dur: 0.2, gain: 0.14),
            Tone(freq: 349.23, start: 0.16, dur: 0.3, gain: 0.12),
        ])
    }

    /// Soft click when the pen strays outside the corridor.
    func bump() {
        play([Tone(freq: 180, start: 0, dur: 0.07, gain: 0.07)])
    }

    func tick() {
        play([Tone(freq: 1200, start: 0, dur: 0.05, gain: 0.04)])
    }

    /// Picking up a different pen.
    func pop() {
        play([Tone(freq: 880, start: 0, dur: 0.09, gain: 0.07, square: true)])
    }
}
