//
//  SoraeApp.swift
//  Sorae
//
//  Created by Muhammad Fadhil Abidin on 03/09/26.
//

import SwiftUI

@main
struct SoraeApp: App {

    /// One mixer and one library for the whole app: the soundscape keeps
    /// playing and Sorae keeps her mood while the user moves between tabs.
    @State private var mixer = MixerModel()
    @State private var store = SoundscapeStore()
    @State private var router = AppRouter()
    @State private var sessionActivity = SessionActivityController()
    @State private var onboarding = OnboardingController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(mixer)
                .environment(store)
                .environment(router)
                .environment(sessionActivity)
                .environment(onboarding)
                .tint(Palette.sky)
                .task { sessionActivity.attach(to: mixer) }
                .task {
                    #if DEBUG
                    LaunchOptions.apply(mixer: mixer, store: store, router: router)
                    if LaunchOptions.runsTimerCheck { await SessionTimerCheck.run() }
                    if LaunchOptions.runsAudioProbe { await AudioIntensityProbe.run() }
                    #endif
                }
        }
    }
}

/// Cross-tab navigation. Home can hand the user to the mixer or open the
/// session cover without either screen knowing about the other.
@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable { case home, mix, explore, library }

    var selectedTab: Tab = .home
    var isSessionPresented = false

    func openMixer() {
        selectedTab = .mix
    }

    func startSession() {
        isSessionPresented = true
    }
}
