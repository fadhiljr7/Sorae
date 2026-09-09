//
//  SoundCatalog.swift
//  Sorae
//
//  The registry of every sound Sorae can layer. This is the only file that
//  needs editing to add, remove or reorder a sound.
//

import Foundation

enum SoundCatalog {

    static let channels: [SoundChannel] = [
        SoundChannel(
            id: "rain",
            name: "Rain",
            blurb: "Steady on the window",
            symbol: "cloud.rain.fill",
            category: .water,
            tintHex: "5A9BE8",
            calmWeight: 1.15,
            audioResource: "rainsound"
        ),
        SoundChannel(
            id: "wind",
            name: "Wind",
            blurb: "Through the pines",
            symbol: "wind",
            category: .air,
            tintHex: "7FB6E9",
            calmWeight: 0.95,
            audioResource: "windsound"
        ),
        SoundChannel(
            id: "birds",
            name: "Birds",
            blurb: "Early and far away",
            symbol: "bird.fill",
            category: .life,
            tintHex: "6FC5C0",
            calmWeight: 0.75,
            audioResource: "birdsound"
        ),
        SoundChannel(
            id: "river",
            name: "River",
            blurb: "Over smooth stones",
            symbol: "water.waves",
            category: .water,
            tintHex: "4FA9D8",
            calmWeight: 1.05,
            audioResource: "riversound"
        ),
        SoundChannel(
            id: "campfire",
            name: "Campfire",
            blurb: "Crackling low",
            symbol: "flame.fill",
            category: .warmth,
            tintHex: "F0954E",
            calmWeight: 1.1,
            audioResource: "campfiresound"
        )
    ]

    static let byID: [String: SoundChannel] = Dictionary(
        uniqueKeysWithValues: channels.map { ($0.id, $0) }
    )

    static func channel(_ id: String) -> SoundChannel? { byID[id] }

    /// Levels dictionary with every known channel at zero — the empty mix.
    static var silentLevels: [String: Double] {
        Dictionary(uniqueKeysWithValues: channels.map { ($0.id, 0.0) })
    }
}
