import SwiftUI
import Charts

/// Habit tracker: today's water level, streaks, week chart, month heatmap.
struct TrackerView: View {
    @ObservedObject var store: Store
    var scrolls = true
    @State private var month = Date()

    private let water = Color(red: 0.33, green: 0.65, blue: 1)
    private let cal = Calendar.current

    var body: some View {
        Group {
            if scrolls { ScrollView { content } } else { content }
        }
        .frame(maxWidth: scrolls ? .infinity : 520, maxHeight: scrolls ? .infinity : nil)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var content: some View {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    todayCard
                    VStack(spacing: 12) {
                        stat("🔥", "\(store.streak)", "day streak", .orange)
                        stat("🏆", "\(store.bestStreak)", "best streak", .yellow)
                        stat("💧", liters(store.totalGlasses), "all time", water)
                    }
                }
                weekCard
                monthCard
            }
            .padding(18)
    }

    // MARK: today
    private var todayCard: some View {
        VStack(spacing: 10) {
            Text("Today").font(.system(.headline, design: .rounded)).foregroundStyle(.secondary)
            WaterGlass(level: store.progress, color: water)
                .frame(width: 130, height: 170)
            Text("\(store.count) / \(store.goal) glasses")
                .font(.system(.title3, design: .rounded).bold())
            Text("\(store.count * store.cupML) ml of \(store.goal * store.cupML) ml")
                .font(.system(.callout, design: .rounded)).foregroundStyle(.secondary)
            HStack {
                Button { withAnimation(.spring) { store.undo() } } label: { Image(systemName: "minus") }
                    .buttonStyle(Round(color: .gray))
                Button { withAnimation(.spring) { store.drink() } } label: {
                    Label("Drink", systemImage: "drop.fill").font(.system(.body, design: .rounded).bold())
                }
                .buttonStyle(Round(color: water))
            }
            if store.goalReached {
                Text("Goal reached! 🎉").font(.system(.callout, design: .rounded).bold()).foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func stat(_ icon: String, _ value: String, _ label: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Text(icon).font(.system(size: 28))
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(tint)
                Text(label).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(width: 170)
        .card()
    }

    // MARK: week
    private struct DayStat: Identifiable { let id: Date; let label: String; let glasses: Int; let met: Bool }

    private var weekCard: some View {
        let days: [DayStat] = (0..<7).reversed().map { back in
            let d = cal.date(byAdding: .day, value: -back, to: Date())!
            let f = DateFormatter(); f.dateFormat = "EEE"
            return DayStat(id: d, label: back == 0 ? "Today" : f.string(from: d), glasses: store.glasses(on: d), met: store.met(on: d))
        }
        let avg = Double(days.map(\.glasses).reduce(0, +)) / 7
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last 7 days").font(.system(.headline, design: .rounded))
                Spacer()
                Text(String(format: "avg %.1f / day", avg)).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(days) { d in
                    BarMark(x: .value("Day", d.label), y: .value("Glasses", d.glasses))
                        .foregroundStyle(d.met ? water.gradient : water.opacity(0.4).gradient)
                        .cornerRadius(6)
                        .annotation(position: .top) {
                            if d.met { Text("✓").font(.caption2.bold()).foregroundStyle(.green) }
                        }
                }
                RuleMark(y: .value("Goal", store.goal))
                    .foregroundStyle(.green.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("goal").font(.caption2).foregroundStyle(.green)
                    }
            }
            .frame(height: 160)
        }
        .card()
    }

    // MARK: month heatmap
    private var monthCard: some View {
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let count = cal.range(of: .day, in: .month, for: start)!.count
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        let title = { let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: start) }()
        let metDays = (0..<count).filter { store.met(on: cal.date(byAdding: .day, value: $0, to: start)!) }.count
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

        return VStack(spacing: 10) {
            HStack {
                Button { month = cal.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text(title).font(.system(.headline, design: .rounded))
                Spacer()
                Button { month = cal.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                    .disabled(cal.isDate(month, equalTo: Date(), toGranularity: .month))
            }
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    Text(cal.veryShortWeekdaySymbols[(i + cal.firstWeekday - 1) % 7])
                        .font(.caption2).foregroundStyle(.secondary)
                        .id("h\(i)")
                }
                ForEach(0..<lead, id: \.self) { i in Color.clear.frame(height: 34).id("pad\(i)") }
                ForEach(0..<count, id: \.self) { i in
                    dayCell(cal.date(byAdding: .day, value: i, to: start)!, number: i + 1).id("d\(i)")
                }
            }
            HStack {
                Text("\(metDays) goal day\(metDays == 1 ? "" : "s") this month")
                Spacer()
                HStack(spacing: 3) {
                    Text("less")
                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { v in
                        RoundedRectangle(cornerRadius: 3).fill(fill(v)).frame(width: 12, height: 12)
                    }
                    Text("more")
                }
            }
            .font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
        }
        .card()
    }

    private func dayCell(_ d: Date, number: Int) -> some View {
        let future = d > Date() && !cal.isDateInToday(d)
        let g = store.glasses(on: d)
        let ratio = min(1, Double(g) / Double(max(1, store.goal(on: d))))
        return ZStack {
            RoundedRectangle(cornerRadius: 8).fill(future ? Color.gray.opacity(0.06) : fill(ratio))
            if store.met(on: d) {
                Text("💧").font(.system(size: 13))
            } else {
                Text("\(number)").font(.system(size: 11, design: .rounded))
                    .foregroundStyle(ratio > 0.6 ? .white : .secondary)
            }
        }
        .frame(height: 34)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cal.isDateInToday(d) ? water : .clear, lineWidth: 2))
        .help(future ? "" : "\(g) glass\(g == 1 ? "" : "es")")
    }

    private func fill(_ v: Double) -> Color { v == 0 ? Color.gray.opacity(0.12) : water.opacity(0.2 + 0.8 * v) }
    private func liters(_ glasses: Int) -> String { String(format: "%.1f L", Double(glasses * store.cupML) / 1000) }
}

/// Animated glass with a sloshing wave.
struct WaterGlass: View {
    let level: Double
    let color: Color

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                GlassShape().fill(color.opacity(0.08))
                ZStack {
                    Wave(level: level, phase: t * 2.2, amp: 5).fill(color.opacity(0.45))
                    Wave(level: level, phase: t * 3 + 1.5, amp: 4).fill(color.gradient)
                }
                .clipShape(GlassShape())
                .animation(.spring(response: 0.8, dampingFraction: 0.7), value: level)
                GlassShape().stroke(color.opacity(0.6), lineWidth: 3)
                Text("\(Int(level * 100))%")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(level > 0.45 ? .white : color)
                    .shadow(color: .black.opacity(level > 0.45 ? 0.2 : 0), radius: 2)
            }
        }
    }
}

struct GlassShape: Shape {
    func path(in r: CGRect) -> Path {
        let inset = r.width * 0.12
        return Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - inset, y: r.maxY - 14))
            p.addQuadCurve(to: CGPoint(x: r.maxX - inset - 14, y: r.maxY), control: CGPoint(x: r.maxX - inset, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + inset + 14, y: r.maxY))
            p.addQuadCurve(to: CGPoint(x: r.minX + inset, y: r.maxY - 14), control: CGPoint(x: r.minX + inset, y: r.maxY))
            p.closeSubpath()
        }
    }
}

struct Wave: Shape {
    var level: Double
    var phase: Double
    var amp: Double
    var animatableData: Double { get { level } set { level = newValue } }

    func path(in r: CGRect) -> Path {
        let y0 = r.maxY - r.height * level
        return Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            for x in stride(from: r.minX, through: r.maxX, by: 2) {
                let a = level <= 0 || level >= 1 ? amp * 0.3 : amp
                p.addLine(to: CGPoint(x: x, y: y0 + sin(x / r.width * 2 * .pi * 1.3 + phase) * a))
            }
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

struct Round: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(color))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .contentShape(Capsule())
    }
}

extension View {
    func card() -> some View {
        padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.gray.opacity(0.15)))
    }
}
