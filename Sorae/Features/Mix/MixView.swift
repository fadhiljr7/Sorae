//
//  MixView.swift
//  Sorae
//
//  The mixing desk. Five vertical faders read straight from the catalog, so the
//  desk grows by itself when a sixth sound is added.
//
//  Sorae sits at the top of the screen while you work: every fader change moves
//  her temperature immediately, which is what turns volume-setting into
//  something with a point.
//

import SwiftUI

struct MixView: View {

    var sessionTransition: Namespace.ID

    @Environment(MixerModel.self) private var mixer
    @Environment(SoundscapeStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isSaveSheetPresented = false

    private var isLargeText: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    stateCard
                    desk
                    transport
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(AmbientBackground(calm: mixer.calmScore, intensity: 0.8))
            .scrollIndicators(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { mixTitle }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.startSession()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .disabled(mixer.isSilent)
                    .accessibilityLabel("Enter full-screen session")
                    .matchedTransitionSource(id: "session", in: sessionTransition)
                }
            }
            .onAppear {
                #if DEBUG
                if LaunchOptions.opensSaveSheet { isSaveSheetPresented = true }
                #endif
            }
            .sheet(isPresented: $isSaveSheetPresented) {
                SaveMixSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: Title

    /// Doubles as the mix picker, which keeps the saved library one tap away
    /// without adding another control to the screen.
    private var mixTitle: some View {
        Menu {
            if !store.saved.isEmpty {
                Section("Your mixes") {
                    ForEach(store.saved) { scape in
                        Button {
                            load(scape)
                        } label: {
                            Label(scape.name, systemImage: mixer.loadedSoundscapeID == scape.id ? "checkmark" : "waveform")
                        }
                    }
                }
            }
            Section("Environments") {
                ForEach(store.curated) { scape in
                    Button(scape.name) { load(scape) }
                }
            }
            Section {
                Button("New mix", systemImage: "plus") {
                    withAnimation(Motion.calm) { mixer.clearAll() }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(mixer.loadedName ?? "New mix")
                    .font(.soraeTitle(.body))
                if mixer.hasUnsavedChanges && mixer.loadedName != nil {
                    Text("•")
                        .font(.soraeTitle(.body))
                        .foregroundStyle(Palette.sky)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Palette.ink)
        }
        .accessibilityLabel("Current mix, \(mixer.loadedName ?? "New mix")")
        .accessibilityHint("Choose a saved mix")
    }

    // MARK: Sorae + calm state

    private var stateCard: some View {
        // Side by side normally; stacked at accessibility sizes so the mood
        // copy gets the card's full width.
        let layout = isLargeText
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 4))
        return layout {
            SoraeMascotView(
                calm: mixer.calmScore,
                pose: mixer.calmScore > 0.86 ? .resting : .meditating,
                isBreathing: mixer.isPlaying,
                size: 104
            )
            .frame(width: 146)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mixer.mood.title)
                        .font(.soraeTitle(.subheadline))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(mixer.mood.guidance)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .animation(Motion.mood, value: mixer.mood)

                CalmMeter(calm: mixer.calmScore, mood: mixer.mood, showsLabel: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, isLargeText ? 18 : 0)
        }
        .padding(.trailing, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Palette.surface)
                .shadow(color: Palette.skyDeep.opacity(0.08), radius: 20, y: 8)
        )
        .padding(.top, 4)
        .onboardingTarget(.calmMeter)
    }

    // MARK: The desk

    private var desk: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Layers")
                    .font(.soraeTitle(.subheadline))
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                if !mixer.isSilent {
                    Button("Clear", systemImage: "arrow.counterclockwise") {
                        withAnimation(Motion.calm) { mixer.clearAll() }
                        Haptics.tap(.rigid, intensity: 0.5)
                    }
                    .font(.soraeTitle(.footnote))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Palette.inkSoft)
                }
            }

            // Up to five channels fit the width; beyond that, or at accessibility
            // text sizes where five columns would truncate every label, the
            // desk scrolls with wider faders, so the layout never breaks.
            if mixer.channels.count <= 5 && !isLargeText {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(mixer.channels) { channel in
                        fader(for: channel)
                    }
                }
                .onboardingTarget(.faders)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(mixer.channels) { channel in
                            fader(for: channel).frame(width: isLargeText ? 150 : 64)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(isLargeText ? .visible : .hidden)
                .onboardingTarget(.faders)
            }

            if !mixer.silentChannels.isEmpty {
                recordingNotice
            }
        }
    }

    /// Only some layers have recordings so far. Saying so is better than letting
    /// someone raise a fader and wonder why they hear nothing.
    private var recordingNotice: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform.badge.mic")
                .font(.caption2)
            Text("\(mixer.audibleChannels.map(\.name).formatted(.list(type: .and))) \(mixer.audibleChannels.count == 1 ? "is" : "are") live. \(mixer.silentChannels.map(\.name).formatted(.list(type: .and))) \(mixer.silentChannels.count == 1 ? "is" : "are") still being recorded.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.inkFaint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private func fader(for channel: SoundChannel) -> some View {
        ChannelFader(
            channel: channel,
            level: Binding(
                get: { mixer.level(for: channel.id) },
                set: { mixer.setLevel($0, for: channel.id) }
            ),
            meter: { mixer.meter(for: channel.id) },
            isPlaying: mixer.isPlaying
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: Transport

    private var transport: some View {
        HStack(spacing: 22) {
            timerControl

            PlayButton(
                isPlaying: mixer.isPlaying,
                tint: Palette.mood(mixer.calmScore),
                isEnabled: !mixer.isSilent
            ) {
                mixer.togglePlayback()
            }

            saveControl
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var timerControl: some View {
        Menu {
            Picker("Session length", selection: Binding(
                get: { mixer.sessionDuration ?? 0 },
                set: { mixer.setSessionDuration($0 == 0 ? nil : $0) }
            )) {
                Text("No timer").tag(TimeInterval(0))
                ForEach([5, 10, 20, 45, 60], id: \.self) { minutes in
                    Text("\(minutes) min").tag(TimeInterval(minutes * 60))
                }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mixer.sessionDuration == nil ? "timer" : "timer.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(mixer.sessionDuration == nil ? Palette.skyDeep : Palette.sky)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Palette.well))
                Text(timerLabel)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .accessibilityLabel("Session timer, \(timerLabel)")
        .onboardingTarget(.timer)
    }

    private var timerLabel: String {
        guard let remaining = mixer.sessionRemaining else { return "Timer" }
        return Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond))
    }

    private var saveControl: some View {
        Button {
            isSaveSheetPresented = true
            Haptics.tap()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Palette.skyDeep)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Palette.well))
                Text("Save")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .buttonStyle(.plain)
        .disabled(mixer.isSilent)
        .opacity(mixer.isSilent ? 0.4 : 1)
        .accessibilityLabel("Save this mix")
        .onboardingTarget(.save)
    }

    private func load(_ scape: Soundscape) {
        withAnimation(Motion.calm) { mixer.apply(scape) }
        store.markPlayed(scape.id)
        Haptics.tap()
    }
}
