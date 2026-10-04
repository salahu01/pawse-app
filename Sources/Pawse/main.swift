import AppKit
import SwiftUI
import Combine
import SceneKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store.shared
    private let overlay = PetOverlay()
    private let habits = HabitStore.shared
    private let screen = ScreenTime.shared
    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var nextVisit = Date()
    private var tick: Timer?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        store.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] in DispatchQueue.main.async { self?.refreshTitle() } }
            .store(in: &bag)
        store.onScheduleChange = { [weak self] in self?.scheduleNext() }
        overlay.onFinished = { [weak self] visit, yes in
            guard let self else { return }
            switch visit {
            case .water:
                self.nextVisit = Date().addingTimeInterval(Double(yes ? self.store.intervalMinutes : self.store.snoozeMinutes) * 60)
            case .habit(let h):
                if !yes { self.habits.schedule(h, minutes: self.store.snoozeMinutes) }
            case .breakTime:
                if yes { BreakScreen.shared.start(minutes: self.screen.breakLength, locked: self.screen.hardBlockBreaks) } else { self.screen.snooze() }
            }
        }
        screen.onBreakDue = { [weak self] in self?.check() }
        screen.start()

        scheduleNext()
        refreshTitle()
        tick = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.check() }
        if let i = CommandLine.arguments.firstIndex(of: "--render-pet"), i + 3 < CommandLine.arguments.count,
           let sp = Species(saved: CommandLine.arguments[i + 1]) {
            // dev aid: --render-pet <species> <mood: asking|happy|sad|walking> <out.png>
            let rig = PetRig(); rig.build(sp)
            rig.mood = ["happy": Mood.happy, "sad": .sad, "walking": .walking][CommandLine.arguments[i + 2]] ?? .asking
            let r = SCNRenderer(device: nil, options: nil); r.scene = rig.scene
            for k in 0..<90 { rig.renderer(r, updateAtTime: 0.9 + Double(k) / 60) }
            let img = r.snapshot(atTime: 0, with: CGSize(width: Double(ProcessInfo.processInfo.environment["PAWSE_RENDER_SIZE"] ?? "400") ?? 400, height: Double(ProcessInfo.processInfo.environment["PAWSE_RENDER_SIZE"] ?? "400") ?? 400), antialiasingMode: .multisampling4X)
            if let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 3]))
            }
            exit(0)
        }
        if CommandLine.arguments.contains("--tracker") { openTracker(); return }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            // dev aid: render tracker to PNG and exit
            let r = ImageRenderer(content: TrackerView(store: store, scrolls: false).environment(\.colorScheme, .dark))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            }
            exit(0)
        }
        if CommandLine.arguments.contains("--main") { openMainToday() }
        if let i = CommandLine.arguments.firstIndex(of: "--tab"), i + 1 < CommandLine.arguments.count,
           let t = Tab.allCases.first(where: { $0.rawValue.lowercased().hasPrefix(CommandLine.arguments[i + 1]) }) {
            openMain(tab: t)   // dev aid: open a specific tab
        }
        if CommandLine.arguments.contains("--break") { breakNow() }
        if CommandLine.arguments.contains("--block"), let h = habits.habits.first { var t = h; t.hardBlock = true; visit(.habit(t)) }
        // say hi on first launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.overlay.show() }
    }

    private func scheduleNext() {
        nextVisit = Date().addingTimeInterval(Double(store.intervalMinutes) * 60)
        refreshTitle()
    }

    /// One pet at a time. Priority: break > water > habits.
    private func check() {
        store.rollDayIfNeeded()
        refreshTitle()
        guard !store.paused, !overlay.isVisible, !BreakScreen.shared.isActive, !BlockScreen.shared.isActive else { return }
        if screen.breaksOn, screen.continuous >= Double(screen.breakEvery * 60), Date() >= screen.snoozedUntil.addingTimeInterval(-60) {
            return visit(.breakTime)
        }
        guard store.isAwakeHours() else { return }
        if Date() >= nextVisit, !store.goalReached { return visit(.water) }
        if let h = habits.dueHabit() { visit(.habit(h)) }
    }

    /// Normal visits walk in; hard-block visits take over the screen until "yes".
    private func visit(_ v: Visit) {
        let sp = store.species
        switch v {
        case .breakTime where screen.hardBlockBreaks:
            BlockScreen.shared.show(question: "You've been on screen \(screen.breakEvery) min.\nBreak time! ☕",
                                    yesLabel: "Start my break ☕", voiceVariant: "break",
                onYes: { [weak self] in
                    guard let self else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                        BreakScreen.shared.start(minutes: self.screen.breakLength, locked: true)
                    }
                },
                onEscape: { [weak self] in self?.screen.snooze() })
        case .water where store.hardBlockWater:
            BlockScreen.shared.show(question: "Did you drink water? 💧", yesLabel: "Yes, I drank! 💧", voiceVariant: "ask_0",
                onYes: { [weak self] in
                    guard let self else { return }
                    self.store.drink(); self.scheduleNext()
                    SoundFX.shared.play(.happy, species: sp, variant: self.store.goalReached ? "goal" : nil)
                },
                onEscape: { [weak self] in
                    guard let self else { return }
                    self.nextVisit = Date().addingTimeInterval(Double(self.store.snoozeMinutes) * 60)
                })
        case .habit(let h) where h.hardBlock:
            BlockScreen.shared.show(question: h.question, yesLabel: "Done! \(h.emoji)", voiceVariant: "habit",
                onYes: { [weak self] in
                    guard let self else { return }
                    self.habits.done(h)
                    SoundFX.shared.play(.happy, species: sp, variant: self.habits.met(h) ? "goal" : nil)
                },
                onEscape: { [weak self] in self?.habits.schedule(h, minutes: self?.store.snoozeMinutes) })
        default:
            overlay.show(v)
        }
    }

    private func refreshTitle() {
        statusItem.button?.title = "\(store.species.emoji) \(store.count)/\(store.goal) · \(ScreenTime.format(screen.today))"
    }

    // MARK: menu (rebuilt on open so values are fresh)
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(disabled("💧 \(store.count)/\(store.goal) glasses · \(store.count * store.cupML) ml · 🔥 \(store.streak)"))
        menu.addItem(disabled("🖥️ \(ScreenTime.format(screen.today)) today · ☕ \(screen.taken()) breaks"))
        if store.paused { menu.addItem(disabled("Reminders paused")) }
        else if screen.breaksOn { menu.addItem(disabled("Next break in \(screen.minutesToBreak) min")) }
        menu.addItem(.separator())
        menu.addItem(item("Open \(AppInfo.name)", #selector(openMainToday), "o"))
        menu.addItem(item("I drank a glass 💧", #selector(logDrink), "d"))
        if !habits.habits.isEmpty {
            let sub = NSMenu()
            for (i, h) in habits.habits.enumerated() {
                let it = NSMenuItem(title: "\(h.emoji) \(h.name)  \(habits.count(h))/\(h.goal)", action: #selector(logHabit(_:)), keyEquivalent: "")
                it.target = self; it.tag = i
                sub.addItem(it)
            }
            let parent = NSMenuItem(title: "Log habit", action: nil, keyEquivalent: ""); parent.submenu = sub
            menu.addItem(parent)
        }
        menu.addItem(item("Take a break now ☕", #selector(breakNow), "b"))
        menu.addItem(item("Call \(store.species.shortName) now", #selector(summon), "p"))
        menu.addItem(item(store.paused ? "Resume reminders" : "Pause reminders", #selector(togglePause), ""))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), ","))
        menu.addItem(item("Quit \(AppInfo.name)", #selector(quit), "q"))
    }

    private func disabled(_ s: String) -> NSMenuItem {
        let i = NSMenuItem(title: s, action: nil, keyEquivalent: ""); i.isEnabled = false; return i
    }
    private func item(_ s: String, _ sel: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: s, action: sel, keyEquivalent: key); i.target = self; return i
    }

    @objc private func logDrink() { store.drink(); scheduleNext() }
    @objc private func undoDrink() { store.undo() }
    @objc private func logHabit(_ sender: NSMenuItem) {
        guard habits.habits.indices.contains(sender.tag) else { return }
        habits.done(habits.habits[sender.tag])
    }
    @objc private func breakNow() { BreakScreen.shared.start(minutes: screen.breakLength) }
    @objc private func summon() { overlay.show() }
    @objc private func togglePause() { store.paused.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSounds() { NSWorkspace.shared.open(SoundFX.customDir) }

    @objc private func openTracker() { openMain(tab: .water) }
    @objc private func openSettings() { openMain(tab: .settings) }
    @objc private func openMainToday() { openMain(tab: .today) }

    private func openMain(tab: Tab) {
        let view = MainView(store: store, habits: habits, screen: screen, tab: tab,
                            preview: { [weak self] in self?.overlay.show() },
                            startBreak: { [weak self] in self?.breakNow() })
        if mainWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = AppInfo.name
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("MainWindow")
            mainWindow = w
        }
        mainWindow?.contentView = NSHostingView(rootView: view)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }
}

Migration.run()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
