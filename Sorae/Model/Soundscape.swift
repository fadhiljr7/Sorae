//
//  Soundscape.swift
//  Sorae
//
//  A saved mix. Levels are keyed by `SoundChannel.id` rather than stored as a
//  fixed list of five numbers, so a soundscape saved today still opens
//  correctly after new sounds are added (unknown ids are ignored, missing ids
//  read as silent).
//

import Foundation

struct Soundscape: Identifiable, Hashable, Codable, Sendable {

    var id: UUID
    var name: String
    /// channel id → 0...1
    var levels: [String: Double]
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var origin: Origin
    /// Optional artwork. Curated environments carry an image asset; user mixes
    /// are drawn from their own sound colours.
    var artworkName: String?
    /// One-line description, used by curated environments in Explore.
    var caption: String?

    init(
        id: UUID = UUID(),
        name: String,
        levels: [String: Double],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isFavorite: Bool = false,
        origin: Origin = .user,
        artworkName: String? = nil,
        caption: String? = nil
    ) {
        self.id = id
        self.name = name
        self.levels = levels.filter { $0.value > 0.001 }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.origin = origin
        self.artworkName = artworkName
        self.caption = caption
    }

    enum Origin: String, Codable, Sendable {
        /// Made by the person using the app.
        case user
        /// Shipped with the app or fetched later. Read-only; editing one
        /// creates a user copy.
        case curated
    }

    // MARK: Derived

    func level(for channelID: String) -> Double { levels[channelID] ?? 0 }

    /// Channels that actually make sound, in catalog order.
    var activeChannels: [SoundChannel] {
        SoundCatalog.channels.filter { level(for: $0.id) > 0.001 }
    }

    var calmScore: Double { CalmEvaluator.score(for: levels) }

    var mood: SoraeMood { SoraeMood(calm: calmScore) }

    /// "Rain · River · Campfire" — the subtitle used on every card.
    var summary: String {
        let names = activeChannels.map(\.name)
        return names.isEmpty ? "Silent" : names.joined(separator: " · ")
    }

    /// Full-level mix normalised for display in a card's mini bar chart.
    var levelBars: [(channel: SoundChannel, level: Double)] {
        SoundCatalog.channels.map { ($0, level(for: $0.id)) }
    }
}
