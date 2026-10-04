import SwiftUI
import Charts

enum Tab: String, CaseIterable, Identifiable {
    case today = "Today", water = "Water", habits = "Habits", screen = "Screen Time", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .water: return "drop.fill"
        case .habits: return "checkmark.circle.fill"
        case .screen: return "desktopcomputer"
        case .settings: return "gearshape.fill"
        }
    }
}

/// The all-in-one window: dashboard, water, habits, screen time, settings.
struct MainView: View {
    @ObservedObject var store: Store
    @ObservedObject var habits: HabitStore
    @ObservedObject var screen: ScreenTime
    @State var tab: Tab = .today
    let preview: () -> Void
    let startBreak: () -> Void

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $tab) { t in
                Label(t.rawValue, systemImage: t.icon).tag(t)
            }
            .navigationSplitViewColumnWidth(170)
            .safeAreaInset(edge: .bottom) {
                PetView(species: store.species, mood: .asking).scaleEffect(0.55).frame(height: 100)
            }
        } detail: {
            switch tab {
            case .today: TodayView(store: store, habits: habits, screen: screen, go: { tab = $0 }, startBreak: startBreak)
            case .water: TrackerView(store: store)
            case .habits: HabitsView(habits: habits)
            case .screen: ScreenTimeView(screen: screen, startBreak: startBreak)
            case .settings: SettingsView(store: store, preview: preview)
            }
        }
        .frame(minWidth: 760, minHeight: 620)
    }
}

// MARK: - Today

struct TodayView: View {
    @ObservedObject var store: Store
    @ObservedObject var habits: HabitStore
    @ObservedObject var screen: ScreenTime
    let go: (Tab) -> Void
    let startBreak: () -> Void

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning ☀️" : h < 17 ? "Good afternoon 🌤️" : "Good evening 🌙"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(greeting).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(Date().formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    // water
                    Button { go(.water) } label: {
                        ringCard(emoji: "💧", title: "Water", value: "\(store.count)/\(store.goal)",
                                 sub: "\(store.count * store.cupML) ml · 🔥 \(store.streak)",
                                 progress: store.progress, color: .blue)
                    }.buttonStyle(.plain)
                    // screen time
                    Button { go(.screen) } label: {
                        ringCard(emoji: "🖥️", title: "Screen time", value: ScreenTime.format(screen.today),
                                 sub: screen.breaksOn ? "Break in \(screen.minutesToBreak) min · ☕ \(screen.taken())" : "Breaks off",
                                 progress: screen.breaksOn ? min(1, screen.continuous / Double(screen.breakEvery * 60)) : 0,
                                 color: screen.overLimit ? .red : .purple)
                    }.buttonStyle(.plain)
                }

                HStack {
                    Text("Habits").font(.system(.title3, design: .rounded).bold())
                    Spacer()
                    Button("Manage") { go(.habits) }.buttonStyle(.borderless)
                }
                if habits.habits.isEmpty {
                    Text("No habits yet. Add some in Habits ✨").foregroundStyle(.secondary).card()
                }
                ForEach(habits.habits) { h in HabitRow(habits: habits, habit: h) }

                HStack(spacing: 12) {
                    Button { store.drink() } label: { Label("Log water", systemImage: "drop.fill") }
                        .buttonStyle(Round(color: .blue))
                    Button(action: startBreak) { Label("Take a break now", systemImage: "cup.and.saucer.fill") }
                        .buttonStyle(Round(color: .purple))
                }
                .padding(.top, 6)
            }
            .padding(22)
        }
    }

    private func ringCard(emoji: String, title: String, value: String, sub: String, progress: Double, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(color.opacity(0.15), lineWidth: 8)
                Circle().trim(from: 0, to: progress).stroke(color.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90)).animation(.spring, value: progress)
                Text(emoji).font(.system(size: 24))
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.callout, design: .rounded)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(sub).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .card()
    }
}

struct HabitRow: View {
    @ObservedObject var habits: HabitStore
    let habit: Habit

    var body: some View {
        let c = habits.count(habit), met = habits.met(habit)
        HStack(spacing: 12) {
            Text(habit.emoji).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(habit.name).font(.system(.body, design: .rounded).bold())
                    if habits.streak(habit) > 0 {
                        Text("🔥 \(habits.streak(habit))").font(.caption).foregroundStyle(.orange)
                    }
                }
                ProgressView(value: habits.progress(habit)).tint(met ? .green : .accentColor)
            }
            Text("\(c)/\(habit.goal)").font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundStyle(met ? .green : .secondary)
            Button { withAnimation { habits.undo(habit) } } label: { Image(systemName: "minus") }
                .buttonStyle(.borderless).disabled(c == 0)
            Button { withAnimation(.spring) { habits.done(habit) } } label: {
                Image(systemName: met ? "checkmark.circle.fill" : "plus.circle.fill").font(.title2)
            }
            .buttonStyle(.borderless).foregroundStyle(met ? .green : .accentColor)
        }
        .card()
    }
}

// MARK: - Habits

struct HabitsView: View {
    @ObservedObject var habits: HabitStore
    @State private var editing: Habit?
    @State private var selected: Habit.ID?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(habits.habits) { h in
                        HStack {
                            Text(h.emoji); Text(h.name); Spacer()
                            if h.hardBlock { Text("🔒") }
                            if h.intervalMinutes > 0 { Text("\(h.intervalMinutes)m").font(.caption).foregroundStyle(.secondary) }
                            Text("🔥\(habits.streak(h))").foregroundStyle(.secondary)
                        }
                            .tag(h.id)
                            .contextMenu {
                                Button("Edit") { editing = h }
                                Button("Delete", role: .destructive) { habits.remove(h) }
                            }
                    }
                }
                Divider()
                HStack {
                    Menu {
                        ForEach(Habit.presets.filter { p in !habits.habits.contains { $0.name == p.name } }) { p in
                            Button("\(p.emoji) \(p.name)") { var n = p; n.id = UUID(); habits.add(n) }
                        }
                        Divider()
                        Button("Custom habit…") { editing = Habit(name: "", emoji: "⭐") }
                    } label: { Label("Add", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize()
                    Spacer()
                    if let h = habits.habits.first(where: { $0.id == selected }) {
                        Button("Edit") { editing = h }.buttonStyle(.borderless)
                    }
                }
                .padding(8)
            }
            .frame(minWidth: 200, maxWidth: 260)

            Group {
                if let h = habits.habits.first(where: { $0.id == selected }) ?? habits.habits.first {
                    HabitDetail(habits: habits, habit: h)
                } else {
                    Text("Add a habit to get started ✨").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 380)
        }
        .sheet(item: $editing) { h in
            HabitEditor(habit: h, isNew: !habits.habits.contains { $0.id == h.id }) { saved in
                if habits.habits.contains(where: { $0.id == saved.id }) { habits.update(saved) } else { habits.add(saved) }
                selected = saved.id
            }
        }
    }
}

struct HabitEditor: View {
    @State var habit: Habit
    let isNew: Bool
    let onSave: (Habit) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Text(isNew ? "New habit" : "Edit habit").font(.title2.bold())
            TextField("Name (e.g. Stretch)", text: $habit.name)
            TextField("Emoji", text: $habit.emoji)
            Stepper("Goal: \(habit.goal) time\(habit.goal == 1 ? "" : "s") a day", value: $habit.goal, in: 1...30)
            Toggle("Pet reminds me", isOn: Binding(
                get: { habit.intervalMinutes > 0 },
                set: { habit.intervalMinutes = $0 ? 30 : 0; if !$0 { habit.hardBlock = false } }))
            if habit.intervalMinutes > 0 {
                HStack {
                    Text("Every")
                    TextField("", value: $habit.intervalMinutes, format: .number)
                        .frame(width: 60).multilineTextAlignment(.trailing)
                    Stepper("minutes", value: $habit.intervalMinutes, in: 1...720, step: 5)
                }
                HStack(spacing: 6) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { m in
                        Button(m < 60 ? "\(m)m" : "\(m / 60)h\(m % 60 == 0 ? "" : "30")") { habit.intervalMinutes = m }
                            .buttonStyle(.bordered).controlSize(.small)
                            .tint(habit.intervalMinutes == m ? .accentColor : nil)
                    }
                }
                Toggle(isOn: $habit.hardBlock) {
                    VStack(alignment: .leading) {
                        Text("🔒 Hard block")
                        Text("Covers the screen until you tap Done").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("The pet will ask: “\(habit.name.isEmpty ? "…" : habit.question)”").foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(isNew ? "Add" : "Save") { onSave(habit); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(habit.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding(.vertical, 8)
    }
}

struct HabitDetail: View {
    @ObservedObject var habits: HabitStore
    let habit: Habit
    private let cal = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text(habit.emoji).font(.system(size: 44))
                    VStack(alignment: .leading) {
                        Text(habit.name).font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(habit.intervalMinutes > 0
                             ? "Pet reminds every \(habit.intervalMinutes) min\(habit.hardBlock ? " · 🔒 hard block" : "")"
                             : "No reminders")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    stat("Today", "\(habits.count(habit))/\(habit.goal)", .accentColor)
                    stat("Streak", "🔥 \(habits.streak(habit))", .orange)
                    stat("Best", "🏆 \(habits.bestStreak(habit))", .yellow)
                }
                weekChart
                monthGrid
            }
            .padding(20)
        }
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var weekChart: some View {
        let days = (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: Date())! }
        return VStack(alignment: .leading) {
            Text("Last 7 days").font(.headline)
            Chart {
                ForEach(days, id: \.self) { d in
                    BarMark(x: .value("Day", d.formatted(.dateTime.weekday(.abbreviated))), y: .value("Count", habits.count(habit, on: d)))
                        .foregroundStyle(habits.met(habit, on: d) ? Color.green.gradient : Color.accentColor.opacity(0.5).gradient)
                        .cornerRadius(5)
                }
                RuleMark(y: .value("Goal", habit.goal)).foregroundStyle(.green.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            .frame(height: 150)
        }
        .card()
    }

    private func dayCell(_ d: Date, number: Int) -> some View {
        let r: Double = min(1, Double(habits.count(habit, on: d)) / Double(max(1, habit.goal)))
        let fill: Color = r == 0 ? Color.gray.opacity(0.12) : Color.green.opacity(0.25 + 0.75 * r)
        let label: String = habits.met(habit, on: d) ? habit.emoji : "\(number)"
        let ring: Color = cal.isDateInToday(d) ? Color.accentColor : Color.clear
        return RoundedRectangle(cornerRadius: 6).fill(fill)
            .overlay(Text(label).font(.system(size: 11)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ring, lineWidth: 2))
            .frame(height: 28)
    }

    private var monthGrid: some View {
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        let n = cal.range(of: .day, in: .month, for: start)!.count
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        return VStack(alignment: .leading) {
            Text(Date().formatted(.dateTime.month(.wide).year())).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(0..<lead, id: \.self) { i in Color.clear.frame(height: 28).id("p\(i)") }
                ForEach(0..<n, id: \.self) { i in
                    dayCell(cal.date(byAdding: .day, value: i, to: start)!, number: i + 1).id("d\(i)")
                }
            }
        }
        .card()
    }
}

// MARK: - Screen time

struct ScreenTimeView: View {
    @ObservedObject var screen: ScreenTime
    let startBreak: () -> Void
    private let cal = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    big("Today", ScreenTime.format(screen.today), screen.overLimit ? .red : .purple)
                    big("Since last break", ScreenTime.format(Int(screen.continuous)), .orange)
                    big("Breaks", "☕ \(screen.taken())  ⏭ \(screen.skipped())", .teal)
                }
                if screen.isIdle {
                    Label("You're away. Timer paused", systemImage: "moon.zzz.fill").foregroundStyle(.secondary)
                }

                VStack(alignment: .leading) {
                    Text("Today by hour").font(.headline)
                    Chart {
                        ForEach(Array(screen.hours(on: Date()).enumerated()), id: \.offset) { h, s in
                            BarMark(x: .value("Hour", h), y: .value("Minutes", s / 60))
                                .foregroundStyle(Color.purple.gradient).cornerRadius(3)
                        }
                    }
                    .chartXScale(domain: 0...23)
                    .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                        AxisValueLabel { if let h = v.as(Int.self) { Text(h == 0 ? "12am" : h < 12 ? "\(h)am" : h == 12 ? "12pm" : "\(h - 12)pm") } }
                    } }
                    .frame(height: 140)
                }
                .card()

                VStack(alignment: .leading) {
                    Text("Last 7 days").font(.headline)
                    let days = (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: Date())! }
                    Chart {
                        ForEach(days, id: \.self) { d in
                            BarMark(x: .value("Day", d.formatted(.dateTime.weekday(.abbreviated))),
                                    y: .value("Hours", Double(screen.seconds(on: d)) / 3600))
                                .foregroundStyle(Color.purple.opacity(0.7).gradient).cornerRadius(5)
                        }
                        if screen.dailyLimit > 0 {
                            RuleMark(y: .value("Limit", Double(screen.dailyLimit) / 60)).foregroundStyle(.red.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                    }
                    .frame(height: 150)
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Breaks").font(.headline)
                    Toggle("Remind me to take breaks", isOn: $screen.breaksOn)
                    Stepper("Break every \(screen.breakEvery) min of screen time", value: $screen.breakEvery, in: 10...120, step: 5)
                        .disabled(!screen.breaksOn)
                    Stepper("Break length: \(screen.breakLength) min", value: $screen.breakLength, in: 1...30)
                        .disabled(!screen.breaksOn)
                    Stepper("Snooze: \(screen.breakSnooze) min", value: $screen.breakSnooze, in: 1...30)
                        .disabled(!screen.breaksOn)
                    Toggle(isOn: $screen.hardBlockBreaks) {
                        VStack(alignment: .leading) {
                            Text("🔒 Hard block breaks")
                            Text("No snoozing, and the screen stays locked until the break ends").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!screen.breaksOn)
                    Stepper(screen.dailyLimit == 0 ? "Daily screen limit: off" : "Daily screen limit: \(ScreenTime.format(screen.dailyLimit * 60))",
                            value: $screen.dailyLimit, in: 0...960, step: 30)
                    Text("Stepping away for 3+ minutes counts as a break automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(action: startBreak) { Label("Take a break now", systemImage: "cup.and.saucer.fill") }
                        .buttonStyle(Round(color: .purple))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .padding(20)
        }
    }

    private func big(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
