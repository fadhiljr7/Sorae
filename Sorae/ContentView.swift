//
//  ContentView.swift
//  Sorae
//
//  Created by Muhammad Fadhil Abidin on 03/09/26.
//
//  The tab bar is the app's spine: four flat destinations, no nesting, which is
//  what HIG asks for when the sections are peers rather than steps.
//

import SwiftUI

struct ContentView: View {

    @Environment(MixerModel.self) private var mixer
    @Environment(AppRouter.self) private var router
    @Environment(SessionActivityController.self) private var sessionActivity
    @Environment(OnboardingController.self) private var onboarding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @Namespace private var sessionTransition

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab("Today", systemImage: "sun.horizon.fill", value: AppRouter.Tab.home) {
                HomeView(sessionTransition: sessionTransition)
            }
            Tab("Mix", systemImage: "slider.vertical.3", value: AppRouter.Tab.mix) {
                MixView(sessionTransition: sessionTransition)
            }
            Tab("Explore", systemImage: "safari", value: AppRouter.Tab.explore) {
                ExploreView()
            }
            Tab("Saved", systemImage: "heart", value: AppRouter.Tab.library) {
                LibraryView()
            }
        }
        // The tour reads the anchors published by whatever is on screen, so a
        // highlight follows its control even inside a scroll view.
        .overlayPreferenceValue(OnboardingAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if onboarding.isRunning {
                    OnboardingOverlay(
                        controller: onboarding,
                        spotlight: onboarding.step?.target
                            .flatMap { anchors[$0] }
                            .map { proxy[$0] },
                        size: proxy.size
                    )
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: onboarding.index) { followTour() }
        .onChange(of: onboarding.isRunning) { followTour() }
        .task {
            // A beat for the first screen to lay out, so the opening highlight
            // has something to land on.
            try? await Task.sleep(for: .milliseconds(650))
            #if DEBUG
            if let step = LaunchOptions.onboardingStep {
                onboarding.start(at: step)
            } else {
                onboarding.startIfNeeded(force: LaunchOptions.forcesOnboarding)
            }
            #else
            onboarding.startIfNeeded()
            #endif
        }
        .fullScreenCover(isPresented: $router.isSessionPresented) {
            SessionView()
                .soraeZoomTransition(sourceID: "session", in: sessionTransition)
        }
        .environment(\.soraeAmbientMotionEnabled, !reduceMotion)
        // Whether the app is in front is the one thing the controller cannot
        // work out for itself. Everything else it hears from the mixer.
        .onChange(of: scenePhase, initial: true) {
            sessionActivity.setForeground(scenePhase == .active)
        }
    }

    /// The tour walks across tabs; it moves the app itself rather than asking
    /// the user to go and find the screen.
    private func followTour() {
        guard onboarding.isRunning, let tab = onboarding.step?.tab else { return }
        withAnimation(Motion.calm) { router.selectedTab = tab }
    }
}

#Preview {
    ContentView()
        .environment(MixerModel(engine: SimulatedAudioEngine()))
        .environment(SessionActivityController())
        .environment(OnboardingController())
        .environment(SoundscapeStore())
        .environment(AppRouter())
}
