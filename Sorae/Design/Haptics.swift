//
//  Haptics.swift
//  Sorae
//
//  Haptics are used sparingly: a soft tick when a fader crosses a step, a
//  light tap on transport controls, success when a mix is saved.
//

import UIKit

enum Haptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// Warms the Taptic Engine before a burst of ticks, so the first one is
    /// not late.
    static func prepare() {
        selection.prepare()
    }

    static func tick() {
        selection.selectionChanged()
    }

    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light, intensity: CGFloat = 0.7) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred(intensity: intensity)
    }

    static func success() {
        notification.notificationOccurred(.success)
    }
}
