import SwiftUI

/// Pro: layer up to four sounds, shape each one and save mixes.
struct MixView: View {
    @Binding var showPaywall: Bool
    @Environment(StoreManager.self) private var store
    @Environment(SoundEngine.self) private var sound
    @Environment(MixLibrary.self) private var library
    @State private var mixName = ""

    var body: some View {
        List {
            if !store.isPro {
                Section {
                    Text("Mixing is part of Quietwell Pro.")
                    Button("See Quietwell Pro") { showPaywall = true }
                }
            } else {
                Section {
                    ForEach(sound.layers) { layer in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(layer.kind.title, systemImage: layer.kind.icon).font(.headline)
                                Spacer()
                                if sound.layers.count > 1 {
                                    Button(role: .destructive) { sound.remove(layer) } label: {
                                        Image(systemName: "minus.circle.fill")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Remove \(layer.kind.title)")
                                }
                            }
                            ShapeControls(layer: layer, showVolume: true)
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("Layers (\(sound.layers.count) of \(VoiceBank.maxLayers))")
                } footer: {
                    Text("Tap more sounds on the home screen to add them to the mix.")
                }

                Section("Save this mix") {
                    TextField(MixLibrary.suggestedName(for: sound.layers), text: $mixName)
                    Button("Save mix") {
                        library.save(sound.layers, name: mixName)
                        mixName = ""
                    }
                }

                if !library.mixes.isEmpty {
                    Section("Saved mixes") {
                        ForEach(library.mixes) { mix in
                            Button { sound.load(mix.layers) } label: {
                                Label(mix.name, systemImage: "play.circle")
                            }
                        }
                        .onDelete { idx in
                            let doomed = idx.map { library.mixes[$0] }
                            for m in doomed { library.delete(m) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Mix")
    }
}
