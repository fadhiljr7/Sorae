//
//  SaveMixSheet.swift
//  Sorae
//
//  Saving is a sheet, not a screen: it is a short, cancellable side-trip from
//  the mixer. The name is pre-filled from the mix itself so the common case is
//  a single tap.
//

import SwiftUI

struct SaveMixSheet: View {

    @Environment(MixerModel.self) private var mixer
    @Environment(SoundscapeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    /// The loaded mix, when it is one of the user's own and can be updated in
    /// place. Curated environments are read-only, so they always save as new.
    private var updatableMix: Soundscape? {
        guard let id = mixer.loadedSoundscapeID else { return nil }
        return store.saved.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section("Name") {
                    TextField("Name this mix", text: $name)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                }

                Section {
                    if let updatableMix {
                        Button {
                            store.overwrite(updatableMix.id, levels: mixer.currentLevels)
                            if name != updatableMix.name, !name.trimmed.isEmpty {
                                store.rename(updatableMix.id, to: name.trimmed)
                            }
                            if let refreshed = store.saved.first(where: { $0.id == updatableMix.id }) {
                                mixer.markSaved(as: refreshed)
                            }
                            Haptics.success()
                            dismiss()
                        } label: {
                            Label("Update “\(updatableMix.name)”", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }

                    Button {
                        saveAsNew()
                    } label: {
                        Label(updatableMix == nil ? "Save mix" : "Save as a new mix",
                              systemImage: "plus.circle")
                    }
                    .disabled(name.trimmed.isEmpty)
                } footer: {
                    Text("Saved mixes live in the Saved tab. You can rename, edit or delete them any time.")
                }
            }
            .presentationBackground(Palette.canvas)
            .navigationTitle("Save mix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmed.isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                name = updatableMix?.name ?? SoundscapeNaming.suggestion(for: mixer.currentLevels)
            }
        }
    }

    private var preview: some View {
        let draft = Soundscape(name: name, levels: mixer.currentLevels)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            SoraeMascotView(calm: mixer.calmScore, size: 76, showsAura: true)

            MixSignature(scape: draft, barWidth: 7, height: 44, spacing: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(mixer.summary)
                    .font(.soraeTitle(.subheadline))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(mixer.mood.shortLabel) · \(mixer.activeChannelCount) layers")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Updates the loaded mix when there is one, otherwise saves a new one.
    private func save() {
        guard let updatableMix else {
            saveAsNew()
            return
        }
        store.overwrite(updatableMix.id, levels: mixer.currentLevels)
        if name.trimmed != updatableMix.name, !name.trimmed.isEmpty {
            store.rename(updatableMix.id, to: name.trimmed)
        }
        if let refreshed = store.saved.first(where: { $0.id == updatableMix.id }) {
            mixer.markSaved(as: refreshed)
        }
        Haptics.success()
        dismiss()
    }

    private func saveAsNew() {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { return }
        let scape = store.save(name: trimmed, levels: mixer.currentLevels)
        mixer.markSaved(as: scape)
        store.markPlayed(scape.id)
        Haptics.success()
        dismiss()
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
