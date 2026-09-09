//
//  ChannelFader.swift
//  Sorae
//
//  One vertical fader per sound layer — the mixing-desk metaphor the product is
//  built on. The fill *is* the volume, so intensity is read at a glance across
//  the whole desk without looking at a single number.
//
//  Custom visuals, native semantics: `accessibilityRepresentation` hands
//  VoiceOver and Voice Control a real `Slider`, so the control is adjustable
//  with standard gestures and announces a percentage.
//

import SwiftUI

struct ChannelFader: View {

    let channel: SoundChannel
    @Binding var level: Double
    /// Live output level from the audio engine, for the moving meter line.
    var meter: () -> Double
    var isPlaying: Bool
    var height: CGFloat = 236

    @State private var isDragging = false
    @State private var lastHapticStep = -1
    @Environment(\.soraeAmbientMotionEnabled) private var motionEnabled

    private var isActive: Bool { level > 0.001 }

    var body: some View {
        VStack(spacing: 10) {
            fader
            label
        }
        .accessibilityElement(children: .ignore)
        .accessibilityRepresentation {
            Slider(value: $level, in: 0...1) {
                Text(channel.name)
            } minimumValueLabel: {
                Text("Off")
            } maximumValueLabel: {
                Text("Full")
            }
            .accessibilityValue(Text("\(Int(level * 100)) percent"))
        }
    }

    // MARK: Fader body

    private var fader: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Palette.well)

                // The volume itself.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [channel.tint.opacity(0.72), channel.tint],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: max(0, size.height * level))
                    .overlay(alignment: .top) { meterLine }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                // Icon sits at the top and inverts once the fill reaches it.
                Image(systemName: channel.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconTint(fillHeight: size.height * level, in: size))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 18)
                    .allowsHitTesting(false)

                if isDragging {
                    valueChip
                        .frame(maxHeight: .infinity, alignment: .top)
                        .offset(y: -34)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .gesture(dragGesture(in: size))
        }
        .frame(height: height)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(channel.tint.opacity(isActive ? 0.22 : 0.10), lineWidth: 1)
        }
        .shadow(color: channel.tint.opacity(isActive ? 0.22 : 0), radius: 14, y: 6)
        .scaleEffect(isDragging ? 1.035 : 1, anchor: .bottom)
        .animation(Motion.responsive, value: isDragging)
        .animation(isDragging ? nil : Motion.calm, value: level)
    }

    /// A soft band riding on top of the fill at the engine's live output level.
    /// With the simulated engine this is a believable ambience envelope; with a
    /// real engine it is the mixer node tap.
    private var meterLine: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !motionEnabled || !isPlaying)) { _ in
            let value = isPlaying ? meter() : 0
            let overshoot = max(0, value - level)
            Rectangle()
                .fill(.white.opacity(0.55))
                .frame(height: 2.5)
                .blur(radius: 1.5)
                .offset(y: -overshoot * 60)
                .opacity(isActive && isPlaying ? 1 : 0)
        }
    }

    private var valueChip: some View {
        Text("\(Int((level * 100).rounded()))%")
            .font(.soraeNumeric(.footnote, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(channel.tint))
            .shadow(color: channel.tint.opacity(0.4), radius: 8, y: 3)
    }

    // MARK: Label

    private var label: some View {
        VStack(spacing: 2) {
            Text(channel.name)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(isActive ? Palette.ink : Palette.inkFaint)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(isActive ? "\(Int((level * 100).rounded()))%" : "Off")
                .font(.soraeNumeric(.caption2))
                .monospacedDigit()
                .foregroundStyle(isActive ? channel.tint : Palette.inkFaint)
                .contentTransition(.numericText())
        }
        .minimumScaleFactor(0.7)
        .animation(Motion.responsive, value: isActive)
    }

    private func iconTint(fillHeight: CGFloat, in size: CGSize) -> Color {
        // The icon centre sits ~26pt from the top.
        fillHeight > size.height - 40 ? .white : (isActive ? channel.tint : Palette.inkFaint)
    }

    // MARK: Interaction

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    Haptics.prepare()
                }
                let newLevel = (1 - value.location.y / size.height).clamped01
                level = newLevel
                emitStepHaptic(for: newLevel)
            }
            .onEnded { _ in
                isDragging = false
                lastHapticStep = -1
                Haptics.tap(.soft, intensity: 0.5)
            }
    }

    /// A tick every 10% gives the fader physical detents without quantising the
    /// value itself.
    private func emitStepHaptic(for value: Double) {
        let step = Int((value * 10).rounded())
        guard step != lastHapticStep else { return }
        lastHapticStep = step
        Haptics.tick()
    }
}
