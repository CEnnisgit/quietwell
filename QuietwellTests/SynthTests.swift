import XCTest
@testable import Quietwell

/// Spectral checks for the generators. Power is measured with a Hann-windowed Goertzel filter at
/// 11 frequencies from 500 Hz to 8 kHz, averaged over 24 segments, and fitted on log-log axes:
/// white noise is flat (slope 0), pink falls 3 dB/octave (slope -1), brown 6 dB/octave (slope -2).
final class SynthTests: XCTestCase {
    private let sampleRate: Double = 44_100

    private func bandPower(_ kind: SoundKind, params: SoundParams = .neutral, freqs: [Double]) -> [Double] {
        var g = SoundGenerator(kind: kind, sampleRate: Float(sampleRate), seed: 42, params: params)
        _ = g.samples(Int(sampleRate))   // let filters settle
        let n = 4096, segments = 24
        var window = [Double](repeating: 0, count: n)
        for i in 0..<n { window[i] = 0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(n - 1)) }
        var power = [Double](repeating: 0, count: freqs.count)
        for _ in 0..<segments {
            let x = g.samples(n)
            for (k, f) in freqs.enumerated() {
                for offset in -3...3 {
                    let bin = (f / sampleRate * Double(n)).rounded() + Double(offset)
                    let c = 2 * cos(2 * .pi * bin / Double(n))
                    var s1 = 0.0, s2 = 0.0
                    for i in 0..<n {
                        let s0 = Double(x[i]) * window[i] + c * s1 - s2
                        s2 = s1; s1 = s0
                    }
                    power[k] += s1 * s1 + s2 * s2 - c * s1 * s2
                }
            }
        }
        return power
    }

    private func slope(_ kind: SoundKind) -> Double {
        let freqs = (0..<11).map { 500 * pow(2, Double($0) * 0.4) }
        let p = bandPower(kind, freqs: freqs)
        let lx = freqs.map { log10($0) }, ly = p.map { log10($0) }
        let mx = lx.reduce(0, +) / Double(lx.count), my = ly.reduce(0, +) / Double(ly.count)
        var num = 0.0, den = 0.0
        for i in lx.indices { num += (lx[i] - mx) * (ly[i] - my); den += (lx[i] - mx) * (lx[i] - mx) }
        return num / den
    }

    func testWhiteNoiseIsFlat() {
        XCTAssertEqual(slope(.white), 0, accuracy: 0.25)
    }

    func testPinkNoiseFallsThreeDBPerOctave() {
        XCTAssertEqual(slope(.pink), -1, accuracy: 0.25)
    }

    func testBrownNoiseFallsSixDBPerOctave() {
        XCTAssertEqual(slope(.brown), -2, accuracy: 0.3)
    }

    func testBrownIsSteeperThanPinkIsSteeperThanWhite() {
        let w = slope(.white), p = slope(.pink), b = slope(.brown)
        XCTAssertLessThan(b, p - 0.6)
        XCTAssertLessThan(p, w - 0.6)
    }

    func testLowerToneMakesBrownDeeper() {
        let freqs: [Double] = [200, 4000]
        let bright = bandPower(.brown, params: SoundParams(tone: 1, intensity: 0.5), freqs: freqs)
        let deep = bandPower(.brown, params: SoundParams(tone: 0.2, intensity: 0.5), freqs: freqs)
        XCTAssertGreaterThan(deep[0] / deep[1], bright[0] / bright[1] * 10)
    }

    func testEverySoundIsAudibleBoundedAndFinite() {
        for kind in SoundKind.allCases {
            var g = SoundGenerator(kind: kind, sampleRate: 44_100, seed: 7)
            let s = g.samples(44_100 * 4)
            let rms = sqrt(s.reduce(0) { $0 + Double($1 * $1) } / Double(s.count))
            XCTAssertGreaterThan(rms, 0.02, "\(kind) too quiet")
            XCTAssertTrue(s.allSatisfy { $0.isFinite && abs($0) <= 1 }, "\(kind) out of range")
        }
    }

    func testGeneratorsAreDeterministicPerSeed() {
        var a = SoundGenerator(kind: .rain, seed: 99), b = SoundGenerator(kind: .rain, seed: 99)
        var c = SoundGenerator(kind: .rain, seed: 100)
        let sa = a.samples(2048), sb = b.samples(2048), sc = c.samples(2048)
        XCTAssertEqual(sa, sb)
        XCTAssertNotEqual(sa, sc)
    }

    func testFreeTierIsTheFiveListedSounds() {
        XCTAssertEqual(SoundKind.freeKinds, [.white, .pink, .brown, .fan, .rain])
        XCTAssertEqual(SoundKind.allCases.filter { !$0.isFree }, [.green, .ocean, .thunder, .hum])
        for k in SoundKind.allCases { XCTAssertEqual(SoundKind.from(index: k.index), k) }
    }

    func testVoiceBankMixesAndFadesMaster() {
        let bank = VoiceBank(sampleRate: 44_100)
        var buf = [Float](repeating: 0, count: 8192)
        func rms() -> Double {
            buf.withUnsafeMutableBufferPointer { bank.render(into: $0.baseAddress!, count: $0.count) }
            return sqrt(buf.reduce(0) { $0 + Double($1 * $1) } / Double(buf.count))
        }
        bank.setLayer(0, kind: .brown, params: SoundParams(), volume: 0.8)
        bank.setMasterGain(1)
        _ = rms()
        let one = rms()
        XCTAssertGreaterThan(one, 0.02)
        bank.setLayer(1, kind: .white, params: .neutral, volume: 0.8)
        _ = rms()
        XCTAssertGreaterThan(rms(), one)
        bank.setMasterGain(0)
        _ = rms()
        XCTAssertLessThan(rms(), 0.001)
    }
}

final class SleepTimerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testFifteenMinuteTimerFadesOverLastQuarter() {
        let t = SleepTimer(duration: 15 * 60, start: t0)
        XCTAssertEqual(t.fade, 225)
        XCTAssertEqual(t.gain(at: t0), 1)
        XCTAssertEqual(t.gain(at: t0.addingTimeInterval(675)), 1)
        XCTAssertEqual(t.gain(at: t0.addingTimeInterval(675 + 112.5)), Float(cos(Double.pi / 4)), accuracy: 0.001)
        XCTAssertEqual(t.gain(at: t0.addingTimeInterval(900)), 0)
        XCTAssertTrue(t.isFinished(at: t0.addingTimeInterval(900)))
        XCTAssertFalse(t.isFinished(at: t0.addingTimeInterval(899)))
    }

    func testFadeIsCappedAtFiveMinutesAndMonotonic() {
        let t = SleepTimer(duration: 8 * 3600, start: t0)
        XCTAssertEqual(t.fade, 300)
        var last: Float = 1
        for s in stride(from: 8 * 3600 - 300, through: 8 * 3600, by: 10) {
            let g = t.gain(at: t0.addingTimeInterval(TimeInterval(s)))
            XCTAssertLessThanOrEqual(g, last)
            last = g
        }
        XCTAssertEqual(last, 0)
    }

    func testRemainingAndLabels() {
        let t = SleepTimer(duration: 1800, start: t0)
        XCTAssertEqual(t.remaining(at: t0.addingTimeInterval(600)), 1200)
        XCTAssertEqual(t.remaining(at: t0.addingTimeInterval(5000)), 0)
        XCTAssertEqual(SleepTimer.presets.first, 15 * 60)
        XCTAssertEqual(SleepTimer.presets.last, 8 * 3600)
        XCTAssertEqual(SleepTimer.label(45 * 60), "45 min")
        XCTAssertEqual(SleepTimer.label(3600), "1 hour")
        XCTAssertEqual(SleepTimer.label(8 * 3600), "8 hours")
        XCTAssertEqual(SleepTimer.countdown(3725), "1:02:05")
        XCTAssertEqual(SleepTimer.countdown(59.2), "1:00")
    }
}

final class MixLibraryTests: XCTestCase {
    @MainActor func testSaveLoadDelete() {
        let name = "mix-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        let lib = MixLibrary(defaults: d)
        lib.save([MixLayer(kind: .brown), MixLayer(kind: .rain)])
        XCTAssertEqual(lib.mixes.first?.name, "Brown Noise + Rain")
        let reloaded = MixLibrary(defaults: d)
        XCTAssertEqual(reloaded.mixes.count, 1)
        XCTAssertEqual(reloaded.mixes.first?.layers.map(\.kind), [.brown, .rain])
        reloaded.delete(reloaded.mixes[0])
        XCTAssertTrue(MixLibrary(defaults: d).mixes.isEmpty)
        d.removePersistentDomain(forName: name)
    }
}
