//
//  OnboardingOverlay.swift
//  Sorae
//
//  The tour's presentation: everything dims, one control stays lit, and Sorae
//  explains it from a card nearby.
//
//  The card sits on whichever side of the highlight has room, so it never
//  covers the thing it is describing.
//

import SwiftUI

struct OnboardingOverlay: View {

    let controller: OnboardingController
    /// Resolved by the caller, which owns the coordinate space.
    let spotlight: CGRect?
    let size: CGSize

    @Environment(\.soraeAmbientMotionEnabled) private var motionEnabled

    private var step: OnboardingStep? { controller.step }

    /// The highlight, grown by the step's inset and kept on screen.
    private var cutout: CGRect? {
        guard let spotlight, let step else { return nil }
        return spotlight.insetBy(dx: -step.inset, dy: -step.inset)
            .intersection(CGRect(origin: .zero, size: size).insetBy(dx: -200, dy: -200))
    }

    /// True when there is more room below the highlight than above it.
    private var placesCardBelow: Bool {
        guard let cutout else { return true }
        return cutout.midY < size.height * 0.5
    }

    var body: some View {
        if let step {
            ZStack {
                dimming(step: step)
                if let cutout { ring(cutout) }
                card(step: step)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: controller.index)
            .transition(.opacity)
        }
    }

    // MARK: Dimming

    private func dimming(step: OnboardingStep) -> some View {
        Rectangle()
            .fill(.black.opacity(0.62))
            .mask {
                Rectangle()
                    .overlay {
                        if let cutout {
                            RoundedRectangle(cornerRadius: step.cornerRadius, style: .continuous)
                                .frame(width: cutout.width, height: cutout.height)
                                .position(x: cutout.midX, y: cutout.midY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
            }
            .ignoresSafeArea()
            // The whole surface is a target so the tour can be walked through by
            // tapping anywhere, and so the app underneath stays untouched.
            .contentShape(Rectangle())
            .onTapGesture { controller.advance() }
    }

    private func ring(_ rect: CGRect) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !motionEnabled)) { timeline in
            let t = motionEnabled ? timeline.date.timeIntervalSinceReferenceDate : 0
            let pulse = 1 + sin(t * 1.8) * 0.012
            RoundedRectangle(cornerRadius: (step?.cornerRadius ?? 22), style: .continuous)
                .strokeBorder(Palette.sky.opacity(0.9), lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .scaleEffect(pulse)
                .position(x: rect.midX, y: rect.midY)
                .shadow(color: Palette.sky.opacity(0.5), radius: 12)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    // MARK: Card

    private func card(step: OnboardingStep) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(step.mascot)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 78, height: 78)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(step.title)
                        .font(.soraeTitle(.title3))
                        .foregroundStyle(Palette.ink)
                    Text(step.message)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 14) {
                Text(controller.counter)
                    .font(.soraeNumeric(.footnote, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.inkFaint)
                    .accessibilityLabel("Step \(controller.counter.replacingOccurrences(of: "/", with: " of "))")

                Spacer(minLength: 0)

                if !controller.isLastStep {
                    Button("Skip") { controller.skip() }
                        .font(.soraeTitle(.subheadline))
                        .foregroundStyle(Palette.inkSoft)
                }

                Button {
                    controller.advance()
                } label: {
                    HStack(spacing: 5) {
                        Text(controller.isLastStep ? "Start" : "Next")
                        if !controller.isLastStep {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .font(.soraeTitle(.subheadline))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(Capsule().fill(Palette.sky))
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Palette.surface)
                .shadow(color: .black.opacity(0.28), radius: 26, y: 10)
        )
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cardAlignment)
        .padding(.top, cardTopPadding)
        .padding(.bottom, cardBottomPadding)
    }

    private var cardAlignment: Alignment {
        cutout == nil ? .center : (placesCardBelow ? .top : .bottom)
    }

    private var cardTopPadding: CGFloat {
        guard let cutout, placesCardBelow else { return 0 }
        return max(0, cutout.maxY + 18)
    }

    private var cardBottomPadding: CGFloat {
        guard let cutout, !placesCardBelow else { return 0 }
        return max(0, size.height - cutout.minY + 18)
    }
}
