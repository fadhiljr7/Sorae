//
//  AmbientSoundLayer.swift
//  Sorae
//
//  One playable ambience — rain, and later wind, ocean, fire.
//
//  The UI only ever says `setIntensity(_:)`. How a given sound turns "how
//  present should this feel" into gain, tone and space is the layer's business,
//  described by its `AmbientIntensityProfile`. That is what keeps a future
//  Ocean layer from having to behave like rain.
//

import AVFoundation

@MainActor
protocol AmbientSoundLayer: AnyObject {

    /// Matches `SoundChannel.id`.
    var id: String { get }

    /// 0...1, the last value asked for (not the ramped value that is currently
    /// audible).
    var intensity: Float { get }

    /// True while the layer holds audio resources.
    var isActive: Bool { get }

    /// Live output level, 0...1, measured from the layer's own output.
    var outputLevel: Float { get }

    /// Attach the layer's nodes. Called once per engine lifetime.
    func attach(to host: AmbientEngineHost)

    /// How present this sound should feel, 0...1. Never jumps: the layer ramps
    /// every parameter it changes.
    func setIntensity(_ intensity: Float)

    /// Advance ramps. Driven by the controller's clock so every layer moves on
    /// the same tick.
    func tick(delta: TimeInterval)

    /// The layer's own fade-out time, so callers that simply want it to stop
    /// gently do not have to invent a number and accidentally cut short a fade
    /// that is already running.
    var fadeOutDuration: TimeInterval { get }

    /// Fade out over `duration` and release audio resources at the end.
    func fadeOut(over duration: TimeInterval)

    /// Immediate teardown, no fade. Used when the whole engine goes away.
    func teardown()

    /// The engine's graph was rebuilt underneath us — typically a route change,
    /// such as headphones being plugged in. Connections and the running player
    /// are no longer valid and must be re-made.
    func engineConfigurationDidChange()
}

/// What a layer needs from whoever owns the `AVAudioEngine`. Layers never start
/// or stop the engine or the audio session themselves — they ask.
@MainActor
protocol AmbientEngineHost: AnyObject {
    var engine: AVAudioEngine { get }
    /// Bring the engine and audio session up. Throws if audio is unavailable.
    func engineWillStartPlayback() throws
    /// A layer has finished fading out and released its resources.
    func layerDidGoIdle(_ layer: AmbientSoundLayer)
}

// MARK: - Intensity profile

/// The recipe that turns a 0...1 intensity into audio parameters for one sound.
///
/// Every value here is a design dial. A new ambience is a new profile, not a
/// new class.
struct AmbientIntensityProfile: Sendable {

    // MARK: Calibration
    //
    // Recordings arrive at whatever level they were captured at — the rain
    // asset sits at -44 dBFS RMS — so each layer measures its own source once
    // and applies makeup gain to reach these targets. That keeps every sound at
    // a consistent loudness without hand-tuned numbers per asset, and it means
    // the intensity curve below can be written in relative terms.

    /// Where full intensity should land, in RMS dBFS. Ambience for sleep sits
    /// well below music; this is a level you can leave on all night.
    var targetRMSDBFS: Float = -26
    /// Peak ceiling used to cap makeup gain. The margin below 0 dBFS leaves
    /// room for the EQ's presence lift and the reverb.
    var peakCeilingDBFS: Float = -2

    /// Which peak the ceiling is measured against.
    var peakReference: PeakReference = .workingPeak

    enum PeakReference: Sendable {
        /// The level 99.99% of samples sit below. A handful of transients above
        /// it reach the limiter, which is the right trade for a dense source
        /// where those transients are texture rather than content.
        case workingPeak
        /// The level 99.999% of samples sit below. For a recording with a very
        /// high crest factor this buys back several decibels of usable level
        /// while leaving the transients themselves alone — the limiter can only
        /// touch the top thousandth of a percent, and then only by a decibel or
        /// two of a few milliseconds.
        case nearPeak
        /// The loudest sample in the recording. Nothing ever reaches the
        /// limiter, so the recording's dynamics arrive completely untouched.
        /// The right choice when the loud moments *are* the sound.
        case truePeak
    }

    // MARK: Loudness curve
    //
    // Relative to the calibrated full-intensity level: 0 dB is full, and the
    // floor is how far below that intensity 0⁺ sits.

    /// Level at intensity 0⁺, relative to unity.
    var minimumGainDB: Float = -44
    /// Level at full intensity. Sits below unity so that the handful of droplet
    /// impacts the limiter has already caught at 0 dBFS still land with real
    /// headroom, which also covers inter-sample peaks after resampling to
    /// whatever the output device is running at.
    var maximumGainDB: Float = -1.5
    /// Shapes the travel between the two. Below 1 it spends more of the slider
    /// in quiet territory, which is what makes the bottom of the range usable
    /// instead of a step from "off" to "loud".
    var gainCurveExponent: Float = 0.55

    /// Anything at or below this reads as off.
    var silenceThreshold: Float = 0.005

    // MARK: Tone
    //
    // Three gentle bands. At low intensity the sound sits back — a little less
    // top end, a little more body — and at high intensity a touch of air and
    // sparkle returns so individual detail reads. Everything is a few dB; none
    // of it should be identifiable as "an EQ".

    /// Intensity at which the sound is heard exactly as recorded.
    var neutralIntensity: Float = 0.55

    var bodyFrequency: Float = 160
    /// Low shelf, dB at intensity 0 → at neutral → at 1.
    var bodyGainDB: (low: Float, neutral: Float, high: Float) = (1.5, 0, -1.5)

    var airFrequency: Float = 3800
    /// High shelf, dB at intensity 0 → at neutral → at 1.
    var airGainDB: (low: Float, neutral: Float, high: Float) = (-6.5, 0, 2.2)

    var detailFrequency: Float = 7500
    var detailBandwidth: Float = 1.0
    /// Presence peak that only opens up in the top of the range.
    var detailGainDB: Float = 1.8
    var detailOnsetIntensity: Float = 0.6

    // MARK: Space

    /// A hint of room, not a room. Constant across the range on purpose:
    /// reverb is not the intensity mechanism, and moving it is the fastest way
    /// to make ambience sound artificial.
    var reverbPreset: AVAudioUnitReverbPreset = .smallRoom
    var reverbWetDryMix: Float = 6

    /// Lets the sense of space follow intensity instead of staying put.
    ///
    /// Only worth doing where distance is the metaphor and the source is a
    /// point rather than a field: something far away outdoors reaches you more
    /// reverberant than dry, because the direct sound has faded while the
    /// scattered sound has not. `nil` keeps `reverbWetDryMix` fixed, which is
    /// what a continuous bed like rain or wind wants.
    var reverbWetDryMixRange: (low: Float, neutral: Float, high: Float)?

    /// How much of the recording's own stereo spread to use, as a multiplier on
    /// its side signal. 1 is the recording exactly as it was made; below 1 draws
    /// it toward the centre, which reads as further away and also survives being
    /// folded to a single speaker.
    ///
    /// `nil` means the width stage is not built at all — no extra nodes, no
    /// processing, the signal path is untouched. This is never a moving effect:
    /// the value follows the fader and nothing else, so the image opens and
    /// closes with intensity rather than wandering left and right.
    var stereoWidth: StereoWidth?

    struct StereoWidth: Sendable {
        var low: Float
        var neutral: Float
        var high: Float
    }

    // MARK: Repair

    /// Corner frequency of a fourth-order high-pass applied once, when the
    /// recording loads. `nil` leaves the recording alone, which is the right
    /// answer for a clean field recording.
    ///
    /// This is not tone shaping. It exists for recordings carrying rumble below
    /// the range of anything they were pointed at — mic handling, wind on the
    /// capsule — which no phone can reproduce but which still dominates the
    /// level measurements and eats the headroom that the actual sound needs.
    var highPassFrequency: Float?

    // MARK: Looping

    /// Seconds of the recording's tail crossfaded over its head when it loads,
    /// so the loop joins onto itself with no step in level. 0 leaves the file
    /// exactly as recorded, which is right when its ends already match.
    var loopCrossfade: TimeInterval = 0

    /// How strongly to prefer a quiet moment when choosing where the loop
    /// joins. For a continuous bed, matching the levels either side is all that
    /// matters and this stays 0. For an intermittent sound it matters more that
    /// the join lands in a gap: a well-matched join in the middle of a bird call
    /// still cuts the call in half.
    var loopJoinQuietWeight: Float = 0

    // MARK: Ramp times

    /// Rising out of silence. Long, so the sound arrives rather than starts.
    var fadeInDuration: TimeInterval = 1.4
    /// Returning to silence.
    var fadeOutDuration: TimeInterval = 1.1
    /// Ordinary slider movement between two audible levels.
    var adjustDuration: TimeInterval = 0.28
    /// Ceiling on how fast the level is allowed to travel, whatever the UI asks
    /// for. A finger thrown from silence to full in a tenth of a second would
    /// otherwise cover fifty decibels inside one ramp and step audibly; this
    /// stretches the ramp instead. Small moves are unaffected — they are slower
    /// than this already.
    var maximumSlewDBPerSecond: Float = 90

    // MARK: Derived

    /// Perceptual gain in dB for an intensity, relative to the calibrated
    /// full-intensity level. See `gainCurveExponent`.
    /// nil when this sound's sense of space does not move.
    func reverbWetDryMix(for intensity: Float) -> Float? {
        guard let range = reverbWetDryMixRange else { return nil }
        return interpolate((range.low, range.neutral, range.high), at: intensity)
    }

    func gainDB(for intensity: Float) -> Float {
        guard intensity > silenceThreshold else { return -.infinity }
        let shaped = powf(min(1, max(0, intensity)), gainCurveExponent)
        return minimumGainDB + (maximumGainDB - minimumGainDB) * shaped
    }

    /// Linear amplitude for an intensity, 0 at silence.
    func amplitude(for intensity: Float) -> Float {
        let db = gainDB(for: intensity)
        return db.isFinite ? powf(10, db / 20) : 0
    }

    func bodyGainDB(for intensity: Float) -> Float {
        interpolate(bodyGainDB, at: intensity)
    }

    func airGainDB(for intensity: Float) -> Float {
        interpolate(airGainDB, at: intensity)
    }

    /// nil when this sound has no width stage.
    func stereoWidth(for intensity: Float) -> Float? {
        guard let stereoWidth else { return nil }
        return interpolate((stereoWidth.low, stereoWidth.neutral, stereoWidth.high), at: intensity)
    }

    func detailGainDB(for intensity: Float) -> Float {
        guard intensity > detailOnsetIntensity else { return 0 }
        let t = (intensity - detailOnsetIntensity) / max(0.0001, 1 - detailOnsetIntensity)
        return detailGainDB * smoothstep(t)
    }

    /// Two-segment interpolation through the neutral point, so "as recorded"
    /// lands exactly where the profile says it should.
    private func interpolate(_ points: (low: Float, neutral: Float, high: Float), at intensity: Float) -> Float {
        let i = min(1, max(0, intensity))
        if i <= neutralIntensity {
            let t = i / max(0.0001, neutralIntensity)
            return points.low + (points.neutral - points.low) * smoothstep(t)
        } else {
            let t = (i - neutralIntensity) / max(0.0001, 1 - neutralIntensity)
            return points.neutral + (points.high - points.neutral) * smoothstep(t)
        }
    }

    /// The time a move of `distanceDB` should take: the requested duration,
    /// stretched if that would exceed the slew ceiling.
    func rampDuration(base: TimeInterval, distanceDB: Float) -> TimeInterval {
        guard distanceDB.isFinite, maximumSlewDBPerSecond > 0 else { return base }
        return max(base, TimeInterval(abs(distanceDB) / maximumSlewDBPerSecond))
    }

    private func smoothstep(_ t: Float) -> Float {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }
}

extension AmbientIntensityProfile {

    /// Rain: a wide, dense, noise-like source. It takes EQ well and needs very
    /// little space added, so almost all of the perceived change comes from the
    /// gain curve. Its recording runs for a minute and its ends already meet,
    /// so it needs neither a width stage nor a loop crossfade.
    static let rain = AmbientIntensityProfile()

    /// Wind. Three things make it behave unlike rain.
    ///
    /// Its recording is very wide — the side signal is louder than the middle,
    /// which is striking on headphones and largely cancels on a single speaker.
    /// So the width stage exists here, drawing the image toward the centre when
    /// the wind should feel distant and opening out to the recording's own
    /// spread at full intensity.
    ///
    /// Its tone shaping sits much lower than rain's — 220 Hz and 2.6 kHz rather
    /// than 160 Hz and 3.8 kHz — because that is where this recording's energy
    /// actually is. A shelf at 3.8 kHz has almost nothing to work on here.
    ///
    /// The direction is the same as rain's, and deliberately so: distance
    /// absorbs high frequencies, so far-away wind is darker. An earlier version
    /// cut the body at low intensity on the theory that distant wind has less
    /// buffeting; measured, that just made it thinner and relatively brighter,
    /// which reads as closer, not further. The body band now lifts slightly when
    /// the wind is faint and eases back when it is strong, which also keeps the
    /// low end from becoming tiring at the top of the range.
    ///
    /// And it is six seconds long, so the loop comes round often enough that the
    /// join has to be made rather than assumed.
    static let wind: AmbientIntensityProfile = {
        var profile = AmbientIntensityProfile()

        // Calibration happens before the tone shaping, and wind's shaping ends
        // up a little lossy at full intensity — it eases the low end back, which
        // is where most of this recording's energy sits. Aiming higher lands
        // wind at the same delivered level as rain, so a fader at the top means
        // the same thing for both.
        profile.targetRMSDBFS = -24.6

        profile.bodyFrequency = 220
        profile.bodyGainDB = (low: 1.0, neutral: 0, high: -1.0)
        profile.airFrequency = 2600
        profile.airGainDB = (low: -5.5, neutral: 0, high: 2.5)
        profile.detailFrequency = 5200
        profile.detailBandwidth = 1.2
        profile.detailGainDB = 1.5

        // The recording carries plenty of its own space already.
        profile.reverbWetDryMix = 3.5
        profile.stereoWidth = StereoWidth(low: 0.55, neutral: 0.8, high: 1.0)
        profile.loopCrossfade = 0.9

        // Wind gathers and dies away; it should arrive a little more slowly
        // than rain does.
        profile.fadeInDuration = 1.6
        profile.fadeOutDuration = 1.3

        return profile
    }()

    /// Birds.
    ///
    /// The recording is intermittent — calls punching out of quiet gaps, with
    /// twelve decibels between its quiet and busy moments where rain has five.
    /// That intermittency is the sound. Everything here is arranged so nothing
    /// flattens it:
    ///
    /// The gain is set against the recording's *true* peak rather than a
    /// percentile, so the limiter never engages and no call is ever shaved.
    /// That costs about a decibel of overall level, which is a bargain — the
    /// loud calls are what makes birds feel present, not the average.
    ///
    /// Turning it down is also what makes low intensity work: the quiet calls
    /// simply fall below hearing while the nearer ones stay, so few birds are
    /// audible rather than all of them equally. Nothing has to gate or trigger
    /// anything for that to happen.
    ///
    /// The sense of space follows the fader here, unlike rain and wind. A
    /// distant bird reaches you more scattered than direct, so the wet mix eases
    /// up as the intensity comes down. It is a few percent either way — enough
    /// to put the birds around the listener rather than inside their head.
    ///
    /// And the loop joins in a gap. On a continuous bed the only thing that
    /// matters is that the levels match; here a perfectly matched join in the
    /// middle of a call would still cut the call in half.
    static let bird: AmbientIntensityProfile = {
        var profile = AmbientIntensityProfile()

        profile.peakReference = .truePeak

        // Birds live in the top of the spectrum — this recording carries eight
        // decibels more above 2.5 kHz than below 300 Hz — so the shelves sit
        // where the calls are and the body band has almost nothing to do.
        profile.bodyFrequency = 250
        profile.bodyGainDB = (low: 0.5, neutral: 0, high: -0.5)
        profile.airFrequency = 3000
        profile.airGainDB = (low: -7.0, neutral: 0, high: 2.0)
        profile.detailFrequency = 6000
        profile.detailBandwidth = 1.2
        profile.detailGainDB = 1.5

        profile.reverbWetDryMixRange = (low: 9, neutral: 7, high: 5)

        // Nearly seventy seconds, so the join is rare — but it should still land
        // somewhere nothing is singing.
        profile.loopCrossfade = 1.5
        profile.loopJoinQuietWeight = 1.0

        profile.fadeInDuration = 1.5
        profile.fadeOutDuration = 1.2

        return profile
    }()

    /// A river.
    ///
    /// The most continuous of the four: two hundred millisecond windows move
    /// less than two decibels across the whole recording, where birds move
    /// twelve. Nothing here needs protecting from being flattened, and the
    /// recording is loud and even enough that its loudness target binds well
    /// before its peaks do — so it never approaches the limiter either.
    ///
    /// What distinguishes a near river from a far one is texture rather than
    /// weight. Far away it is a smooth filtered hiss; close up you hear
    /// individual gurgles and breaks in the flow. So the presence band does more
    /// of the work here than in any other profile — it opens earlier and lifts
    /// further, which is what brings that texture forward through the top half
    /// of the fader.
    ///
    /// The recording is also very nearly mono: its channels are 98% correlated,
    /// so there is no stereo image to preserve and narrowing it would be
    /// pointless. A little more room than rain gets is what stops it sitting as
    /// a point in the middle of the listener's head. It stays put — the spatial
    /// character should be stable, not moving.
    static let river: AmbientIntensityProfile = {
        var profile = AmbientIntensityProfile()

        profile.bodyFrequency = 180
        profile.bodyGainDB = (low: 1.5, neutral: 0, high: -0.5)
        profile.airFrequency = 3200
        profile.airGainDB = (low: -6.5, neutral: 0, high: 1.8)

        // Lower, wider and stronger than the others, and it opens from halfway
        // rather than from two-thirds.
        profile.detailFrequency = 5000
        profile.detailBandwidth = 1.4
        profile.detailGainDB = 2.2
        profile.detailOnsetIntensity = 0.5

        profile.reverbWetDryMix = 7

        return profile
    }()

    /// A campfire.
    ///
    /// This recording needed repairing before anything else could be decided.
    /// Nearly all of its energy sits below 10 Hz — mic rumble, not fire, and
    /// seventeen decibels above everything audible in it. Left in, it decides
    /// the loudness measurement, eats the headroom, and is inaudible on every
    /// device this will ever play on. A fourth-order high-pass at 35 Hz removes
    /// it and touches nothing a fire produces. It also happens to fix the loop:
    /// the seven-decibel step between the recording's ends turned out to be the
    /// rumble, and drops to half a decibel once it is gone.
    ///
    /// What remains has a thirty-five decibel crest factor — a quiet bed of
    /// hiss with a few very sharp cracks over it. That is the sound, so the gain
    /// is set against a high percentile rather than the loudness target: the bed
    /// lands at a usable level and the limiter can only reach the top thousandth
    /// of a percent of samples, by a decibel or so, for a few milliseconds. The
    /// small crackles stay small and the big pops stay big.
    ///
    /// Its stereo image is healthy on its own — the channels are half correlated
    /// — so it is left alone, and there is barely any reverb: a fire is a close,
    /// dry thing. What little there is eases up as the intensity falls, which is
    /// the whole of the distance cue.
    static let campfire: AmbientIntensityProfile = {
        var profile = AmbientIntensityProfile()

        profile.highPassFrequency = 35
        profile.peakReference = .nearPeak

        // The warmth is 60-500 Hz and the crackle is 1-6 kHz, so the shelves sit
        // lower than rain's and the presence band sits on the cracks themselves.
        profile.bodyFrequency = 200
        profile.bodyGainDB = (low: 1.0, neutral: 0, high: -0.5)
        profile.airFrequency = 2500
        profile.airGainDB = (low: -6.0, neutral: 0, high: 2.0)
        profile.detailFrequency = 4000
        profile.detailBandwidth = 1.2
        profile.detailGainDB = 1.8

        // Barely any, and less of it as the fire comes closer.
        profile.reverbWetDryMixRange = (low: 6, neutral: 4, high: 3)

        profile.fadeInDuration = 1.4
        profile.fadeOutDuration = 1.2

        return profile
    }()
}

// MARK: - Source calibration

/// What a layer measures about its recording, once, at load.
struct AmbientSourceStatistics: Sendable {

    /// Whole-file RMS in dBFS.
    let rmsDBFS: Float
    /// The level 99.99% of samples sit below. Used instead of the absolute peak
    /// because a handful of loud droplet impacts should not decide the gain for
    /// the entire recording — the limiter catches those.
    let workingPeakDBFS: Float
    /// The level 99.999% of samples sit below.
    let nearPeakDBFS: Float
    /// The true maximum sample, for reporting.
    let truePeakDBFS: Float

    /// Makeup gain that brings the recording to the profile's target level
    /// without pushing its working peak past the ceiling.
    func makeupGainDB(for profile: AmbientIntensityProfile) -> Float {
        let toTargetLoudness = profile.targetRMSDBFS - rmsDBFS
        let toPeakCeiling = profile.peakCeilingDBFS - referencePeakDBFS(for: profile)
        // AVAudioUnitEQ's global gain tops out at +24 dB.
        return min(toTargetLoudness, toPeakCeiling, 24)
    }

    func referencePeakDBFS(for profile: AmbientIntensityProfile) -> Float {
        switch profile.peakReference {
        case .workingPeak: workingPeakDBFS
        case .nearPeak: nearPeakDBFS
        case .truePeak: truePeakDBFS
        }
    }

    /// Which constraint decided the gain. Reported so it is obvious whether a
    /// sound is sitting at its loudness target or against its peak ceiling.
    func makeupLimit(for profile: AmbientIntensityProfile) -> String {
        let toTargetLoudness = profile.targetRMSDBFS - rmsDBFS
        return toTargetLoudness <= profile.peakCeilingDBFS - referencePeakDBFS(for: profile)
            ? "loudness target" : "peak ceiling"
    }
}

/// What loop preparation did to a recording, and how well its ends now meet.
/// Reported rather than inferred, because a seam is the one flaw in a looping
/// bed that is impossible to miss once you have heard it.
struct AmbientLoopReport: Sendable {
    let duration: TimeInterval
    /// Level of the first and last 50 ms of the prepared loop. These are what
    /// sit either side of the join.
    let headRMSDBFS: Float
    let tailRMSDBFS: Float
    /// Largest jump between adjacent samples across the join, relative to the
    /// recording's own peak. A click would show here.
    let joinDiscontinuity: Float
    /// How much head-to-tail tilt was ramped out.
    let tiltCorrectedDB: Float
    /// Spread between the quietest and loudest 250 ms of the loop — the
    /// recording's own gusting, which is left alone.
    let levelRangeDB: Float
    /// Median level change between neighbouring 50 ms windows anywhere in the
    /// loop. This is the number `joinStepDB` has to be compared against: a join
    /// that moves no more than the recording moves on its own is a join nobody
    /// can hear.
    let typicalWindowStepDB: Float

    var joinStepDB: Float { headRMSDBFS - tailRMSDBFS }
    /// True when the join is no more eventful than an ordinary moment.
    var joinIsIndistinguishable: Bool { abs(joinStepDB) <= typicalWindowStepDB * 1.5 }
}

// MARK: - Ramping

/// A value that always travels to its target rather than jumping there.
///
/// Gain is ramped in decibels, which is how loudness is actually perceived and
/// which gives the natural exponential shape a fade needs; EQ gains are already
/// in dB and ramp linearly.
struct RampedValue {

    private(set) var current: Float
    private(set) var target: Float
    private var remaining: TimeInterval = 0

    init(_ value: Float) {
        current = value
        target = value
    }

    var isSettled: Bool { remaining <= 0 }

    mutating func set(_ newTarget: Float, over duration: TimeInterval) {
        guard newTarget != target || !isSettled else { return }
        target = newTarget
        remaining = max(0, duration)
        if remaining == 0 { current = newTarget }
    }

    /// Snap without ramping — only for setup, never while audible.
    mutating func reset(to value: Float) {
        current = value
        target = value
        remaining = 0
    }

    mutating func tick(delta: TimeInterval) {
        guard remaining > 0 else {
            current = target
            return
        }
        if delta >= remaining {
            current = target
            remaining = 0
        } else {
            // Fraction of the way left to travel in this frame.
            let step = Float(delta / remaining)
            current += (target - current) * step
            remaining -= delta
        }
    }
}
