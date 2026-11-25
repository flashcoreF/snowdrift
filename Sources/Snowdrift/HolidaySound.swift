import AVFoundation

/// Synthesised holiday sounds (no audio files needed): sleigh bells and a little chime.
/// Only plays when "Sounds" is switched on in the menu.
@MainActor
final class HolidaySound {
    private let audio = AVAudioEngine()
    private let bellPlayer = AVAudioPlayerNode()
    private let fxPlayer = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var started = false
    private var failed = false

    private lazy var bells: AVAudioPCMBuffer? = makeBells(duration: 4.5)
    private lazy var chime: AVAudioPCMBuffer? = makeChime(notes: [1046.5, 1318.5, 1568.0, 2093.0])
    private lazy var fanfare: AVAudioPCMBuffer? = makeChime(notes: [784.0, 1046.5, 1318.5, 1568.0, 2093.0, 2637.0])

    func playBells() { play(bells, on: bellPlayer) }
    func playChime() { play(chime, on: fxPlayer) }
    func playFanfare() { play(fanfare, on: fxPlayer) }

    private func play(_ buffer: AVAudioPCMBuffer?, on player: AVAudioPlayerNode) {
        guard Settings.shared.sounds, let buffer, start() else { return }
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func start() -> Bool {
        if started { return true }
        if failed { return false }
        guard let format else { failed = true; return false }
        audio.attach(bellPlayer)
        audio.attach(fxPlayer)
        audio.connect(bellPlayer, to: audio.mainMixerNode, format: format)
        audio.connect(fxPlayer, to: audio.mainMixerNode, format: format)
        do {
            try audio.start()
            started = true
        } catch {
            failed = true
        }
        return started
    }

    private func makeBuffer(seconds: Double) -> (AVAudioPCMBuffer, UnsafeMutablePointer<Float>, Int)? {
        guard let format else { return nil }
        let n = Int(format.sampleRate * seconds)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
              let channels = buf.floatChannelData else { return nil }
        buf.frameLength = AVAudioFrameCount(n)
        let data = channels[0]
        for i in 0..<n { data[i] = 0 }
        return (buf, data, n)
    }

    /// Jingling bells that swell up and fade away, like a sleigh passing by.
    private func makeBells(duration: Double) -> AVAudioPCMBuffer? {
        guard let made = makeBuffer(seconds: duration) else { return nil }
        let (buf, data, n) = made
        let sr = 44_100.0
        var beat = 0.05
        while beat < duration - 0.6 {
            let swell = pow(sin(Double.pi * beat / duration), 0.8)
            for _ in 0..<3 {
                let t0 = beat + Double.random(in: 0...0.035)
                let f0 = Double.random(in: 2400...3400)
                let amp = Float(Double.random(in: 0.04...0.08) * swell)
                let start = Int(t0 * sr)
                let len = Int(0.3 * sr)
                for k in 0..<len where start + k < n {
                    let t = Double(k) / sr
                    let w = 2 * Double.pi * f0 * t
                    let v = sin(w) * exp(-t * 16)
                        + 0.55 * sin(w * 2.76) * exp(-t * 22)
                        + 0.3 * sin(w * 5.4) * exp(-t * 35)
                    data[start + k] += amp * Float(v)
                }
            }
            beat += Double.random(in: 0.2...0.26)
        }
        return buf
    }

    /// A rising run of soft bell notes.
    private func makeChime(notes: [Double]) -> AVAudioPCMBuffer? {
        let step = 0.11
        let duration = Double(notes.count) * step + 1.4
        guard let made = makeBuffer(seconds: duration) else { return nil }
        let (buf, data, n) = made
        let sr = 44_100.0
        for (i, f) in notes.enumerated() {
            let start = Int(Double(i) * step * sr)
            let len = Int(1.3 * sr)
            for k in 0..<len where start + k < n {
                let t = Double(k) / sr
                let w = 2 * Double.pi * f * t
                let v = (sin(w) + 0.25 * sin(2 * w) + 0.1 * sin(3.01 * w)) * exp(-t * 4.2)
                data[start + k] += Float(0.09 * v)
            }
        }
        return buf
    }
}
