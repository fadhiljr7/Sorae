//
//  SoraeMascotView.swift
//  Sorae
//
//  Sorae herself.
//
//  Her emotional state is a real change of drawing, not a filter: the
//  overwhelmed artwork is its own scene — papers flying, a laptop, a red island
//  — rather than a warmed copy of the calm one.
//
//  That rules out blending the two by the calm score. The score is a value the
//  user can park anywhere, so any blend band is a place they can sit and stare
//  at a doubled face with pine trees growing through a laptop.
//
//  So which drawing is showing is a state, not a mixture. It flips on a
//  threshold with hysteresis — she gives up below 0.10 and recovers above 0.16,
//  so a fader wobbling on the boundary does not make her flicker — and the flip
//  itself animates. The blend exists only while the change is happening, which
//  is when the eye reads it as a transformation rather than as two pictures.
//
//  Everything around her — the aura, the weather, the interface — still moves
//  continuously with the calm score. Only the drawing snaps.
//
//  Motion is time-driven inside a `TimelineView` rather than state-driven, so
//  the float, the breath and the tension tremor never fall out of sync and stop
//  cleanly when Reduce Motion is on.
//

import SwiftUI

struct SoraeMascotView: View {

    /// 0 = overwhelmed (fire), 1 = serene (ice).
    var calm: Double
    var pose: Pose = .meditating
    /// Deeper breathing while a soundscape is playing.
    var isBreathing: Bool = true
    var size: CGFloat = 260
    /// The glow behind her. Turn off inside small cards.
    var showsAura: Bool = true

    @Environment(\.soraeAmbientMotionEnabled) private var motionEnabled

    enum Pose {
        /// Sitting up on her island, paws together — the hero pose.
        case meditating
        /// Lying down, fully at rest — used once she is properly calm.
        case resting

        var assetName: String {
            switch self {
            case .meditating: "mainmascot"
            case .resting: "cutecalm"
            }
        }
    }

    /// Shares the palette's easing, so Sorae and the interface warm up together
    /// and only when she is genuinely struggling. Drives the aura and her
    /// tremor.
    private var warmth: Double { 1 - Palette.moodAmount(calm) }

    /// Which drawing is showing. Never derived directly from `calm` — see the
    /// note at the top of the file.
    @State private var showsOverwhelmed = false

    /// She gives up below this and recovers above the other. The gap between
    /// them is the hysteresis.
    private static let overwhelmBelow = 0.10
    private static let recoverAbove = 0.16
    private static let swapDuration = 0.55

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !motionEnabled)) { timeline in
            let time = motionEnabled ? timeline.date.timeIntervalSinceReferenceDate : 0
            let breathDepth = isBreathing ? 1.0 : 0.45

            ZStack {
                if showsAura { aura(time: time) }
                artwork
                    .frame(width: size, height: size)
                    .scaleEffect(1 + sin(time * 0.42) * 0.016 * breathDepth, anchor: .bottom)
                    .rotationEffect(.degrees(sin(time * 0.29) * 1.1))
                    .offset(
                        // A fine tremor when she is overstimulated; pure float when calm.
                        x: sin(time * 8.4) * 0.7 * warmth,
                        y: sin(time * 0.55) * size * 0.022 + sin(time * 9.1) * 0.6 * warmth
                    )
            }
            // Height only: the intrinsic width is the aura (1.35 x size), so the
            // mascot never forces its container wider than the screen.
            .frame(height: size * 1.32)
        }
        .animation(Motion.mood, value: calm)
        .onAppear {
            // Land on the right drawing rather than animating into it.
            showsOverwhelmed = calm < Self.overwhelmBelow
        }
        .onChange(of: calm) { _, _ in updateDrawing(animated: true) }
        .accessibilityElement()
        .accessibilityLabel("Sorae")
        .accessibilityValue(SoraeMood(calm: calm).shortLabel)
    }

    // MARK: Artwork

    private var artwork: some View {
        ZStack {
            Image(pose.assetName)
                .resizable()
                .scaledToFit()
                .opacity(showsOverwhelmed ? 0 : 1)
                // The one leaving shrinks a little as it goes, so the swap has a
                // beat of its own rather than being a flat crossfade.
                .scaleEffect(showsOverwhelmed ? 0.94 : 1)

            Image(.overwhelmed)
                .resizable()
                .scaledToFit()
                .opacity(showsOverwhelmed ? 1 : 0)
                .scaleEffect(showsOverwhelmed ? 1 : 0.94)
        }
        .animation(.easeInOut(duration: Self.swapDuration), value: showsOverwhelmed)
        .shadow(color: Palette.mood(calm).opacity(0.28), radius: size * 0.09, y: size * 0.03)
    }

    private func updateDrawing(animated: Bool) {
        let next: Bool
        if showsOverwhelmed {
            next = calm <= Self.recoverAbove
        } else {
            next = calm < Self.overwhelmBelow
        }
        guard next != showsOverwhelmed else { return }
        if animated {
            showsOverwhelmed = next
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { showsOverwhelmed = next }
        }
    }

    // MARK: Aura

    private func aura(time: TimeInterval) -> some View {
        let pulse = 1 + sin(time * 0.5) * 0.05
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.mood(calm).opacity(0.30), .clear],
                        center: .center,
                        startRadius: size * 0.05,
                        endRadius: size * 0.62
                    )
                )
                .frame(width: size * 1.35, height: size * 1.35)
                .scaleEffect(pulse)
                .blur(radius: size * 0.06)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.mood(calm).opacity(0.16), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.45
                    )
                )
                .frame(width: size * 0.95, height: size * 0.95)
                .scaleEffect(2 - pulse)
                .blur(radius: size * 0.1)
        }
    }
}

/// Mascot, aura and weather composed together. This is the piece Home and the
/// session screen share so Sorae is literally the same object in both.
struct SoraeScene: View {

    var calm: Double
    var pose: SoraeMascotView.Pose = .meditating
    var isBreathing: Bool = true
    var size: CGFloat = 260
    var particleCount: Int = 26

    var body: some View {
        ZStack {
            AmbientParticles(calm: calm, count: particleCount)
                .frame(maxWidth: .infinity)
            SoraeMascotView(calm: calm, pose: pose, isBreathing: isBreathing, size: size)
        }
        .frame(maxWidth: .infinity)
        .frame(height: size * 1.32)
    }
}

#Preview("Fire → Ice") {
    VStack(spacing: 0) {
        ForEach([0.0, 0.5, 1.0], id: \.self) { calm in
            SoraeScene(calm: calm, size: 160)
        }
    }
    .background(Palette.canvas)
}
