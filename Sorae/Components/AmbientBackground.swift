//
//  AmbientBackground.swift
//  Sorae
//
//  White, with weather in it. A single soft wash of the current mood colour
//  sits behind the content — enough to make the app feel like a place rather
//  than a form, without becoming a gradient poster.
//

import SwiftUI

struct AmbientBackground: View {
    var calm: Double
    var intensity: Double = 1

    var body: some View {
        ZStack {
            Palette.canvas

            // Sky wash falling from the top of the screen.
            LinearGradient(
                colors: [Palette.mood(calm).opacity(0.065 * intensity),
                         Palette.mood(calm).opacity(0.015 * intensity),
                         .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.30)
            )

            // A second, off-centre bloom keeps the wash from looking like a
            // straight linear fade.
            RadialGradient(
                colors: [Palette.mood(calm).opacity(0.07 * intensity), .clear],
                center: UnitPoint(x: 0.78, y: 0.10),
                startRadius: 0,
                endRadius: 320
            )
        }
        .ignoresSafeArea()
        .animation(Motion.mood, value: calm)
    }
}

/// The deeper, fully immersive backdrop used only by the session screen.
struct ImmersiveBackground: View {
    var calm: Double

    @Environment(\.soraeAmbientMotionEnabled) private var motionEnabled

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !motionEnabled)) { timeline in
            let time = motionEnabled ? timeline.date.timeIntervalSinceReferenceDate : 0
            let drift = sin(time * 0.08)
            let drift2 = cos(time * 0.06)

            ZStack {
                Palette.canvasTint

                RadialGradient(
                    colors: [Palette.mood(calm).opacity(0.20), .clear],
                    center: UnitPoint(x: 0.5 + drift * 0.12, y: 0.30 + drift2 * 0.05),
                    startRadius: 0,
                    endRadius: 420
                )

                RadialGradient(
                    colors: [Palette.moodSoft(calm).opacity(0.40), .clear],
                    center: UnitPoint(x: 0.18 - drift2 * 0.1, y: 0.78 + drift * 0.06),
                    startRadius: 0,
                    endRadius: 360
                )

                RadialGradient(
                    colors: [Palette.mood(calm).opacity(0.10), .clear],
                    center: UnitPoint(x: 0.88 + drift * 0.06, y: 0.66),
                    startRadius: 0,
                    endRadius: 300
                )
            }
        }
        .ignoresSafeArea()
        .animation(Motion.mood, value: calm)
    }
}
