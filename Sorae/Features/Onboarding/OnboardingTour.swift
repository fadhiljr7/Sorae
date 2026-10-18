//
//  OnboardingTour.swift
//  Sorae
//
//  The first-run tour: what it says, where it points, and whether it has been
//  seen. Shown once, then never again.
//
//  It is a highlight sequence rather than a carousel of screenshots — each step
//  dims the app and lifts one real control out of it, so the first time anyone
//  sees the mixer they are looking at the actual mixer.
//

import Foundation
import Observation

/// The parts of the interface the tour can point at. A view marks itself with
/// `.onboardingTarget(_:)`; nothing else couples the two.
enum OnboardingTarget: String, Hashable, CaseIterable {
    case soraeHero
    case quickCalm
    case faders
    case calmMeter
    case timer
    case save
}

nonisolated struct OnboardingStep: Identifiable {
    let id = UUID()
    /// Asset name of the mascot for this step.
    let mascot: String
    /// What to lift out of the interface. `nil` centres the card and dims
    /// everything, which is what the closing step wants.
    let target: OnboardingTarget?
    /// The tab this step's target lives on. The tour moves there itself.
    let tab: AppRouter.Tab
    let title: String
    let message: String
    /// Extra room around the cut-out, for targets that want breathing space.
    var inset: CGFloat = 10
    var cornerRadius: CGFloat = 22
}

extension OnboardingStep {

    /// Seven steps, seven different Sorae. The order walks the product: who she
    /// is, the fastest way in, then the mixer, and how to keep what you made.
    nonisolated static let script: [OnboardingStep] = [
        OnboardingStep(
            mascot: "onb4", target: .soraeHero, tab: .home,
            title: "This is Sorae",
            message: "Silence leaves her overwhelmed. The sounds you play are what settle her down.",
            inset: 4, cornerRadius: 130
        ),
        OnboardingStep(
            mascot: "onb1", target: .quickCalm, tab: .home,
            title: "One tap is enough",
            message: "Quick Calm builds a gentle mix and takes you straight into it.",
            inset: 6, cornerRadius: 30
        ),
        OnboardingStep(
            mascot: "onb7", target: .faders, tab: .mix,
            title: "Or make your own",
            message: "Drag a layer up to bring it in. The fill is the volume, so you can read the whole mix at a glance."
        ),
        OnboardingStep(
            mascot: "onb6", target: .calmMeter, tab: .mix,
            title: "She reacts to it",
            message: "Layering settles her faster than sheer volume. Watch her go from fire to ice.",
            cornerRadius: 28
        ),
        OnboardingStep(
            mascot: "onb2", target: .timer, tab: .mix,
            title: "Drift off",
            message: "Set a timer and the soundscape fades out on its own while you sleep.",
            inset: 8, cornerRadius: 34
        ),
        OnboardingStep(
            mascot: "onb3", target: .save, tab: .mix,
            title: "Keep what works",
            message: "Save a mix you like and it will be waiting in Saved next time.",
            inset: 8, cornerRadius: 34
        ),
        OnboardingStep(
            mascot: "onb5", target: nil, tab: .home,
            title: "That's everything",
            message: "Go and find your quiet."
        )
    ]
}

// MARK: - Persistence

/// Remembers that the tour has been seen.
///
/// A file rather than `UserDefaults`, and for a specific reason: the preferences
/// daemon keeps a domain cached in memory and will write it back after the app
/// has been deleted, so a defaults flag can survive an uninstall and leave a
/// fresh install with no tour. A file in the app's own container cannot — when
/// the container goes, it goes.
///
/// It survives app *updates*, which is what we want: nobody should be walked
/// through the app again because they installed a new build.
nonisolated struct OnboardingRecord {

    private let url: URL

    init(filename: String = "onboarding.v1") {
        let directory = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: true))
            ?? URL.temporaryDirectory
        url = directory.appendingPathComponent(filename)
    }

    var hasBeenSeen: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func markSeen() {
        // The date is not read back; it is there so the file explains itself to
        // anyone who finds it in a container dump.
        let stamp = ISO8601DateFormatter().string(from: .now)
        try? Data(stamp.utf8).write(to: url, options: .atomic)
    }

    func forget() {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Controller

@MainActor
@Observable
final class OnboardingController {

    private(set) var isRunning = false
    private(set) var index = 0

    let steps: [OnboardingStep]
    private let record: OnboardingRecord

    init(steps: [OnboardingStep] = OnboardingStep.script,
         record: OnboardingRecord = OnboardingRecord()) {
        self.steps = steps
        self.record = record
    }

    var step: OnboardingStep? { steps.indices.contains(index) ? steps[index] : nil }
    var isLastStep: Bool { index == steps.count - 1 }
    /// "3/7", for the step indicator.
    var counter: String { "\(index + 1)/\(steps.count)" }

    var hasBeenSeen: Bool { record.hasBeenSeen }

    /// Runs the tour if this is the first launch. `force` is for the debug hook.
    func startIfNeeded(force: Bool? = nil) {
        if let force {
            guard force else { return }
        } else if hasBeenSeen {
            return
        }
        index = 0
        isRunning = true
    }

    #if DEBUG
    /// Begin partway through, for looking at a single step.
    func start(at index: Int) {
        self.index = min(max(0, index), steps.count - 1)
        isRunning = true
    }
    #endif

    /// Run the tour again on purpose. Does not un-remember it — asking for the
    /// tour is not the same as never having seen it.
    func replay() {
        index = 0
        isRunning = true
    }

    func advance() {
        if isLastStep {
            finish()
        } else {
            index += 1
        }
    }

    func skip() { finish() }

    private func finish() {
        isRunning = false
        record.markSeen()
    }
}
