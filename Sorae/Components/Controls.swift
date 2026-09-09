//
//  Controls.swift
//  Sorae
//
//  Shared buttons. Everything here is a real `Button` with a standard hit area
//  and a `ButtonStyle`, so focus, hover, and press feedback come from the system.
//

import SwiftUI

/// The single filled call to action per screen.
struct SoraeButtonStyle: ButtonStyle {
    var tint: Color = Palette.sky
    var isProminent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.soraeTitle(.body))
            .foregroundStyle(isProminent ? Color.white : tint)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                if isProminent {
                    Capsule().fill(
                        LinearGradient(colors: [tint.opacity(0.92), tint],
                                       startPoint: .top, endPoint: .bottom)
                    )
                } else {
                    Capsule().fill(Palette.well)
                }
            }
            .shadow(color: isProminent ? tint.opacity(0.32) : .clear,
                    radius: configuration.isPressed ? 8 : 16,
                    y: configuration.isPressed ? 3 : 8)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(Motion.responsive, value: configuration.isPressed)
    }
}

/// Small circular control (timer, shuffle, close).
struct CircleButtonStyle: ButtonStyle {
    var diameter: CGFloat = 52
    var tint: Color = Palette.skyDeep
    var background: Color = Palette.well

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.36, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(background))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.responsive, value: configuration.isPressed)
    }
}

/// The transport button. Deliberately the largest tap target in the app.
struct PlayButton: View {
    var isPlaying: Bool
    var tint: Color
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap(.medium)
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [tint.opacity(0.9), tint],
                                         startPoint: .top, endPoint: .bottom))
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .offset(x: isPlaying ? 0 : 2)
            }
            .frame(width: 72, height: 72)
            .shadow(color: tint.opacity(isEnabled ? 0.42 : 0), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(Motion.calm, value: tint)
        .accessibilityLabel(isPlaying ? "Pause soundscape" : "Play soundscape")
    }
}

/// Rounded container used for every card surface in the app.
struct SoraeCard: ViewModifier {
    var padding: CGFloat = 18
    var radius: CGFloat = 26

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.surface)
                    .shadow(color: Palette.skyDeep.opacity(0.07), radius: 18, y: 8)
            )
    }
}

extension View {
    func soraeCard(padding: CGFloat = 18, radius: CGFloat = 26) -> some View {
        modifier(SoraeCard(padding: padding, radius: radius))
    }
}
