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
        buffers[.bazookaFire] = makeBuffer(duration: 0.34) { t, dur in
            let env = exp(-t * 7.5)
            let freq = 240.0 * exp(-t * 4.5) + 70.0
            let noise = Double.random(in: -1...1) * 0.45
            return Float((sin(2 * .pi * freq * t) * 0.55 + noise) * env * 0.65)
        }

        buffers[.grenadeBounce] = makeBuffer(duration: 0.11) { t, _ in
            let env = exp(-t * 36.0)
            return Float((sin(2 * .pi * 640 * t) * 0.6 + sin(2 * .pi * 1180 * t) * 0.4) * env * 0.5)
        }

        buffers[.explosion] = makeBuffer(duration: 0.65) { t, _ in
            let env = exp(-t * 4.2)
            let sub = sin(2 * .pi * (92.0 * exp(-t * 3.8) + 28.0) * t)
            let rumble = Double.random(in: -1...1)
            return Float((sub * 0.55 + rumble * 0.65) * env * 0.85)
        }

        buffers[.holyExplosion] = makeBuffer(duration: 0.95) { t, _ in
            let env = exp(-t * 2.8)
            let sub = sin(2 * .pi * (110.0 * exp(-t * 3.0) + 24.0) * t)
            let shimmer = sin(2 * .pi * 523.25 * t) * exp(-t * 6.0) * 0.25
            let rumble = Double.random(in: -1...1)
            return Float((sub * 0.55 + rumble * 0.6 + shimmer) * env * 0.9)
        }

        buffers[.shotgun] = makeBuffer(duration: 0.24) { t, _ in
            let env = exp(-t * 16.0)
            let crack = Double.random(in: -1...1)
            let punch = sin(2 * .pi * (180.0 * exp(-t * 12.0)) * t)
            return Float((crack * 0.78 + punch * 0.42) * env * 0.8)
        }

        buffers[.jump] = makeBuffer(duration: 0.18) { t, _ in
            let env = exp(-t * 12.0)
            let freq = 230.0 + t * 1450.0
            return Float(sin(2 * .pi * freq * t) * env * 0.42)
        }

        buffers[.splash] = makeBuffer(duration: 0.42) { t, _ in
            let env = exp(-t * 6.5)
            let bubbles = sin(2 * .pi * (380.0 + sin(t * 48.0) * 180.0) * t) * 0.35
            let spray = Double.random(in: -1...1) * 0.55
            return Float((bubbles + spray) * env * 0.6)
        }

        buffers[.hurt] = makeBuffer(duration: 0.20) { t, _ in
            let env = exp(-t * 14.0)
            let freq = 420.0 * exp(-t * 4.5) + 140.0
            return Float(sin(2 * .pi * freq * t) * env * 0.48)
        }

        buffers[.turnStart] = makeBuffer(duration: 0.28) { t, _ in
            let noteFreq = t < 0.11 ? 523.25 : 659.25
            let localT = t < 0.11 ? t : (t - 0.11)
            let env = exp(-localT * 10.0)
            return Float(sin(2 * .pi * noteFreq * t) * env * 0.36)
        }

        buffers[.cratePickup] = makeBuffer(duration: 0.32) { t, _ in
            let freq: Double = t < 0.10 ? 587.33 : (t < 0.20 ? 783.99 : 1046.50)
            let localT = t.truncatingRemainder(dividingBy: 0.10)
            let env = exp(-localT * 12.0)
            return Float(sin(2 * .pi * freq * t) * env * 0.36)
        }

        buffers[.holyChoir] = makeBuffer(duration: 0.72) { t, _ in
            let attack = min(1.0, t / 0.12)
            let release = max(0.0, 1.0 - max(0.0, (t - 0.45) / 0.27))
            let env = attack * release
            let c5 = sin(2 * .pi * 523.25 * t)
            let e5 = sin(2 * .pi * 659.25 * t)
            let g5 = sin(2 * .pi * 783.99 * t)
            let c6 = sin(2 * .pi * 1046.50 * t) * 0.5
            return Float((c5 + e5 + g5 + c6) * 0.18 * env)
        }

        buffers[.victory] = makeBuffer(duration: 0.75) { t, _ in
            let notes: [(Double, Double)] = [(0.0, 523.25), (0.14, 659.25), (0.28, 783.99), (0.44, 1046.5)]
            var sample = 0.0
            for (start, freq) in notes where t >= start {
                let lt = t - start
                sample += sin(2 * .pi * freq * lt) * exp(-lt * 5.2) * 0.28
            }
            return Float(sample)
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
