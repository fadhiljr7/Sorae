//
//  SessionTimerCheck.swift
//  Sorae
//
//  A few assertions about the session timer, run with SORAE_TIMER_CHECK=1.
//  It needs no audio, so it uses the simulated engine and finishes in seconds.
//
//  Debug only. Safe to delete.
//

#if DEBUG
import Foundation

@MainActor
enum SessionTimerCheck {

    static func run() async {
        print("\n──────── session timer ────────")

        let mixer = MixerModel(engine: SimulatedAudioEngine())
        mixer.setLevel(0.6, for: "rain")
        mixer.play()
        mixer.setSessionDuration(600)
        report("armed at 10:00", mixer.sessionRemaining ?? 0, expected: 600)

        // Hold it still across a stretch of wall clock.
        mixer.pause()
        let atPause = mixer.sessionRemaining ?? 0
        try? await Task.sleep(for: .seconds(2))
        let afterWaiting = mixer.sessionRemaining ?? 0
        print(String(format: "  paused at %.1f s, two seconds later %.1f s → %@",
                     atPause, afterWaiting,
                     abs(afterWaiting - atPause) < 0.05 ? "held" : "STILL RUNNING"))

        // And pick it up where it was left.
        mixer.play()
        print(String(format: "  resumed at %.1f s → %@", mixer.sessionRemaining ?? 0,
                     abs((mixer.sessionRemaining ?? 0) - atPause) < 0.5 ? "continued" : "JUMPED"))

        // A timer armed while paused should not start counting until play.
        let idle = MixerModel(engine: SimulatedAudioEngine())
        idle.setLevel(0.5, for: "rain")
        idle.pause()
        idle.setSessionDuration(300)
        try? await Task.sleep(for: .seconds(1))
        report("armed while paused, a second later", idle.sessionRemaining ?? 0, expected: 300)

        print("───────────────────────────────\n")
    }

    private static func report(_ label: String, _ value: Double, expected: Double) {
        print(String(format: "  %-38@ %.1f s → %@", label as NSString, value,
                     abs(value - expected) < 0.5 ? "correct" : "WRONG"))
    }
}
#endif
