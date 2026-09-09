//
//  CalmEvaluator.swift
//  Sorae
//
//  Turns a mix into a single 0...1 "calm score", which is the number the whole
//  product hangs off: Sorae's colour, her expression, the ambient particles,
//  the meter on the mixer and the copy on Home all read from it.
//
//  The rules, in words:
//   • Silence is not calm. Sorae is left alone with the noise in her head.
//   • Presence — enough total sound to cover the silence — matters most.
//   • Layering matters: two or three gentle layers settle her faster than one
//     loud one, which is why the mixer is worth using at all.
//   • Blasting a single channel is *less* calming than the same energy spread
//     out. Overstimulation cuts both ways.
//

import Foundation

enum CalmEvaluator {

    /// Weighted sound energy at which Sorae is fully covered. Roughly three
    /// layers held near full, so serenity is something you build towards rather
    /// than trip over.
    private static let presenceTarget = 2.7
    /// Number of simultaneous layers that counts as a full, rounded soundscape.
    private static let layerTarget = 4.0

    static func score(for levels: [String: Double]) -> Double {
        let active = levels.filter { $0.value > 0.001 }
        guard !active.isEmpty else { return 0 }

        let weighted = active.reduce(0.0) { partial, entry in
            let weight = SoundCatalog.channel(entry.key)?.calmWeight ?? 1
            return partial + entry.value * weight
        }

        let presence = min(1, weighted / presenceTarget)
        let layering = min(1, Double(active.count - 1) / (layerTarget - 1))

        // Anything pinned near the top is shouting, not soothing.
        let peak = active.values.max() ?? 0
        let harshness = max(0, peak - 0.88) / 0.12 * 0.16

        return (presence * 0.64 + layering * 0.36 - harshness).clamped01
    }
}

/// Sorae's emotional state. Fire at the bottom, ice at the top.
enum SoraeMood: String, CaseIterable, Sendable {
    case overwhelmed
    case restless
    case settling
    case calm
    case serene

    init(calm: Double) {
        switch calm {
        case ..<0.10: self = .overwhelmed
        case ..<0.34: self = .restless
        case ..<0.62: self = .settling
        case ..<0.88: self = .calm
        default: self = .serene
        }
    }

    /// Shown as the state label under the mascot.
    var title: String {
        switch self {
        case .overwhelmed: "Sorae is overwhelmed"
        case .restless: "Sorae is restless"
        case .settling: "Sorae is settling"
        case .calm: "Sorae is calm"
        case .serene: "Sorae is serene"
        }
    }

    /// The short line that tells the user what to do next.
    var guidance: String {
        switch self {
        case .overwhelmed: "The world is loud. Add a sound to cool her down."
        case .restless: "Good start. Layer in something else."
        case .settling: "She's cooling. Almost there."
        case .calm: "Her world is quiet now. Stay a while."
        case .serene: "Perfectly still. This is her favourite place."
        }
    }

    /// Single word used in compact places (Home hero chip, session HUD).
    var shortLabel: String {
        switch self {
        case .overwhelmed: "Overwhelmed"
        case .restless: "Restless"
        case .settling: "Settling"
        case .calm: "Calm"
        case .serene: "Serene"
        }
    }

    var symbol: String {
        switch self {
        case .overwhelmed, .restless: "flame.fill"
        case .settling: "thermometer.medium"
        case .calm, .serene: "snowflake"
        }
    }
}
