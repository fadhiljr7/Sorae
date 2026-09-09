//
//  SoundscapeStore.swift
//  Sorae
//
//  Owns every saved soundscape and the small amount of session history Home
//  reads from. Persistence is a JSON file in Application Support — right-sized
//  for a prototype and swappable for SwiftData without touching a view.
//

import Foundation
import Observation

@MainActor
@Observable
final class SoundscapeStore {

    /// Mixes the user made, newest first.
    private(set) var saved: [Soundscape] = []
    /// Editorial scenes. Read-only.
    let curated: [Soundscape] = CuratedSoundscapes.all
    /// Ids of curated scenes the user favourited (curated items are immutable,
    /// so the flag lives here).
    private(set) var favoritedCuratedIDs: Set<UUID> = []
    /// Ids of anything recently played, newest first, capped.
    private(set) var recentIDs: [UUID] = []

    private let archive: SoundscapeArchive

    init(archive: SoundscapeArchive = .init()) {
        self.archive = archive
        let snapshot = archive.load()
        self.saved = snapshot.saved
        self.favoritedCuratedIDs = snapshot.favoritedCuratedIDs
        self.recentIDs = snapshot.recentIDs
    }

    // MARK: Lookup

    var all: [Soundscape] { saved + curated }

    func soundscape(_ id: UUID) -> Soundscape? {
        all.first { $0.id == id }
    }

    var favorites: [Soundscape] {
        saved.filter(\.isFavorite) + curated.filter { favoritedCuratedIDs.contains($0.id) }
    }

    /// Up to `limit` recently played scenes, in play order.
    func recent(limit: Int = 6) -> [Soundscape] {
        recentIDs.compactMap { soundscape($0) }.prefix(limit).map { $0 }
    }

    // MARK: Mutations

    @discardableResult
    func save(name: String, levels: [String: Double]) -> Soundscape {
        let scape = Soundscape(name: name, levels: levels)
        saved.insert(scape, at: 0)
        persist()
        return scape
    }

    func update(_ scape: Soundscape) {
        guard let index = saved.firstIndex(where: { $0.id == scape.id }) else { return }
        var updated = scape
        updated.updatedAt = .now
        saved[index] = updated
        persist()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = saved.firstIndex(where: { $0.id == id }) else { return }
        saved[index].name = name
        saved[index].updatedAt = .now
        persist()
    }

    func overwrite(_ id: UUID, levels: [String: Double]) {
        guard let index = saved.firstIndex(where: { $0.id == id }) else { return }
        saved[index].levels = levels.filter { $0.value > 0.001 }
        saved[index].updatedAt = .now
        persist()
    }

    func delete(_ id: UUID) {
        saved.removeAll { $0.id == id }
        recentIDs.removeAll { $0 == id }
        persist()
    }

    func delete(atOffsets offsets: IndexSet, in list: [Soundscape]) {
        for index in offsets {
            guard list.indices.contains(index) else { continue }
            delete(list[index].id)
        }
    }

    func toggleFavorite(_ scape: Soundscape) {
        switch scape.origin {
        case .user:
            guard let index = saved.firstIndex(where: { $0.id == scape.id }) else { return }
            saved[index].isFavorite.toggle()
        case .curated:
            if favoritedCuratedIDs.contains(scape.id) {
                favoritedCuratedIDs.remove(scape.id)
            } else {
                favoritedCuratedIDs.insert(scape.id)
            }
        }
        persist()
    }

    func isFavorite(_ scape: Soundscape) -> Bool {
        switch scape.origin {
        case .user: saved.first { $0.id == scape.id }?.isFavorite ?? false
        case .curated: favoritedCuratedIDs.contains(scape.id)
        }
    }

    func markPlayed(_ id: UUID) {
        recentIDs.removeAll { $0 == id }
        recentIDs.insert(id, at: 0)
        recentIDs = Array(recentIDs.prefix(12))
        persist()
    }

    /// Turns a curated scene into an editable copy the user owns.
    @discardableResult
    func duplicateAsUserMix(_ scape: Soundscape) -> Soundscape {
        let copy = Soundscape(name: "\(scape.name) (Mine)", levels: scape.levels)
        saved.insert(copy, at: 0)
        persist()
        return copy
    }

    private func persist() {
        archive.save(.init(saved: saved,
                           favoritedCuratedIDs: favoritedCuratedIDs,
                           recentIDs: recentIDs))
    }
}

// MARK: - Persistence

nonisolated struct SoundscapeArchive {

    struct Snapshot: Codable {
        var saved: [Soundscape] = []
        var favoritedCuratedIDs: Set<UUID> = []
        var recentIDs: [UUID] = []
    }

    private let url: URL

    init(filename: String = "soundscapes.json") {
        let directory = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: true))
            ?? URL.documentsDirectory
        self.url = directory.appendingPathComponent(filename)
    }

    func load() -> Snapshot {
        guard let data = try? Data(contentsOf: url) else { return Snapshot() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Snapshot.self, from: data)) ?? Snapshot()
    }

    func save(_ snapshot: Snapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
