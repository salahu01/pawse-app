import AVFoundation

/// Procedurally synthesized cute voices. No audio files needed.
final class SoundFX {
    static let shared = SoundFX()
    enum Cue { case ask, happy, sad, goal }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sr: Double = 44100
    private let format: AVAudioFormat
    private var stepTimer: Timer?
    private var filePlayer: AVAudioPlayer?

    /// Drop real clips here named <species>_<cue>.(wav|mp3|m4a|aiff), e.g. cat_ask.mp3
    static let customDir: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pawse/Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        let readme = u.appendingPathComponent("README.txt")
        if !FileManager.default.fileExists(atPath: readme.path) {
            try? """
            Put real sound clips here to replace the built-in synthesized voices.
            Name them <pet>_<moment>.<ext>
              pet:    cat, penguin, capybara, bunny
              moment: ask, happy, sad
              ext:    wav, mp3, m4a, aiff
            Example: cat_ask.mp3, cat_happy.wav, cat_sad.m4a
            """.write(to: readme, atomically: true, encoding: .utf8)
        }
        return u
    }()

    /// Looks for <pet>_<variant> (e.g. kid_ask_1, kid_plead, kid_goal) then <pet>_<cue>,
    /// first in the custom folder, then in the app bundle.
    private func customFile(_ cue: Cue, _ species: Species, variant: String?) -> URL? {
        let name: String
        switch cue { case .ask: name = "ask"; case .happy: name = "happy"; case .sad: name = "sad"; case .goal: return nil }
        for n in [variant, name].compactMap({ $0 }).map({ "\(species.rawValue)_\($0)" }) {
            for ext in ["wav", "mp3", "m4a", "aiff", "caf"] {
                let u = Self.customDir.appendingPathComponent("\(n).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { return u }
            }
            if let u = Bundle.main.url(forResource: n, withExtension: "wav") { return u }
        }
        return nil
    }

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }

    func play(_ cue: Cue, species: Species, variant: String? = nil) {
        let s = Store.shared
        guard s.soundOn else { return }
        if let url = customFile(cue, species, variant: variant), let p = try? AVAudioPlayer(contentsOf: url) {
            p.volume = Float(s.volume)
            p.play()
            filePlayer = p
            if cue == .happy { schedule(chime(goal: false), gain: Float(s.volume)) }
            return
        }
        var buf: [Float]
        switch (cue, species) {
        case (.ask, .cat): buf = meow(pitch: 1, length: 0.75)
        case (.happy, .cat): buf = meow(pitch: 1.35, length: 0.35) + silence(0.06) + meow(pitch: 1.5, length: 0.3)
        case (.sad, .cat): buf = meow(pitch: 0.8, length: 1.0, sad: true)
        case (.ask, .penguin): buf = chirp(1300, 1900, 0.12) + silence(0.05) + chirp(1400, 2100, 0.14)
        case (.happy, .penguin): buf = (0..<4).flatMap { i in chirp(1500 + Double(i) * 150, 2400, 0.08) + silence(0.035) }
        case (.sad, .penguin): buf = chirp(1500, 800, 0.45)
        case (.ask, .capybara): buf = wheek(0.22) + silence(0.07) + wheek(0.3)
        case (.happy, .capybara): buf = purr(0.5) + wheek(0.18, up: 1.25) + silence(0.04) + wheek(0.18, up: 1.35)
        case (.sad, .capybara): buf = wheek(0.6, up: 0.75, falling: true)
        case (.ask, .bunny): buf = ghost(0.5, from: 1.0, to: 1.35) + silence(0.05) + ghost(0.35, from: 1.3, to: 1.6)
        case (.happy, .bunny): buf = sparkle()
        case (.sad, .bunny): buf = ghost(0.9, from: 1.2, to: 0.75)
        case (.ask, .kid): buf = hum(0.18, 1.5) + silence(0.04) + hum(0.26, 1.9, rise: 0.15)
        case (.happy, .kid): buf = gulp() + silence(0.08) + hum(0.14, 1.9) + hum(0.14, 2.25) + hum(0.3, 2.5, rise: 0.1)
        case (.sad, .kid): buf = hum(0.25, 1.6) + hum(0.5, 1.3, rise: -0.25)
        case (.goal, _): buf = []
        case (.ask, _): buf = chirp(900, 1300, 0.15) + silence(0.05) + chirp(1000, 1500, 0.18)
        case (.happy, _): buf = (0..<3).flatMap { i in chirp(1100 + Double(i) * 150, 1800, 0.09) + silence(0.04) }
        case (.sad, _): buf = chirp(1200, 700, 0.5)
        }
        if cue == .happy || cue == .goal { buf = mix(buf, chime(goal: cue == .goal), at: cue == .goal ? 0 : 0.15) }
        schedule(buf, gain: Float(s.volume))
    }

    /// Soft paw-pad taps while the pet walks.
    func startSteps(species: Species) {
        stopSteps()
        guard Store.shared.soundOn, species != .bunny else { return }   // ghosts float silently
        var left = true
        let interval = species == .penguin ? 0.2 : 0.17
        stepTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.schedule(self.tap(pitch: left ? 1 : 1.12, squeak: species == .penguin), gain: Float(Store.shared.volume) * 0.35)
            left.toggle()
        }
    }
    func stopSteps() { stepTimer?.invalidate(); stepTimer = nil }

    // MARK: voices

    /// Realistic "m-i-a-ow": jittery glottal pulse + breath, filtered by moving
    /// vocal-tract formants (time-varying resonators), plus a tiny room echo.
    private func meow(pitch: Double, length: Double, sad: Bool = false) -> [Float] {
        let n = Int(length * sr)
        var out = [Float](repeating: 0, count: n)
        // (time, F1, F2, F3, mouth opening)
        let keys: [(Double, Double, Double, Double, Double)] = [
            (0.00, 300, 1300, 2700, 0.15),  // m (closed)
            (0.12, 450, 2300, 3300, 0.6),   // i
            (0.45, 1000, 1750, 3000, 1.0),  // a
            (0.80, 650, 1100, 2700, 0.7),   // o
            (1.00, 450, 900, 2600, 0.2),    // w (closing)
        ]
        func at(_ p: Double) -> (Double, Double, Double, Double) {
            var j = 0
            while j < keys.count - 2 && p > keys[j + 1].0 { j += 1 }
            let a = keys[j], b = keys[j + 1]
            var u = (p - a.0) / (b.0 - a.0); u = max(0, min(1, u)); u = u * u * (3 - 2 * u)
            return (a.1 + (b.1 - a.1) * u, a.2 + (b.2 - a.2) * u, a.3 + (b.3 - a.3) * u, a.4 + (b.4 - a.4) * u)
        }
        var res = [Resonator(), Resonator(), Resonator()]
        var phase = 0.0, jitter = 0.0, shimmer = 1.0, breath = 0.0, lp = 0.0
        let base = 620 * pitch
        for i in 0..<n {
            let p = Double(i) / Double(n)
            // pitch contour: rise then fall (sad = steady droop)
            let contour = sad ? 1.05 - 0.4 * p
                              : (p < 0.3 ? 0.9 + 0.55 * (p / 0.3) * (2 - p / 0.3) * 0.5 : 1.17 - 0.5 * (p - 0.3))
            if i % 300 == 0 {
                jitter = jitter * 0.6 + Double.random(in: -1...1) * 0.012
                shimmer = 1 + Double.random(in: -0.08...0.08)
            }
            let f0 = base * contour * (1 + jitter + 0.01 * sin(2 * .pi * 5.5 * Double(i) / sr))
            phase += f0 / sr
            phase -= floor(phase)
            // glottal pulse (Rosenberg-like): open phase hump, sharp closure
            let oq = 0.6
            let g = phase < oq ? 0.5 * (1 - cos(.pi * phase / oq)) * (phase < oq * 0.8 ? 1 : (oq - phase) / (oq * 0.2)) : 0
            let dg = g - lp; lp = g          // derivative = radiated flow, brighter
            breath = breath * 0.3 + Double.random(in: -1...1) * 0.7
            let src = dg * 6 * shimmer + breath * (0.04 + 0.08 * g) + breath * (p > 0.85 ? 0.05 : 0)
            let (f1, f2, f3, open) = at(p)
            let bw = 1 + 0.5 * (1 - open)  // closed mouth = damped
            let v = res[0].process(src, f: f1, bw: 110 * bw, sr: sr) * 1.0
                  + res[1].process(src, f: f2, bw: 160 * bw, sr: sr) * 0.55
                  + res[2].process(src, f: f3, bw: 250 * bw, sr: sr) * 0.25
            out[i] = Float(v * (0.25 + 0.75 * open) * env(p, attack: 0.06, release: 0.18))
        }
        // small room: two short echoes
        for (d, gain) in [(0.023, 0.18), (0.041, 0.1)] {
            let k = Int(d * sr)
            for i in stride(from: n - 1, through: k, by: -1) { out[i] += out[i - k] * Float(gain) }
        }
        let peak = out.map(abs).max() ?? 1
        return peak > 0 ? out.map { $0 / peak * 0.55 } : out
    }

    /// Squeaky penguin chirp: pitch sweep, a little buzz.
    private func chirp(_ from: Double, _ to: Double, _ len: Double) -> [Float] {
        let n = Int(len * sr)
        var phase = 0.0
        return (0..<n).map { i in
            let p = Double(i) / Double(n)
            let f = from + (to - from) * (p * p * (3 - 2 * p))
            phase += f / sr
            let x = sin(2 * .pi * phase) + 0.35 * sin(4 * .pi * phase) + 0.15 * sin(6 * .pi * phase)
            return Float(x * env(p, attack: 0.1, release: 0.3) * 0.22)
        }
    }

    /// Guinea-pig/capybara style "wheek": breathy rising squeak.
    private func wheek(_ len: Double, up: Double = 1, falling: Bool = false) -> [Float] {
        let n = Int(len * sr)
        var phase = 0.0
        var noise: Double = 0
        return (0..<n).map { i in
            let p = Double(i) / Double(n)
            let rise = falling ? 1.15 - p * 0.5 : 0.8 + p * 0.5
            let f = 900 * up * rise
            phase += f / sr
            noise = noise * 0.7 + Double.random(in: -1...1) * 0.3
            let x = sin(2 * .pi * phase) * 0.8 + sin(4 * .pi * phase) * 0.25 + noise * 0.25
            return Float(x * env(p, attack: 0.15, release: 0.4) * 0.2)
        }
    }

    /// Soft wobbly "ooo~" ghost voice: sine + octave, vibrato, airy breath, echo.
    private func ghost(_ len: Double, from: Double, to: Double) -> [Float] {
        let n = Int(len * sr)
        var phase = 0.0, noise = 0.0
        var out: [Float] = (0..<n).map { i in
            let p = Double(i) / Double(n), t = Double(i) / sr
            let f = 520 * (from + (to - from) * p) * (1 + 0.03 * sin(2 * .pi * 7 * t))
            phase += f / sr
            noise = noise * 0.9 + Double.random(in: -1...1) * 0.1
            let x = sin(2 * .pi * phase) + 0.25 * sin(4 * .pi * phase) + noise * 0.6
            return Float(x * env(p, attack: 0.25, release: 0.4) * 0.18)
        }
        for (d, g) in [(0.09, 0.35), (0.18, 0.18)] {
            let k = Int(d * sr)
            out += [Float](repeating: 0, count: k)
            for i in stride(from: out.count - 1, through: k, by: -1) { out[i] += out[i - k] * Float(g) }
        }
        return out
    }

    /// Twinkly upward glissando of tiny bells.
    private func sparkle() -> [Float] {
        let notes: [Double] = [1568, 1760, 2093, 2349, 2637, 3136]
        var out = [Float](repeating: 0, count: Int(1.0 * sr))
        for (j, f) in notes.enumerated() {
            let st = Int(Double(j) * 0.06 * sr)
            for i in 0..<Int(0.4 * sr) where st + i < out.count {
                let t = Double(i) / sr
                out[st + i] += Float(sin(2 * .pi * f * t) * exp(-t * 9) * 0.08)
            }
        }
        return ghost(0.3, from: 1.4, to: 1.8) + out
    }

    /// Cheerful hummed syllable ("mm!"): soft sine with a little brightness, no echo.
    private func hum(_ len: Double, _ pitch: Double, rise: Double = 0) -> [Float] {
        let n = Int(len * sr)
        var phase = 0.0
        return (0..<n).map { i in
            let p = Double(i) / Double(n), t = Double(i) / sr
            let f = 320 * pitch * (1 + rise * p) * (1 + 0.015 * sin(2 * .pi * 6 * t))
            phase += f / sr
            let x = sin(2 * .pi * phase) + 0.3 * sin(4 * .pi * phase) + 0.1 * sin(6 * .pi * phase)
            return Float(x * env(p, attack: 0.12, release: 0.35) * 0.2)
        }
    }

    /// Two cartoon "gulp" bloops (falling sine plops).
    private func gulp() -> [Float] {
        func plop() -> [Float] {
            let n = Int(0.09 * sr)
            return (0..<n).map { i in
                let t = Double(i) / sr
                return Float(sin(2 * .pi * (700 - 4000 * t) * t) * exp(-t * 30) * 0.35)
            }
        }
        return plop() + silence(0.12) + plop()
    }

    /// Low contented rumble.
    private func purr(_ len: Double) -> [Float] {
        let n = Int(len * sr)
        var noise: Double = 0
        return (0..<n).map { i in
            let t = Double(i) / sr, p = Double(i) / Double(n)
            noise = noise * 0.95 + Double.random(in: -1...1) * 0.05
            let pulse = 0.5 + 0.5 * sin(2 * .pi * 24 * t)
            let x = (sin(2 * .pi * 95 * t) * 0.6 + noise * 3) * pulse
            return Float(x * env(p, attack: 0.2, release: 0.3) * 0.25)
        }
    }

    /// Sparkly bell arpeggio.
    private func chime(goal: Bool) -> [Float] {
        let notes: [Double] = goal ? [1047, 1319, 1568, 2093, 2637] : [1319, 1568, 2093]
        let gap = 0.08, tail = 0.6
        var out = [Float](repeating: 0, count: Int((Double(notes.count) * gap + tail) * sr))
        for (j, f) in notes.enumerated() {
            let start = Int(Double(j) * gap * sr)
            for i in 0..<Int(tail * sr) where start + i < out.count {
                let t = Double(i) / sr
                let x = (sin(2 * .pi * f * t) + 0.3 * sin(2 * .pi * f * 2.76 * t)) * exp(-t * 7)
                out[start + i] += Float(x * 0.07)
            }
        }
        return out
    }

    private func tap(pitch: Double, squeak: Bool) -> [Float] {
        let n = Int(0.05 * sr)
        return (0..<n).map { i in
            let t = Double(i) / sr
            let f = (squeak ? 900 : 260) * pitch
            return Float(sin(2 * .pi * f * t) * exp(-t * 90) * 0.5)
        }
    }

    // MARK: helpers
    private func env(_ p: Double, attack: Double, release: Double) -> Double {
        p < attack ? p / attack : (p > 1 - release ? max(0, (1 - p) / release) : 1)
    }
    private func silence(_ s: Double) -> [Float] { [Float](repeating: 0, count: Int(s * sr)) }
    private func mix(_ a: [Float], _ b: [Float], at offset: Double) -> [Float] {
        let o = Int(offset * sr)
        var out = a + [Float](repeating: 0, count: max(0, o + b.count - a.count))
        for i in 0..<b.count { out[o + i] += b[i] }
        return out
    }

    private func schedule(_ samples: [Float], gain: Float) {
        guard !samples.isEmpty,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buf.frameLength = buf.frameCapacity
        let ch = buf.floatChannelData![0]
        for i in 0..<samples.count { ch[i] = max(-1, min(1, samples[i] * gain)) }
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buf, at: nil, options: [])
        if !player.isPlaying { player.play() }
    }
}

/// Two-pole resonant bandpass, retuned per sample.
private struct Resonator {
    var y1 = 0.0, y2 = 0.0
    mutating func process(_ x: Double, f: Double, bw: Double, sr: Double) -> Double {
        let r = exp(-.pi * bw / sr)
        let c = 2 * r * cos(2 * .pi * f / sr)
        let y = (1 - r) * x + c * y1 - r * r * y2
        y2 = y1; y1 = y
        return y
    }
}
