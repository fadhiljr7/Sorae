//
//  LibraryView.swift
//  Sorae
//
//  Everything the user has kept. A plain `List` on purpose: swipe-to-delete,
//  context menus, edit mode and the rename alert all come from the system, and
//  a familiar list is the right answer for a collection of saved items.
//

import SwiftUI

struct LibraryView: View {

    @Environment(MixerModel.self) private var mixer
    @Environment(SoundscapeStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var renaming: Soundscape?
    @State private var draftName = ""
    @State private var pendingDeletion: Soundscape?

    private var favourites: [Soundscape] { store.favorites }

    var body: some View {
        NavigationStack {
            Group {
                if store.saved.isEmpty && favourites.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(AmbientBackground(calm: mixer.calmScore, intensity: 0.45))
            .navigationTitle("Saved")
            .toolbar {
                if !store.saved.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
            }
            .alert("Rename mix", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Name", text: $draftName)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") {
                    if let renaming, !draftName.trimmed.isEmpty {
                        store.rename(renaming.id, to: draftName.trimmed)
                    }
                    renaming = nil
                }
            }
            .confirmationDialog(
                "Delete “\(pendingDeletion?.name ?? "")”?",
                isPresented: Binding(get: { pendingDeletion != nil },
                                     set: { if !$0 { pendingDeletion = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete mix", role: .destructive) {
                    if let pendingDeletion { store.delete(pendingDeletion.id) }
                    pendingDeletion = nil
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    // MARK: List

    private var list: some View {
        List {
            if !favourites.isEmpty {
                Section("Favourites") {
                    ForEach(favourites) { scape in
                        row(scape)
                    }
                }
            }

            Section {
                if store.saved.isEmpty {
                    Text("You haven't saved a mix of your own yet.")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                } else {
                    ForEach(store.saved) { scape in
                        row(scape)
                    }
                    .onDelete { offsets in
                        store.delete(atOffsets: offsets, in: store.saved)
                    }
                }
            } header: {
                if !favourites.isEmpty { Text("All mixes") }
            } footer: {
                if !store.saved.isEmpty {
                    Text("Swipe a mix to favourite or delete it. Touch and hold for more.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ scape: Soundscape) -> some View {
        Button {
            play(scape)
        } label: {
            SoundscapeRow(
                scape: scape,
                isCurrent: mixer.loadedSoundscapeID == scape.id,
                isFavorite: store.isFavorite(scape)
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(Palette.surface)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                store.toggleFavorite(scape)
            } label: {
                Label("Favourite", systemImage: store.isFavorite(scape) ? "heart.slash" : "heart")
            }
            .tint(Palette.sky)
        }
        .contextMenu {
            Button("Play", systemImage: "play.fill") { play(scape) }
            Button("Edit in mixer", systemImage: "slider.vertical.3") {
                play(scape)
                router.selectedTab = .mix
            }
            if scape.origin == .user {
                Button("Rename", systemImage: "pencil") {
                    draftName = scape.name
                    renaming = scape
                }
                Button("Duplicate", systemImage: "square.on.square") {
                    store.duplicateAsUserMix(scape)
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    pendingDeletion = scape
                }
            } else {
                Button("Make it mine", systemImage: "square.on.square") {
                    store.duplicateAsUserMix(scape)
                }
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                SoraeScene(calm: 0.9, pose: .resting, isBreathing: false, size: 190, particleCount: 16)
                    .padding(.top, 20)

                VStack(spacing: 8) {
                    Text("Nothing saved yet")
                        .font(.soraeTitle(.title3))
                        .foregroundStyle(Palette.ink)
                    Text("Build a mix you like and Sorae will keep it here for next time.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }

                Button {
                    router.selectedTab = .mix
                } label: {
                    Label("Open the mixer", systemImage: "slider.vertical.3")
                }
                .buttonStyle(SoraeButtonStyle())
                .padding(.horizontal, 40)
                .padding(.top, 4)

                Button("Browse environments") {
                    router.selectedTab = .explore
                }
                .font(.soraeTitle(.subheadline))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private func play(_ scape: Soundscape) {
        withAnimation(Motion.calm) { mixer.apply(scape) }
        store.markPlayed(scape.id)
        Haptics.tap()
    }
}
