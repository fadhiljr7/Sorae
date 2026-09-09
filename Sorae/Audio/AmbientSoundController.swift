//
//  AmbientSoundController.swift
//  Sorae
//
//  Owns the audio engine, the audio session and every sound layer, and is the
//  real implementation behind `SoundscapeAudioEngine`.
//
//  Channels whose `audioResource` is filled in get a real `LoopingAmbienceLayer`.
//  Channels that do not yet have a recording stay silent and fall back to the
//  simulated meter, so the mixer keeps behaving exactly as it did before while
//  the remaining sounds are recorded.
//
//  Nothing here knows about rain specifically. Shipping wind is: add the asset,
//  fill in `SoundChannel.audioResource`, add an `AmbientIntensityProfile`.
//

import AVFoundation
import Observation

@MainActor
final class AmbientSoundController: SoundscapeAudioEngine, AmbientEngineHost {

    let engine = AVAudioEngine()

    private(set) var isPlaying = false

    /// What the user asked for, per channel, independent of transport state.
    private var levels: [String: Double] = [:]
    private var layers: [String: AmbientSoundLayer] = [:]
    private var channels: [SoundChannel] = []

    /// Stands in for channels that have no recording yet, so their faders keep
    /// their level indicators. Shrinks to nothing as the remaining sounds land.
    private let unrecordedChannels = SimulatedAudioEngine()

    private var isSessionActive = false
    private var clock: Task<Void, Never>?
    private var interruptionObservers: [NSObjectProtocol] = []

    /// 60 Hz. Fine enough that a dB ramp is inaudible as steps, cheap enough to
    /// run while a finger is on a fader.
    private static let tickInterval: TimeInterval = 1.0 / 60.0

    init() {
        observeSessionEvents()
    }

    // MARK: SoundscapeAudioEngine

    func prepare(channels: [SoundChannel]) {
        self.channels = channels
        unrecordedChannels.prepare(channels: channels.filter { $0.audioResource == nil })

        for channel in channels {
            guard let resource = channel.audioResource, layers[channel.id] == nil else { continue }
            let layer = LoopingAmbienceLayer(
                id: channel.id,
                assetName: resource,
                profile: AmbientIntensityProfile.profile(for: channel)
            )
            layer.attach(to: self)
            layers[channel.id] = layer
            levels[channel.id] = levels[channel.id] ?? 0
        }
    }

    func setLevel(_ level: Double, for channelID: String, ramp: TimeInterval) {
        let clamped = min(1, max(0, level))
        levels[channelID] = clamped
        unrecordedChannels.setLevel(clamped, for: channelID, ramp: ramp)
        pushIntensity(for: channelID)
        startClockIfNeeded()
    }

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        unrecordedChannels.play()
        for id in levels.keys { pushIntensity(for: id) }
        startClockIfNeeded()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        unrecordedChannels.pause()
        // The same route play() takes, so the layers' own view of their level
        // cannot drift out of step with the transport. Each falls to zero over
        // its own fade time.
        for id in levels.keys { pushIntensity(for: id) }
        startClockIfNeeded()
    }

    func fadeOutAndStop(duration: TimeInterval) {
        isPlaying = false
        unrecordedChannels.fadeOutAndStop(duration: duration)
        for layer in layers.values {
            layer.fadeOut(over: duration)
        }
        startClockIfNeeded()
    }

    func meter(for channelID: String) -> Double {
        if let layer = layers[channelID] {
            return Double(layer.outputLevel)
        }
        return unrecordedChannels.meter(for: channelID)
    }

    // MARK: AmbientEngineHost

    func engineWillStartPlayback() throws {
        try activateSession()
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    func layerDidGoIdle(_ layer: AmbientSoundLayer) {
        stopEngineIfIdle()
    }

    // MARK: Intensity routing

    private func pushIntensity(for channelID: String) {
        guard let layer = layers[channelID] else { return }
        // Pausing is a mute, not a reset: the level the user set is preserved
        // so pressing play again returns to exactly that mix.
        let effective = isPlaying ? Float(levels[channelID] ?? 0) : 0
        layer.setIntensity(effective)
    }

    // MARK: Clock

    private var needsTicking: Bool {
        layers.values.contains { $0.isActive } || engine.isRunning
    }

    private func startClockIfNeeded() {
        guard clock == nil else { return }
        clock = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.tickInterval))
                guard let self else { return }
                let now = ContinuousClock.now
                let delta = TimeInterval(last.duration(to: now).components.seconds)
                    + TimeInterval(last.duration(to: now).components.attoseconds) / 1e18
                last = now

                for layer in self.layers.values {
                    layer.tick(delta: delta)
                }

                if !self.needsTicking {
                    self.clock = nil
                    return
                }
            }
        }
    }

    // MARK: Engine / session

    private func stopEngineIfIdle() {
        guard !layers.values.contains(where: { $0.isActive }) else { return }
        if engine.isRunning { engine.stop() }
        deactivateSession()
    }

    private func activateSession() throws {
        guard !isSessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        // Ambience for relaxation: it should behave like playback, keep going
        // when the ringer is silenced, and not duck other audio unnecessarily.
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        isSessionActive = true
    }

    private func deactivateSession() {
        guard isSessionActive else { return }
        isSessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: Interruptions and route changes

    private func observeSessionEvents() {
        let center = NotificationCenter.default

        interruptionObservers.append(
            center.addObserver(forName: AVAudioSession.interruptionNotification,
                               object: AVAudioSession.sharedInstance(),
                               queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.handleInterruption(note) }
            }
        )

        interruptionObservers.append(
            center.addObserver(forName: AVAudioSession.routeChangeNotification,
                               object: AVAudioSession.sharedInstance(),
                               queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.handleRouteChange(note) }
            }
        )

        interruptionObservers.append(
            center.addObserver(forName: .AVAudioEngineConfigurationChange,
                               object: engine,
                               queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleConfigurationChange() }
            }
        )
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            pause()
        case .ended:
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume), wasPlayingBeforeInterruption {
                isSessionActive = false
                play()
            }
        @unknown default:
            break
        }
    }

    private var wasPlayingBeforeInterruption = false

    private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        // Headphones pulled out: stop, the way every audio app on iOS does.
        if reason == .oldDeviceUnavailable {
            pause()
        }
    }

    private func handleConfigurationChange() {
        for layer in layers.values {
            layer.engineConfigurationDidChange()
        }
        startClockIfNeeded()
    }
}

// MARK: - Per-channel profiles

private extension AmbientIntensityProfile {
    /// The profile a channel plays through. Each sound gets its own once it has
    /// a recording; anything unlisted falls back to the rain shaping, which is a
    /// sensible neutral starting point for a broadband ambience.
    static func profile(for channel: SoundChannel) -> AmbientIntensityProfile {
        switch channel.id {
        case "rain": .rain
        case "wind": .wind
        case "birds": .bird
        case "river": .river
        case "campfire": .campfire
        default: .rain
        }
    }
}

