//
//  AudioIntensityProbe.swift
//  Sorae
//
//  Renders the ambience graph offline and measures it, so the intensity curve
//  and the transitions can be checked without anyone having to listen and
//  guess. Run with SORAE_AUDIO_PROBE=1; results go to the console.
//
//  It reports, per intensity: output RMS in dBFS, peak, and whether the signal
//  is bit-exact silence.
//
//  Transitions are checked on the parameter rather than on the audio. Rain is
//  noise, so its own envelope swings by several dB over any window short enough
//  to see a ramp in — measuring the rendered signal cannot tell a fade from the
//  weather. The gain the layer is applying is unambiguous: the probe traces it
//  every tick and reports the largest single-tick step and the peak slope. A
//  parameter that was assigned rather than ramped shows up as one step of the
//  full distance.
//
//  Debug only. Safe to delete.
//

#if DEBUG
import AVFoundation
import Foundation

@MainActor
enum AudioIntensityProbe {

    private static let sampleRate: Double = 44_100

    private struct Sound {
        let id: String
        let asset: String
        let profile: AmbientIntensityProfile
    }

    private static let sounds = [
        Sound(id: "rain", asset: "rainsound", profile: .rain),
        Sound(id: "wind", asset: "windsound", profile: .wind),
        Sound(id: "birds", asset: "birdsound", profile: .bird),
        Sound(id: "river", asset: "riversound", profile: .river),
        Sound(id: "campfire", asset: "campfiresound", profile: .campfire)
    ]

    static func run() async {
        for sound in sounds {
            await measure(sound)
        }
        await checkIndependence()
    }

    /// Rain and wind share one engine. This confirms they sum rather than
    /// interfere, and that moving one leaves the other exactly where it was.
    private static func checkIndependence() async {
        print("\n──────── all five together ────────")
        guard let rig = MixedRig(sounds: sounds) else {
            print("probe: could not build the mixed rig")
            return
        }

        // Every layer has to have finished reading its file before any
        // measuring starts. The renders below are synchronous, so a layer that
        // is still loading would never get the chance to start and would measure
        // as silence.
        rig.set(["rain": 0.4, "wind": 0.2, "birds": 0.1, "river": 0.5, "campfire": 0.7])
        var waited = 0
        while !rig.allLayersPlaying, waited < 300 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        guard rig.engine.isRunning, rig.allLayersPlaying else {
            print("probe: not every layer started (waited \(waited * 100) ms)")
            return
        }

        let mix: [String: Float] = ["rain": 0.4, "wind": 0.2, "birds": 0.1,
                                    "river": 0.5, "campfire": 0.7]
        var alone: [String: Float] = [:]
        for id in mix.keys.sorted() {
            var solo = mix.mapValues { _ in Float(0) }
            solo[id] = mix[id]
            let measured = rig.settle(solo)
            alone[id] = measured.rmsDB
            print(String(format: "  %-6@ %.2f alone            %7.2f dBFS",
                         id as NSString, mix[id] ?? 0, measured.rmsDB))
        }
        let together = rig.settle(mix)
        let expected = 10 * log10(alone.values.reduce(0) { $0 + pow(10, $1 / 10) })
        print(String(format: "  all five                   %7.2f dBFS   (independent sources would sum to %.2f)",
                     together.rmsDB, expected))

        // Whether moving wind disturbs rain cannot be answered by comparing two
        // rendered levels: rain loops for a minute, so any two windows land on
        // different weather and differ by a decibel regardless. Rain's own gain
        // parameter has no such ambiguity.
        // Move each sound to an extreme and back, and check the other three
        // never moved. Gains are exact, so this needs no tolerance.
        for moved in mix.keys.sorted() {
            _ = rig.settle(mix)
            let before = rig.allGainsDB()
            var pushed = mix
            pushed[moved] = 0.95
            _ = rig.settle(pushed)
            _ = rig.settle(mix)
            let after = rig.allGainsDB()
            let others = before.keys.filter { $0 != moved }.sorted()
            let held = others.allSatisfy { before[$0] == after[$0] }
            print("  moving \(moved) to 0.95 and back → \(others.joined(separator: ", ")) \(held ? "untouched" : "CHANGED")")
        }

        let silent = rig.settle(mix.mapValues { _ in Float(0) })
        print("  all five at 0: \(silent.isDigitalSilence ? "digital silence" : "NOT SILENT")")
        rig.teardown()
        print("──────────────────────────────────────\n")
    }

    private static func measure(_ sound: Sound) async {
        print("\n──────── \(sound.id) ────────")

        guard let rig = Rig(sound: sound) else {
            print("probe: could not build the offline rig")
            return
        }

        // Cold start: the first time the slider moves, the recording still has
        // to be materialised and read. The fade must happen over the audio, not
        // run to completion while the file is still loading.
        rig.layer.setIntensity(0.8)
        var waited = 0
        while !rig.engine.isRunning, waited < 100 {
            try? await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        guard rig.engine.isRunning else {
            print("probe: engine did not start — is rainsound in the asset catalog?")
            return
        }

        let gainAtStart = rig.layer.currentGainDB
        let coldStart = rig.timeToReachTarget(within: 3, limit: 4)
        print(String(format: "\nCold start   gain when playback began %.1f dB   reached target in %.2f s (fade is %.2f s)",
                     gainAtStart, coldStart, sound.profile.fadeInDuration))

        if let stats = rig.layer.sourceStatistics {
            print(String(format: "\nSource  RMS %.2f dBFS   working peak %.2f dBFS   true peak %.2f dBFS",
                         stats.rmsDBFS, stats.workingPeakDBFS, stats.truePeakDBFS))
            print(String(format: "Makeup  %+.2f dB applied, set by the %@   (target RMS %.1f dBFS, ceiling %.1f dBFS vs %@)",
                         stats.makeupGainDB(for: sound.profile),
                         stats.makeupLimit(for: sound.profile),
                         sound.profile.targetRMSDBFS,
                         sound.profile.peakCeilingDBFS,
                         {
                             switch sound.profile.peakReference {
                             case .workingPeak: "working peak (P99.99)"
                             case .nearPeak: "near peak (P99.999)"
                             case .truePeak: "true peak"
                             }
                         }()))
            if let highPass = sound.profile.highPassFrequency {
                print(String(format: "Repair  4th-order high-pass at %.0f Hz applied before measuring", highPass))
            }
        }
        if let loop = rig.layer.loopDuration {
            print(String(format: "Loop    %.3f s%@", loop,
                         sound.profile.loopCrossfade > 0
                            ? String(format: "  (%.2f s seam crossfade applied)", sound.profile.loopCrossfade)
                            : "  (recording used as-is)"))
        }

        if let stats = rig.layer.sourceStatistics {
            // Deterministic, not measured: the loudest sample the recording can
            // produce once makeup and the curve's ceiling are applied. The
            // limiter sits at 0 dBFS.
            let loudest = stats.truePeakDBFS
                + stats.makeupGainDB(for: sound.profile)
                + sound.profile.maximumGainDB
            // How far into the recording the limiter can actually reach.
            let gain = stats.makeupGainDB(for: sound.profile) + sound.profile.maximumGainDB
            let exposure: String
            if loudest < -0.5 {
                exposure = "cannot engage; dynamics arrive untouched"
            } else if stats.nearPeakDBFS + gain < 0 {
                exposure = String(format: "reaches only the top 0.001%% of samples, by at most %.1f dB", loudest)
            } else if stats.workingPeakDBFS + gain < 0 {
                exposure = String(format: "reaches only the top 0.01%% of samples, by at most %.1f dB", loudest)
            } else {
                exposure = "engages broadly — check this"
            }
            print(String(format: "Headroom  loudest possible sample at full intensity %.2f dBFS → limiter %@",
                         loudest, exposure))
        }

        print("\nSteady state  (gain is exact; the rendered columns sample whatever")
        print("               part of the recording the window happened to land on)")
        print("intensity   gain dB    RMS dBFS   peak     band tilt   side/mid   silent")
        let window = min(12.0, max(1.5, (rig.layer.loopDuration ?? 0) * 1.05))
        for intensity in [0.0, 0.01, 0.10, 0.2, 0.4, 0.5, 0.6, 0.8, 1.0] as [Float] {
            let measured = rig.settle(at: intensity, seconds: 3.0 + window, measuring: window)
            print(String(format: "  %5.2f   %8.2f   %8.2f   %6.4f   %10.4f   %+8.2f   %@",
                         intensity,
                         rig.layer.currentGainDB,
                         measured.rmsDB,
                         measured.peak,
                         measured.bandTiltDB,
                         measured.sideOverMidDB,
                         measured.isDigitalSilence ? "yes" : "no"))
        }

        print("\nTransitions (gain ramp traced every tick)")
        print("  move          travel   max step   peak slope   end RMS    peak")
        let transitions: [(Float, Float)] = [
            (0.0, 0.01), (0.01, 0.2), (0.2, 0.5), (0.5, 0.8), (0.8, 1.0), (1.0, 0.0)
        ]
        for (from, to) in transitions {
            _ = rig.settle(at: from, seconds: 3.0, measuring: 0.2)
            let move = rig.transition(to: to, seconds: 3.0)
            print(String(format: "  %4.2f → %4.2f   %5.1f dB   %5.2f dB   %6.1f dB/s   %7.2f   %6.4f",
                         from, to,
                         move.gainTravelDB,
                         move.maxGainStepDB,
                         move.maxGainSlopeDBPerSecond,
                         move.rmsDB,
                         move.peak))
        }

        // The recording's own loud-and-quiet must survive the whole range. If
        // anything in the chain were compressing, this spread would shrink as
        // the intensity rose and the limiter started working.
        print("\nDynamics over 20 s — spread is the 200 ms envelope, crest is peak")
        print("over RMS, which is where a sound with very short transients keeps its life")
        for intensity in [0.2, 0.5, 1.0] as [Float] {
            let measured = rig.settle(at: intensity, seconds: 3.0 + 20.0, measuring: 20.0)
            print(String(format: "  at %.2f   quiet %.1f   busy %.1f   spread %5.1f dB   crest %5.1f dB",
                         intensity,
                         measured.quietWindowDB,
                         measured.busyWindowDB,
                         measured.dynamicSpreadDB,
                         measured.crestDB))
        }

        // Pausing fades the layer out and the player is torn down when the fade
        // lands. Asking for the same level again has to bring it back.
        let cycle = rig.pauseAndResume(at: 0.6)
        print("\nPause and resume at 0.60")
        print(String(format: "  playing %7.2f dBFS   paused %8.2f dBFS (%@)   resumed %7.2f dBFS → %@",
                     cycle.before.rmsDB,
                     cycle.paused.rmsDB,
                     cycle.paused.isDigitalSilence ? "silent" : "NOT SILENT",
                     cycle.after.rmsDB,
                     cycle.after.rmsDB > cycle.before.rmsDB - 6 ? "came back" : "STAYED SILENT"))

        print("\nFast drag — the worst case the ramps have to absorb")
        for (label, steps, seconds) in [("0 → 1.0 in 150 ms", 10, 0.15),
                                        ("1.0 → 0 in 150 ms", 10, 0.15)] as [(String, Int, Double)] {
            let ascending = label.hasPrefix("0 →")
            _ = rig.settle(at: ascending ? 0 : 1, seconds: 3.0, measuring: 0.2)
            let drag = rig.drag(to: ascending ? 1 : 0, steps: steps, seconds: seconds, settle: 2.5)
            print(String(format: "  %-18@  max step %5.2f dB   peak slope %6.1f dB/s   peak %6.4f",
                         label as NSString, drag.maxGainStepDB, drag.maxGainSlopeDBPerSecond, drag.peak))
        }

        if let report = rig.layer.loopReport {
            print("\nLoop join (measured on the prepared loop, not on a render)")
            print(String(format: "  head 50 ms %.2f dBFS   tail 50 ms %.2f dBFS   step across the join %+.2f dB",
                         report.headRMSDBFS, report.tailRMSDBFS, report.joinStepDB))
            print(String(format: "  the loop moves %.2f dB between neighbouring 50 ms windows anyway → join is %@",
                         report.typicalWindowStepDB,
                         report.joinIsIndistinguishable ? "indistinguishable" : "AUDIBLE"))
            print(String(format: "  sample discontinuity %.4f of peak   tilt ramped out %+.2f dB   gusting range %.1f dB",
                         report.joinDiscontinuity, report.tiltCorrectedDB, report.levelRangeDB))
        }

        if let loop = rig.layer.loopDuration {
            let span = min(62.0, max(30.0, loop * 5))
            let seam = rig.loopCheck(intensity: 0.6, seconds: span, loopDuration: loop)
            print(String(format: "  %.0f s continuous render: 50 ms windows mean %.2f, min %.2f (t=%.2f s), max %.2f dBFS",
                         span, seam.meanBlockDB, seam.minBlockDB, seam.minBlockTime, seam.maxBlockDB))
            print("  dropout: \(seam.minBlockDB < seam.meanBlockDB - 25 ? "YES" : "none")")
        }

        print("\nSilence check after returning to 0")
        let tail = rig.settle(at: 0, seconds: 4.0, measuring: 2.0)
        print("  digital silence: \(tail.isDigitalSilence ? "yes" : "no")   peak \(tail.peak)")

        rig.layer.teardown()
        print("───────────────────────────────────\n")
    }

    // MARK: Rig

    @MainActor
    private final class Rig {

        let engine = AVAudioEngine()
        let layer: LoopingAmbienceLayer
        private let host: OfflineHost
        private let renderBuffer: AVAudioPCMBuffer

        init?(sound: Sound) {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: AudioIntensityProbe.sampleRate,
                                             channels: 2) else { return nil }
            host = OfflineHost(engine: engine)
            layer = LoopingAmbienceLayer(id: sound.id, assetName: sound.asset, profile: sound.profile)

            do {
                _ = engine.mainMixerNode
                try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            } catch {
                return nil
            }

            guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                                frameCapacity: engine.manualRenderingMaximumFrameCount) else {
                return nil
            }
            renderBuffer = buffer
            layer.attach(to: host)
        }

        /// Hold an intensity for `seconds`, measuring only the final `measuring`
        /// seconds so the reading is of the settled state, not the ramp.
        func settle(at intensity: Float, seconds: TimeInterval, measuring: TimeInterval) -> Measurement {
            layer.setIntensity(intensity)
            let skip = max(0, seconds - measuring)
            _ = render(seconds: skip)
            return render(seconds: measuring)
        }

        /// Move to a new intensity and measure the whole move.
        func transition(to intensity: Float, seconds: TimeInterval) -> Measurement {
            layer.setIntensity(intensity)
            return render(seconds: seconds)
        }

        /// Renders in `tickFrames` slices so the layer's clock advances at
        /// roughly the 60 Hz the controller drives it at in the app — a coarser
        /// slice would flatter the ramps.
        private static let tickFrames = AVAudioFrameCount(735) // 1/60 s at 44.1 kHz

        /// Feeds intensity in small increments the way a finger on a fader does,
        /// then holds so the tail of the ramp is included.
        func drag(to intensity: Float, steps: Int, seconds: TimeInterval, settle: TimeInterval) -> Measurement {
            let start = layer.intensity
            var worst = Measurement(rmsDB: 0, peak: 0, isDigitalSilence: false)
            for step in 1...steps {
                let value = start + (intensity - start) * Float(step) / Float(steps)
                layer.setIntensity(value)
                let slice = render(seconds: seconds / Double(steps))
                worst.maxGainStepDB = max(worst.maxGainStepDB, slice.maxGainStepDB)
                worst.maxGainSlopeDBPerSecond = max(worst.maxGainSlopeDBPerSecond,
                                                    slice.maxGainSlopeDBPerSecond)
                worst.peak = max(worst.peak, slice.peak)
            }
            let tail = render(seconds: settle)
            worst.maxGainStepDB = max(worst.maxGainStepDB, tail.maxGainStepDB)
            worst.maxGainSlopeDBPerSecond = max(worst.maxGainSlopeDBPerSecond, tail.maxGainSlopeDBPerSecond)
            worst.peak = max(worst.peak, tail.peak)
            return worst
        }

        /// Renders until the ramped gain is within `tolerance` dB of its target,
        /// and reports how long that took.
        func timeToReachTarget(within tolerance: Float, limit: TimeInterval) -> TimeInterval {
            var elapsed: TimeInterval = 0
            while elapsed < limit {
                let frames = Self.tickFrames
                let delta = Double(frames) / AudioIntensityProbe.sampleRate
                layer.tick(delta: delta)
                _ = try? engine.renderOffline(frames, to: renderBuffer)
                elapsed += delta
                if abs(layer.currentGainDB - layer.targetGainDB) <= tolerance { break }
            }
            return elapsed
        }

        /// Fades out the way the transport does on pause, waits for the player
        /// to stop, then asks for the same level again.
        func pauseAndResume(at intensity: Float) -> (before: Measurement,
                                                     paused: Measurement,
                                                     after: Measurement) {
            let before = settle(at: intensity, seconds: 5.0, measuring: 2.0)
            layer.fadeOut(over: layer.fadeOutDuration)
            _ = render(seconds: 3.5)
            let paused = render(seconds: 1.5)
            layer.setIntensity(intensity)
            _ = render(seconds: 3.5)
            let after = render(seconds: 2.0)
            return (before, paused, after)
        }

        struct LoopResult {
            var minBlockDB: Float = 0
            var minBlockTime: Double = 0
            var maxBlockDB: Float = -200
            var meanBlockDB: Float = 0
            /// How far the windows straddling each loop join sit from the
            /// overall mean. A seam that has not been dealt with shows here.
            var seamMeanDeviationDB: Float = 0
            var seamWorstDeviationDB: Float = 0
        }

        /// Renders past the end of the recording. `.loops` should carry straight
        /// through; a re-scheduling bug would show as a window of near-silence
        /// around the file's duration.
        func loopCheck(intensity: Float, seconds: TimeInterval, loopDuration: TimeInterval) -> LoopResult {
            _ = settle(at: intensity, seconds: 3.0, measuring: 0.2)

            let windowFrames = AVAudioFrameCount(AudioIntensityProbe.sampleRate * 0.05)
            var result = LoopResult(minBlockDB: 200)
            var remaining = AVAudioFrameCount(seconds * AudioIntensityProbe.sampleRate)
            var elapsed: Double = 0
            var windowSquares: Double = 0
            var windowCount: AVAudioFrameCount = 0
            var windows: [(db: Float, time: Double)] = []

            while remaining > 0 {
                let frames = min(Self.tickFrames, remaining)
                layer.tick(delta: Double(frames) / AudioIntensityProbe.sampleRate)
                guard let status = try? engine.renderOffline(frames, to: renderBuffer),
                      status == .success else { break }

                if let channels = renderBuffer.floatChannelData {
                    let count = Int(renderBuffer.frameLength)
                    let channelCount = Int(renderBuffer.format.channelCount)
                    for frame in 0..<count {
                        for channel in 0..<channelCount {
                            let sample = channels[channel][frame]
                            windowSquares += Double(sample * sample)
                        }
                    }
                    windowCount += AVAudioFrameCount(count)
                }

                if windowCount >= windowFrames {
                    let rms = sqrt(windowSquares / Double(windowCount * 2))
                    let db = Float(20 * log10(max(rms, 1e-9)))
                    if db < result.minBlockDB {
                        result.minBlockDB = db
                        result.minBlockTime = elapsed
                    }
                    result.maxBlockDB = max(result.maxBlockDB, db)
                    windows.append((db, elapsed))
                    windowSquares = 0
                    windowCount = 0
                }

                elapsed += Double(frames) / AudioIntensityProbe.sampleRate
                remaining -= frames
            }

            guard !windows.isEmpty else { return result }
            result.meanBlockDB = windows.reduce(0) { $0 + $1.db } / Float(windows.count)

            // Windows within 100 ms of a join, compared with everything else.
            var deviations: [Float] = []
            for window in windows {
                let phase = window.time.truncatingRemainder(dividingBy: loopDuration)
                let nearJoin = phase < 0.1 || phase > loopDuration - 0.1
                if nearJoin { deviations.append(window.db - result.meanBlockDB) }
            }
            if !deviations.isEmpty {
                result.seamMeanDeviationDB = deviations.reduce(0, +) / Float(deviations.count)
                result.seamWorstDeviationDB = deviations.max(by: { abs($0) < abs($1) }) ?? 0
            }
            return result
        }

        private func render(seconds: TimeInterval) -> Measurement {
            var accumulator = Accumulator()
            var remaining = AVAudioFrameCount(seconds * AudioIntensityProbe.sampleRate)

            var previousGainDB = layer.currentGainDB
            var startGainDB = previousGainDB
            var endGainDB = previousGainDB
            var maxStepDB: Float = 0
            var isFirst = true

            while remaining > 0 {
                let frames = min(Self.tickFrames, remaining)
                let delta = Double(frames) / AudioIntensityProbe.sampleRate
                layer.tick(delta: delta)

                let gainDB = layer.currentGainDB
                if isFirst {
                    startGainDB = previousGainDB
                    isFirst = false
                }
                // Steps in and out of the silence floor are the fade arriving,
                // not a jump.
                if gainDB > -70, previousGainDB > -70 {
                    maxStepDB = max(maxStepDB, abs(gainDB - previousGainDB))
                }
                previousGainDB = gainDB
                endGainDB = gainDB

                guard let status = try? engine.renderOffline(frames, to: renderBuffer),
                      status == .success else { break }
                accumulator.consume(renderBuffer)
                remaining -= frames
            }

            var measurement = accumulator.result()
            measurement.gainTravelDB = abs(endGainDB - startGainDB)
            measurement.maxGainStepDB = maxStepDB
            measurement.maxGainSlopeDBPerSecond = maxStepDB * Float(AudioIntensityProbe.sampleRate)
                / Float(Self.tickFrames)
            return measurement
        }
    }

    /// Several layers in one engine, which is how the app runs them.
    @MainActor
    private final class MixedRig {
        let engine = AVAudioEngine()
        private let host: OfflineHost
        private var layers: [String: LoopingAmbienceLayer] = [:]
        private let renderBuffer: AVAudioPCMBuffer

        init?(sounds: [Sound]) {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: AudioIntensityProbe.sampleRate,
                                             channels: 2) else { return nil }
            host = OfflineHost(engine: engine)
            do {
                _ = engine.mainMixerNode
                try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            } catch {
                return nil
            }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                                frameCapacity: engine.manualRenderingMaximumFrameCount) else {
                return nil
            }
            renderBuffer = buffer
            for sound in sounds {
                let layer = LoopingAmbienceLayer(id: sound.id, assetName: sound.asset, profile: sound.profile)
                layer.attach(to: host)
                layers[sound.id] = layer
            }
        }

        func set(_ intensities: [String: Float]) {
            for (id, value) in intensities { layers[id]?.setIntensity(value) }
        }

        func teardown() { layers.values.forEach { $0.teardown() } }

        func gainDB(of id: String) -> Float { layers[id]?.currentGainDB ?? .nan }

        func allGainsDB() -> [String: Float] { layers.mapValues { $0.currentGainDB } }

        /// Every layer has its buffer and is running.
        var allLayersPlaying: Bool {
            layers.values.allSatisfy { $0.isActive && $0.loopDuration != nil }
        }

        /// Apply, let the ramps finish, then measure a settled window.
        func settle(_ intensities: [String: Float]) -> Measurement {
            set(intensities)
            _ = render(seconds: 3.0)
            return render(seconds: 5.5)
        }

        private func render(seconds: TimeInterval) -> Measurement {
            var accumulator = Accumulator()
            var remaining = AVAudioFrameCount(seconds * AudioIntensityProbe.sampleRate)
            while remaining > 0 {
                let frames = min(AVAudioFrameCount(735), remaining)
                let delta = Double(frames) / AudioIntensityProbe.sampleRate
                for layer in layers.values { layer.tick(delta: delta) }
                guard let status = try? engine.renderOffline(frames, to: renderBuffer),
                      status == .success else { break }
                accumulator.consume(renderBuffer)
                remaining -= frames
            }
            return accumulator.result()
        }
    }

    // MARK: Host

    @MainActor
    private final class OfflineHost: AmbientEngineHost {
        let engine: AVAudioEngine
        init(engine: AVAudioEngine) { self.engine = engine }

        /// No audio session offline; just bring the graph up.
        func engineWillStartPlayback() throws {
            guard !engine.isRunning else { return }
            engine.prepare()
            try engine.start()
        }

        func layerDidGoIdle(_ layer: AmbientSoundLayer) {}
    }

    // MARK: Measurement

    struct Measurement {
        var rmsDB: Float
        var peak: Float
        /// Level above 2.5 kHz against level below 300 Hz, in dB. This is what
        /// the tone shaping moves: down at low intensity so the sound sits back,
        /// up at high intensity so detail comes forward.
        var bandTiltDB: Float = 0
        /// Stereo spread: the side signal relative to the middle, in dB. 0 is a
        /// normally wide recording; large positive values fold down badly to a
        /// single speaker.
        var sideOverMidDB: Float = 0
        /// The 10th and 90th percentile of 200 ms window levels, and the gap
        /// between them — how much loud-and-quiet the recording still has.
        var quietWindowDB: Float = 0
        var busyWindowDB: Float = 0
        var dynamicSpreadDB: Float = 0
        /// Peak over RMS. Compression or limiting would pull this down.
        var crestDB: Float = 0
        var isDigitalSilence: Bool
        var gainTravelDB: Float = 0
        var maxGainStepDB: Float = 0
        var maxGainSlopeDBPerSecond: Float = 0
    }

    private struct Accumulator {
        private var squareSum: Double = 0
        private var midSquareSum: Double = 0
        private var sideSquareSum: Double = 0
        private var lowSquareSum: Double = 0
        private var highSquareSum: Double = 0
        private var lowState: [Float] = []
        private var highState: [Float] = []
        private var windowSquares: Double = 0
        private var windowFrames = 0
        private var windowLevels: [Float] = []
        private var frames: Int = 0
        private var peak: Float = 0

        mutating func consume(_ buffer: AVAudioPCMBuffer) {
            guard let channels = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)

            if lowState.count != channelCount {
                lowState = [Float](repeating: 0, count: channelCount)
                highState = [Float](repeating: 0, count: channelCount)
            }

            // One-pole splits at 300 Hz and 2.5 kHz. Gentle slopes, but enough
            // to see which end of the spectrum the EQ is moving.
            let rate = Float(buffer.format.sampleRate)
            let lowAlpha = 1 - expf(-2 * .pi * 300 / rate)
            let highAlpha = 1 - expf(-2 * .pi * 2500 / rate)

            for frame in 0..<count {
                var frameSquares: Double = 0
                for channel in 0..<channelCount {
                    let sample = channels[channel][frame]
                    squareSum += Double(sample * sample)
                    frameSquares += Double(sample * sample)
                    peak = max(peak, abs(sample))

                    lowState[channel] += lowAlpha * (sample - lowState[channel])
                    lowSquareSum += Double(lowState[channel] * lowState[channel])
                    highState[channel] += highAlpha * (sample - highState[channel])
                    let high = sample - highState[channel]
                    highSquareSum += Double(high * high)
                }
                windowSquares += frameSquares
                windowFrames += 1
                if windowFrames >= Int(buffer.format.sampleRate * 0.2) {
                    let level = sqrt(windowSquares / Double(windowFrames * channelCount))
                    windowLevels.append(Float(20 * log10(max(level, 1e-9))))
                    windowSquares = 0
                    windowFrames = 0
                }

                if channelCount >= 2 {
                    let left = channels[0][frame]
                    let right = channels[1][frame]
                    let mid = (left + right) / 2
                    let side = (left - right) / 2
                    midSquareSum += Double(mid * mid)
                    sideSquareSum += Double(side * side)
                }
                frames += 1
            }
        }

        private func percentile(_ values: [Float], _ fraction: Float) -> Float {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            let index = min(sorted.count - 1, max(0, Int(Float(sorted.count - 1) * fraction)))
            return sorted[index]
        }

        func result() -> Measurement {
            let denominator = Double(max(1, frames * 2))
            let rms = sqrt(squareSum / denominator)
            let midRMS = sqrt(midSquareSum / Double(max(1, frames)))
            let sideRMS = sqrt(sideSquareSum / Double(max(1, frames)))
            return Measurement(
                rmsDB: Float(20 * log10(max(rms, 1e-9))),
                peak: peak,
                bandTiltDB: {
                    let low = sqrt(lowSquareSum / denominator)
                    let high = sqrt(highSquareSum / denominator)
                    return low > 1e-9 ? Float(20 * log10(max(high, 1e-12) / low)) : 0
                }(),
                sideOverMidDB: midRMS > 1e-9
                    ? Float(20 * log10(max(sideRMS, 1e-12) / midRMS))
                    : 0,
                quietWindowDB: percentile(windowLevels, 0.10),
                busyWindowDB: percentile(windowLevels, 0.90),
                dynamicSpreadDB: percentile(windowLevels, 0.90) - percentile(windowLevels, 0.10),
                crestDB: rms > 1e-9 ? Float(20 * log10(Double(peak) / rms)) : 0,
                isDigitalSilence: peak == 0
            )
        }
    }
}
#endif
