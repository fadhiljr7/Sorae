//
//  CuratedSoundscapes.swift
//  Sorae
//
//  Editorial soundscapes shown in Explore.
//
//  These are plain `Soundscape` values with `origin == .curated`, i.e. exactly
//  the same shape the user's own mixes have — so the same cards, the same
//  player and the same "apply to mixer" path serve both. This array is the only
//  thing that would be swapped for a remote feed later; nothing else knows the
//  difference.
//
//  Each carries its own banner art, named after the scene.
//

import Foundation

enum CuratedSoundscapes {

    static let all: [Soundscape] = [
        make("Rainy Night", "Heavy rain, a distant river, nothing else awake.",
             ["rain": 0.85, "river": 0.35, "wind": 0.2]),
        make("Forest Morning", "First light, birdsong, a breeze in the canopy.",
             ["birds": 0.5, "wind": 0.4, "river": 0.3, "rain": 0.1]),
        make("Cozy Cabin", "Fire in the grate while the weather stays outside.",
             ["campfire": 0.75, "rain": 0.45, "wind": 0.3]),
        make("Deep Focus", "Even, featureless, nothing to pull your attention.",
             ["rain": 0.6, "river": 0.5, "wind": 0.25]),
        make("Mountain Stream", "Cold water over stone, high and open.",
             ["river": 0.8, "wind": 0.35, "birds": 0.2]),
        make("Summer Breeze", "Warm air, far-off birds, a slow afternoon.",
             ["wind": 0.55, "birds": 0.35, "river": 0.25, "campfire": 0.15])
    ]

    private static func make(_ name: String, _ caption: String, _ levels: [String: Double]) -> Soundscape {
        Soundscape(
            // Deterministic ids so favouriting a curated scene survives relaunch.
            id: UUID(uuidString: stableUUID(for: name)) ?? UUID(),
            name: name,
            levels: levels,
            origin: .curated,
            // The banner art is named after the scene.
            artworkName: name,
            caption: caption
        )
    }

    /// Cheap deterministic UUID from the name — good enough for a fixed,
    /// hand-authored list.
    private static func stableUUID(for name: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in name.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        let hex = String(format: "%016llx", hash)
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-4\(hex.dropFirst(12).prefix(3))-a\(hex.prefix(3))-\(hex.prefix(12))"
    }
}
