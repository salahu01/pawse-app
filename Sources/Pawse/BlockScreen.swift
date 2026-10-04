import AppKit
import SwiftUI

/// Hard block: covers every screen until the user answers yes.
/// Emergency exit: hold Esc for 5 seconds.
final class BlockScreen {
    static let shared = BlockScreen()
    private var windows: [NSWindow] = []
    private let model = BlockModel()
    private var keyMonitor: Any?
    private var escDownAt: Date?
    private var escTimer: Timer?
    private var onYes: (() -> Void)?
    private var onEscape: (() -> Void)?
    private var savedOptions: NSApplication.PresentationOptions = []
    var isActive: Bool { !windows.isEmpty }

    /// - onYes: user confirmed. - onEscape: emergency unlock (treated as "not now").
    func show(question: String, yesLabel: String, voiceVariant: String,
              onYes: @escaping () -> Void, onEscape: @escaping () -> Void) {
        guard windows.isEmpty else { return }
        self.onYes = onYes
        self.onEscape = onEscape
        model.question = question
        model.yesLabel = yesLabel
        model.mood = .asking
        model.done = false
        model.escProgress = 0
        let sp = Store.shared.species

        for screen in NSScreen.screens {
            let w = KeyWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.contentView = NSHostingView(rootView: BlockView(model: model, species: sp, onYes: { [weak self] in self?.confirm() }))
            w.setFrame(screen.frame, display: true)
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.6; w.animator().alphaValue = 1 }
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
        savedOptions = NSApp.presentationOptions
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]
        SoundFX.shared.play(.ask, species: sp, variant: voiceVariant)
        watchEscape()
    }

    private func confirm() {
        model.done = true
        model.mood = .happy
        onYes?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.close() }
    }

    private func watchEscape() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            guard let self, e.keyCode == 53 else { return e }   // 53 = Esc
            if e.type == .keyDown, self.escDownAt == nil {
                self.escDownAt = Date()
                self.escTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    guard let self, let t = self.escDownAt else { return }
                    self.model.escProgress = min(1, Date().timeIntervalSince(t) / 5)
                    if self.model.escProgress >= 1 {
                        self.onEscape?()
                        self.close()
                    }
                }
            } else if e.type == .keyUp {
                self.escDownAt = nil
                self.escTimer?.invalidate()
                self.model.escProgress = 0
            }
            return nil
        }
    }

    private func close() {
        escTimer?.invalidate(); escTimer = nil; escDownAt = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        NSApp.presentationOptions = savedOptions
        let ws = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            ws.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { ws.forEach { $0.orderOut(nil) } })
    }
}

final class BlockModel: ObservableObject {
    @Published var question = ""
    @Published var yesLabel = "Yes!"
    @Published var mood: Mood = .asking
    @Published var done = false
    @Published var escProgress: Double = 0
}

struct BlockView: View {
    @ObservedObject var model: BlockModel
    let species: Species
    let onYes: () -> Void

    var body: some View {
        ZStack {
            BlurBehind().ignoresSafeArea()
            LinearGradient(colors: [Color(red: 0.98, green: 0.85, blue: 0.9), Color(red: 0.8, green: 0.88, blue: 1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.88).ignoresSafeArea()
            VStack(spacing: 22) {
                PetView(species: species, mood: model.mood).scaleEffect(1.8).frame(width: 300, height: 300)
                Text(model.done ? "Yay! Thank you 💖" : model.question)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.2, green: 0.22, blue: 0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                if !model.done {
                    Text("Your screen unlocks when you say yes")
                        .font(.system(size: 16, design: .rounded)).foregroundStyle(Color(red: 0.35, green: 0.37, blue: 0.5))
                    Button(action: onYes) {
                        Text(model.yesLabel).font(.system(size: 20, weight: .bold, design: .rounded))
                            .padding(.horizontal, 14).padding(.vertical, 4)
                    }
                    .buttonStyle(Pill(color: Color(red: 0.35, green: 0.65, blue: 1)))
                    .keyboardShortcut(.defaultAction)
                }
            }
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    if model.escProgress > 0 {
                        ProgressView(value: model.escProgress).frame(width: 120)
                    }
                    Text("Emergency: hold Esc for 5 seconds").font(.caption).foregroundStyle(Color(red: 0.4, green: 0.42, blue: 0.55))
                }
                .padding(.bottom, 24)
            }
        }
    }
}
