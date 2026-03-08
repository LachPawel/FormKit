// BeepController.swift
// Plays a repeating warning beep while the user is misaligned.
//
// Uses AVAudioEngine + AVAudioPlayerNode so it coexists with AVCaptureSession.
// AVAudioPlayer touches audio hardware at prepareToPlay() time and can interrupt
// the capture pipeline (err=-17281 / kCMIOHardwareNotRunningError).
// AVAudioEngine is the correct API to use alongside capture — it shares the
// same audio graph without needing a separate AVAudioSession activation.
//
// The engine is created lazily on first beep so nothing touches audio at init.

import Foundation
import AVFoundation

final class BeepController {
    var gracePeriod: TimeInterval = 1.0
    var beepInterval: TimeInterval = 0.6

    private var graceTimer: Timer?
    private var beepTimer: Timer?
    private var isBeeping = false

    // Lazily created on first beep
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var beepBuffer: AVAudioPCMBuffer?

    // MARK: - Public

    func update(isAligned: Bool) {
        if isAligned {
            stopAll()
        } else {
            startGraceIfNeeded()
        }
    }

    func stopAll() {
        graceTimer?.invalidate()
        graceTimer = nil
        stopBeeping()
    }

    // MARK: - Engine (lazy)

    private func prepareEngineIfNeeded() {
        guard engine == nil else { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        // Use the engine's output format so no conversion is needed
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)

        beepBuffer = makeSineBuffer(format: format, frequency: 880, durationSeconds: 0.15)

        do {
            try engine.start()
        } catch {
            print("BeepController: engine start error – \(error)")
            return
        }

        self.engine = engine
        self.playerNode = player
    }

    // MARK: - Sine buffer

    private func makeSineBuffer(format: AVAudioFormat,
                                frequency: Double,
                                durationSeconds: Double) -> AVAudioPCMBuffer? {
        let sampleRate  = format.sampleRate
        let frameCount  = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        let channelData = buffer.floatChannelData![0]
        let fadeLen     = Int(frameCount) / 8

        for i in 0..<Int(frameCount) {
            let fade: Float
            if i < fadeLen {
                fade = Float(i) / Float(fadeLen)
            } else if i > Int(frameCount) - fadeLen {
                fade = Float(Int(frameCount) - i) / Float(fadeLen)
            } else {
                fade = 1.0
            }
            channelData[i] = fade * 0.8 * Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
        }
        return buffer
    }

    // MARK: - Timers

    private func startGraceIfNeeded() {
        guard graceTimer == nil, !isBeeping else { return }
        graceTimer = Timer.scheduledTimer(withTimeInterval: gracePeriod, repeats: false) { [weak self] _ in
            self?.graceTimer = nil
            self?.startBeeping()
        }
    }

    private func startBeeping() {
        guard !isBeeping else { return }
        isBeeping = true
        playBeep()
        beepTimer = Timer.scheduledTimer(withTimeInterval: beepInterval, repeats: true) { [weak self] _ in
            self?.playBeep()
        }
    }

    private func stopBeeping() {
        beepTimer?.invalidate()
        beepTimer = nil
        isBeeping = false
    }

    private func playBeep() {
        prepareEngineIfNeeded()
        guard let player = playerNode, let buffer = beepBuffer else { return }
        // scheduleBuffer is non-blocking; the node plays it asynchronously
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    deinit {
        stopAll()
        engine?.stop()
    }
}
