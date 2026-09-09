//
//  MixerModel.swift
//  Sorae
//
//  The live soundscape: what is playing right now, how loud, for how long, and
//  how calm that makes Sorae. One instance lives for the life of the app so the
//  mix survives tab switches and the mascot stays in the same mood everywhere.
//

import Foundation
import Observation

@MainActor
@Observable
final class MixerModel {

    // MARK: Mix

    let channels: [SoundChannel] = SoundCatalog.channels
    private(set) var levels: [String: Double] = SoundCatalog.silentLevels

    /// The saved soundscape currently loaded, if any. Drives "Save changes"
    /// vs "Save as new" in the mixer.
    private(set) var loadedSoundscapeID: UUID?
    private(set) var loadedName: String?
    private(set) var hasUnsavedChanges = false

    // MARK: Playback

    private(set) var isPlaying = false

    // MARK: Session timer

    private(set) var sessionDuration: TimeInterval?
    /// Only set while playing — it is a fixed point in the future, which is what
    /// lets the Live Activity count down without being told the time.
    private(set) var sessionEndsAt: Date?
    /// Only set while paused. A session that is not playing is not elapsing
    /// either, so the remaining time is held still rather than measured against
    /// a wall clock that keeps moving.
    private var pausedRemaining: TimeInterval?
    private(set) var now: Date = .now
    private var ticker: Task<Void, Never>?

    // MARK: Audio

    private let engine: SoundscapeAudioEngine

    /// Pass a different engine to substitute playback — `SimulatedAudioEngine`
    /// for previews and tests, the real one otherwise.
    init(engine: SoundscapeAudioEngine? = nil) {
        let engine = engine ?? AmbientSoundController()
        self.engine = engine
        engine.prepare(channels: channels)
        startTicker()
    }

    // MARK: Derived state

    var calmScore: Double { CalmEvaluator.score(for: levels) }
    var mood: SoraeMood { SoraeMood(calm: calmScore) }
    var isSilent: Bool { levels.values.allSatisfy { $0 <= 0.001 } }

    var activeChannelCount: Int { levels.values.filter { $0 > 0.001 }.count }

    func level(for channelID: String) -> Double { levels[channelID] ?? 0 }

    /// Channels that have a recording behind them, and those still waiting for
    /// one. Both are derived from the catalog, so they update themselves as
    /// audio lands.
    var audibleChannels: [SoundChannel] { channels.filter { $0.audioResource != nil } }
    var silentChannels: [SoundChannel] { channels.filter { $0.audioResource == nil } }

    /// Live output level for the channel, used by the moving meters.
    func meter(for channelID: String) -> Double { engine.meter(for: channelID) }

    /// Everything the Live Activity needs. Note it carries the end *date*
    /// rather than a remaining duration — the widget counts down from it on its
    /// own, so the app never has to push a tick.
    var activitySnapshot: (isPlaying: Bool, endsAt: Date?, summary: String) {
        (isPlaying, sessionEndsAt, loadedName ?? summary)
    }

    /// Fired whenever playback or the session timer changes.
    ///
    /// Deliberately a direct callback rather than something a view observes:
    /// the moment that matters most — a timed session ending while the app is
    /// minimised — happens when no view is being rendered, and the Live Activity
    /// has to come down then and not when the user next opens the app.
    var onPlaybackStateChange: (() -> Void)?

    /// A one-line description of the mix: "Rain · River · Campfire".
    var summary: String {
        let names = channels.filter { level(for: $0.id) > 0.001 }.map(\.name)
        return names.isEmpty ? "No sounds yet" : names.joined(separator: " · ")
    }

    var currentLevels: [String: Double] { levels.filter { $0.value > 0.001 } }

    // MARK: Editing

    func setLevel(_ value: Double, for channelID: String) {
        let clamped = value.clamped01
        guard levels[channelID] != clamped else { return }
        levels[channelID] = clamped
        engine.setLevel(clamped, for: channelID, ramp: 0.08)
        hasUnsavedChanges = true

        // Touching a fader from silence starts the soundscape: the control the
        // user reached for is the one that begins playback.
        if clamped > 0.001 && !isPlaying { play() }
        if isSilent && isPlaying { pause() }
    }

    func toggle(_ channelID: String) {
        setLevel(level(for: channelID) > 0.001 ? 0 : 0.6, for: channelID)
    }

    func clearAll() {
        for channel in channels {
            levels[channel.id] = 0
            engine.setLevel(0, for: channel.id, ramp: 0.4)
        }
        pause()
        setSessionDuration(nil)
        loadedSoundscapeID = nil
        loadedName = nil
        hasUnsavedChanges = false
    }

    // MARK: Loading saved scenes

    func apply(_ scape: Soundscape) {
        for channel in channels {
            let value = scape.level(for: channel.id)
            levels[channel.id] = value
            engine.setLevel(value, for: channel.id, ramp: 0.35)
        }
        loadedSoundscapeID = scape.id
        loadedName = scape.name
        hasUnsavedChanges = false
        play()
        onPlaybackStateChange?()
    }

    func markSaved(as scape: Soundscape) {
        loadedSoundscapeID = scape.id
        loadedName = scape.name
        hasUnsavedChanges = false
    }

    /// A gentle three-layer blend built from whichever channels the catalog says
    /// are most calming — stays correct as the catalog grows.
    func quickCalmLevels() -> [String: Double] {
        let picks = channels.sorted { $0.calmWeight > $1.calmWeight }.prefix(3)
        let weights = [0.72, 0.45, 0.28]
        return Dictionary(uniqueKeysWithValues: zip(picks, weights).map { ($0.id, $1) })
    }

    // MARK: Transport

    func play() {
        guard !isSilent else { return }
        // Pick the countdown up where it was left.
        if let pausedRemaining {
            sessionEndsAt = Date.now.addingTimeInterval(pausedRemaining)
            self.pausedRemaining = nil
        }
        engine.play()
        isPlaying = true
        onPlaybackStateChange?()
    }

    func pause() {
        // Hold the countdown still. Without this it goes on elapsing against the
        // clock while nothing is playing, and a paused session quietly runs out.
        if sessionEndsAt != nil {
            pausedRemaining = sessionRemaining
            sessionEndsAt = nil
        }
        engine.pause()
        isPlaying = false
        onPlaybackStateChange?()
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    // MARK: Timer

    /// nil clears the timer and lets the soundscape run open-ended.
    func setSessionDuration(_ duration: TimeInterval?) {
        sessionDuration = duration
        guard let duration else {
            sessionEndsAt = nil
            pausedRemaining = nil
            onPlaybackStateChange?()
            return
        }
        // Setting a timer on a paused mix arms it; it starts running on play.
        if isPlaying {
            sessionEndsAt = Date.now.addingTimeInterval(duration)
            pausedRemaining = nil
        } else {
            sessionEndsAt = nil
            pausedRemaining = duration
        }
        onPlaybackStateChange?()
    }

    var sessionRemaining: TimeInterval? {
        if let pausedRemaining { return pausedRemaining }
        guard let sessionEndsAt else { return nil }
        return max(0, sessionEndsAt.timeIntervalSince(now))
    }

    /// 0...1 through the session, for the ring around the mascot.
    var sessionProgress: Double? {
        guard let sessionDuration, let remaining = sessionRemaining, sessionDuration > 0 else { return nil }
        return ((sessionDuration - remaining) / sessionDuration).clamped01
    }

    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.now = .now
                if let remaining = self.sessionRemaining, remaining <= 0, self.isPlaying {
                    self.finishSession()
                }
            }
        }
    }

    private func finishSession() {
        engine.fadeOutAndStop(duration: 4)
        isPlaying = false
        sessionEndsAt = nil
        pausedRemaining = nil
        sessionDuration = nil
        onPlaybackStateChange?()
    }
}
