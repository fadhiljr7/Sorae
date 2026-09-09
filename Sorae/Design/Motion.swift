//
//  Motion.swift
//  Sorae
//
//  Every animation in Sorae is calm: nothing snaps, nothing bounces hard.
//  Springs are long and low-bounce so the interface feels like it is breathing
//  rather than reacting.
//

import SwiftUI

enum Motion {
    /// Default for state changes the user caused (tapping, selecting).
    static let responsive = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// For larger layout or mood changes.
    static let calm = Animation.spring(response: 0.7, dampingFraction: 0.9)
    /// Mood / colour crossfades — deliberately slow so the shift is felt, not seen.
    static let mood = Animation.easeInOut(duration: 1.1)
    /// Continuous ambient loops (floating, breathing).
    static func drift(_ duration: TimeInterval) -> Animation {
        .easeInOut(duration: duration).repeatForever(autoreverses: true)
    }
}

/// Set from the root view out of Reduce Motion. Ambient loops (floating,
/// breathing, particles, the session's idle dimming) read it and hold a still
/// frame rather than animating.
private struct AmbientMotionKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var soraeAmbientMotionEnabled: Bool {
        get { self[AmbientMotionKey.self] }
        set { self[AmbientMotionKey.self] = newValue }
    }
}
