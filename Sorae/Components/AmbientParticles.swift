//
//  AmbientParticles.swift
//  Sorae
//
//  The weather around Sorae. Embers rise when she is overwhelmed; snow settles
//  when she is calm. The two are the same particle system read in opposite
//  directions, so moving between moods is one continuous motion rather than a
//  cut between two effects.
//
//  Drawn in a single `Canvas` inside `TimelineView(.animation)` — one drawing
//  pass per frame, no per-particle views.
//

import SwiftUI

struct AmbientParticles: View {

    /// 0 = ember storm, 1 = quiet snowfall.
    var calm: Double
    var count: Int = 26
    var speed: Double = 1

    @Environment(\.soraeAmbientMotionEnabled) private var motionEnabled

    private let seeds: [Seed]

    init(calm: Double, count: Int = 26, speed: Double = 1) {
        self.calm = calm
        self.count = count
        self.speed = speed
        var generator = SplitMix64(seed: 0x5052_4145)
        self.seeds = (0..<count).map { _ in Seed(using: &generator) }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !motionEnabled)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate * speed
                let calm = calm.clamped01
                let warmth = 1 - calm
                let tint = Palette.mood(calm)

                for seed in seeds {
                    let cycle = (time * seed.speed + seed.phase).truncatingRemainder(dividingBy: 1)
                    // Cool particles fall, warm particles rise; blending the two
                    // makes mid-calm read as a slow hover.
                    let normalisedY = (1 - cycle) * warmth + cycle * calm

                    let x = seed.x * size.width + sin(time * seed.drift + seed.phase * 6) * size.width * 0.06
                    let y = normalisedY * size.height

                    // Fade at both ends so nothing pops in or out.
                    let fade = min(1, min(cycle, 1 - cycle) / 0.18)
                    let twinkle = 0.5 + 0.5 * abs(sin(time * 0.6 + seed.phase * 3))
                    let alpha = seed.alpha * fade * twinkle
                    guard alpha > 0.01 else { continue }

                    let side = seed.size * (0.65 + 0.7 * calm)
                    let centre = CGPoint(x: x, y: y)

                    if calm > 0.45 {
                        let spin = time * seed.drift * 0.4 + seed.phase * 3
                        context.stroke(
                            snowflake(at: centre, radius: side / 2, rotation: spin),
                            with: .color(tint.opacity(alpha)),
                            lineWidth: max(0.9, side * 0.075)
                        )
                    } else {
                        let r = side * 0.22
                        context.fill(
                            Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r,
                                                   width: r * 2, height: r * 2)),
                            with: .color(tint.opacity(alpha))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Six spokes with small side branches — reads as a snowflake at 8–16pt.
    private func snowflake(at centre: CGPoint, radius: CGFloat, rotation: Double) -> Path {
        var path = Path()
        for index in 0..<6 {
            let angle = rotation + Double(index) * .pi / 3
            let tip = CGPoint(x: centre.x + cos(angle) * radius,
                              y: centre.y + sin(angle) * radius)
            path.move(to: centre)
            path.addLine(to: tip)

            let branchRoot = CGPoint(x: centre.x + cos(angle) * radius * 0.55,
                                     y: centre.y + sin(angle) * radius * 0.55)
            for direction in [-1.0, 1.0] {
                let branchAngle = angle + direction * .pi / 4
                path.move(to: branchRoot)
                path.addLine(to: CGPoint(x: branchRoot.x + cos(branchAngle) * radius * 0.3,
                                         y: branchRoot.y + sin(branchAngle) * radius * 0.3))
            }
        }
        return path
    }

    private struct Seed {
        let x: Double
        let size: Double
        let speed: Double
        let phase: Double
        let drift: Double
        let alpha: Double

        init(using generator: inout SplitMix64) {
            x = generator.nextUnit()
            size = 7 + generator.nextUnit() * 13
            speed = 0.045 + generator.nextUnit() * 0.075
            phase = generator.nextUnit()
            drift = 0.25 + generator.nextUnit() * 0.5
            alpha = 0.16 + generator.nextUnit() * 0.34
        }
    }
}

/// Deterministic particle layout — the same field every launch, so the scene
/// looks composed rather than random.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
