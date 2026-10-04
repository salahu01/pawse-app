import Foundation
import Combine

enum AppInfo {
    /// Product name shown everywhere in the UI. Change here to rename the app.
    static let name = "Pawse"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    static let website = URL(string: "https://salahu01.github.io/pawse/")!
    static let repo = URL(string: "https://github.com/salahu01/pawse-app")!
}

/// A custom daily habit (water is handled separately by Store, with ml tracking).
struct Habit: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var emoji: String
    var goal: Int = 1               // times per day
    var intervalMinutes: Int = 0    // 0 = no pet reminder, otherwise remind every N min until goal
    var hardBlock = false           // block the screen until the user says yes
    var question: String { "Did you \(verb)? \(emoji)" }
    var verb: String { name.prefix(1).lowercased() + name.dropFirst() }

    init(name: String, emoji: String, goal: Int = 1, intervalMinutes: Int = 0, hardBlock: Bool = false) {
        self.name = name; self.emoji = emoji; self.goal = goal
        self.intervalMinutes = intervalMinutes; self.hardBlock = hardBlock
    }
    // tolerate data saved before new fields existed
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        emoji = try c.decode(String.self, forKey: .emoji)
        goal = try c.decodeIfPresent(Int.self, forKey: .goal) ?? 1
        intervalMinutes = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? 0
        hardBlock = try c.decodeIfPresent(Bool.self, forKey: .hardBlock) ?? false
    }

    static let presets: [Habit] = [
        Habit(name: "Stretch", emoji: "🧘", goal: 3, intervalMinutes: 90),
        Habit(name: "Rest your eyes", emoji: "👀", goal: 6, intervalMinutes: 60),
        Habit(name: "Take vitamins", emoji: "💊", goal: 1, intervalMinutes: 0),
        Habit(name: "Go for a walk", emoji: "🚶", goal: 1, intervalMinutes: 180),
        Habit(name: "Eat fruit", emoji: "🍎", goal: 2, intervalMinutes: 0),
        Habit(name: "Read", emoji: "📖", goal: 1, intervalMinutes: 0),
        Habit(name: "Meditate", emoji: "🧠", goal: 1, intervalMinutes: 0),
        Habit(name: "Fix posture", emoji: "🪑", goal: 8, intervalMinutes: 45),
    ]
}

final class HabitStore: ObservableObject {
    static let shared = HabitStore()
    private let d = UserDefaults.standard

    @Published var habits: [Habit] { didSet { save() } }
    /// habit id -> day key -> count
    @Published private(set) var log: [String: [String: Int]]
    /// when each habit's pet reminder is next due (not persisted)
    var nextDue: [UUID: Date] = [:]

    private init() {
        if let data = d.data(forKey: "habits"), let h = try? JSONDecoder().decode([Habit].self, from: data) {
            habits = h
        } else {
            habits = [Habit.presets[0], Habit.presets[1]]   // sensible starters
        }
        log = d.dictionary(forKey: "habitLog") as? [String: [String: Int]] ?? [:]
    }

    private func save() {
        if let data = try? JSONEncoder().encode(habits) { d.set(data, forKey: "habits") }
        d.set(log, forKey: "habitLog")
    }

    private func key(_ date: Date) -> String { Store.key(date) }

    func count(_ h: Habit, on date: Date = Date()) -> Int { log[h.id.uuidString]?[key(date)] ?? 0 }
    func met(_ h: Habit, on date: Date = Date()) -> Bool { count(h, on: date) >= max(1, h.goal) }
    func progress(_ h: Habit) -> Double { min(1, Double(count(h)) / Double(max(1, h.goal))) }

    func done(_ h: Habit) {
        log[h.id.uuidString, default: [:]][key(Date()), default: 0] += 1
        schedule(h)
        save()
    }
    func undo(_ h: Habit) {
        let k = key(Date())
        log[h.id.uuidString, default: [:]][k] = max(0, count(h) - 1)
        save()
    }

    func add(_ h: Habit) { habits.append(h); schedule(h) }
    func remove(_ h: Habit) { habits.removeAll { $0.id == h.id }; log[h.id.uuidString] = nil; save() }
    func update(_ h: Habit) {
        guard let i = habits.firstIndex(where: { $0.id == h.id }) else { return }
        habits[i] = h; schedule(h)
    }

    func schedule(_ h: Habit, minutes: Int? = nil) {
        guard h.intervalMinutes > 0 else { nextDue[h.id] = nil; return }
        nextDue[h.id] = Date().addingTimeInterval(Double(minutes ?? h.intervalMinutes) * 60)
    }
    /// First habit whose reminder is due and whose goal isn't met yet.
    func dueHabit() -> Habit? {
        for h in habits where h.intervalMinutes > 0 && !met(h) {
            if nextDue[h.id] == nil { schedule(h) }
            if let t = nextDue[h.id], t <= Date() { return h }
        }
        return nil
    }

    func streak(_ h: Habit) -> Int {
        let cal = Calendar.current
        var day = Date()
        if !met(h, on: day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while met(h, on: day) { n += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return n
    }
    func bestStreak(_ h: Habit) -> Int {
        let days = (log[h.id.uuidString] ?? [:]).keys.compactMap { Store.dayFmt.date(from: $0) }.sorted()
        guard var day = days.first else { return 0 }
        var best = 0, run = 0
        while day <= Date() {
            run = met(h, on: day) ? run + 1 : 0
            best = max(best, run)
            day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        }
        return best
    }
}
