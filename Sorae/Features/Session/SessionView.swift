//
//  SessionView.swift
//  Sorae
//
//  The room you sit in. Everything that is not Sorae, the time and one or two
//  controls has been removed — no tab bar, no navigation chrome, no lists.
//
//  After a few seconds of stillness the controls dim so the screen becomes
//  something to look at rather than operate; any touch brings them back.
//

import SwiftUI

struct SessionView: View {

    @Environment(MixerModel.self) private var mixer
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.soraeAmbientMotionEnabled) private var motionEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The countdown and the round controls follow Dynamic Type, within reason.
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 56
    @ScaledMetric(relativeTo: .subheadline) private var controlSize: CGFloat = 52

    private var isLargeText: Bool { dynamicTypeSize.isAccessibilitySize }

    @State private var chromeIsDimmed = false
    @State private var idleTask: Task<Void, Never>?
    @State private var hasEntered = false

    private var calm: Double { mixer.calmScore }

    var body: some View {
        ZStack {
            ImmersiveBackground(calm: calm)
            AmbientParticles(calm: calm, count: 40, speed: 0.85)
                .ignoresSafeArea()

            if isLargeText {
                // At accessibility sizes the room no longer fits on one screen,
                // so it scrolls, with a smaller Sorae, rather than truncating.
                ScrollView {
                    VStack(spacing: 20) {
                        topBar
                        mascot
                        readout
                        layers
                        controls
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            } else {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    mascot
                    Spacer(minLength: 0)
                    readout
                    layers
                    controls
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { wakeChrome() }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            withAnimation(Motion.calm) { hasEntered = true }
            wakeChrome()
        }
        .onDisappear { idleTask?.cancel() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tap(.soft)
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(CircleButtonStyle(diameter: 44,
                                           tint: Palette.skyDeep,
                                           background: Palette.surface.opacity(0.7)))
            .accessibilityLabel("Close session")

            Spacer()

            Text(mixer.loadedName ?? mixer.summary)
                .font(.soraeTitle(.subheadline))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .lineLimit(isLargeText ? 3 : 1)

            Spacer()

            Button {
                Haptics.tap(.soft)
                router.selectedTab = .mix
                dismiss()
            } label: {
                Image(systemName: "slider.vertical.3")
            }
            .buttonStyle(CircleButtonStyle(diameter: 44,
                                           tint: Palette.skyDeep,
                                           background: Palette.surface.opacity(0.7)))
            .accessibilityLabel("Adjust the mix")
        }
        .opacity(chromeOpacity)
        .animation(Motion.calm, value: chromeIsDimmed)
    }

    // MARK: Mascot

    private var mascot: some View {
        ZStack {
            if let progress = mixer.sessionProgress {
                CalmRing(progress: progress, calm: calm, lineWidth: 4)
                    .frame(width: isLargeText ? 210 : 300, height: isLargeText ? 210 : 300)
                    .transition(.opacity)
            }
            SoraeMascotView(
                calm: calm,
                pose: calm > 0.86 ? .resting : .meditating,
                isBreathing: mixer.isPlaying,
                size: isLargeText ? 160 : 236
            )
        }
        .scaleEffect(hasEntered || !motionEnabled ? 1 : 0.9)
        .opacity(hasEntered ? 1 : 0)
        .animation(Motion.calm, value: mixer.sessionProgress != nil)
    }

    // MARK: Readout

    private var readout: some View {
        VStack(spacing: 8) {
            if let remaining = mixer.sessionRemaining {
                Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: min(timerSize, 104), weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: Int(remaining))
            } else {
                Text(mixer.mood.title)
                    .font(.soraeDisplay(.title2))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
            }

            Text(mixer.isPlaying ? mixer.mood.guidance : "Paused")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
        }
        .animation(Motion.mood, value: mixer.mood)
        .padding(.bottom, 26)
    }

    // MARK: Layers

    /// A read-only glance at what is playing — colour, icon and level for each
    /// active layer. Tapping any of them takes you to the desk.
    private var layers: some View {
        // One row when it fits; otherwise (large text) the chips stack, each
        // kept whole so a level never breaks across lines.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { layerChips }
            VStack(spacing: 10) { layerChips }
        }
        .animation(Motion.responsive, value: mixer.activeChannelCount)
        .opacity(chromeOpacity)
        .padding(.bottom, 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Playing: \(mixer.summary)")
    }

    private var layerChips: some View {
        ForEach(mixer.channels.filter { mixer.level(for: $0.id) > 0.001 }) { channel in
            HStack(spacing: 6) {
                Image(systemName: channel.symbol)
                    .font(.soraeNumeric(.caption2, weight: .semibold))
                Text("\(Int((mixer.level(for: channel.id) * 100).rounded()))")
                    .font(.soraeNumeric(.caption2, weight: .bold))
                    .monospacedDigit()
            }
            .fixedSize()
            .foregroundStyle(channel.tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(channel.tint.opacity(0.13)))
            .transition(.soraePop(0.7, motion: motionEnabled))
        }
    }

    // MARK: Controls

    private var controlDiameter: CGFloat { min(controlSize, 84) }

    private var controls: some View {
        HStack(spacing: 28) {
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
                Image(systemName: mixer.sessionDuration == nil ? "timer" : "timer.circle.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Palette.skyDeep)
                    .frame(width: controlDiameter, height: controlDiameter)
                    .background(Circle().fill(Palette.surface.opacity(0.7)))
            }
            .accessibilityLabel("Session timer")

            PlayButton(isPlaying: mixer.isPlaying,
                       tint: Palette.mood(calm),
                       isEnabled: !mixer.isSilent) {
                mixer.togglePlayback()
                wakeChrome()
            }

            Button {
                mixer.setSessionDuration((mixer.sessionRemaining ?? 0) + 5 * 60)
                Haptics.tap(.soft)
                wakeChrome()
            } label: {
                Text("+5")
                    .font(.soraeNumeric(.subheadline, weight: .bold))
                    .foregroundStyle(Palette.skyDeep)
                    .fixedSize()
                    .frame(width: controlDiameter, height: controlDiameter)
                    .background(Circle().fill(Palette.surface.opacity(0.7)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add five minutes")
        }
        .opacity(chromeOpacity)
        .animation(Motion.calm, value: chromeIsDimmed)
    }

    // MARK: Chrome dimming

    private var chromeOpacity: Double { chromeIsDimmed ? 0.32 : 1 }

    private func wakeChrome() {
        idleTask?.cancel()
        withAnimation(Motion.calm) { chromeIsDimmed = false }
        guard motionEnabled else { return }
        idleTask = Task {
            try? await Task.sleep(for: .seconds(9))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.mood) { chromeIsDimmed = true }
        }
    }
}
