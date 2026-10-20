//
//  SoundscapeCards.swift
//  Sorae
//
//  Every way a saved or curated soundscape is shown. All of them read the same
//  `Soundscape` value, so a curated environment and a mix the user made an hour
//  ago behave identically everywhere.
//

import SwiftUI

/// A compact bar chart of the mix. This is a user mix's artwork: it is made of
/// their own sounds, which is more honest than a stock photograph.
struct MixSignature: View {
    let scape: Soundscape
    var barWidth: CGFloat = 6
    var height: CGFloat = 34
    var spacing: CGFloat = 5

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(scape.levelBars, id: \.channel.id) { bar in
                Capsule()
                    .fill(bar.level > 0.001 ? bar.channel.tint : bar.channel.tint.opacity(0.18))
                    .frame(width: barWidth,
                           height: max(barWidth, height * (0.2 + 0.8 * bar.level)))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// Wide row used in Library and in Home's "Recent" list.
struct SoundscapeRow: View {
    let scape: Soundscape
    var isCurrent: Bool = false
    var isFavorite: Bool = false

    @Environment(\.soraeAmbientMotionEnabled) private var motionEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.moodSoft(scape.calmScore).opacity(0.45))
                MixSignature(scape: scape, barWidth: 4, height: 24, spacing: 3.5)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(scape.name)
                        .font(.soraeTitle(.body))
                        .foregroundStyle(Palette.ink)
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(Palette.sky)
                    }
                }
                Text(scape.summary)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }

            Spacer(minLength: 8)

            if isCurrent {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.sky)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: motionEnabled)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays this soundscape")
    }
}

/// Square tile used in Home's horizontal "Jump back in" carousel.
struct SoundscapeTile: View {
    let scape: Soundscape
    var isCurrent: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isLargeText: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                MixSignature(scape: scape, barWidth: 5, height: 30, spacing: 4)
                Spacer()
                // The border alone says "playing" only in colour; the waveform
                // says it in shape too, as the Saved rows do.
                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(Palette.sky)
                        .accessibilityLabel("Now playing")
                }
                Image(systemName: SoraeMood(calm: scape.calmScore).symbol)
                    .font(.caption)
                    .foregroundStyle(Palette.mood(scape.calmScore))
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(scape.name)
                    .font(.soraeTitle(.subheadline))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(isLargeText ? 3 : 1)
                Text(scape.summary)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(isLargeText ? 4 : 1)
            }
        }
        .padding(16)
        // Fixed at regular sizes so the carousel stays even; at accessibility
        // sizes the tile widens and grows to fit its text.
        .frame(width: isLargeText ? 260 : 168, alignment: .leading)
        .frame(minHeight: 132, alignment: .leading)
        .fixedSize(horizontal: false, vertical: isLargeText)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.surface)
                .shadow(color: Palette.skyDeep.opacity(0.08), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isCurrent ? Palette.sky.opacity(0.5) : .clear, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
    }
}

/// The artwork behind every environment surface.
///
/// Always `scaledToFill` inside a fixed-ratio frame, so the source image is
/// cropped and never stretched — which is what lets one 9:16 banner serve a tall
/// hero, a squarer grid tile and a full-bleed header.
///
/// The blur and colour blend below are both off. They existed only to make the
/// grey placeholder presentable, and the real banners need neither: they are
/// already lit and graded, and softening them would throw away the thing that
/// makes them worth having. `.placeholder` keeps the old treatment for any
/// scene that still has no art of its own.
struct EnvironmentArtwork: View {
    var name: String?
    /// Pulls the image toward Sorae's blue, keeping its own light and shade.
    var tintStrength: Double = 0
    /// Depth-of-field softening.
    var softness: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme

    /// In Dark Mode the sunlit banners (Summer Breeze, Mountain Stream…) would be
    /// the brightest thing on screen, large and sudden. Dimming them keeps the
    /// interface dark for people who are sensitive to light, while the art keeps
    /// its colour and grade.
    private var darkModeDim: Double { colorScheme == .dark ? 0.3 : 0 }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let name {
                    Image(name)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [Palette.skySoft, Palette.skyMist],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .blur(radius: softness)
            // Overscan so any blur never reveals a soft edge at the crop.
            .scaleEffect(softness > 0 ? 1 + softness / 40 : 1)
            .clipped()
            // A filled shape rather than a bare `Color`: on a Color, `.opacity` is
            // ambiguous between Color.opacity and View.opacity once `.blendMode`
            // follows. Inside `fill` only the ShapeStyle (Color) one applies.
            .overlay(Rectangle().fill(Palette.skyDeep.opacity(tintStrength)).blendMode(.color))
            .overlay(Rectangle().fill(Color.black.opacity(darkModeDim)))
            .compositingGroup()
        }
        .accessibilityHidden(true)
    }

    /// A scene's banner, falling back to the placeholder — and to the softening
    /// and colour grade that make the placeholder presentable — when it has
    /// none of its own.
    static func forScene(_ name: String?) -> EnvironmentArtwork {
        guard let name else {
            return EnvironmentArtwork(name: "ph2", tintStrength: 0.6, softness: 9)
        }
        return EnvironmentArtwork(name: name)
    }
}

/// Environment card for Explore. `ratio` is height ÷ width, so the same card
/// serves the tall carousel and the squarer grid.
struct EnvironmentCard: View {
    let scape: Soundscape
    /// Fixed width for carousels; `nil` fills the available width, which is
    /// what grid columns want.
    var width: CGFloat?
    var ratio: CGFloat = 16 / 9
    /// Drops the caption and trims padding on small cards.
    var isCompact: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isLargeText: Bool { dynamicTypeSize.isAccessibilitySize }

    /// Carousel cards widen at accessibility sizes so a name like
    /// "Mountain Stream" still fits in a couple of lines.
    private var resolvedWidth: CGFloat? { width.map { isLargeText ? max($0, 280) : $0 } }
    private var height: CGFloat? { resolvedWidth.map { $0 * ratio } }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
            scrim
            content
        }
        .frame(width: resolvedWidth, height: height)
        .aspectRatio(width == nil ? 1 / ratio : nil, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Palette.skyDeep.opacity(0.16), radius: 20, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this environment")
    }

    private var artwork: some View {
        EnvironmentArtwork.forScene(scape.artworkName)
    }

    private var scrim: some View {
        LinearGradient(
            colors: [.black.opacity(0), .black.opacity(0.06), .black.opacity(0.32), .black.opacity(0.78)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isCompact {
                HStack(spacing: 5) {
                    ForEach(scape.activeChannels.prefix(4)) { channel in
                        Image(systemName: channel.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(.white.opacity(0.22)))
                    }
                }
            }
            Text(scape.name)
                .font(.soraeTitle(isCompact ? .headline : .title3))
                .foregroundStyle(.white)
                .lineLimit(isLargeText ? 4 : 2)
            if let caption = scape.caption, !isCompact {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(isCompact ? 14 : 18)
    }
}
