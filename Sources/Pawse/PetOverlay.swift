import AppKit
import SwiftUI

/// State shared between the overlay window and its SwiftUI content.
final class VisitModel: ObservableObject {
    @Published var mood: Mood = .walking
    @Published var facingLeft = true
    @Published var message: String?
    @Published var showButtons = false
    @Published var yesLabel = "Yes! 💧"
    @Published var noLabel = "Not yet"
}

/// What the pet is visiting about.
enum Visit: Equatable {
    case water
    case habit(Habit)
    case breakTime
}

/// Floating transparent panel the pet walks across.
final class PetOverlay {
    private var panel: NSPanel?
    private let model = VisitModel()
    private let store = Store.shared
    private var declines = 0
    private var timeout: DispatchWorkItem?
    private var visit: Visit = .water
    private let habits = HabitStore.shared
    var onFinished: ((_ visit: Visit, _ accepted: Bool) -> Void)?
    var isVisible: Bool { panel != nil }

    private let size = NSSize(width: 340, height: 300)

    private static let asks: [Species: [String]] = [
        .cat: ["Meow~ did you drink water? 💧", "Psst… water break? 🐾", "Hydration check, hooman! 💦"],
        .penguin: ["Waddle waddle… water time? 💧", "Pip says: sip sip? 🧊", "Have you had water yet? 💙"],
        .kid: ["Hey hey! Did you drink water? 💧", "Momo brought you water! 🥤✨", "Sip break together? 💙"],
        .bunny: ["Boo~ did you drink water? 👻💧", "Even ghosts stay hydrated~ 💧", "Ooo… sip time? 🐰"],
        .capybara: ["Chill… but did you drink? 💧", "Yuzu reminds you: sip water 🍊", "Stay calm, stay hydrated 🛁"],
    ]
    private static let pleads = [
        "Again? Pretty please drink 🥺",
        "I'm getting worried… 😿 one sip?",
        "I will sit here until you drink. 😤💧",
    ]

    func show(_ v: Visit = .water) {
        guard panel == nil, let screen = NSScreen.main else { return }
        if v != visit { declines = 0 }
        visit = v
        let vf = screen.visibleFrame
        let p = NSPanel(contentRect: NSRect(x: vf.maxX + 10, y: vf.minY, width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = true
        p.contentView = NSHostingView(rootView: OverlayContent(model: model, species: store.species,
            onYes: { [weak self] in self?.answer(true) },
            onNo: { [weak self] in self?.answer(false) }))
        panel = p

        model.mood = .walking
        model.facingLeft = true
        model.message = nil
        model.showButtons = false
        p.orderFrontRegardless()
        SoundFX.shared.startSteps(species: store.species)

        move(to: vf.maxX - size.width - 20, duration: 3.2) { [weak self] in self?.ask() }
    }

    private static let breakAsks = [
        "You've been on screen %d min! Break time? ☕",
        "Your eyes need a rest~ %d min straight! 👀",
        "%d minutes of work! Stretch with me? 🧘",
    ]

    private func ask() {
        SoundFX.shared.stopSteps()
        let sp = store.species
        model.mood = .asking
        var message: String
        var variant: String
        switch visit {
        case .water:
            let list = declines == 0 ? (Self.asks[sp] ?? sp.asks) : Self.pleads
            let idx = declines == 0 ? Int.random(in: 0..<list.count) : min(declines - 1, list.count - 1)
            message = list[idx]
            variant = declines == 0 ? "ask_\(idx)" : "plead"
            model.yesLabel = "Yes! 💧"; model.noLabel = "Not yet"
        case .habit(let h):
            message = declines == 0 ? h.question : "Pretty please? \(h.name) \(h.emoji) 🥺"
            variant = declines == 0 ? "habit" : "plead"
            model.yesLabel = "Done! \(h.emoji)"; model.noLabel = "Later"
        case .breakTime:
            let mins = ScreenTime.shared.breakEvery
            message = String(format: Self.breakAsks[declines % Self.breakAsks.count], mins + declines * ScreenTime.shared.breakSnooze)
            variant = declines == 0 ? "break" : "plead"
            model.yesLabel = "Start break ☕"; model.noLabel = "\(ScreenTime.shared.breakSnooze) more min"
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            model.message = message
            model.showButtons = true
        }
        SoundFX.shared.play(.ask, species: sp, variant: variant)
        let w = DispatchWorkItem { [weak self] in self?.answer(false, silent: true) }
        timeout = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: w)
    }

    private func answer(_ yes: Bool, silent: Bool = false) {
        timeout?.cancel()
        model.showButtons = false
        let sp = store.species
        if yes {
            declines = 0
            model.mood = .happy
            switch visit {
            case .water:
                store.drink()
                model.message = store.goalReached
                    ? "GOAL! \(store.count)/\(store.goal) 🎉 so proud!"
                    : "Yay! \(store.count)/\(store.goal) glasses 💙"
                SoundFX.shared.play(.happy, species: sp, variant: store.goalReached ? "goal" : nil)
                if store.goalReached { SoundFX.shared.play(.goal, species: sp) }
            case .habit(let h):
                habits.done(h)
                let met = habits.met(h)
                model.message = met ? "\(h.name) done for today! 🎉" : "Nice! \(habits.count(h))/\(h.goal) \(h.emoji)"
                SoundFX.shared.play(.happy, species: sp, variant: met ? "goal" : nil)
            case .breakTime:
                model.message = "Yay! Let's rest together 💤"
                SoundFX.shared.play(.happy, species: sp, variant: "breakstart")
            }
        } else {
            declines += 1
            model.mood = .sad
            model.message = silent ? "…I'll come back later 💤" : "Okay… I'll come back soon 🥺"
            if !silent { SoundFX.shared.play(.sad, species: sp) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (yes ? 2.6 : 2.0)) { [weak self] in
            self?.leave(drank: yes)
        }
    }

    private func leave(drank: Bool) {
        guard let screen = NSScreen.main else { return close(drank) }
        model.message = nil
        model.mood = .walking
        model.facingLeft = false
        SoundFX.shared.startSteps(species: store.species)
        move(to: screen.frame.maxX + 10, duration: 2.6) { [weak self] in self?.close(drank) }
    }

    private func close(_ drank: Bool) {
        SoundFX.shared.stopSteps()
        panel?.orderOut(nil)
        panel = nil
        onFinished?(visit, drank)
    }

    private func move(to x: CGFloat, duration: Double, done: @escaping () -> Void) {
        guard let p = panel else { return }
        var f = p.frame
        f.origin.x = x
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            p.animator().setFrame(f, display: true)
        }, completionHandler: done)
    }
}

struct OverlayContent: View {
    @ObservedObject var model: VisitModel
    let species: Species
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            if let msg = model.message {
                VStack(spacing: 10) {
                    Text(msg)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(red: 0.2, green: 0.22, blue: 0.3))
                    if model.showButtons {
                        HStack(spacing: 8) {
                            Button(action: onYes) { Text(model.yesLabel).bold() }
                                .buttonStyle(Pill(color: Color(red: 0.35, green: 0.65, blue: 1)))
                            Button(action: onNo) { Text(model.noLabel) }
                                .buttonStyle(Pill(color: Color(red: 0.75, green: 0.75, blue: 0.8)))
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(BubbleShape().fill(.white).shadow(color: .black.opacity(0.18), radius: 8, y: 3))
                .frame(maxWidth: 280)
                .transition(.scale(scale: 0.3, anchor: .bottom).combined(with: .opacity))
            }
            PetView(species: species, mood: model.mood, facingLeft: model.facingLeft)
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Pill: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(color))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .contentShape(Capsule())
    }
}

/// Rounded speech bubble with a tail pointing down at the pet.
struct BubbleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: r, cornerRadius: 18)
        p.move(to: CGPoint(x: r.midX - 9, y: r.maxY - 1))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY + 10))
        p.addLine(to: CGPoint(x: r.midX + 9, y: r.maxY - 1))
        p.closeSubpath()
        return p
    }
}
