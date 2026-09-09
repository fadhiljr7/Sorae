//
//  SoraeLiveActivity.swift
//  SoraeWidgets
//
//  Sorae while the app is not in front.
//
//  The compact presentation is the design. It is the one people actually see —
//  a glance at the top of the screen while doing something else — so it carries
//  the whole idea: Sorae on the left, how long is left on the right. The
//  expanded state exists because the system requires one, and is deliberately a
//  larger arrangement of the same two things rather than a second interface.
//
//  Nothing here counts down in code. `Text(timerInterval:)` is handed the date
//  the session ends and does its own ticking, on time, with the app suspended.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct SoraeLiveActivity: Widget {

    /// A fixed footprint for the compact readout.
    ///
    /// `Text(timerInterval:)` asks for a good deal more width than its digits
    /// need — enough to stretch the island by over a hundred points the moment a
    /// timer is set, next to the single glyph ∞ gets. Pinning both to the same
    /// width keeps the island one length whatever is playing. Wide enough for
    /// five monospaced digits at this size, which covers up to 99:59.
    private static let compactReadoutWidth: CGFloat = 46

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SoraeActivityAttributes.self) { context in
            LockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Mascot(size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Readout(state: context.state, font: .system(size: 22, weight: .semibold, design: .rounded))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.summary)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Mascot()
            } compactTrailing: {
                Readout(state: context.state,
                        font: .system(size: 15, weight: .semibold, design: .rounded),
                        width: Self.compactReadoutWidth)
            } minimal: {
                Mascot(size: 20)
            }
            .keylineTint(.sky)
        }
    }
}

// MARK: - Pieces

/// The countdown, or ∞ when the soundscape is open-ended.
private struct Readout: View {
    let state: SoraeActivityAttributes.ContentState
    let font: Font
    /// Set in the compact regions, where the footprint has to be the same for a
    /// countdown as for ∞. The lock screen and expanded views size to content.
    var width: CGFloat?

    var body: some View {
        Group {
            if let endsAt = state.sessionEndsAt {
                Text(timerInterval: countdown(to: endsAt),
                     countsDown: true,
                     showsHours: false)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            } else {
                Text(verbatim: "∞")
            }
        }
        .font(font)
        .foregroundStyle(.sky)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        // Trailing, so ∞ sits against the same edge the last digit of a
        // countdown does rather than floating in the middle of the slot.
        .frame(width: width, alignment: .trailing)
    }

    /// `Text(timerInterval:)` needs a valid range even if the end has just
    /// passed, which it can have between the timer firing and the app tearing
    /// the activity down.
    private func countdown(to endsAt: Date) -> ClosedRange<Date> {
        let now = Date()
        return now...max(endsAt, now.addingTimeInterval(1))
    }
}

/// Sorae.
///
/// With a `size` she is a fixed square, which is what the larger presentations
/// want. Without one she fills whatever height she is given, keeping the
/// artwork's wide aspect — in the compact region that means as large as the
/// island allows, ears against the top edge.
///
/// Filling rather than a measured constant on purpose: the compact region clips
/// its content a few points inside the capsule, and that inset is the system's
/// to decide. Asking for the height it offers gets the largest image that fits
/// on any island, with nothing cropped.
private struct Mascot: View {
    var size: CGFloat?

    var body: some View {
        let art = Image(.dyImg1)
            .resizable()
            .scaledToFit()

        return Group {
            if let size {
                art.frame(width: size, height: size)
            } else {
                art.frame(maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Lock screen and banner. The same two things, with room to breathe.
private struct LockScreenView: View {
    let state: SoraeActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Mascot(size: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sorae")
                    .font(.system(.headline, design: .rounded))
                Text(state.summary)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Readout(state: state, font: .system(size: 26, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(nil)
    }
}

private extension ShapeStyle where Self == Color {
    /// Sorae's accent. Kept here rather than shared from the app so the
    /// extension has no dependency on it.
    static var sky: Color { Color(red: 0.298, green: 0.604, blue: 0.941) }
}
