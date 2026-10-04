import AppKit
import SwiftUI

/// Calm full-screen break with a countdown, covering every display.
final class BreakScreen {
    static let shared = BreakScreen()
    private var windows: [NSWindow] = []
    private let model = BreakModel()
    private var timer: Timer?
    var isActive: Bool { !windows.isEmpty }

    private var escMonitor: Any?
    private var escDownAt: Date?

    /// locked = hard block: can't end early (emergency: hold Esc 5 s).
    func start(minutes: Int, locked: Bool = false) {
        guard windows.isEmpty else { return }
        model.locked = locked
        let st = ScreenTime.shared
        st.onBreak = true
        model.total = Double(minutes * 60)
        model.remaining = model.total
        model.finished = false
        model.tipIndex = Int.random(in: 0..<BreakModel.tips.count)

        for screen in NSScreen.screens {
            let w = KeyWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.contentView = NSHostingView(rootView: BreakView(model: model, species: Store.shared.species,
                                                              onEnd: { [weak self] in self?.end() }))
            w.setFrame(screen.frame, display: true)
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.8; w.animator().alphaValue = 1 }
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
        if locked {
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
                guard let self, e.keyCode == 53 else { return e }
                if e.type == .keyDown {
                    if self.escDownAt == nil { self.escDownAt = Date() }
                    if Date().timeIntervalSince(self.escDownAt!) >= 5 { self.escDownAt = nil; self.end() }
                } else { self.escDownAt = nil }
                return nil
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.model.remaining > 0 {
                self.model.remaining -= 1
                if Int(self.model.remaining) % 20 == 0 { self.model.tipIndex += 1 }
                if self.model.remaining <= 0 {
                    self.model.finished = true
                    SoundFX.shared.play(.happy, species: Store.shared.species, variant: "breakdone")
                }
            }
        }
    }

    func end() {
        timer?.invalidate(); timer = nil
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        let completed = model.remaining <= 0 || model.remaining <= model.total * 0.2
        ScreenTime.shared.breakFinished(completed: completed)
        let ws = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            ws.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { ws.forEach { $0.orderOut(nil) } })
    }
}

final class BreakModel: ObservableObject {
    @Published var remaining: Double = 300
    @Published var total: Double = 300
    @Published var finished = false
    @Published var tipIndex = 0
    @Published var locked = false

    static let tips = [
        ("👀", "Look at something 20 feet away for 20 seconds"),
        ("🧘", "Roll your shoulders and stretch your neck"),
        ("💧", "Grab a glass of water"),
        ("🚶", "Stand up and walk around a little"),
        ("🌬️", "Take 5 slow, deep breaths"),
        ("🙆", "Reach up high and stretch your whole body"),
        ("🪟", "Look out the window and rest your eyes"),
        ("✋", "Shake out your hands and wrists"),
    ]
}

struct BreakView: View {
    @ObservedObject var model: BreakModel
    let species: Species
    let onEnd: () -> Void

    var body: some View {
        let tip = BreakModel.tips[model.tipIndex % BreakModel.tips.count]
        let progress = 1 - model.remaining / max(1, model.total)
        ZStack {
            BlurBehind().ignoresSafeArea()
            LinearGradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.3), Color(red: 0.25, green: 0.18, blue: 0.38)],
                           startPoint: .top, endPoint: .bottom)
                .opacity(0.82)
                .ignoresSafeArea()
            VStack(spacing: 26) {
                Text(model.finished ? "Break complete! 🎉" : "Break time ☕")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 14)
                    Circle().trim(from: 0, to: progress)
                        .stroke(LinearGradient(colors: [.cyan, .purple], startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)
                    VStack(spacing: 0) {
                        PetView(species: species, mood: model.finished ? .happy : .asking)
                        Text(String(format: "%d:%02d", Int(model.remaining) / 60, Int(model.remaining) % 60))
                            .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 280, height: 280)
                HStack(spacing: 12) {
                    Text(tip.0).font(.system(size: 30))
                    Text(tip.1).font(.system(size: 20, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 22).padding(.vertical, 14)
                .background(Capsule().fill(.white.opacity(0.1)))
                .animation(.easeInOut, value: model.tipIndex)
                if model.finished || !model.locked {
                    Button(action: onEnd) {
                        Text(model.finished ? "Back to work 💪" : "End break early")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(Pill(color: model.finished ? Color(red: 0.35, green: 0.65, blue: 1) : .white.opacity(0.18)))
                    .keyboardShortcut(model.locked ? .defaultAction : .cancelAction)
                } else {
                    Text("🔒 Screen unlocks when the break ends · Emergency: hold Esc 5 s")
                        .font(.system(size: 13, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}

/// Borderless windows can't take keyboard focus by default (needed for Esc).
final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Real blur of whatever is behind the window.
struct BlurBehind: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.material = .fullScreenUI
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
