//
//  HomeView.swift
//  Sorae
//
//  The first thing you see is not a control panel — it is Sorae, at whatever
//  temperature your current soundscape has left her at, and one sentence about
//  what she needs. Everything else on this screen is a way to get back to a mix
//  you already like.
//

import SwiftUI

struct HomeView: View {

    var sessionTransition: Namespace.ID

    @Environment(MixerModel.self) private var mixer
    @Environment(SoundscapeStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(OnboardingController.self) private var onboarding
    @Environment(\.soraeAmbientMotionEnabled) private var motionEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    greeting
                    hero
                    actions
                    if !recents.isEmpty { recentSection }
                    suggestionSection
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(AmbientBackground(calm: mixer.calmScore))
            .scrollIndicators(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Wordmark() }
                ToolbarItem(placement: .topBarTrailing) {
                    // The only way back into the tour once it has been seen.
                    Button {
                        onboarding.replay()
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Show me around Sorae again")
                }
            }
        }
    }

    // MARK: Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeOfDayGreeting)
                .font(.soraeDisplay(.title))
                .foregroundStyle(Palette.ink)
            Text("Let's find your quiet.")
                .font(.body)
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var timeOfDayGreeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Still awake?"
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 14) {
            SoraeScene(
                calm: mixer.calmScore,
                pose: mixer.calmScore > 0.86 ? .resting : .meditating,
                isBreathing: mixer.isPlaying,
                size: 196,
                particleCount: 24
            )
            .onboardingTarget(.soraeHero)

            VStack(spacing: 6) {
                Text(mixer.mood.title)
                    .font(.soraeTitle(.title3))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.opacity)
                Text(mixer.mood.guidance)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .animation(Motion.mood, value: mixer.mood)

            if mixer.isPlaying {
                nowPlayingChip
                    .transition(.soraePop(0.9, motion: motionEnabled))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.calm, value: mixer.isPlaying)
    }

    private var nowPlayingChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.caption)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: motionEnabled)
            Text(mixer.loadedName ?? mixer.summary)
                .font(.soraeTitle(.footnote))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        }
        .foregroundStyle(Palette.skyDeep)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Palette.skyMist))
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                startQuickCalm()
            } label: {
                Label(mixer.isSilent ? "Quick Calm" : "Enter the soundscape",
                      systemImage: mixer.isSilent ? "sparkles" : "moon.stars.fill")
            }
            .buttonStyle(SoraeButtonStyle(tint: Palette.sky))
            .onboardingTarget(.quickCalm)
            .matchedTransitionSource(id: "session", in: sessionTransition)

            Button {
                router.openMixer()
            } label: {
                Label(mixer.isSilent ? "Build your own mix" : "Adjust the mix",
                      systemImage: "slider.vertical.3")
            }
            .buttonStyle(SoraeButtonStyle(tint: Palette.skyDeep, isProminent: false))
        }
    }

    /// One tap from a cold start to a working soundscape: builds a gentle
    /// three-layer blend, sets a ten-minute timer and drops into the session.
    private func startQuickCalm() {
        if mixer.isSilent {
            let levels = mixer.quickCalmLevels()
            withAnimation(Motion.calm) {
                for (id, value) in levels { mixer.setLevel(value, for: id) }
            }
            mixer.setSessionDuration(10 * 60)
        }
        mixer.play()
        Haptics.tap(.medium)
        router.startSession()
    }

    // MARK: Recent

    private var recents: [Soundscape] { store.recent(limit: 6) }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Jump back in", subtitle: "Soundscapes you played recently")
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(recents) { scape in
                        Button {
                            play(scape)
                        } label: {
                            SoundscapeTile(scape: scape, isCurrent: mixer.loadedSoundscapeID == scape.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    // MARK: Suggestions

    private var suggestions: [Soundscape] {
        Array(store.curated.shuffledStably(seed: dayIndex).prefix(4))
    }

    /// Rotates the suggestion order once a day rather than on every redraw.
    private var dayIndex: UInt64 {
        UInt64(Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 1)
    }

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: store.saved.isEmpty ? "Start here" : "Made for right now",
                subtitle: store.saved.isEmpty ? "Ready-made places to sit for a while" : nil
            ) {
                Button("See all") { router.selectedTab = .explore }
                    .font(.soraeTitle(.subheadline))
            }

            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(suggestions) { scape in
                        Button {
                            play(scape)
                            router.startSession()
                        } label: {
                            EnvironmentCard(scape: scape, width: 172, ratio: 1.5, isCompact: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Your world is loud.")
            Text("Sorae makes it gentle.")
        }
        .font(.soraeTitle(.subheadline))
        .foregroundStyle(Palette.sky.opacity(0.75))
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func play(_ scape: Soundscape) {
        withAnimation(Motion.calm) { mixer.apply(scape) }
        store.markPlayed(scape.id)
        Haptics.tap()
    }
}

extension Array {
    /// Deterministic shuffle so a list can be varied by day without flickering
    /// on every render.
    func shuffledStably(seed: UInt64) -> [Element] {
        var generator = SplitMix64(seed: seed)
        return shuffled(using: &generator)
    }
}
