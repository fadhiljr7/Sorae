//
//  Palette.swift
//  Sorae
//
//  The single source of truth for colour in the app.
//  Sorae is a white, airy product with one accent family (sky blue) and one
//  opposing family (ember) that only appears when Sorae is overstimulated.
//

import SwiftUI

enum Palette {

    // MARK: Surfaces

    /// The main app background. Pure white in light mode, near-black in dark.
    static let canvas = adaptive(light: 0xFFFFFF, dark: 0x0B1017)
    /// Very slightly tinted background used behind large scenes.
    static let canvasTint = adaptive(light: 0xF6FAFF, dark: 0x0E141D)
    /// Raised cards.
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x161E28)
    /// Recessed wells (fader tracks, empty states).
    static let well = adaptive(light: 0xEEF4FC, dark: 0x1B2430)

    // MARK: Ink

    static let ink = adaptive(light: 0x0F1B2A, dark: 0xF2F7FD)
    static let inkSoft = adaptive(light: 0x5B6D82, dark: 0x9AAABC)
    static let inkFaint = adaptive(light: 0x93A4B8, dark: 0x6C7C8E)

    // MARK: Sky (primary accent — calm)

    static let sky = adaptive(light: 0x4C9AF0, dark: 0x6FB2FA)
    static let skyDeep = adaptive(light: 0x2A6DBF, dark: 0x9CCBFF)
    static let skySoft = adaptive(light: 0xC7E0FA, dark: 0x2B4463)
    static let skyMist = adaptive(light: 0xE8F2FE, dark: 0x18232F)

    // MARK: Ember (secondary — overstimulated)
    //
    // Sampled from the overwhelmed artwork, whose saturated reds cluster around
    // #F03030–#F04040, so the aura and the interface agree with the drawing they
    // are surrounding rather than glowing orange around a red Sorae.

    static let ember = adaptive(light: 0xEF4A3C, dark: 0xFF6B5C)
    static let emberDeep = adaptive(light: 0xC22B22, dark: 0xFF9084)
    static let emberSoft = adaptive(light: 0xFFDCD6, dark: 0x3A1D1B)

    // MARK: Derived

    /// Blends ember → sky across the calm score. Used by everything that
    /// reflects Sorae's emotional state so the whole app moves together.
    static func mood(_ calm: Double) -> Color {
        blend(ember, sky, amount: moodAmount(calm))
    }

    static func moodSoft(_ calm: Double) -> Color {
        blend(emberSoft, skySoft, amount: moodAmount(calm))
    }

    /// Ember is not a halfway house — it means "Sorae is struggling". So the
    /// mood colour swings warm only in the bottom of the range and is fully
    /// brand blue from "settling" upwards, which keeps the app blue-dominant
    /// and makes the fire state mean something when it does appear.
    ///
    /// The ramp ends at 0.34, which is where `SoraeMood` stops calling her
    /// restless. That matters now that the overwhelmed artwork is a real
    /// drawing rather than a warmed copy: the aura has to be most of the way to
    /// blue by the time she is, or a red halo sits around a blue illustration.
    static func moodAmount(_ calm: Double) -> Double {
        let t = (calm / 0.34).clamped01
        return t * t * (3 - 2 * t) // smoothstep
    }

    // MARK: Helpers

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(rgb: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static func blend(_ a: Color, _ b: Color, amount: Double) -> Color {
        Color(uiColor: UIColor { trait in
            let ua = UIColor(a).resolvedColor(with: trait)
            let ub = UIColor(b).resolvedColor(with: trait)
            var (r1, g1, b1, a1) = (CGFloat.zero, CGFloat.zero, CGFloat.zero, CGFloat.zero)
            var (r2, g2, b2, a2) = (CGFloat.zero, CGFloat.zero, CGFloat.zero, CGFloat.zero)
            ua.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            ub.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            let t = CGFloat(amount.clamped01)
            return UIColor(red: r1 + (r2 - r1) * t,
                           green: g1 + (g2 - g1) * t,
                           blue: b1 + (b2 - b1) * t,
                           alpha: a1 + (a2 - a1) * t)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(cleaned, radix: 16) ?? 0x4C9AF0
        self.init(uiColor: UIColor(rgb: value))
    }
}

extension Double {
    var clamped01: Double { min(1, max(0, self)) }
}
