//
//  SoundscapeAudioEngine.swift
//  Sorae
//
//  The seam between the UI and audio.
//
//  `AmbientSoundController` is the real implementation. `SimulatedAudioEngine`
//  remains for previews and tests, and for any channel whose recording has not
//  been made yet — it keeps exactly the state a real engine would keep and
//  publishes a believable per-channel meter.
//
//  Adding the next sound needs no change here: drop the asset in, fill in
//  `SoundChannel.audioResource`, give it an `AmbientIntensityProfile`.
//

import Foundation

@MainActor
protocol SoundscapeAudioEngine: AnyObject {

    var isPlaying: Bool { get }

    /// Called once with the full catalog so an implementation can pre-load and
    /// pre-roll its players.
    func prepare(channels: [SoundChannel])

    /// Set a channel's volume, 0...1. `ramp` is the fade duration; the UI passes
    /// a short ramp while dragging so real audio would not click.
    func setLevel(_ level: Double, for channelID: String, ramp: TimeInterval)

    func play()
    func pause()

    /// Used by the session timer when it reaches zero.
    func fadeOutAndStop(duration: TimeInterval)

    /// Live output level for a channel, 0...1. Real engines tap the mixer node;
    /// the simulator synthesises a believable envelope.
    func meter(for channelID: String) -> Double
}

/// Stand-in engine used until the audio assets exist.
@MainActor
final class SimulatedAudioEngine: SoundscapeAudioEngine {

    private(set) var isPlaying = false
    private var levels: [String: Double] = [:]
    /// Per-channel phase offset so the simulated meters do not pulse in unison.
    private var phases: [String: Double] = [:]
    private var fadeMultiplier: Double = 1

    func prepare(channels: [SoundChannel]) {
        for (index, channel) in channels.enumerated() {
            levels[channel.id] = levels[channel.id] ?? 0
            phases[channel.id] = Double(index) * 0.9
        }
    }

    func setLevel(_ level: Double, for channelID: String, ramp: TimeInterval) {
        levels[channelID] = level.clamped01
    }

    func play() {
        fadeMultiplier = 1
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    func fadeOutAndStop(duration: TimeInterval) {
        // A real engine would ramp each node; here we simply stop.
        fadeMultiplier = 0
        isPlaying = false
    }

    func meter(for channelID: String) -> Double {
        let level = levels[channelID] ?? 0
        guard isPlaying, level > 0.001 else { return 0 }
        // Slow, irregular breathing around the set level — what a natural
        // ambience loop actually looks like on a meter.
        let phase = phases[channelID] ?? 0
        let t = Date.timeIntervalSinceReferenceDate
        let wobble = sin(t * 1.1 + phase) * 0.06 + sin(t * 0.37 + phase * 2) * 0.04
        return ((level + wobble) * fadeMultiplier).clamped01
    }
}
