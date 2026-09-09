//
//  SoundChannel.swift
//  Sorae
//
//  A single layer of a soundscape. Everything about a channel — its name,
//  icon, colour, how calming it is and (later) which audio file backs it —
//  lives in data, never in the UI. Adding a sixth sound is one entry in
//  `SoundCatalog`; no view needs to change.
//

import SwiftUI

struct SoundChannel: Identifiable, Hashable, Codable, Sendable {

    /// Stable string id. Used as the persistence key inside `Soundscape.levels`,
    /// so it must never change once a channel has shipped.
    let id: String
    let name: String
    /// Short line shown under the name in the mixer.
    let blurb: String
    /// SF Symbol. Chosen so the set reads as one family at a glance.
    let symbol: String
    let category: Category
    /// Hex tint. Stored as a string so the whole catalog stays `Codable` and
    /// could be served remotely later.
    let tintHex: String

    /// How much this layer contributes to calming Sorae down. Rain and fire
    /// settle her quickly; birds are pleasant but keep her a little alert.
    /// Purely a design dial — tune freely.
    let calmWeight: Double

    /// Name of the looping audio file that will back this channel.
    /// Nil today: the prototype ships without audio assets and the engine
    /// simulates playback. See `SoundscapeAudioEngine`.
    let audioResource: String?

    var tint: Color { Color(hex: tintHex) }

    enum Category: String, Codable, Sendable, CaseIterable {
        case water, air, life, warmth, earth

        var title: String {
            switch self {
            case .water: "Water"
            case .air: "Air"
            case .life: "Life"
            case .warmth: "Warmth"
            case .earth: "Earth"
            }
        }
    }
}
