import SwiftUI

struct TimerSheet: View {
    @Environment(SoundEngine.self) private var sound
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if sound.timer != nil {
                        HStack {
                            Label("Fading out in", systemImage: "moon.zzz.fill")
                            Spacer()
                            Text(SleepTimer.countdown(sound.timerRemaining))
                                .monospacedDigit().fontWeight(.semibold)
                        }
                    }
                    ForEach(SleepTimer.presets, id: \.self) { d in
                        Button { start(d) } label: {
                            HStack {
                                Text(SleepTimer.label(d))
                                Spacer()
                                if sound.timer?.duration == d { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    Button { start(nil) } label: {
                        HStack {
                            Text("All night (no timer)")
                            Spacer()
                            if sound.timer == nil { Image(systemName: "checkmark") }
                        }
                    }
                } header: { Text("Sleep timer") } footer: {
                    Text("When the timer ends, the sound fades out slowly, then Quietwell stops playing.")
                }

            }
            .navigationTitle("Sleep timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func start(_ duration: TimeInterval?) {
        sound.startTimer(duration)
    }
}
