import Foundation

// Real-time-safe DSP building blocks. Everything here is plain value types with no allocation,
// locks or Objective-C, so it can run inside an AVAudioSourceNode render block.

/// xorshift32 white noise in [-1, 1).
struct NoiseRNG: Sendable {
    private var state: UInt32

    init(seed: UInt32) { state = seed == 0 ? 0x9E37_79B9 : seed }

    mutating func nextUInt() -> UInt32 {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return state
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Float { Float(nextUInt() >> 8) * (1.0 / 16_777_216.0) }

    /// Uniform in [-1, 1).
    mutating func next() -> Float { unit() * 2 - 1 }
}

/// Transposed direct form II biquad (RBJ cookbook coefficients).
struct Biquad: Sendable {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    private var z1: Float = 0, z2: Float = 0

    enum Kind: Sendable { case lowpass, highpass, bandpass }

    init() {}

    init(_ kind: Kind, frequency: Float, q: Float, sampleRate: Float) {
        setCoefficients(kind, frequency: frequency, q: q, sampleRate: sampleRate)
    }

    mutating func setCoefficients(_ kind: Kind, frequency: Float, q: Float, sampleRate: Float) {
        let f = min(max(frequency, 10), sampleRate * 0.45)
        let w0 = 2 * Float.pi * f / sampleRate
        let cosw = cos(w0), alpha = sin(w0) / (2 * max(q, 0.05))
        let a0 = 1 + alpha
        switch kind {
        case .lowpass:
            b0 = (1 - cosw) / 2 / a0; b1 = (1 - cosw) / a0; b2 = b0
        case .highpass:
            b0 = (1 + cosw) / 2 / a0; b1 = -(1 + cosw) / a0; b2 = b0
        case .bandpass:
            b0 = alpha / a0; b1 = 0; b2 = -alpha / a0
        }
        a1 = -2 * cosw / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

/// Paul Kellet's refined pink filter (-3 dB/octave, within 0.05 dB above 9 Hz at 44.1 kHz).
struct PinkFilter: Sendable {
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0

    mutating func process(_ white: Float) -> Float {
        b0 = 0.99886 * b0 + white * 0.0555179
        b1 = 0.99332 * b1 + white * 0.0750759
        b2 = 0.96900 * b2 + white * 0.1538520
        b3 = 0.86650 * b3 + white * 0.3104856
        b4 = 0.55000 * b4 + white * 0.5329522
        b5 = -0.7616 * b5 - white * 0.0168980
        let out = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
        b6 = white * 0.115926
        return out * 0.11
    }
}

/// Leaky integrator: -6 dB/octave (brown / red noise) above ~140 Hz at 44.1 kHz.
struct BrownFilter: Sendable {
    private var y: Float = 0

    mutating func process(_ white: Float) -> Float {
        y = (y + 0.02 * white) / 1.02
        return y * 3.5
    }
}

/// One-pole low-pass used for gentle tone shaping and parameter smoothing.
struct OnePole: Sendable {
    var coefficient: Float = 0
    private(set) var y: Float = 0

    init(coefficient: Float = 0) { self.coefficient = coefficient }

    static func coefficient(cutoff: Float, sampleRate: Float) -> Float {
        exp(-2 * Float.pi * cutoff / sampleRate)
    }

    mutating func process(_ x: Float) -> Float {
        y = x + coefficient * (y - x)
        return y
    }

    mutating func reset(_ value: Float) { y = value }
}

@inline(__always) func clampUnit(_ x: Float) -> Float { min(1, max(-1, x)) }

/// Generates one sound. A value type with no allocation; the audio thread owns its copy.
struct SoundGenerator: Sendable {
    let kind: SoundKind
    let sampleRate: Float
    private(set) var params: SoundParams

    private var rng: NoiseRNG
    private var pink = PinkFilter()
    private var brown = BrownFilter()
    private var brown2 = BrownFilter()
    private var toneLP = Biquad()
    private var toneLP2 = Biquad()
    private var shapeHP = Biquad()
    private var band = Biquad()
    private var bypassTone = true
    private var gain: Float = 1
    // modulation state
    private var phase: Double = 0
    private var lfoPhase: Double = 0
    private var dropEnv: Float = 0
    private var dropColor = Biquad()
    private var rumbleEnv: Float = 0
    private var rumbleTarget: Float = 0
    private var waveEnv = OnePole()
    private var countdown: Int = 0

    init(kind: SoundKind, sampleRate: Float = 44_100, seed: UInt32 = 0x1234_5678, params: SoundParams = SoundParams()) {
        self.kind = kind
        self.sampleRate = sampleRate
        self.params = params
        self.rng = NoiseRNG(seed: seed &+ UInt32(kind.index) &* 7919)
        configure()
    }

    mutating func setParams(_ newValue: SoundParams) {
        guard newValue != params else { return }
        params = newValue
        configure()
    }

    private mutating func configure() {
        let tone = min(max(params.tone, 0), 1)
        let intensity = min(max(params.intensity, 0), 1)
        let sr = sampleRate
        // Noise colors: tone 1 = unfiltered, lower = darker (low-pass from ~20 kHz down to ~300 Hz).
        let cutoff = 300 * pow(Float(60), tone)
        bypassTone = tone >= 0.999
        toneLP.setCoefficients(.lowpass, frequency: cutoff, q: 0.707, sampleRate: sr)
        switch kind {
        case .white, .pink, .brown:
            gain = 0.35 + 0.65 * intensity
        case .green:
            // Band-limited around the middle of the audible range; tone moves the center.
            band.setCoefficients(.bandpass, frequency: 250 + 750 * tone, q: 0.6, sampleRate: sr)
            gain = (0.35 + 0.65 * intensity) * 2.2
        case .fan:
            toneLP.setCoefficients(.lowpass, frequency: 350 + 1800 * tone, q: 0.6, sampleRate: sr)
            toneLP2.setCoefficients(.lowpass, frequency: 4000, q: 0.5, sampleRate: sr)
            gain = 1.1
        case .rain:
            shapeHP.setCoefficients(.highpass, frequency: 400 + 1600 * tone, q: 0.5, sampleRate: sr)
            dropColor.setCoefficients(.bandpass, frequency: 1800 + 3200 * tone, q: 1.2, sampleRate: sr)
            gain = 0.5 + 0.5 * intensity
        case .ocean:
            toneLP.setCoefficients(.lowpass, frequency: 500 + 2500 * tone, q: 0.6, sampleRate: sr)
            waveEnv.coefficient = OnePole.coefficient(cutoff: 0.6, sampleRate: sr)
            gain = 1.4
        case .thunder:
            toneLP.setCoefficients(.lowpass, frequency: 120 + 600 * tone, q: 0.7, sampleRate: sr)
            gain = 2.0
        case .hum:
            toneLP.setCoefficients(.lowpass, frequency: 900, q: 0.5, sampleRate: sr)
            gain = 0.25 + 0.35 * intensity
        }
    }

    mutating func nextSample() -> Float {
        let w = rng.next()
        let tone = params.tone, intensity = params.intensity
        var out: Float
        switch kind {
        case .white:
            out = w * 0.6
            if !bypassTone { out = toneLP.process(out) }
        case .pink:
            out = pink.process(w)
            if !bypassTone { out = toneLP.process(out) }
        case .brown:
            out = brown.process(w)
            if !bypassTone { out = toneLP.process(out) }
        case .green:
            out = band.process(pink.process(w))
        case .fan:
            // Low-passed pink/brown air plus a gentle blade-rate amplitude flutter.
            let air = toneLP.process(pink.process(w) * 0.7 + brown.process(w) * 0.5)
            let bladeHz = 2.0 + 10.0 * Double(intensity)
            lfoPhase += bladeHz / Double(sampleRate)
            if lfoPhase >= 1 { lfoPhase -= 1 }
            let flutter = 1 - 0.12 * Float(0.5 + 0.5 * sin(2 * Double.pi * lfoPhase))
            out = toneLP2.process(air * flutter)
        case .rain:
            // Hiss bed plus randomly timed droplets; intensity sets drop density.
            let bed = shapeHP.process(pink.process(w)) * (0.35 + 0.45 * intensity)
            let dropsPerSecond = 15 + 400 * intensity * intensity
            if rng.unit() < dropsPerSecond / sampleRate { dropEnv = 0.4 + 0.6 * rng.unit() }
            dropEnv *= 0.9965
            let drop = dropColor.process(w * dropEnv) * 1.2
            out = bed + drop
        case .ocean:
            // Brown surf swelling with a slow, slightly irregular wave cycle.
            let waveHz = 0.05 + 0.12 * Double(intensity)
            phase += waveHz / Double(sampleRate)
            if phase >= 1 { phase -= 1 }
            let swell = Float(0.5 - 0.5 * cos(2 * Double.pi * phase))
            let env = waveEnv.process(0.15 + 0.85 * swell * swell)
            out = toneLP.process(brown.process(w) * 0.6 + pink.process(w) * 0.4) * env
        case .thunder:
            // Low rumble with occasional long rolls; intensity sets how often they come.
            if countdown <= 0 {
                let seconds = 4 + (1 - intensity) * 16 * (0.5 + rng.unit())
                countdown = Int(seconds * sampleRate)
                rumbleTarget = 0.6 + 0.4 * rng.unit()
            }
            countdown -= 1
            rumbleEnv += (rumbleTarget - rumbleEnv) * 0.0004
            rumbleTarget *= 0.99996
            let bed = brown2.process(w) * 0.25
            out = toneLP.process(brown.process(w) * (0.2 + rumbleEnv)) + bed * 0.5
        case .hum:
            // Mains-style hum: fundamental plus soft harmonics, filtered and slowly wobbling.
            let f0 = 40 + 40 * Double(tone)
            phase += f0 / Double(sampleRate)
            if phase >= 1 { phase -= 1 }
            lfoPhase += 0.1 / Double(sampleRate)
            if lfoPhase >= 1 { lfoPhase -= 1 }
            let p = 2 * Double.pi * phase
            let s = sin(p) + 0.5 * sin(2 * p) + 0.25 * sin(3 * p) + 0.12 * sin(4 * p)
            let wobble = 0.9 + 0.1 * sin(2 * Double.pi * lfoPhase)
            out = toneLP.process(Float(s * wobble) * 0.5 + w * 0.01)
        }
        return clampUnit(out * gain)
    }

    mutating func render(into buffer: UnsafeMutablePointer<Float>, count: Int) {
        for i in 0..<count { buffer[i] = nextSample() }
    }

    mutating func samples(_ count: Int) -> [Float] {
        var a = [Float](repeating: 0, count: count)
        for i in 0..<count { a[i] = nextSample() }
        return a
    }
}
