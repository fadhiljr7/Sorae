//
//  Typography.swift
//  Sorae
//
//  Sorae uses the system font throughout so Dynamic Type, tracking and
//  optical sizing all behave natively. Rounded is reserved for display and
//  numerals, which is what gives the product its soft, playful voice.
//

import SwiftUI

extension Font {
    /// Big friendly headline (greetings, mood titles).
    static func soraeDisplay(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .rounded, weight: .bold)
    }

    /// Section headers and card titles.
    static func soraeTitle(_ style: Font.TextStyle = .headline) -> Font {
        .system(style, design: .rounded, weight: .semibold)
    }

    /// Numerals: timers, percentages.
    static func soraeNumeric(_ style: Font.TextStyle = .body, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

/// The SORAE wordmark: wide-tracked, light weight, always in sky blue.
struct Wordmark: View {
    var size: CGFloat = 17
    var color: Color = Palette.sky

    var body: some View {
        Text("SORAE")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .tracking(size * 0.42)
            .foregroundStyle(color)
            .accessibilityLabel("Sorae")
    }
}

/// A small, quiet section header used across Home, Explore and Library.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.soraeTitle(.title3))
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}
