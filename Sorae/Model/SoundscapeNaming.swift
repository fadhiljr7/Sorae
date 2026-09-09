//
//  SoundscapeNaming.swift
//  Sorae
//
//  Suggests a name for a mix so saving is one tap rather than a naming task.
//  Built from the loudest layer plus the time of day — "Rainy Evening",
//  "Fireside Night". Unknown channels fall back to their own name, so the
//  suggestion keeps working when new sounds are added.
//

import Foundation

enum SoundscapeNaming {

    /// Adjective for each channel. Anything missing falls back to the channel
    /// name, e.g. a future "Thunder" becomes "Thunder Evening".
    private static let adjectives: [String: String] = [
        "rain": "Rainy",
        "wind": "Windswept",
        "birds": "Birdsong",
        "river": "Riverside",
        "campfire": "Fireside"
    ]

    static func suggestion(for levels: [String: Double], at date: Date = .now) -> String {
        guard let dominant = levels.filter({ $0.value > 0.001 }).max(by: { $0.value < $1.value })?.key else {
            return "New Mix"
        }
        let lead = adjectives[dominant] ?? SoundCatalog.channel(dominant)?.name ?? "Quiet"
        return "\(lead) \(timeWord(at: date))"
    }

    private static func timeWord(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Morning"
        case 12..<17: "Afternoon"
        case 17..<22: "Evening"
        default: "Night"
        }
    }
}
