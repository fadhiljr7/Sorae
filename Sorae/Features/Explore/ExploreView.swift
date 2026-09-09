//
//  ExploreView.swift
//  Sorae
//
//  Curated environments. These are ordinary `Soundscape` values with
//  `origin == .curated`, so they play, save and open in the mixer through
//  exactly the same paths as anything the user makes.
//

import SwiftUI

struct ExploreView: View {

    @Environment(MixerModel.self) private var mixer
    @Environment(SoundscapeStore.self) private var store
    @Environment(AppRouter.self) private var router

    @Namespace private var cardTransition
    @State private var path = NavigationPath()

    private var featured: Soundscape? { store.curated.first }
    private var rest: [Soundscape] { Array(store.curated.dropFirst()) }

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    intro

                    if let featured {
                        NavigationLink(value: featured) {
                            FeaturedEnvironmentCard(scape: featured)
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: featured.id, in: cardTransition)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader("More places", subtitle: "\(rest.count) environments to sit in")
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(rest) { scape in
                                NavigationLink(value: scape) {
                                    EnvironmentCard(scape: scape, ratio: 1.5, isCompact: true)
                                }
                                .buttonStyle(.plain)
                                .matchedTransitionSource(id: scape.id, in: cardTransition)
                            }
                        }
                    }

                    comingSoon
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(AmbientBackground(calm: mixer.calmScore, intensity: 0.55))
            .scrollIndicators(.hidden)
            .navigationTitle("Explore")
            .navigationDestination(for: Soundscape.self) { scape in
                EnvironmentDetailView(scape: scape)
                    .navigationTransition(.zoom(sourceID: scape.id, in: cardTransition))
            }
            .onAppear {
                #if DEBUG
                if LaunchOptions.opensEnvironmentDetail, let featured, path.isEmpty {
                    path.append(featured)
                }
                #endif
            }
        }
    }

    /// The large navigation title already says "Explore", so this is one line
    /// of orientation rather than a second heading.
    private var intro: some View {
        Text("Environments Sorae has already tuned. Play one, then make it yours.")
            .font(.subheadline)
            .foregroundStyle(Palette.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var comingSoon: some View {
        HStack(spacing: 14) {
            Image("ph1")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Palette.sky.opacity(0.2))
                )
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("More places on the way")
                    .font(.soraeTitle(.subheadline))
                    .foregroundStyle(Palette.ink)
                Text("Seasonal environments and guided sessions are being tuned.")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .soraeCard()
    }
}

/// Wide hero card at the top of Explore.
struct FeaturedEnvironmentCard: View {
    let scape: Soundscape

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            EnvironmentArtwork.forScene(scape.artworkName)

            // No mascot overlay: Sorae is in the banner already.
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.35), .black.opacity(0.78)],
                           startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 6) {
                Text("FEATURED")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.85))
                Text(scape.name)
                    .font(.soraeDisplay(.title2))
                    .foregroundStyle(.white)
                if let caption = scape.caption {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .frame(height: 290)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: Palette.skyDeep.opacity(0.18), radius: 22, y: 12)
        .accessibilityElement(children: .combine)
    }
}
