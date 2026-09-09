//
//  SoraeActivityAttributes.swift
//  Sorae
//
//  The contract between the app and its widget extension. Compiled into both,
//  which is why it sits outside the app's own folder.
//
//  The countdown is carried as the *date the session ends*, never as a number of
//  seconds remaining. That is the whole trick to an efficient Live Activity: the
//  widget renders it with `Text(timerInterval:)`, which ticks on its own from a
//  fixed point in time, so the app pushes one update when the timer is set and
//  nothing at all for the rest of the session.
//

import ActivityKit
import Foundation

struct SoraeActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        /// When the timed session ends. `nil` means the soundscape is playing
        /// open-ended, which the Dynamic Island shows as ∞.
        var sessionEndsAt: Date?
        /// "Rain · River · Campfire", or a saved mix's name.
        var summary: String
    }

    /// Nothing about a Sorae session is static, but `ActivityAttributes`
    /// requires the type to exist.
    var kind: String = "soundscape"
}
