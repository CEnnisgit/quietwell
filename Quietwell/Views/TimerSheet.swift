import SwiftUI

struct TimerSheet: View {
    @Binding var showPaywall: Bool
    @Environment(SoundEngine.self) private var sound
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("wake.enabled") private var wakeEnabled = false
    @AppStorage("wake.hour") private var wakeHour = 7
    @AppStorage("wake.minute") private var wakeMinute = 0

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
                    Text("When the timer ends, the sound fades out slowly instead of stopping all at once.")
                }

                Section {
                    if store.isPro {
                        Toggle("Wake-up fade", isOn: $wakeEnabled)
                        if wakeEnabled {
                            DatePicker("Wake at", selection: wakeDate, displayedComponents: .hourAndMinute)
                        }
                    } else {
                        Button { dismiss(); showPaywall = true } label: {
                            Label("Wake-up fade (Pro)", systemImage: "lock.fill")
                        }
                    }
                } footer: {
                    Text("Keeps Quietwell running quietly after the timer, then brings the sound back in over 10 minutes at your wake time. Leave Quietwell open in the background.")
                }
            }
            .navigationTitle("Sleep timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: wakeEnabled) { _, _ in syncWake() }
            .onChange(of: wakeHour) { _, _ in syncWake() }
            .onChange(of: wakeMinute) { _, _ in syncWake() }
            .onAppear { syncWake() }
        }
    }

    private var wakeDate: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: wakeHour, minute: wakeMinute, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            wakeHour = c.hour ?? 7
            wakeMinute = c.minute ?? 0
        })
    }

    private func syncWake() {
        sound.scheduleWake(hour: wakeHour, minute: wakeMinute, enabled: wakeEnabled && store.isPro)
    }

    private func start(_ duration: TimeInterval?) {
        sound.startTimer(duration)
        syncWake()
    }
}
