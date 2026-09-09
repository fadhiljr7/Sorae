//
//  OnboardingTarget+Anchor.swift
//  Sorae
//
//  How a view says "the tour can point at me".
//
//  Anchors rather than measured frames: SwiftUI resolves them in whatever
//  coordinate space the overlay reads them in, so a control can move, animate or
//  live inside a scroll view and the spotlight still lands on it.
//

import SwiftUI

struct OnboardingAnchorKey: PreferenceKey {
    static let defaultValue: [OnboardingTarget: Anchor<CGRect>] = [:]

    static func reduce(value: inout [OnboardingTarget: Anchor<CGRect>],
                       nextValue: () -> [OnboardingTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks this view as something the first-run tour can lift out of the
    /// interface. Costs nothing when the tour is not running.
    func onboardingTarget(_ target: OnboardingTarget) -> some View {
        anchorPreference(key: OnboardingAnchorKey.self, value: .bounds) { [target: $0] }
    }
}
