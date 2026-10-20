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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isLargeText: Bool { dynamicTypeSize.isAccessibilitySize }

    private var step: OnboardingStep? { controller.step }

    /// The highlight, grown by the step's inset and kept on screen.
    private var cutout: CGRect? {
        guard let spotlight, let step else { return nil }
        // At very large text sizes a target can be pushed below the fold (or not
        // laid out yet, which reads as an empty rect). Then there is nothing to
        // ring: the card just sits centred and the tour still reads in full.
        let screen = CGRect(origin: .zero, size: size)
        guard spotlight.width > 1, spotlight.height > 1,
              screen.intersection(spotlight).height >= min(spotlight.height, 44)
        else { return nil }
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
            // Short copy fits as is; at the largest text sizes it scrolls inside
            // the card rather than running off the screen.
            ViewThatFits(in: .vertical) {
                explanation(step: step)
                ScrollView {
                    explanation(step: step)
                }
                .scrollIndicators(.visible)
            }
            controls
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

    private func explanation(step: OnboardingStep) -> some View {
        // Side by side normally; stacked at accessibility sizes so the text gets
        // the full width of the card.
        let layout = isLargeText
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        return layout {
            Image(step.mascot)
                .resizable()
                .scaledToFit()
                .frame(width: isLargeText ? 56 : 78, height: isLargeText ? 56 : 78)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(step.title)
                    .font(.soraeTitle(.title3))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.message)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One row normally. At accessibility sizes the step counter moves above
    /// the buttons so nothing in the row has to be squeezed.
    @ViewBuilder
    private var controls: some View {
        if isLargeText {
            VStack(alignment: .leading, spacing: 10) {
                counter
                HStack(spacing: 14) {
                    skipButton
                    Spacer(minLength: 0)
                    nextButton
                }
            }
        } else {
            HStack(spacing: 14) {
                counter
                Spacer(minLength: 0)
                skipButton
                nextButton
            }
        }
    }

    @ViewBuilder
    private var skipButton: some View {
        if !controller.isLastStep {
            Button("Skip") { controller.skip() }
                .font(.soraeTitle(.subheadline))
                .foregroundStyle(Palette.inkSoft)
        }
    }

    private var nextButton: some View {
        Button {
            controller.advance()
        } label: {
            HStack(spacing: 5) {
                Text(controller.isLastStep ? "Start" : "Next")
                if !controller.isLastStep {
                    Image(systemName: "arrow.right")
                        .font(.soraeTitle(.footnote))
                }
            }
            .font(.soraeTitle(.subheadline))
            .foregroundStyle(.white)
            .fixedSize()
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
            .background(Capsule().fill(Palette.sky))
        }
    }

    private var counter: some View {
        Text(controller.counter)
            .font(.soraeNumeric(.footnote, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Palette.inkFaint)
            .accessibilityLabel("Step \(controller.counter.replacingOccurrences(of: "/", with: " of "))")
    }

    /// At accessibility sizes the card needs real room; when the space beside
    /// the highlight is too small it sits centred instead, over the dimming.
    private var fitsBesideHighlight: Bool {
        guard let cutout else { return false }
        guard isLargeText else { return true }
        let room = placesCardBelow ? size.height - cutout.maxY : cutout.minY
        return room >= 520
    }

    private var cardAlignment: Alignment {
        guard fitsBesideHighlight else { return .center }
        return placesCardBelow ? .top : .bottom
    }

    /// Clear of the status bar / Dynamic Island and the home indicator, so a
    /// tall card (large text) never runs under either.
    private let topSafeMargin: CGFloat = 64
    private let bottomSafeMargin: CGFloat = 44

    private var cardTopPadding: CGFloat {
        guard fitsBesideHighlight else { return topSafeMargin }
        guard let cutout, placesCardBelow else { return topSafeMargin }
        return max(topSafeMargin, cutout.maxY + 18)
    }

    private var cardBottomPadding: CGFloat {
        guard fitsBesideHighlight else { return bottomSafeMargin }
        guard let cutout, !placesCardBelow else { return bottomSafeMargin }
        return max(bottomSafeMargin, size.height - cutout.minY + 18)
    }
}
