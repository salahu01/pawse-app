import Foundation
import Combine

/// A pet: one of the built-in hand-made pets, or any USDZ model in the Models folder.
struct Species: Hashable, Identifiable {
    let rawValue: String
    var id: String { rawValue }

    static let cat = Species(rawValue: "cat")
    static let penguin = Species(rawValue: "penguin")
    static let capybara = Species(rawValue: "capybara")
    static let bunny = Species(rawValue: "bunny")
    static let kid = Species(rawValue: "kid")
    static let builtIn: [Species] = [.kid, .cat, .penguin, .capybara, .bunny]

    init(rawValue: String) { self.rawValue = rawValue }
    /// nil if neither built in nor a model file present
    init?(saved: String) {
        self.init(rawValue: saved)
        if isModel && modelURL == nil { return nil }
    }

    var isModel: Bool { !Self.builtIn.contains(self) }

    /// Drop any .usdz here and it becomes a pet.
    static let modelsDir: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pawse/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    var modelURL: URL? {
        guard isModel else { return nil }
        let u = Self.modelsDir.appendingPathComponent("\(rawValue).usdz")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    static var models: [Species] {
        let files = (try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "usdz" }
            .map { Species(rawValue: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.rawValue < $1.rawValue }
    }
    static var available: [Species] { builtIn + models }

    /// "Chibi_Cute_Sheep" -> "Chibi Cute Sheep"
    var name: String {
        switch self {
        case .cat: return "Mochi the Cat"
        case .penguin: return "Pip the Penguin"
        case .capybara: return "Yuzu the Capybara"
        case .bunny: return "Boo the Ghost Bunny"
        case .kid: return "Momo the Chibi"
        default:
            return rawValue.replacingOccurrences(of: "_", with: " ")
                .components(separatedBy: " ").filter { !$0.isEmpty && $0 != "-" }.prefix(4).joined(separator: " ")
        }
    }
    var shortName: String { name.components(separatedBy: " ").first ?? name }
    private func has(_ words: String...) -> Bool { words.contains { rawValue.lowercased().contains($0) } }
    var emoji: String {
        switch self {
        case .cat: return "🐱"
        case .penguin: return "🐧"
        case .capybara: return "🦫"
        case .bunny: return "👻"
        case .kid: return "🧒"
        default:
            if has("sheep", "lamb") { return "🐑" }
            if has("fox") { return "🦊" }
            if has("shiba", "dog", "puppy") { return "🐕" }
            if has("cat", "kitty") { return "🐱" }
            return "⭐"
        }
    }
    /// Model pets get messages that fit their name.
    var asks: [String] {
        if has("sheep", "lamb") { return ["Baa~ did you drink water? 💧", "Fluffy reminder: hydrate 🐑", "Sip sip, then back to grazing 🌿"] }
        if has("fox") { return ["Psst… clever foxes drink water 🦊💧", "Water break? Yip! 💦", "Stay sharp, stay hydrated 🦊"] }
        if has("shiba", "dog") { return ["Woof! Water time? 💧", "Good human drinks water 🐕", "*tail wag* did you sip? 💦"] }
        return ["Hey! Did you drink water? 💧", "\(shortName) says: time to hydrate 💦", "Quick sip break? 🥤"]
    }
}

/// All user settings and today's progress, persisted in UserDefaults.
final class Store: ObservableObject {
    static let shared = Store()
    private let d = UserDefaults.standard

    @Published var species: Species { didSet { d.set(species.rawValue, forKey: "species") } }
    @Published var goal: Int { didSet { d.set(goal, forKey: "goal"); save() } }
    @Published var intervalMinutes: Int { didSet { d.set(intervalMinutes, forKey: "interval"); onScheduleChange?() } }
    @Published var snoozeMinutes: Int { didSet { d.set(snoozeMinutes, forKey: "snooze") } }
    @Published var cupML: Int { didSet { d.set(cupML, forKey: "cupML") } }
    @Published var startHour: Int { didSet { d.set(startHour, forKey: "startHour") } }
    @Published var endHour: Int { didSet { d.set(endHour, forKey: "endHour") } }
    @Published var paused: Bool { didSet { d.set(paused, forKey: "paused"); onScheduleChange?() } }
    @Published var hardBlockWater: Bool { didSet { d.set(hardBlockWater, forKey: "hardBlockWater") } }
    @Published var soundOn: Bool { didSet { d.set(soundOn, forKey: "soundOn") } }
    @Published var volume: Double { didSet { d.set(volume, forKey: "volume") } }
    @Published private(set) var count: Int
    /// day ("yyyy-MM-dd") -> [glasses, goal]
    @Published private(set) var history: [String: [Int]]

    var onScheduleChange: (() -> Void)?

    private init() {
        species = Species(saved: d.string(forKey: "species") ?? "") ?? .cat
        goal = d.object(forKey: "goal") as? Int ?? 8
        intervalMinutes = d.object(forKey: "interval") as? Int ?? 45
        snoozeMinutes = d.object(forKey: "snooze") as? Int ?? 10
        cupML = d.object(forKey: "cupML") as? Int ?? 250
        startHour = d.object(forKey: "startHour") as? Int ?? 8
        endHour = d.object(forKey: "endHour") as? Int ?? 22
        paused = d.bool(forKey: "paused")
        hardBlockWater = d.bool(forKey: "hardBlockWater")
        soundOn = d.object(forKey: "soundOn") as? Bool ?? true
        volume = d.object(forKey: "volume") as? Double ?? 0.8
        count = d.integer(forKey: "count")
        history = d.dictionary(forKey: "history") as? [String: [Int]] ?? [:]
        rollDayIfNeeded()
    }

    static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
    static func key(_ date: Date) -> String { dayFmt.string(from: date) }

    /// Resets the counter on a new day (past days stay in history).
    func rollDayIfNeeded() {
        let t = Self.key(Date())
        guard d.string(forKey: "day") != t else { return }
        count = 0
        d.set(t, forKey: "day")
        save()
    }

    func drink() { rollDayIfNeeded(); count += 1; save() }
    func undo() { count = max(0, count - 1); save() }
    func resetToday() { count = 0; save() }
    private func save() {
        d.set(count, forKey: "count")
        history[Self.key(Date())] = [count, goal]
        d.set(history, forKey: "history")
    }

    // MARK: history queries
    func glasses(on date: Date) -> Int { history[Self.key(date)]?[0] ?? 0 }
    func goal(on date: Date) -> Int { history[Self.key(date)]?[1] ?? goal }
    func met(on date: Date) -> Bool { glasses(on: date) >= max(1, goal(on: date)) }

    /// Consecutive goal days ending today (or yesterday, if today isn't done yet).
    var streak: Int {
        let cal = Calendar.current
        var day = Date()
        if !met(on: day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while met(on: day) { n += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return n
    }
    var bestStreak: Int {
        let days = history.keys.compactMap { Self.dayFmt.date(from: $0) }.sorted()
        guard let first = days.first else { return 0 }
        let cal = Calendar.current
        var best = 0, run = 0, day = first
        while day <= Date() {
            run = met(on: day) ? run + 1 : 0
            best = max(best, run)
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return best
    }
    var totalGlasses: Int { history.values.reduce(0) { $0 + $1[0] } }
    var daysTracked: Int { history.values.filter { $0[0] > 0 }.count }

    var progress: Double { min(1, Double(count) / Double(max(goal, 1))) }
    var goalReached: Bool { count >= goal }

    func isAwakeHours(_ date: Date = Date()) -> Bool {
        let h = Calendar.current.component(.hour, from: date)
        return startHour <= endHour ? (h >= startHour && h < endHour) : (h >= startHour || h < endHour)
    }
}

extension Int {
    func clamped(_ lo: Int, _ hi: Int) -> Int { Swift.min(Swift.max(self, lo), hi) }
}
