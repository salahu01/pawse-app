import Foundation
import CoreGraphics
import Combine

/// Tracks active computer use (keyboard/mouse activity) and decides when a break is due.
final class ScreenTime: ObservableObject {
    static let shared = ScreenTime()
    private let d = UserDefaults.standard
    private let tickSeconds = 10.0

    // settings
    @Published var breaksOn: Bool { didSet { d.set(breaksOn, forKey: "breaksOn") } }
    @Published var breakEvery: Int { didSet { d.set(breakEvery, forKey: "breakEvery") } }      // minutes of continuous use
    @Published var breakLength: Int { didSet { d.set(breakLength, forKey: "breakLength") } }   // minutes
    @Published var breakSnooze: Int { didSet { d.set(breakSnooze, forKey: "breakSnooze") } }
    @Published var hardBlockBreaks: Bool { didSet { d.set(hardBlockBreaks, forKey: "hardBlockBreaks") } }
    @Published var dailyLimit: Int { didSet { d.set(dailyLimit, forKey: "dailyLimit") } }      // minutes, 0 = none

    // live state
    @Published private(set) var continuous: Double = 0      // seconds since last break
    @Published private(set) var isIdle = false
    @Published var onBreak = false
    var snoozedUntil = Date.distantPast
    var onBreakDue: (() -> Void)?

    // history: day -> 24 hourly buckets (seconds); breaks taken / skipped per day
    @Published private(set) var hourly: [String: [Int]]
    @Published private(set) var breaksTaken: [String: Int]
    @Published private(set) var breaksSkipped: [String: Int]

    private var timer: Timer?
    private var lastSave = Date()

    /// Idle this long = you stepped away, which counts as a natural break.
    private let naturalBreak: Double = 180
    /// No input for this long = not actively using the computer.
    private let idleAfter: Double = 60

    private init() {
        breaksOn = d.object(forKey: "breaksOn") as? Bool ?? true
        breakEvery = d.object(forKey: "breakEvery") as? Int ?? 30
        breakLength = d.object(forKey: "breakLength") as? Int ?? 5
        breakSnooze = d.object(forKey: "breakSnooze") as? Int ?? 5
        dailyLimit = d.object(forKey: "dailyLimit") as? Int ?? 0
        hardBlockBreaks = d.bool(forKey: "hardBlockBreaks")
        hourly = d.dictionary(forKey: "screenHourly") as? [String: [Int]] ?? [:]
        breaksTaken = d.dictionary(forKey: "breaksTaken") as? [String: Int] ?? [:]
        breaksSkipped = d.dictionary(forKey: "breaksSkipped") as? [String: Int] ?? [:]
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: tickSeconds, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private func tick() {
        let idle = idleSeconds()
        isIdle = idle >= idleAfter
        if onBreak { return }
        if idle >= naturalBreak { continuous = 0 }
        guard !isIdle else { return }

        continuous += tickSeconds
        let k = Store.key(Date()), h = Calendar.current.component(.hour, from: Date())
        var day = hourly[k] ?? Array(repeating: 0, count: 24)
        day[h] += Int(tickSeconds)
        hourly[k] = day
        if Date().timeIntervalSince(lastSave) > 60 { save() }

        if breaksOn, continuous >= Double(breakEvery * 60), Date() >= snoozedUntil {
            snoozedUntil = Date().addingTimeInterval(60)   // don't re-fire while the pet is visiting
            onBreakDue?()
        }
    }

    func snooze() {
        snoozedUntil = Date().addingTimeInterval(Double(breakSnooze * 60))
        breaksSkipped[Store.key(Date()), default: 0] += 1
        save()
    }
    func breakFinished(completed: Bool) {
        onBreak = false
        continuous = 0
        snoozedUntil = .distantPast
        if completed { breaksTaken[Store.key(Date()), default: 0] += 1 }
        save()
    }

    private func save() {
        lastSave = Date()
        d.set(hourly, forKey: "screenHourly")
        d.set(breaksTaken, forKey: "breaksTaken")
        d.set(breaksSkipped, forKey: "breaksSkipped")
    }

    // MARK: queries
    func seconds(on date: Date) -> Int { (hourly[Store.key(date)] ?? []).reduce(0, +) }
    func hours(on date: Date) -> [Int] { hourly[Store.key(date)] ?? Array(repeating: 0, count: 24) }
    func taken(on date: Date = Date()) -> Int { breaksTaken[Store.key(date)] ?? 0 }
    func skipped(on date: Date = Date()) -> Int { breaksSkipped[Store.key(date)] ?? 0 }
    var today: Int { seconds(on: Date()) }
    var minutesToBreak: Int { max(0, breakEvery - Int(continuous / 60)) }
    var overLimit: Bool { dailyLimit > 0 && today >= dailyLimit * 60 }

    static func format(_ secs: Int) -> String {
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
