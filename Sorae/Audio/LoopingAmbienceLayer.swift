//
//  LoopingAmbienceLayer.swift
//  Sorae
//
//  The reusable ambience layer. One looping recording through a gentle tone
//  shaping stage and a hint of room, with everything the intensity touches on a
//  ramp.
//
//  Signal chain:
//
//      AVAudioPlayerNode
//        → AVAudioUnitEQ        makeup gain + three gentle tone bands
//        → width stage          optional; see below
//        → AVAudioUnitReverb    a hint of room, constant
//        → peak limiter         catches the rare loud transient, nothing else
//        → gain mixer           the intensity curve
//        → main mixer
//
//  The width stage exists only for sounds whose profile asks for one, and is
//  built from the EQ's output feeding two paths that are summed again:
//
//        eq ┬→ direct  (the recording as it is)  ┐
//           └→ fold    (summed to the centre)    ┴→ width mixer
//
//  Crossfading between them narrows or opens the stereo image. Both paths come
//  from the same node in the same render cycle, so they stay sample-aligned and
//  cannot comb-filter the way two players reading the same file could.
//
//  Two orderings matter:
//
//  The gain mixer is last, so when the intensity returns to zero the ramp takes
//  the reverb tail down with the source rather than leaving it ringing after the
//  rain has stopped.
//
//  The limiter is before it, so it always sees the same calibrated signal
//  whatever the slider is doing. If it sat after the gain it would engage only
//  at the top of the range, and the sound's character would change as the user
//  moved the fader.
//
//  Adding a second sound is `LoopingAmbienceLayer(id: "wind", asset: "windsound",
//  profile: .wind)` — no new class.
//

import AVFoundation
import os

@MainActor
final class LoopingAmbienceLayer: AmbientSoundLayer {

    let id: String
    private let assetName: String
    private let profile: AmbientIntensityProfile

    private(set) var intensity: Float = 0
    private(set) var isActive = false

    // MARK: Nodes

    private let player = AVAudioPlayerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 3)
    private let reverb = AVAudioUnitReverb()
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    ))
    private let gainMixer = AVAudioMixerNode()

    /// Built only when the profile asks for a width stage. Rain has none, so its
    /// signal path is exactly what it was.
    private let directPath: AVAudioMixerNode?
    private let centreFold: AVAudioMixerNode?
    private let widthMixer: AVAudioMixerNode?

    private weak var host: AmbientEngineHost?
    private var isAttached = false
    private var isConnected = false

    // MARK: Ramps

    /// Ramped in dB. Anything at or below `silenceFloorDB` is rendered as a true
    /// zero, so silence is silence and not a very quiet signal.
    nonisolated private static let silenceFloorDB: Float = -72
    nonisolated private static let audibleFloorDB: Float = -66

    private var gain = RampedValue(silenceFloorDB)
    private var bodyGain = RampedValue(0)
    private var airGain = RampedValue(0)
    private var detailGain = RampedValue(0)
    private var width = RampedValue(1)
    private var reverbMix: RampedValue?

    /// Set while a fade to silence is in flight, so the player is stopped only
    /// once the fade has actually finished.
    private var isFadingToSilence = false

    // MARK: Buffer

    private var buffer: AVAudioPCMBuffer?
    private var loadTask: Task<Void, Never>?
    /// Measured once from the recording; drives the makeup gain.
    private(set) var sourceStatistics: AmbientSourceStatistics?
    /// How the loop was prepared and how well its ends meet. Diagnostics only.
    private(set) var loopReport: AmbientLoopReport?

    // MARK: Metering

    private let meter = MeterBox()
    var outputLevel: Float { meter.value }

    /// The gain that is audible right now, in dB — the ramped value, not the
    /// target. Exposed for diagnostics.
    var currentGainDB: Float { gain.current }

    /// Where the gain ramp is heading, in dB. Exposed for diagnostics.
    var targetGainDB: Float { gain.target }

    /// Length of the loop actually being played, after any seam crossfade.
    /// Exposed for diagnostics.
    var loopDuration: TimeInterval? {
        guard let buffer else { return nil }
        return Double(buffer.frameLength) / buffer.format.sampleRate
    }

    var fadeOutDuration: TimeInterval { profile.fadeOutDuration }

    init(id: String, assetName: String, profile: AmbientIntensityProfile) {
        self.id = id
        self.assetName = assetName
        self.profile = profile

        if profile.stereoWidth != nil {
            directPath = AVAudioMixerNode()
            centreFold = AVAudioMixerNode()
            widthMixer = AVAudioMixerNode()
        } else {
            directPath = nil
            centreFold = nil
            widthMixer = nil
        }
        width.reset(to: profile.stereoWidth?.low ?? 1)
        if let range = profile.reverbWetDryMixRange {
            reverbMix = RampedValue(range.low)
        }
    }

    // MARK: Lifecycle

    func attach(to host: AmbientEngineHost) {
        guard !isAttached else { return }
        self.host = host
        isAttached = true

        equalizer.globalGain = 0
        configureBands()

        reverb.loadFactoryPreset(profile.reverbPreset)
        reverb.wetDryMix = reverbMix?.current ?? profile.reverbWetDryMix

        configureLimiter()
        gainMixer.outputVolume = 0

        var nodes: [AVAudioNode] = [player, equalizer, reverb, limiter, gainMixer]
        nodes.append(contentsOf: [directPath, centreFold, widthMixer].compactMap { $0 })
        for node in nodes {
            host.engine.attach(node)
        }
    }

    func teardown() {
        loadTask?.cancel()
        loadTask = nil
        stopPlayback()
        buffer = nil
        isConnected = false
        isAttached = false
    }

    func engineConfigurationDidChange() {
        let wasActive = isActive
        removeMeterTap()
        if player.isPlaying { player.stop() }
        isConnected = false
        isActive = false
        // Come back at the level we were at, without a fade — the interruption
        // in the audio has already happened.
        if wasActive, intensity > profile.silenceThreshold {
            startPlaybackIfNeeded()
        }
    }

    // MARK: Intensity

    func setIntensity(_ newIntensity: Float) {
        let clamped = min(1, max(0, newIntensity))
        let wasSilent = intensity <= profile.silenceThreshold
        let isSilent = clamped <= profile.silenceThreshold
        intensity = clamped

        if isSilent {
            guard !wasSilent || isActive else { return }
            fadeOut(over: profile.fadeOutDuration)
            return
        }

        isFadingToSilence = false
        // Restarting covers more than rising from zero: a pause, or a session
        // timer running out, also leaves the level set but the player stopped.
        let restarting = wasSilent || !isActive
        // Coming back from silence gets the long fade; a slider already in
        // motion gets the short one so it tracks the finger.
        let base = restarting ? profile.fadeInDuration : profile.adjustDuration
        let rawTargetDB = profile.gainDB(for: clamped)
        let targetDB = rawTargetDB.isFinite ? rawTargetDB : Self.silenceFloorDB
        let duration = profile.rampDuration(base: base, distanceDB: targetDB - gain.current)

        gain.set(targetDB, over: duration)
        bodyGain.set(profile.bodyGainDB(for: clamped), over: duration)
        airGain.set(profile.airGainDB(for: clamped), over: duration)
        detailGain.set(profile.detailGainDB(for: clamped), over: duration)
        if let targetWidth = profile.stereoWidth(for: clamped) {
            width.set(targetWidth, over: duration)
        }
        if let targetMix = profile.reverbWetDryMix(for: clamped) {
            reverbMix?.set(targetMix, over: duration)
        }

        if restarting { startPlaybackIfNeeded() }
    }

    func fadeOut(over duration: TimeInterval) {
        // Fading out *is* going to zero. Leaving `intensity` at its old value
        // would make the next `setIntensity` think the layer is already audible,
        // so it would ramp a gain that no longer has a player behind it.
        intensity = 0

        guard isActive || !gain.isSettled else {
            applyToNodes()
            return
        }
        isFadingToSilence = true
        let duration = profile.rampDuration(base: duration,
                                            distanceDB: Self.silenceFloorDB - gain.current)
        gain.set(Self.silenceFloorDB, over: duration)
        // Tone settles back to neutral while it goes, so a re-open starts from
        // the same place it left.
        bodyGain.set(profile.bodyGainDB(for: 0), over: duration)
        airGain.set(profile.airGainDB(for: 0), over: duration)
        detailGain.set(0, over: duration)
        if let narrow = profile.stereoWidth?.low {
            width.set(narrow, over: duration)
        }
        if let range = profile.reverbWetDryMixRange {
            reverbMix?.set(range.low, over: duration)
        }
    }

    // MARK: Clock

    func tick(delta: TimeInterval) {
        guard isActive || !gain.isSettled else { return }

        gain.tick(delta: delta)
        bodyGain.tick(delta: delta)
        airGain.tick(delta: delta)
        detailGain.tick(delta: delta)
        width.tick(delta: delta)
        reverbMix?.tick(delta: delta)

        applyToNodes()

        if isFadingToSilence, gain.isSettled {
            isFadingToSilence = false
            stopPlayback()
            host?.layerDidGoIdle(self)
        }
    }

    private func applyToNodes() {
        gainMixer.outputVolume = Self.amplitude(fromDB: gain.current)
        equalizer.bands[0].gain = bodyGain.current
        equalizer.bands[1].gain = airGain.current
        equalizer.bands[2].gain = detailGain.current

        if let reverbMix { reverb.wetDryMix = reverbMix.current }

        if let directPath, let centreFold {
            // A width of 1 leaves the recording untouched: the fold is silent
            // and the direct path is at unity. Narrowing crossfades the two, so
            // the middle of the image keeps its level throughout.
            let fold = max(0, 1 - width.current)
            directPath.outputVolume = 1 - fold
            centreFold.outputVolume = fold * Self.centreFoldCompensation
        }
    }

    /// The fold path passes through a stereo-to-mono connection and back out to
    /// a stereo bus, and the engine applies its own gain at each. This puts the
    /// centre sum back at the level the width maths assumes. Measured with the
    /// offline probe, not guessed.
    nonisolated private static let centreFoldCompensation: Float = 1.0

    nonisolated private static func amplitude(fromDB db: Float) -> Float {
        db <= audibleFloorDB ? 0 : powf(10, db / 20)
    }

    // MARK: Playback

    private func startPlaybackIfNeeded() {
        guard !isActive else { return }
        isActive = true

        if buffer != nil {
            beginPlayback()
            return
        }

        guard loadTask == nil else { return }
        let assetName = assetName
        let crossfade = profile.loopCrossfade
        let quietWeight = profile.loopJoinQuietWeight
        let highPass = profile.highPassFrequency
        loadTask = Task { [weak self] in
            let loaded = await Self.loadBuffer(named: assetName,
                                               crossfade: crossfade,
                                               quietWeight: quietWeight,
                                               highPass: highPass)
            guard let self, !Task.isCancelled else { return }
            self.loadTask = nil
            guard let loaded else {
                self.isActive = false
                return
            }
            self.buffer = loaded.buffer
            self.sourceStatistics = loaded.statistics
            self.loopReport = loaded.loop
            self.equalizer.globalGain = loaded.statistics.makeupGainDB(for: self.profile)
            // The slider may have gone back to zero while the file was loading.
            guard self.isActive else { return }
            self.beginPlayback()
        }
    }

    private func beginPlayback() {
        guard let host, let buffer else { return }

        connectIfNeeded(format: buffer.format)

        do {
            try host.engineWillStartPlayback()
        } catch {
            isActive = false
            return
        }

        guard !player.isPlaying else { return }

        // Reading the recording takes a moment the first time, and the gain ramp
        // has been running against the clock all the while — against silence.
        // Rewind it to the floor so the fade happens over the audio rather than
        // before it, or the first sound the user ever hears arrives at full
        // level with no fade at all.
        let target = gain.target
        gain.reset(to: Self.silenceFloorDB)
        applyToNodes()

        // `.loops` hands the loop to the render thread, so the seam is
        // sample-accurate and cannot drift or gap the way re-scheduling can.
        player.scheduleBuffer(buffer, at: nil, options: [.loops])
        player.play()

        gain.set(target, over: profile.rampDuration(base: profile.fadeInDuration,
                                                    distanceDB: target - Self.silenceFloorDB))
        installMeterTap()
    }

    private func connectIfNeeded(format: AVAudioFormat) {
        guard !isConnected, let engine = host?.engine else { return }

        engine.connect(player, to: equalizer, format: format)

        if let directPath, let centreFold, let widthMixer {
            engine.connect(equalizer, to: [
                AVAudioConnectionPoint(node: directPath, bus: 0),
                AVAudioConnectionPoint(node: centreFold, bus: 0)
            ], fromBus: 0, format: format)
            engine.connect(directPath, to: widthMixer, fromBus: 0, toBus: 0, format: format)
            // A mono connection format is what actually folds the two channels
            // together; the width mixer then places that sum back in the centre.
            let centreFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)
            engine.connect(centreFold, to: widthMixer, fromBus: 0, toBus: 1, format: centreFormat)
            engine.connect(widthMixer, to: reverb, format: format)
        } else {
            engine.connect(equalizer, to: reverb, format: format)
        }

        engine.connect(reverb, to: limiter, format: format)
        engine.connect(limiter, to: gainMixer, format: format)
        engine.connect(gainMixer, to: engine.mainMixerNode, format: nil)
        isConnected = true
    }

    /// Transparent protection, not an effect: it only has anything to do when a
    /// droplet impact would otherwise exceed the ceiling, which in the rain
    /// recording is a few hundred samples out of five million.
    private func configureLimiter() {
        limiter.auAudioUnit.parameterTree?.parameter(withAddress: AUParameterAddress(kLimiterParam_AttackTime))?
            .value = 0.002
        limiter.auAudioUnit.parameterTree?.parameter(withAddress: AUParameterAddress(kLimiterParam_DecayTime))?
            .value = 0.03
        limiter.auAudioUnit.parameterTree?.parameter(withAddress: AUParameterAddress(kLimiterParam_PreGain))?
            .value = 0
    }

    private func stopPlayback() {
        isActive = false
        isFadingToSilence = false
        removeMeterTap()
        if player.isPlaying { player.stop() }
        gain.reset(to: Self.silenceFloorDB)
        gainMixer.outputVolume = 0
        meter.reset()
    }

    // MARK: EQ

    private func configureBands() {
        let body = equalizer.bands[0]
        body.filterType = .lowShelf
        body.frequency = profile.bodyFrequency
        body.gain = profile.bodyGainDB(for: 0)
        body.bypass = false

        let air = equalizer.bands[1]
        air.filterType = .highShelf
        air.frequency = profile.airFrequency
        air.gain = profile.airGainDB(for: 0)
        air.bypass = false

        let detail = equalizer.bands[2]
        detail.filterType = .parametric
        detail.frequency = profile.detailFrequency
        detail.bandwidth = profile.detailBandwidth
        detail.gain = 0
        detail.bypass = false
    }

    // MARK: Metering

    private var hasMeterTap = false

    private func installMeterTap() {
        guard !hasMeterTap else { return }
        hasMeterTap = true
        let meter = meter
        gainMixer.installTap(onBus: 0, bufferSize: 2048, format: nil) { buffer, _ in
            meter.update(with: buffer)
        }
    }

    private func removeMeterTap() {
        guard hasMeterTap else { return }
        hasMeterTap = false
        gainMixer.removeTap(onBus: 0)
    }

    // MARK: Loading

    private struct LoadedBuffer: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        let statistics: AmbientSourceStatistics
        let loop: AmbientLoopReport
    }

    /// The whole recording is held in memory so the loop can be handed to the
    /// render thread as a single buffer, which is the only way to be certain the
    /// seam is sample-accurate. Rain is ~21 MB at 44.1 kHz stereo float; if the
    /// full set of sounds ever makes that uncomfortable, the assets are the
    /// place to fix it (shorter loops, or mono sources widened by the reverb),
    /// not this class.
    nonisolated private static func loadBuffer(named name: String,
                                               crossfade: TimeInterval,
                                               quietWeight: Float,
                                               highPass: Float?) async -> LoadedBuffer? {
        await Task.detached(priority: .userInitiated) { () -> LoadedBuffer? in
            do {
                let url = try AudioAssetStore.url(forDataSet: name)
                let file = try AVAudioFile(forReading: url)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)) else {
                    return nil
                }
                try file.read(into: buffer)
                if let highPass { applyHighPass(to: buffer, frequency: highPass) }
                let prepared = seamlessLoop(from: buffer,
                                            crossfade: crossfade,
                                            quietWeight: quietWeight)
                let looped = prepared?.buffer ?? buffer
                return LoadedBuffer(buffer: looped,
                                    statistics: measure(looped),
                                    loop: describeLoop(looped,
                                                       tiltCorrectedDB: prepared?.tiltCorrectedDB ?? 0))
            } catch {
                return nil
            }
        }.value
    }

    /// Fourth-order Butterworth high-pass, applied in place.
    ///
    /// Two biquad sections rather than a chain of one-pole filters: a one-pole
    /// cascade has such a wide skirt that clearing rumble below 20 Hz would also
    /// take several decibels out of the low mids, which for a campfire is the
    /// warmth. This is flat by 100 Hz.
    nonisolated private static func applyHighPass(to buffer: AVAudioPCMBuffer, frequency: Float) {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let sampleRate = Float(buffer.format.sampleRate)
        let frames = Int(buffer.frameLength)
        // Butterworth pole quality factors for a fourth-order response.
        let stages: [Float] = [0.541_20, 1.306_56]

        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for q in stages {
                let w0 = 2 * Float.pi * frequency / sampleRate
                let cosine = cos(w0)
                let alpha = sin(w0) / (2 * q)
                let a0 = 1 + alpha
                let b0 = ((1 + cosine) / 2) / a0
                let b1 = (-(1 + cosine)) / a0
                let b2 = b0
                let a1 = (-2 * cosine) / a0
                let a2 = (1 - alpha) / a0

                var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
                for frame in 0..<frames {
                    let x0 = samples[frame]
                    let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                    x2 = x1; x1 = x0
                    y2 = y1; y1 = y0
                    samples[frame] = y0
                }
            }
        }
    }

    /// Makes a recording join onto itself.
    ///
    /// Two separate problems, both of which a short loop exposes.
    ///
    /// The join itself: field recordings do not end where they began, so looping
    /// one raw puts a step at every wrap. Laying the tail over the head with an
    /// equal-power crossfade and dropping the overlap gives a slightly shorter
    /// recording whose end runs continuously into its own beginning. Equal power
    /// rather than equal gain, because the two ends are uncorrelated and a
    /// linear fade would dip through the middle of the blend.
    ///
    /// The tilt: the wind bed is nearly 5 dB louder at its head than at its
    /// tail. A seamless join does not fix that — it just turns the step into a
    /// swell that arrives every five seconds, which the ear hears as a rhythm.
    /// So before blending, a gentle ramp is applied across the whole recording
    /// to bring the two ends level. It is bounded to a few dB spread over
    /// several seconds, far too slow to hear as processing, and it leaves the
    /// wind's own gusting untouched.
    nonisolated private static func seamlessLoop(from source: AVAudioPCMBuffer,
                                                 crossfade: TimeInterval,
                                                 quietWeight: Float)
        -> (buffer: AVAudioPCMBuffer, tiltCorrectedDB: Float)? {
        guard crossfade > 0,
              let sourceChannels = source.floatChannelData else { return nil }

        let sampleRate = source.format.sampleRate
        let total = Int(source.frameLength)
        let channelCount = Int(source.format.channelCount)

        func windowRMS(_ range: Range<Int>) -> Double {
            guard range.lowerBound >= 0, range.upperBound <= total, !range.isEmpty else { return 0 }
            var sum: Double = 0
            for channel in 0..<channelCount {
                let input = sourceChannels[channel]
                for frame in range {
                    sum += Double(input[frame]) * Double(input[frame])
                }
            }
            return sqrt(sum / Double(range.count * channelCount))
        }

        // The join lands wherever the crossfade starts, and a recording is not
        // equally even everywhere. Trying a spread of crossfade lengths and
        // keeping the best one costs a handful of sums.
        //
        // "Best" means the two sides match in level, and — for an intermittent
        // sound, where `quietWeight` is above zero — that the join sits in a
        // quiet moment. A perfectly matched join in the middle of a bird call
        // still cuts the call in half.
        // A sound hunting for a gap needs more places to look. A continuous bed
        // does not, and searching harder would only move a join that is already
        // where it should be.
        let edge = max(1, Int(sampleRate * 0.05))
        let overallDB = 20 * log10(max(windowRMS(0..<total), 1e-9))
        let steps = quietWeight > 0 ? 25 : 13
        let stride = quietWeight > 0 ? 0.05 : 0.08
        let origin = quietWeight > 0 ? 0.5 : 0.6
        var overlap = Int(crossfade * sampleRate)
        var bestCost = Double.greatestFiniteMagnitude
        for step in 0..<steps {
            let candidate = Int(crossfade * sampleRate * (origin + stride * Double(step)))
            guard candidate > 64, candidate < total / 3 else { continue }
            let joinAt = total - candidate
            let before = windowRMS((joinAt - edge)..<joinAt)
            let after = windowRMS(joinAt..<(joinAt + edge))
            guard before > 1e-9, after > 1e-9 else { continue }

            let mismatch = abs(20 * log10(after / before))
            let joinDB = 20 * log10(max((before + after) / 2, 1e-9))
            let loudness = max(0, joinDB - overallDB)
            let cost = mismatch + Double(quietWeight) * loudness
            if cost < bestCost {
                bestCost = cost
                overlap = candidate
            }
        }

        // The overlap has to leave a healthy stretch of untouched recording
        // between the two blended ends.
        guard overlap > 64, overlap < total / 3 else { return nil }

        let loopLength = total - overlap
        guard let output = AVAudioPCMBuffer(pcmFormat: source.format,
                                            frameCapacity: AVAudioFrameCount(loopLength)),
              let outputChannels = output.floatChannelData else { return nil }

        // How much louder the head is than the tail it will be blended with.
        let headRMS = windowRMS(0..<overlap)
        let tailRMS = windowRMS(loopLength..<total)
        let rawTilt = (headRMS > 1e-9 && tailRMS > 1e-9)
            ? Float(20 * log10(headRMS / tailRMS))
            : 0
        let tiltDB = min(6, max(-6, rawTilt))

        // Half the correction is taken off the head and half added to the tail,
        // so the recording's overall level is unchanged.
        let span = Float(max(1, total - 1))
        func tilt(_ frame: Int) -> Float {
            powf(10, (-tiltDB / 2 + tiltDB * Float(frame) / span) / 20)
        }

        for channel in 0..<channelCount {
            let input = sourceChannels[channel]
            let result = outputChannels[channel]

            for frame in 0..<overlap {
                let t = Float(frame) / Float(overlap)
                let rising = sinf(t * .pi / 2)
                let falling = cosf(t * .pi / 2)
                result[frame] = input[frame] * tilt(frame) * rising
                    + input[loopLength + frame] * tilt(loopLength + frame) * falling
            }
            for frame in overlap..<loopLength {
                result[frame] = input[frame] * tilt(frame)
            }
        }

        output.frameLength = AVAudioFrameCount(loopLength)
        return (output, tiltDB)
    }

    /// Measures how the prepared loop behaves at its join.
    nonisolated private static func describeLoop(_ buffer: AVAudioPCMBuffer,
                                                 tiltCorrectedDB: Float) -> AmbientLoopReport {
        let sampleRate = buffer.format.sampleRate
        let total = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard let channels = buffer.floatChannelData, total > 0 else {
            return AmbientLoopReport(duration: 0, headRMSDBFS: -96, tailRMSDBFS: -96,
                                     joinDiscontinuity: 0, tiltCorrectedDB: tiltCorrectedDB,
                                     levelRangeDB: 0, typicalWindowStepDB: 0)
        }

        func rms(_ range: Range<Int>) -> Float {
            var sum: Double = 0
            for channel in 0..<channelCount {
                for frame in range {
                    let sample = Double(channels[channel][frame])
                    sum += sample * sample
                }
            }
            return Float(sqrt(sum / Double(max(1, range.count * channelCount))))
        }
        func dB(_ value: Float) -> Float { 20 * log10(max(value, 1e-6)) }

        let edge = min(total / 4, Int(sampleRate * 0.05))

        // The join: the loop's last sample runs straight into its first.
        var discontinuity: Float = 0
        var peak: Float = 0
        for channel in 0..<channelCount {
            discontinuity = max(discontinuity,
                                abs(channels[channel][0] - channels[channel][total - 1]))
            for frame in 0..<total { peak = max(peak, abs(channels[channel][frame])) }
        }

        // The recording's own gusting, measured in quarter-second windows.
        let windowFrames = max(1, Int(sampleRate * 0.25))
        var quietest = Float.greatestFiniteMagnitude
        var loudest: Float = 0
        var start = 0
        while start + windowFrames <= total {
            let level = rms(start..<(start + windowFrames))
            quietest = min(quietest, level)
            loudest = max(loudest, level)
            start += windowFrames
        }

        // How much the level normally moves from one 50 ms window to the next.
        var steps: [Float] = []
        var previous: Float?
        var cursor = 0
        while cursor + edge <= total {
            let level = dB(rms(cursor..<(cursor + edge)))
            if let previous { steps.append(abs(level - previous)) }
            previous = level
            cursor += edge
        }
        steps.sort()
        let typicalStep = steps.isEmpty ? 0 : steps[steps.count / 2]

        return AmbientLoopReport(
            duration: Double(total) / sampleRate,
            headRMSDBFS: dB(rms(0..<edge)),
            tailRMSDBFS: dB(rms((total - edge)..<total)),
            joinDiscontinuity: peak > 0 ? discontinuity / peak : 0,
            tiltCorrectedDB: tiltCorrectedDB,
            levelRangeDB: (loudest > 0 && quietest < .greatestFiniteMagnitude)
                ? dB(loudest) - dB(quietest) : 0,
            typicalWindowStepDB: typicalStep
        )
    }

    /// One pass over the buffer for RMS and a histogram of sample magnitudes,
    /// from which the working peak percentile is read back.
    nonisolated private static func measure(_ buffer: AVAudioPCMBuffer) -> AmbientSourceStatistics {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else {
            return AmbientSourceStatistics(rmsDBFS: -96, workingPeakDBFS: -96,
                                           nearPeakDBFS: -96, truePeakDBFS: -96)
        }

        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let binCount = 2048

        var squareSum: Double = 0
        var truePeak: Float = 0
        var histogram = [Int](repeating: 0, count: binCount)
        var total = 0

        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frames {
                let magnitude = abs(samples[frame])
                squareSum += Double(magnitude) * Double(magnitude)
                truePeak = max(truePeak, magnitude)
                let bin = min(binCount - 1, Int(magnitude * Float(binCount)))
                histogram[bin] += 1
                total += 1
            }
        }

        let rms = sqrt(squareSum / Double(max(1, total)))

        // Walk down from the top, noting the level each allowance is passed.
        func level(passing fraction: Double) -> Float {
            let allowance = max(1, Int(Double(total) * fraction))
            var counted = 0
            for bin in stride(from: binCount - 1, through: 0, by: -1) {
                counted += histogram[bin]
                if counted >= allowance {
                    return Float(bin + 1) / Float(binCount)
                }
            }
            return Float(binCount) / Float(binCount)
        }

        func dB(_ value: Float) -> Float { 20 * log10(max(value, 1e-6)) }
        return AmbientSourceStatistics(rmsDBFS: dB(Float(rms)),
                                       workingPeakDBFS: dB(level(passing: 0.0001)),
                                       nearPeakDBFS: dB(level(passing: 0.00001)),
                                       truePeakDBFS: dB(truePeak))
    }
}

// MARK: - Meter

/// Reads the layer's own output. Written from the render thread by the tap and
/// read from the main actor by the mixer UI, so it is behind a lock.
private final class MeterBox: Sendable {

    private let storage = OSAllocatedUnfairLock(initialState: Float(0))

    var value: Float { storage.withLock { $0 } }

    func reset() { storage.withLock { $0 = 0 } }

    nonisolated func update(with buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        var sum: Float = 0
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in stride(from: 0, to: frames, by: 4) {
                let sample = samples[frame]
                sum += sample * sample
            }
        }
        let counted = Float(max(1, (frames / 4) * channelCount))
        let rms = sqrtf(sum / counted)

        // Normalised against the profile's own ceiling so a full slider reads
        // near the top of the meter, then smoothed so the UI does not flicker.
        let normalised = min(1, rms * 3.2)
        storage.withLock { previous in
            previous += (normalised - previous) * 0.25
        }
    }
}
