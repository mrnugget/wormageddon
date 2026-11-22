import Foundation
import AVFoundation

enum SoundEffect: CaseIterable {
    case bazookaFire
    case grenadeBounce
    case explosion
    case holyExplosion
    case shotgun
    case jump
    case splash
    case hurt
    case turnStart
    case cratePickup
    case holyChoir
    case victory
    case sheepBaa
    case firePunch
    case dynamitePlace
}

final class SoundEngine {
    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private let playerPool: [AVAudioPlayerNode]
    private var poolIndex = 0
    private var buffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private let format: AVAudioFormat
    private var isReady = false
    var isMuted = false

    private init() {
        let sampleRate = 44100.0
        self.format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        self.playerPool = (0..<6).map { _ in AVAudioPlayerNode() }
        setupEngine()
        generateBuffers()
    }

    private func setupEngine() {
        #if os(tvOS) || os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Audio session may be unavailable in headless simulator; degrade silently
        }
        #endif

        for player in playerPool {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        engine.mainMixerNode.outputVolume = 0.72
        do {
            try engine.start()
            isReady = true
        } catch {
            isReady = false
        }
    }

    func play(_ effect: SoundEffect) {
        guard !isMuted, isReady, let buffer = buffers[effect] else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        let player = playerPool[poolIndex]
        poolIndex = (poolIndex + 1) % playerPool.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    // MARK: - Procedural Waveform Generation

    private func generateBuffers() {
        let twoPi: Double = 2.0 * Double.pi

        buffers[.bazookaFire] = makeBuffer(duration: 0.34) { t, _ in
            let env: Double = exp(-t * 7.5)
            let freq: Double = 240.0 * exp(-t * 4.5) + 70.0
            let tone: Double = sin(twoPi * freq * t) * 0.55
            let noise: Double = Double.random(in: -1.0...1.0) * 0.45
            return Float((tone + noise) * env * 0.65)
        }

        buffers[.grenadeBounce] = makeBuffer(duration: 0.11) { t, _ in
            let env: Double = exp(-t * 36.0)
            let low: Double = sin(twoPi * 640.0 * t) * 0.6
            let high: Double = sin(twoPi * 1180.0 * t) * 0.4
            return Float((low + high) * env * 0.5)
        }

        buffers[.explosion] = makeBuffer(duration: 0.65) { t, _ in
            let env: Double = exp(-t * 4.2)
            let subFreq: Double = 92.0 * exp(-t * 3.8) + 28.0
            let sub: Double = sin(twoPi * subFreq * t) * 0.55
            let rumble: Double = Double.random(in: -1.0...1.0) * 0.65
            return Float((sub + rumble) * env * 0.85)
        }

        buffers[.holyExplosion] = makeBuffer(duration: 0.95) { t, _ in
            let env: Double = exp(-t * 2.8)
            let subFreq: Double = 110.0 * exp(-t * 3.0) + 24.0
            let sub: Double = sin(twoPi * subFreq * t) * 0.55
            let shimmer: Double = sin(twoPi * 523.25 * t) * exp(-t * 6.0) * 0.25
            let rumble: Double = Double.random(in: -1.0...1.0) * 0.60
            return Float((sub + rumble + shimmer) * env * 0.9)
        }

        buffers[.shotgun] = makeBuffer(duration: 0.24) { t, _ in
            let env: Double = exp(-t * 16.0)
            let crack: Double = Double.random(in: -1.0...1.0) * 0.78
            let punchFreq: Double = 180.0 * exp(-t * 12.0)
            let punch: Double = sin(twoPi * punchFreq * t) * 0.42
            return Float((crack + punch) * env * 0.8)
        }

        buffers[.jump] = makeBuffer(duration: 0.18) { t, _ in
            let env: Double = exp(-t * 12.0)
            let freq: Double = 230.0 + t * 1450.0
            let wave: Double = sin(twoPi * freq * t)
            return Float(wave * env * 0.42)
        }

        buffers[.splash] = makeBuffer(duration: 0.42) { t, _ in
            let env: Double = exp(-t * 6.5)
            let bubbleMod: Double = sin(t * 48.0) * 180.0
            let bubbleFreq: Double = 380.0 + bubbleMod
            let bubbles: Double = sin(twoPi * bubbleFreq * t) * 0.35
            let spray: Double = Double.random(in: -1.0...1.0) * 0.55
            return Float((bubbles + spray) * env * 0.6)
        }

        buffers[.hurt] = makeBuffer(duration: 0.20) { t, _ in
            let env: Double = exp(-t * 14.0)
            let freq: Double = 420.0 * exp(-t * 4.5) + 140.0
            let wave: Double = sin(twoPi * freq * t)
            return Float(wave * env * 0.48)
        }

        buffers[.turnStart] = makeBuffer(duration: 0.28) { t, _ in
            let noteFreq: Double = t < 0.11 ? 523.25 : 659.25
            let localT: Double = t < 0.11 ? t : (t - 0.11)
            let env: Double = exp(-localT * 10.0)
            let wave: Double = sin(twoPi * noteFreq * t)
            return Float(wave * env * 0.36)
        }

        buffers[.cratePickup] = makeBuffer(duration: 0.32) { t, _ in
            let freq: Double = t < 0.10 ? 587.33 : (t < 0.20 ? 783.99 : 1046.50)
            let localT: Double = t.truncatingRemainder(dividingBy: 0.10)
            let env: Double = exp(-localT * 12.0)
            let wave: Double = sin(twoPi * freq * t)
            return Float(wave * env * 0.36)
        }

        buffers[.holyChoir] = makeBuffer(duration: 0.72) { t, _ in
            let attack: Double = min(1.0, t / 0.12)
            let release: Double = max(0.0, 1.0 - max(0.0, (t - 0.45) / 0.27))
            let env: Double = attack * release
            let c5: Double = sin(twoPi * 523.25 * t)
            let e5: Double = sin(twoPi * 659.25 * t)
            let g5: Double = sin(twoPi * 783.99 * t)
            let c6: Double = sin(twoPi * 1046.50 * t) * 0.5
            let chord: Double = c5 + e5 + g5 + c6
            return Float(chord * 0.18 * env)
        }

        buffers[.victory] = makeBuffer(duration: 0.75) { t, _ in
            let notes: [(Double, Double)] = [
                (0.0, 523.25),
                (0.14, 659.25),
                (0.28, 783.99),
                (0.44, 1046.5)
            ]
            var sample: Double = 0.0
            for (start, freq) in notes where t >= start {
                let lt: Double = t - start
                let noteWave: Double = sin(twoPi * freq * lt)
                let noteEnv: Double = exp(-lt * 5.2)
                sample += noteWave * noteEnv * 0.28
            }
            return Float(sample)
        }

        buffers[.sheepBaa] = makeBuffer(duration: 0.36) { t, _ in
            let env: Double = sin(min(1.0, t / 0.36) * Double.pi)
            let vibrato: Double = sin(twoPi * 26.0 * t) * 28.0
            let f1: Double = 360.0 + vibrato
            let f2: Double = 720.0 + vibrato * 1.5
            let voice: Double = sin(twoPi * f1 * t) * 0.45 + sin(twoPi * f2 * t) * 0.25
            return Float(voice * env * 0.55)
        }

        buffers[.firePunch] = makeBuffer(duration: 0.32) { t, _ in
            let env: Double = exp(-t * 6.0)
            let sweep: Double = 180.0 + t * 950.0
            let punch: Double = sin(twoPi * sweep * t) * 0.5
            let whoosh: Double = Double.random(in: -1.0...1.0) * 0.55
            return Float((punch + whoosh) * env * 0.78)
        }

        buffers[.dynamitePlace] = makeBuffer(duration: 0.16) { t, _ in
            let env: Double = exp(-t * 20.0)
            let thud: Double = sin(twoPi * 150.0 * t) * 0.5
            let sizzle: Double = Double.random(in: -1.0...1.0) * 0.35
            return Float((thud + sizzle) * env * 0.6)
        }
    }

    private func makeBuffer(duration: Double, sample: (Double, Double) -> Float) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let ptr = buffer.floatChannelData?[0] else { return nil }
        let sr = format.sampleRate
        for i in 0..<Int(frameCount) {
            ptr[i] = max(-1.0, min(1.0, sample(Double(i) / sr, duration)))
        }
        return buffer
    }
}
