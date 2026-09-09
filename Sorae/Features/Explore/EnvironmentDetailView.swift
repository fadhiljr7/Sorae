//
//  EnvironmentDetailView.swift
//  Sorae
//
//  What a curated environment is actually made of. Showing the recipe is the
//  point: it teaches the mixer, and every scene here can be taken apart and
//  made into the user's own.
//

import SwiftUI

struct EnvironmentDetailView: View {

    let scape: Soundscape

    @Environment(MixerModel.self) private var mixer
    @Environment(SoundscapeStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var didCopy = false

    private var isCurrent: Bool { mixer.loadedSoundscapeID == scape.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                artwork
                VStack(alignment: .leading, spacing: 22) {
                    header
                    actions
                    recipe
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
        .background(AmbientBackground(calm: scape.calmScore, intensity: 0.6))
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.toggleFavorite(scape)
                    Haptics.tap()
                } label: {
                    Image(systemName: store.isFavorite(scape) ? "heart.fill" : "heart")
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(store.isFavorite(scape) ? "Remove from saved" : "Add to saved")
            }
        }
    }

    // MARK: Artwork

    private var artwork: some View {
        ZStack(alignment: .bottom) {
            EnvironmentArtwork.forScene(scape.artworkName)

            // The banner is whatever it is — a bright lantern, a pale sky — so
            // the navigation controls get their own contrast rather than hoping
            // for it.
            // Locations are fractions of this 390pt header, and the buttons sit
            // between 10% and 22% of it, so the scrim holds full strength across
            // that band before releasing.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .black.opacity(0.42), location: 0.22),
                    .init(color: .black.opacity(0.14), location: 0.31),
                    .init(color: .clear, location: 0.42)
                ],
                startPoint: .top, endPoint: .bottom
            )

            // Fades the banner into the page rather than cutting it off.
            LinearGradient(colors: [.clear, Palette.canvas.opacity(0.55), Palette.canvas],
                           startPoint: UnitPoint(x: 0.5, y: 0.72), endPoint: .bottom)
        }
        .frame(height: 390)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(scape.name)
                .font(.soraeDisplay(.title))
                .foregroundStyle(Palette.ink)
            if let caption = scape.caption {
                Text(caption)
                    .font(.body)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Image(systemName: SoraeMood(calm: scape.calmScore).symbol)
                Text(SoraeMood(calm: scape.calmScore).shortLabel)
                Text("·")
                Text("\(scape.activeChannels.count) layers")
            }
            .font(.soraeTitle(.footnote))
            .foregroundStyle(Palette.mood(scape.calmScore))
            .padding(.top, 2)
        }
        .padding(.top, 2)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                play()
                router.startSession()
            } label: {
                Label(isCurrent && mixer.isPlaying ? "Now playing" : "Play this place",
                      systemImage: isCurrent && mixer.isPlaying ? "waveform" : "play.fill")
            }
            .buttonStyle(SoraeButtonStyle(tint: Palette.sky))

            HStack(spacing: 12) {
                Button {
                    play()
                    router.selectedTab = .mix
                    dismiss()
                } label: {
                    Label("Open in mixer", systemImage: "slider.vertical.3")
                }
                .buttonStyle(SoraeButtonStyle(tint: Palette.skyDeep, isProminent: false))

                Button {
                    store.duplicateAsUserMix(scape)
                    didCopy = true
                    Haptics.success()
                } label: {
                    Label(didCopy ? "Saved" : "Make it mine",
                          systemImage: didCopy ? "checkmark" : "square.on.square")
                }
                .buttonStyle(SoraeButtonStyle(tint: Palette.skyDeep, isProminent: false))
                .disabled(didCopy)
            }
        }
    }

    // MARK: Recipe

    private var recipe: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("The recipe", subtitle: "How this place is mixed")

            VStack(spacing: 14) {
                ForEach(scape.activeChannels) { channel in
                    HStack(spacing: 14) {
                        Image(systemName: channel.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(channel.tint)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(channel.tint.opacity(0.12)))

                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(channel.name)
                                    .font(.soraeTitle(.subheadline))
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Text("\(Int((scape.level(for: channel.id) * 100).rounded()))%")
                                    .font(.soraeNumeric(.subheadline))
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.inkSoft)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Palette.well)
                                    Capsule()
                                        .fill(channel.tint)
                                        .frame(width: proxy.size.width * scape.level(for: channel.id))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .soraeCard()
        }
    }

    private func play() {
        withAnimation(Motion.calm) { mixer.apply(scape) }
        store.markPlayed(scape.id)
        Haptics.tap(.medium)
    }
}
