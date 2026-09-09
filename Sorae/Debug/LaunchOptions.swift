//
//  LaunchOptions.swift
//  Sorae
//
//  Debug-only hooks that let the simulator be dropped straight into a given
//  screen and state — used for screenshots and UI runs, compiled out of
//  release builds.
//
//    SORAE_TAB=home|mix|explore|library
//    SORAE_MIX=rain:0.8,river:0.5,campfire:0.3
//    SORAE_SESSION=1
//    SORAE_TIMER=<seconds>   short session timer, for watching it end
//    SORAE_SHEET=save|detail
//    SORAE_SEED=1        seeds a couple of saved mixes
//    SORAE_AUDIO_PROBE=1 renders the ambience graph offline and prints measurements
//    SORAE_TIMER_CHECK=1 asserts the session timer's pause behaviour
//    SORAE_ONBOARDING=1|0 forces or suppresses the first-run tour
//    SORAE_ONB_STEP=<n>  opens the tour on step n (1-based)
//

#if DEBUG
import Foundation

enum LaunchOptions {

    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    static func apply(mixer: MixerModel, store: SoundscapeStore, router: AppRouter) {
        if let levels = parsedMix() {
            for (id, value) in levels { mixer.setLevel(value, for: id) }
        }

        if env["SORAE_SEED"] == "1", store.saved.isEmpty {
            store.save(name: "Rainy Evening", levels: ["rain": 0.8, "wind": 0.3, "birds": 0.1, "river": 0.5])
            store.save(name: "Late Desk", levels: ["rain": 0.45, "campfire": 0.6])
            store.curated.prefix(2).forEach { store.markPlayed($0.id) }
        }

        switch env["SORAE_TAB"] {
        case "mix": router.selectedTab = .mix
        case "explore": router.selectedTab = .explore
        case "library": router.selectedTab = .library
        default: break
        }

        if let seconds = env["SORAE_TIMER"].flatMap(Double.init) {
            mixer.setSessionDuration(seconds)
        } else if env["SORAE_SESSION"] == "1" {
            mixer.setSessionDuration(10 * 60)
            router.isSessionPresented = true
        }
    }

    static var runsAudioProbe: Bool { env["SORAE_AUDIO_PROBE"] == "1" }
    static var runsTimerCheck: Bool { env["SORAE_TIMER_CHECK"] == "1" }
    /// nil leaves the first-run rule alone; 1 forces the tour, 0 suppresses it.
    static var forcesOnboarding: Bool? {
        env["SORAE_ONBOARDING"].map { $0 == "1" }
    }
    /// 1-based step to open the tour on.
    static var onboardingStep: Int? {
        env["SORAE_ONB_STEP"].flatMap(Int.init).map { $0 - 1 }
    }
    static var opensSaveSheet: Bool { env["SORAE_SHEET"] == "save" }
    static var opensEnvironmentDetail: Bool { env["SORAE_SHEET"] == "detail" }

    private static func parsedMix() -> [String: Double]? {
        guard let raw = env["SORAE_MIX"] else { return nil }
        let pairs = raw.split(separator: ",").compactMap { entry -> (String, Double)? in
            let parts = entry.split(separator: ":")
            guard parts.count == 2, let value = Double(parts[1]) else { return nil }
            return (String(parts[0]), value)
        }
        return pairs.isEmpty ? nil : Dictionary(uniqueKeysWithValues: pairs)
    }
}
#endif
