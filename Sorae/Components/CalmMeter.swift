//
//  CalmMeter.swift
//  Sorae
//
//  The one shared readout of Sorae's state: a fire→ice track with a marker at
//  the current calm score. It appears on the mixer so the user can see the
//  effect of a fader change immediately, in the same colours the mascot uses.
//

import SwiftUI

struct CalmMeter: View {

    var calm: Double
    var mood: SoraeMood
    var showsLabel: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsLabel {
                HStack(spacing: 6) {
                    Image(systemName: mood.symbol)
                        .font(.caption)
                        .foregroundStyle(Palette.mood(calm))
                        .contentTransition(.symbolEffect(.replace))
                    Text(mood.shortLabel)
                        .font(.soraeTitle(.subheadline))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(Int((calm * 100).rounded()))%")
                        .font(.soraeNumeric(.subheadline))
                        .monospacedDigit()
                        .foregroundStyle(Palette.inkSoft)
                        .contentTransition(.numericText())
                }
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Palette.ember.opacity(0.35),
                                         Palette.blend(Palette.ember, Palette.sky, amount: 0.5).opacity(0.3),
                                         Palette.sky.opacity(0.35)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 8)

                    Capsule()
                        .fill(Palette.mood(calm))
                        .frame(width: max(8, width * calm.clamped01), height: 8)

                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Palette.mood(calm), lineWidth: 3.5))
                        .shadow(color: Palette.mood(calm).opacity(0.4), radius: 6, y: 2)
                        .offset(x: max(0, min(width - 16, width * calm.clamped01 - 8)))
                }
                .frame(height: 16)
            }
            .frame(height: 16)
        }
        .animation(Motion.calm, value: calm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calm level")
        .accessibilityValue("\(Int((calm * 100).rounded())) percent, \(mood.shortLabel)")
    }
}

/// Circular version used behind the mascot during a timed session.
struct CalmRing: View {

    var progress: Double
    var calm: Double
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.moodSoft(calm).opacity(0.55), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress.clamped01)
                .stroke(
                    AngularGradient(
                        colors: [Palette.mood(calm).opacity(0.55), Palette.mood(calm)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(lineWidth / 2)
        }
        .animation(.linear(duration: 0.5), value: progress)
        .accessibilityHidden(true)
    }
}
