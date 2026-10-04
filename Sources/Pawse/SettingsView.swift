import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var store: Store
    let preview: () -> Void
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Your buddy") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 8) {
                    ForEach(Species.available) { s in
                        Button { store.species = s } label: {
                            VStack(spacing: 2) {
                                PetView(species: s, mood: store.species == s ? .happy : .asking)
                                    .scaleEffect(0.5).frame(width: 82, height: 84)
                                Text(s.shortName).lineLimit(1)
                                    .font(.system(.callout, design: .rounded).bold())
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .fill(store.species == s ? Color.accentColor.opacity(0.18) : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(store.species == s ? Color.accentColor : .gray.opacity(0.25), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Button("Preview visit", action: preview)
                    Spacer()
                    Button("Add 3D models…") { NSWorkspace.shared.open(Species.modelsDir) }
                }
            }
            Section("Sounds") {
                Toggle("Cute sounds", isOn: $store.soundOn)
                Slider(value: $store.volume, in: 0...1) { Text("Volume") }
                    .disabled(!store.soundOn)
                HStack {
                    Text("Try:")
                    Button("Ask") { SoundFX.shared.play(.ask, species: store.species) }
                    Button("Happy") { SoundFX.shared.play(.happy, species: store.species) }
                    Button("Sad") { SoundFX.shared.play(.sad, species: store.species) }
                    Button("Goal 🎉") { SoundFX.shared.play(.goal, species: store.species) }
                }
                .disabled(!store.soundOn)
            }
            Section("Goal") {
                Stepper("Daily goal: \(store.goal) glasses", value: $store.goal, in: 1...30)
                Stepper("Glass size: \(store.cupML) ml", value: $store.cupML, in: 50...1000, step: 50)
                Text("= \(store.goal * store.cupML) ml per day").foregroundStyle(.secondary)
                HStack {
                    Text("Today: \(store.count)")
                    Spacer()
                    Button("−") { store.undo() }
                    Button("+") { store.drink() }
                    Button("Reset") { store.resetToday() }
                }
            }
            Section("Reminders") {
                Stepper("Visit every \(store.intervalMinutes) min", value: $store.intervalMinutes, in: 5...240, step: 5)
                Stepper("If “Not yet”, return in \(store.snoozeMinutes) min", value: $store.snoozeMinutes, in: 1...60)
                Picker("Active from", selection: $store.startHour) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                Picker("Until", selection: $store.endHour) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                Toggle(isOn: $store.hardBlockWater) {
                    VStack(alignment: .leading) {
                        Text("🔒 Hard block water reminders")
                        Text("Covers the screen until you tap Yes").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("Pause reminders", isOn: $store.paused)
            }
            Section("General") {
                Toggle("Open \(AppInfo.name) at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let e = loginError { Text(e).font(.caption).foregroundStyle(.red) }
                Button("Custom sounds folder…") { NSWorkspace.shared.open(SoundFX.customDir) }
            }
            Section("About") {
                HStack {
                    Text("\(AppInfo.name) \(AppInfo.version)")
                    Spacer()
                    Link("Website", destination: AppInfo.website)
                    Link("GitHub", destination: AppInfo.repo)
                }
                Text("Free and open source under the MIT licence. Sound credits are in CREDITS.md.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
