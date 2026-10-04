import SwiftUI
import SceneKit

enum Mood: Equatable { case walking, asking, happy, sad }

/// 3D animated pet (SceneKit) with SwiftUI emoji effects layered on top.
struct PetView: View {
    let species: Species
    let mood: Mood
    var facingLeft = true

    var body: some View {
        Pet3D(species: species, mood: mood, facingLeft: facingLeft)
            .frame(width: 170, height: 170)
            .overlay(alignment: .top) {
                TimelineView(.animation) { tl in effects(t: tl.date.timeIntervalSinceReferenceDate) }
            }
    }

    @ViewBuilder private func effects(t: Double) -> some View {
        switch mood {
        case .happy:
            ZStack {
                ForEach(0..<5, id: \.self) { i in
                    let p = (t * 0.8 + Double(i) * 0.2).truncatingRemainder(dividingBy: 1)
                    Text(i % 2 == 0 ? "💖" : "💧").font(.system(size: 16))
                        .offset(x: CGFloat(i - 2) * 26 + CGFloat(sin(t * 3 + Double(i))) * 6, y: CGFloat(20 - p * 60))
                        .opacity(1 - p)
                }
            }
        case .sad:
            Text("💭").font(.system(size: 18)).offset(x: 46, y: 6 + CGFloat(sin(t * 2)) * 3)
        case .asking:
            Text("💧").font(.system(size: 18))
                .offset(x: -58, y: 14 + CGFloat(sin(t * 3)) * 5)
                .rotationEffect(.degrees(sin(t * 3) * 10))
        case .walking:
            EmptyView()
        }
    }
}

// MARK: - SceneKit bridge

struct Pet3D: NSViewRepresentable {
    let species: Species
    let mood: Mood
    let facingLeft: Bool

    func makeCoordinator() -> PetRig { PetRig() }

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.isPlaying = true
        v.rendersContinuously = true
        v.allowsCameraControl = false
        v.delegate = context.coordinator
        context.coordinator.build(species)
        v.scene = context.coordinator.scene
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {
        let rig = context.coordinator
        if rig.species != species {
            rig.build(species)
            v.scene = rig.scene
        }
        rig.mood = mood
        rig.facingLeft = facingLeft
    }
}

// MARK: - Rig

/// Builds a pet from primitives and animates it procedurally every frame.
final class PetRig: NSObject, SCNSceneRendererDelegate {
    private(set) var scene = SCNScene()
    private(set) var species: Species?
    var mood: Mood = .asking
    var facingLeft = true

    private let root = SCNNode()       // yaw
    private let bodyPivot = SCNNode()  // bob + squash
    private var head = SCNNode()
    private var eyes: [SCNNode] = []
    private var legs: [SCNNode] = []
    private var tail: SCNNode?
    private var flippers: [SCNNode] = []
    private var mouthOpen = SCNNode()
    private var mouthClosed = SCNNode()
    private var tear = SCNNode()
    private var topper: SCNNode?       // yuzu / tuft
    private var shadow = SCNNode()
    private var ears: [SCNNode] = []
    private var wisp: SCNNode?
    private var arms: [SCNNode] = []   // kid: [right (bottle), left]
    private var yaw: Float = -0.4

    // MARK: materials
    private func mat(_ c: NSColor, shine: CGFloat = 0.12) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = c
        m.specular.contents = NSColor(white: 1, alpha: shine)
        m.shininess = 0.15
        return m
    }
    private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(red: r, green: g, blue: b, alpha: 1) }

    private func sphere(_ r: CGFloat, _ c: NSColor, at p: SCNVector3, scale s: SCNVector3 = SCNVector3(1, 1, 1), shine: CGFloat = 0.12) -> SCNNode {
        let g = SCNSphere(radius: r); g.segmentCount = 48; g.firstMaterial = mat(c, shine: shine)
        let n = SCNNode(geometry: g); n.position = p; n.scale = s; return n
    }
    private func capsule(_ r: CGFloat, _ h: CGFloat, _ c: NSColor, at p: SCNVector3) -> SCNNode {
        let g = SCNCapsule(capRadius: r, height: h); g.firstMaterial = mat(c)
        let n = SCNNode(geometry: g); n.position = p; return n
    }
    private func cone(_ r: CGFloat, _ h: CGFloat, _ c: NSColor, at p: SCNVector3) -> SCNNode {
        let g = SCNCone(topRadius: 0.02, bottomRadius: r, height: h); g.firstMaterial = mat(c)
        let n = SCNNode(geometry: g); n.position = p; return n
    }
    private func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, chamfer: CGFloat, _ c: NSColor, at p: SCNVector3) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer); g.chamferSegmentCount = 12
        g.firstMaterial = mat(c)
        let n = SCNNode(geometry: g); n.position = p; return n
    }
    /// Glossy black eye with a sparkle.
    private func eye(at p: SCNVector3, size: CGFloat = 0.085) -> SCNNode {
        let e = sphere(size, rgb(0.08, 0.08, 0.1), at: p, scale: SCNVector3(1, 1.25, 0.6), shine: 1)
        e.addChildNode(sphere(size * 0.38, .white, at: SCNVector3(-size * 0.3, size * 0.4, size * 0.75)))
        e.addChildNode(sphere(size * 0.17, .white, at: SCNVector3(size * 0.35, -size * 0.3, size * 0.8)))
        return e
    }
    private func face(eyeY: Float, eyeX: Float, eyeZ: Float, mouthY: Float, mouthZ: Float, cheekX: Float, cheekZ: Float, into h: SCNNode) {
        eyes = [eye(at: SCNVector3(-eyeX, eyeY, eyeZ)), eye(at: SCNVector3(eyeX, eyeY, eyeZ))]
        eyes.forEach(h.addChildNode)
        for s: Float in [-1, 1] {
            let ch = sphere(0.085, rgb(1, 0.55, 0.62), at: SCNVector3(s * cheekX, eyeY - 0.13, cheekZ), scale: SCNVector3(1, 0.6, 0.35))
            ch.opacity = 0.75
            h.addChildNode(ch)
        }
        mouthClosed = SCNNode()
        for s: Float in [-1, 1] {
            let t = SCNTorus(ringRadius: 0.035, pipeRadius: 0.009); t.firstMaterial = mat(rgb(0.2, 0.12, 0.12))
            let n = SCNNode(geometry: t)
            n.position = SCNVector3(s * 0.035, 0, 0)
            n.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            n.scale = SCNVector3(1, 1, 0.8)
            mouthClosed.addChildNode(n)
        }
        mouthClosed.position = SCNVector3(0, mouthY, mouthZ)
        h.addChildNode(mouthClosed)
        mouthOpen = sphere(0.07, rgb(0.9, 0.32, 0.38), at: SCNVector3(0, mouthY - 0.02, mouthZ), scale: SCNVector3(1, 0.8, 0.4))
        mouthOpen.isHidden = true
        h.addChildNode(mouthOpen)
        tear = sphere(0.035, rgb(0.45, 0.8, 1), at: SCNVector3(eyeX, eyeY - 0.1, eyeZ + 0.03), scale: SCNVector3(1, 1.4, 1), shine: 1)
        tear.opacity = 0.9
        tear.isHidden = true
        h.addChildNode(tear)
    }

    // MARK: build
    func build(_ s: Species) {
        species = s
        scene = SCNScene()
        root.childNodes.forEach { $0.removeFromParentNode() }
        bodyPivot.childNodes.forEach { $0.removeFromParentNode() }
        bodyPivot.position = SCNVector3Zero
        legs = []; flippers = []; tail = nil; topper = nil; head = SCNNode(); ears = []; wisp = nil; arms = []
        root.addChildNode(bodyPivot)
        scene.rootNode.addChildNode(root)

        shadow = sphere(0.7, .black, at: SCNVector3(0, 0.005, 0), scale: SCNVector3(1, 0.01, 0.8))
        shadow.geometry?.firstMaterial?.lightingModel = .constant
        shadow.opacity = 0.18
        scene.rootNode.addChildNode(shadow)

        switch s {
        case .cat: buildCat()
        case .penguin: buildPenguin()
        case .capybara: buildCapybara()
        case .bunny: buildBunny()
        case .kid: buildKid()
        default: buildModel(s)
        }
        bodyPivot.addChildNode(head)
        addLightsAndCamera(lookY: s == .penguin ? 0.85 : (s == .kid ? 1.0 : 0.8))
    }

    private func buildCat() {
        let fur = rgb(0.99, 0.80, 0.55), dark = rgb(0.92, 0.60, 0.32), cream = rgb(1, 0.96, 0.9)
        bodyPivot.addChildNode(sphere(0.52, fur, at: SCNVector3(0, 0.52, -0.05), scale: SCNVector3(1, 0.9, 1.05)))
        bodyPivot.addChildNode(sphere(0.34, cream, at: SCNVector3(0, 0.5, 0.3), scale: SCNVector3(1, 1.05, 0.6)))
        for (x, z) in [(-0.24, 0.25), (0.24, 0.25), (-0.26, -0.3), (0.26, -0.3)] as [(Float, Float)] {
            let pivot = SCNNode(); pivot.position = SCNVector3(x, 0.32, z)
            pivot.addChildNode(capsule(0.12, 0.38, z > 0 ? cream : fur, at: SCNVector3(0, -0.18, 0)))
            bodyPivot.addChildNode(pivot); legs.append(pivot)
        }
        let t = SCNNode(); t.position = SCNVector3(0, 0.55, -0.5)
        let seg = capsule(0.085, 0.75, dark, at: SCNVector3(0, 0.32, 0))
        t.addChildNode(seg)
        t.addChildNode(sphere(0.1, cream, at: SCNVector3(0, 0.68, 0)))
        bodyPivot.addChildNode(t); tail = t

        head.position = SCNVector3(0, 1.18, 0.05)
        head.addChildNode(sphere(0.55, fur, at: SCNVector3Zero, scale: SCNVector3(1.12, 0.92, 0.95)))
        head.addChildNode(sphere(0.25, cream, at: SCNVector3(0, -0.16, 0.36), scale: SCNVector3(1.3, 0.8, 0.6)))
        for sgn: Float in [-1, 1] {
            let ear = cone(0.2, 0.36, fur, at: SCNVector3(sgn * 0.36, 0.44, -0.02))
            ear.eulerAngles = SCNVector3(0, 0, -sgn * 0.38)
            ear.addChildNode(cone(0.11, 0.24, rgb(1, 0.65, 0.7), at: SCNVector3(0, -0.04, 0.09)))
            head.addChildNode(ear)
            for (i, a) in [0.12, -0.08].enumerated() {
                let w = SCNCylinder(radius: 0.007, height: 0.32); w.firstMaterial = mat(rgb(0.35, 0.25, 0.2))
                let n = SCNNode(geometry: w)
                n.position = SCNVector3(sgn * 0.58, -0.12 - Float(i) * 0.06, 0.3)
                n.eulerAngles = SCNVector3(0, 0, Float.pi / 2 + sgn * Float(a))
                head.addChildNode(n)
            }
        }
        for i in -1...1 {
            let st = capsule(0.035, 0.26, dark, at: SCNVector3(Float(i) * 0.13, 0.36, 0.3))
            st.eulerAngles = SCNVector3(0.9, 0, 0)
            head.addChildNode(st)
        }
        head.addChildNode(sphere(0.045, rgb(1, 0.5, 0.6), at: SCNVector3(0, -0.1, 0.52), scale: SCNVector3(1.3, 0.9, 0.8), shine: 0.8))
        face(eyeY: 0.04, eyeX: 0.22, eyeZ: 0.45, mouthY: -0.19, mouthZ: 0.5, cheekX: 0.36, cheekZ: 0.4, into: head)
    }

    private func buildPenguin() {
        let navy = rgb(0.18, 0.23, 0.36), white = rgb(0.98, 0.98, 1), orange = rgb(1, 0.62, 0.2)
        bodyPivot.addChildNode(sphere(0.6, navy, at: SCNVector3(0, 0.8, 0), scale: SCNVector3(1, 1.3, 0.95)))
        bodyPivot.addChildNode(sphere(0.5, white, at: SCNVector3(0, 0.66, 0.24), scale: SCNVector3(0.98, 1.12, 0.7)))
        for sgn: Float in [-1, 1] {
            let foot = SCNNode(); foot.position = SCNVector3(sgn * 0.22, 0.06, 0.15)
            foot.addChildNode(sphere(0.15, orange, at: SCNVector3(0, 0, 0.06), scale: SCNVector3(1, 0.35, 1.4)))
            bodyPivot.addChildNode(foot); legs.append(foot)
            let fl = SCNNode(); fl.position = SCNVector3(sgn * 0.56, 1.0, 0)
            fl.addChildNode(sphere(0.32, navy, at: SCNVector3(sgn * 0.04, -0.3, 0), scale: SCNVector3(0.3, 1, 0.55)))
            bodyPivot.addChildNode(fl); flippers.append(fl)
        }
        head.position = SCNVector3(0, 1.3, 0)
        head.addChildNode(sphere(0.2, white, at: SCNVector3(-0.15, 0.02, 0.38), scale: SCNVector3(1, 1.05, 0.55)))
        head.addChildNode(sphere(0.2, white, at: SCNVector3(0.15, 0.02, 0.38), scale: SCNVector3(1, 1.05, 0.55)))
        let beak = cone(0.09, 0.18, orange, at: SCNVector3(0, -0.12, 0.56))
        beak.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        beak.scale = SCNVector3(1.3, 1, 0.75)
        head.addChildNode(beak)
        let tuft = SCNNode(); tuft.position = SCNVector3(0, 0.45, 0)
        tuft.addChildNode(capsule(0.03, 0.2, navy, at: SCNVector3(0, 0.09, 0)))
        head.addChildNode(tuft); topper = tuft
        face(eyeY: 0.05, eyeX: 0.15, eyeZ: 0.48, mouthY: -0.3, mouthZ: 0.5, cheekX: 0.3, cheekZ: 0.42, into: head)
        mouthClosed.isHidden = true; mouthClosed = SCNNode()
    }

    private func buildCapybara() {
        let fur = rgb(0.74, 0.54, 0.36), dark = rgb(0.52, 0.36, 0.23), snout = rgb(0.6, 0.43, 0.29)
        bodyPivot.addChildNode(sphere(0.58, fur, at: SCNVector3(0, 0.6, -0.15), scale: SCNVector3(1, 0.88, 1.4)))
        for (x, z) in [(-0.3, 0.35), (0.3, 0.35), (-0.3, -0.6), (0.3, -0.6)] as [(Float, Float)] {
            let pivot = SCNNode(); pivot.position = SCNVector3(x, 0.3, z)
            pivot.addChildNode(capsule(0.12, 0.34, dark, at: SCNVector3(0, -0.15, 0)))
            bodyPivot.addChildNode(pivot); legs.append(pivot)
        }
        head.position = SCNVector3(0, 0.98, 0.55)
        head.addChildNode(box(0.66, 0.6, 0.72, chamfer: 0.28, fur, at: SCNVector3(0, 0, 0.12)))
        head.addChildNode(box(0.56, 0.42, 0.3, chamfer: 0.18, snout, at: SCNVector3(0, -0.08, 0.38)))
        for sgn: Float in [-1, 1] {
            head.addChildNode(sphere(0.03, rgb(0.15, 0.1, 0.08), at: SCNVector3(sgn * 0.09, 0.02, 0.535), scale: SCNVector3(0.8, 1.4, 0.5)))
            head.addChildNode(sphere(0.08, dark, at: SCNVector3(sgn * 0.24, 0.3, -0.12), scale: SCNVector3(1, 1, 0.5)))
        }
        let yuzu = SCNNode(); yuzu.position = SCNVector3(0.05, 0.42, 0.02)
        yuzu.addChildNode(sphere(0.15, rgb(1, 0.72, 0.1), at: SCNVector3Zero, shine: 0.6))
        let leaf = sphere(0.07, rgb(0.3, 0.75, 0.3), at: SCNVector3(0.06, 0.15, 0), scale: SCNVector3(1.4, 0.3, 0.7))
        leaf.eulerAngles = SCNVector3(0, 0, 0.5)
        yuzu.addChildNode(leaf)
        head.addChildNode(yuzu); topper = yuzu
        face(eyeY: 0.2, eyeX: 0.2, eyeZ: 0.47, mouthY: -0.22, mouthZ: 0.53, cheekX: 0.29, cheekZ: 0.45, into: head)
        eyes.forEach { $0.scale = SCNVector3(0.85, 0.85, 0.6) }
    }

    private func buildKid() {
        let skin = rgb(1, 0.86, 0.76), hair = rgb(0.32, 0.2, 0.15), hoodie = rgb(0.55, 0.78, 1)
        let pants = rgb(0.98, 0.95, 0.88), shoe = rgb(1, 0.55, 0.6), white = rgb(1, 1, 1)
        // legs + shoes
        for sgn: Float in [-1, 1] {
            let leg = SCNNode(); leg.position = SCNVector3(sgn * 0.14, 0.42, 0)
            leg.addChildNode(capsule(0.1, 0.36, pants, at: SCNVector3(0, -0.2, 0)))
            leg.addChildNode(sphere(0.12, shoe, at: SCNVector3(0, -0.38, 0.05), scale: SCNVector3(1, 0.6, 1.35), shine: 0.4))
            bodyPivot.addChildNode(leg); legs.append(leg)
        }
        // hoodie body
        bodyPivot.addChildNode(sphere(0.33, hoodie, at: SCNVector3(0, 0.66, 0), scale: SCNVector3(1, 1.05, 0.85)))
        bodyPivot.addChildNode(sphere(0.12, hoodie.blended(withFraction: 0.15, of: .black) ?? hoodie,
                                      at: SCNVector3(0, 0.56, 0.26), scale: SCNVector3(1.6, 0.7, 0.4)))      // pocket
        bodyPivot.addChildNode(sphere(0.2, hoodie, at: SCNVector3(0, 0.95, -0.12), scale: SCNVector3(1.4, 0.6, 1)))  // hood
        for sgn: Float in [-1, 1] {   // drawstrings
            bodyPivot.addChildNode(capsule(0.015, 0.14, white, at: SCNVector3(sgn * 0.07, 0.84, 0.28)))
        }
        // arms: pivot at shoulder, sleeve + hand. Right hand holds the bottle.
        for sgn: Float in [1, -1] {
            let arm = SCNNode(); arm.position = SCNVector3(sgn * 0.3, 0.86, 0)
            arm.addChildNode(capsule(0.085, 0.34, hoodie, at: SCNVector3(sgn * 0.02, -0.16, 0)))
            arm.addChildNode(sphere(0.08, skin, at: SCNVector3(sgn * 0.02, -0.35, 0.02)))
            if sgn > 0 {
                let bottle = SCNNode(); bottle.position = SCNVector3(0.02, -0.36, 0.1)
                let glass = SCNCylinder(radius: 0.07, height: 0.3); glass.firstMaterial = mat(rgb(0.7, 0.9, 1), shine: 0.9)
                glass.firstMaterial?.transparency = 0.75
                bottle.addChildNode(SCNNode(geometry: glass))
                let water = SCNCylinder(radius: 0.06, height: 0.2); water.firstMaterial = mat(rgb(0.3, 0.65, 1), shine: 0.8)
                let wn = SCNNode(geometry: water); wn.position = SCNVector3(0, -0.04, 0); bottle.addChildNode(wn)
                let cap = SCNCylinder(radius: 0.05, height: 0.06); cap.firstMaterial = mat(shoe)
                let cn = SCNNode(geometry: cap); cn.position = SCNVector3(0, 0.18, 0); bottle.addChildNode(cn)
                arm.addChildNode(bottle)
            }
            bodyPivot.addChildNode(arm); arms.append(arm)
        }
        // big chibi head
        head.position = SCNVector3(0, 1.32, 0)
        head.addChildNode(sphere(0.5, skin, at: SCNVector3Zero, scale: SCNVector3(1.05, 0.95, 0.95)))
        for sgn: Float in [-1, 1] { head.addChildNode(sphere(0.08, skin, at: SCNVector3(sgn * 0.52, -0.04, 0), scale: SCNVector3(0.6, 1, 0.8))) }
        // hair cap, bangs, side locks, two buns
        head.addChildNode(sphere(0.54, hair, at: SCNVector3(0, 0.08, -0.06), scale: SCNVector3(1.04, 0.92, 0.95)))
        // smooth bowl fringe with a little center part
        let fringe = sphere(0.5, hair, at: SCNVector3(0, 0.24, 0.1), scale: SCNVector3(1.03, 0.42, 0.88))
        fringe.eulerAngles = SCNVector3(0.25, 0, 0)
        head.addChildNode(fringe)
        for sgn: Float in [-1, 1] {
            let tuft = sphere(0.16, hair, at: SCNVector3(sgn * 0.13, 0.16, 0.4), scale: SCNVector3(1.1, 0.55, 0.45))
            tuft.eulerAngles = SCNVector3(0.3, 0, sgn * -0.35)
            head.addChildNode(tuft)
        }
        for sgn: Float in [-1, 1] {
            head.addChildNode(sphere(0.14, hair, at: SCNVector3(sgn * 0.47, -0.12, 0.08), scale: SCNVector3(0.6, 1.5, 0.8)))
            let bun = SCNNode(); bun.position = SCNVector3(sgn * 0.34, 0.46, -0.05)
            bun.addChildNode(sphere(0.17, hair, at: SCNVector3Zero))
            bun.addChildNode(SCNNode(geometry: { let t = SCNTorus(ringRadius: 0.1, pipeRadius: 0.035); t.firstMaterial = mat(shoe); return t }()))
            bun.childNodes.last?.position = SCNVector3(0, -0.1, 0)
            head.addChildNode(bun); ears.append(bun)   // buns bounce like ears
        }
        face(eyeY: -0.02, eyeX: 0.19, eyeZ: 0.44, mouthY: -0.2, mouthZ: 0.46, cheekX: 0.3, cheekZ: 0.4, into: head)
        eyes.forEach { $0.scale = SCNVector3(1.15, 1.3, 0.6) }
    }

    private func buildBunny() {
        // translucent glowing ghost material
        func ghostMat(_ c: NSColor) -> SCNMaterial {
            let m = mat(c, shine: 0.4)
            m.emission.contents = NSColor(red: 0.75, green: 0.7, blue: 1, alpha: 1).withAlphaComponent(0.35)
            m.transparency = 0.86
            m.transparencyMode = .dualLayer
            return m
        }
        let body = rgb(0.92, 0.9, 1), pink = rgb(1, 0.72, 0.82)
        func g(_ n: SCNNode) -> SCNNode { n.geometry?.firstMaterial = ghostMat(body); return n }

        // teardrop body: round top + tapering wispy tail
        bodyPivot.addChildNode(g(sphere(0.55, body, at: SCNVector3(0, 0.85, 0), scale: SCNVector3(1, 1.05, 0.95))))
        let tailRoot = SCNNode(); tailRoot.position = SCNVector3(0, 0.55, -0.05)
        var parent = tailRoot
        for i in 0..<4 {   // chain of shrinking blobs that curl as it sways
            let r = CGFloat(0.42 - Double(i) * 0.09)
            let seg = SCNNode(); seg.position = SCNVector3(0, i == 0 ? 0 : -0.16, i == 0 ? 0 : -0.05)
            seg.addChildNode(g(sphere(r, body, at: SCNVector3Zero, scale: SCNVector3(1, 0.8, 0.9))))
            parent.addChildNode(seg); parent = seg
        }
        bodyPivot.addChildNode(tailRoot); wisp = tailRoot
        // stubby arms
        for sgn: Float in [-1, 1] {
            let arm = SCNNode(); arm.position = SCNVector3(sgn * 0.5, 0.75, 0.15)
            arm.addChildNode(g(sphere(0.13, body, at: SCNVector3(sgn * 0.06, -0.06, 0), scale: SCNVector3(1, 0.8, 0.9))))
            bodyPivot.addChildNode(arm); flippers.append(arm)
        }
        head.position = SCNVector3(0, 1.0, 0)
        // long floppy ears with pink inner
        for sgn: Float in [-1, 1] {
            let ear = SCNNode(); ear.position = SCNVector3(sgn * 0.22, 0.42, -0.05)
            let outer = capsule(0.13, 0.64, body, at: SCNVector3(0, 0.28, 0))
            outer.geometry?.firstMaterial = { let m = ghostMat(body); m.transparency = 0.97; return m }()
            outer.scale = SCNVector3(1, 1, 0.5)
            ear.addChildNode(outer)
            ear.addChildNode(capsule(0.06, 0.42, pink, at: SCNVector3(0, 0.27, 0.055)))
            head.addChildNode(ear); ears.append(ear)
        }
        // tiny nose + whisker dots
        head.addChildNode(sphere(0.04, pink, at: SCNVector3(0, -0.04, 0.53), scale: SCNVector3(1.3, 0.9, 0.8), shine: 0.8))
        face(eyeY: 0.06, eyeX: 0.2, eyeZ: 0.47, mouthY: -0.12, mouthZ: 0.52, cheekX: 0.33, cheekZ: 0.42, into: head)
        // inner glow light
        let glow = SCNLight(); glow.type = .omni; glow.intensity = 250; glow.color = rgb(0.8, 0.75, 1)
        glow.attenuationEndDistance = 2.5
        let gn = SCNNode(); gn.light = glow; gn.position = SCNVector3(0, 0.9, 0.8)
        bodyPivot.addChildNode(gn)
        shadow.opacity = 0.1
    }

    /// Loads a USDZ model, normalizes size/position. Animated as a whole body.
    private func buildModel(_ s: Species) {
        guard let url = s.modelURL, let src = try? SCNScene(url: url) else { return buildCat() }
        let holder = SCNNode()
        src.rootNode.childNodes.forEach { holder.addChildNode($0) }
        holder.enumerateHierarchy { n, _ in if n.light != nil || n.camera != nil { n.removeFromParentNode() } }
        let (mn, mx) = holder.boundingBox
        let h = max(0.001, Float(mx.y - mn.y))
        let scale = 1.7 / h
        holder.scale = SCNVector3(scale, scale, scale)
        holder.position = SCNVector3(-CGFloat(Float(mn.x + mx.x) / 2 * scale), -CGFloat(Float(mn.y) * scale), -CGFloat(Float(mn.z + mx.z) / 2 * scale))
        let wrap = SCNNode(); wrap.addChildNode(holder)
        bodyPivot.addChildNode(wrap)
        head = SCNNode()
    }

    private func addLightsAndCamera(lookY: Float) {
        let cam = SCNCamera(); cam.fieldOfView = 30; cam.wantsHDR = false
        let camNode = SCNNode(); camNode.camera = cam
        camNode.position = SCNVector3(0, 1.75, 5.2)
        camNode.look(at: SCNVector3(0, lookY, 0))
        scene.rootNode.addChildNode(camNode)

        let key = SCNLight(); key.type = .directional; key.intensity = 850; key.color = rgb(1, 0.96, 0.9)
        let kn = SCNNode(); kn.light = key; kn.eulerAngles = SCNVector3(-0.7, -0.5, 0)
        let fill = SCNLight(); fill.type = .ambient; fill.intensity = 480; fill.color = rgb(0.85, 0.9, 1)
        let fn = SCNNode(); fn.light = fill
        let rim = SCNLight(); rim.type = .directional; rim.intensity = 450; rim.color = rgb(0.8, 0.9, 1)
        let rn = SCNNode(); rn.light = rim; rn.eulerAngles = SCNVector3(-0.3, .pi * 0.85, 0)
        [kn, fn, rn].forEach(scene.rootNode.addChildNode)
    }

    // MARK: per-frame animation
    func renderer(_ r: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let t = Float(time)
        let m = mood
        let s: (Float) -> Float = { sinf($0) }, a: (Float) -> Float = { abs($0) }

        // body bounce
        let bob: Float
        switch m {
        case .walking: bob = a(s(t * 9)) * 0.08
        case .happy: bob = a(s(t * 7)) * (species == .kid ? 0.2 : 0.35)
        case .sad: bob = -0.04
        case .asking: bob = s(t * 2.5) * 0.025
        }
        let ghost = species == .bunny
        let floatY: Float = ghost ? 0.22 + s(t * 2) * 0.07 + (m == .happy ? a(s(t * 6)) * 0.2 : 0) + (m == .sad ? -0.1 : 0) : 0
        bodyPivot.position.y = CGFloat(ghost ? floatY : bob)
        let sq: Float = m == .happy ? 1 + (a(s(t * 7)) - 0.5) * 0.08 : 1 + s(t * 2.5) * 0.02
        bodyPivot.scale = SCNVector3(CGFloat(2 - sq), CGFloat(sq), CGFloat(2 - sq))
        let lift = ghost ? floatY : bob
        shadow.scale = SCNVector3(CGFloat(1 - lift * 0.8), 0.01, CGFloat(0.8 - lift * 0.6))

        // facing
        let target: Float
        switch m {
        case .walking: target = facingLeft ? -.pi / 2 : .pi / 2
        default: target = species == .capybara ? -0.75 : -0.3
        }
        yaw += (target - yaw) * 0.08
        root.eulerAngles.y = CGFloat(yaw)

        // head
        let tilt: Float
        switch m {
        case .asking: tilt = s(t * 1.3) * 0.12 + 0.08
        case .happy: tilt = s(t * 7) * 0.1
        case .sad: tilt = -0.1
        case .walking: tilt = s(t * 9) * 0.05
        }
        head.eulerAngles.z = CGFloat(tilt)
        head.eulerAngles.x = CGFloat(m == .sad ? 0.28 : (m == .happy ? -0.15 : 0))

        // eyes: blink / happy squint / sad droop
        let blink = fmodf(t, 3.4) < 0.13
        let eyeY: Float = m == .happy ? 0.3 : (m == .sad ? 0.6 : (blink ? 0.08 : 1))
        let base: Float = species == .capybara ? 0.85 : (species == .kid ? 1.15 : 1)
        for e in eyes { e.scale = SCNVector3(CGFloat(base), CGFloat(base * 1.0 * eyeY), 0.6) }
        mouthOpen.isHidden = m != .happy
        mouthClosed.isHidden = m == .happy

        // tear
        tear.isHidden = m != .sad
        if m == .sad {
            let p = fmodf(t * 0.9, 1)
            tear.position.y = CGFloat(-0.05 - p * 0.35)
            tear.opacity = CGFloat(1 - p)
        }

        // legs
        for (i, l) in legs.enumerated() {
            let phase: Float = i % 2 == 0 ? 0 : .pi
            let swing: Float = m == .walking ? s(t * 16 + phase + Float(i / 2) * .pi) * 0.55 : 0
            l.eulerAngles.x = CGFloat(swing)
            if species == .penguin { l.position.y = CGFloat(0.06 + max(0, s(t * 16 + phase)) * (m == .walking ? 0.08 : 0)) }
        }
        if species == .penguin && m == .walking { root.eulerAngles.z = CGFloat(s(t * 8) * 0.12) }
        else { root.eulerAngles.z = 0 }

        // tail / flippers / topper
        tail?.eulerAngles = SCNVector3(CGFloat(-0.5 + s(t * 2) * 0.1), 0, CGFloat(s(t * (m == .happy ? 12 : 3)) * 0.5))
        let flap: Float = m == .happy ? s(t * 18) * 0.7 : (m == .walking ? s(t * 9) * 0.25 : (m == .sad ? -0.05 : s(t * 2) * 0.08))
        for (i, f) in flippers.enumerated() {
            let sgn: Float = i == 0 ? -1 : 1
            f.eulerAngles.z = CGFloat(sgn * (0.25 + flap + (m == .asking ? 0.15 : 0)))
        }
        // ghost bunny: ears flop, tail wisp sways, body leans while drifting
        // model pets have no separate parts: express mood with the whole body
        if species?.isModel == true {
            let lean: Float
            switch m {
            case .asking: lean = s(t * 1.3) * 0.08
            case .happy: lean = s(t * 7) * 0.12
            case .sad: lean = 0
            case .walking: lean = s(t * 9) * 0.07
            }
            bodyPivot.eulerAngles.z = CGFloat(lean)
            bodyPivot.eulerAngles.x = CGFloat(m == .sad ? 0.18 : 0)
            if m == .happy { bodyPivot.eulerAngles.y = CGFloat(s(t * 3) * 0.3) } else { bodyPivot.eulerAngles.y = 0 }
        }
        if species == .kid && arms.count == 2 {
            let right = arms[0], left = arms[1]
            switch m {
            case .walking:
                right.eulerAngles = SCNVector3(CGFloat(s(t * 16 + .pi) * 0.6), 0, 0.12)
                left.eulerAngles = SCNVector3(CGFloat(s(t * 16) * 0.6), 0, -0.12)
            case .asking:   // offer the bottle, wave with the other hand
                right.eulerAngles = SCNVector3(CGFloat(-1.1 + s(t * 2) * 0.08), 0, 0.15)
                left.eulerAngles = SCNVector3(-0.3, 0, CGFloat(-2.3 + s(t * 7) * 0.35))
            case .happy:    // big sip from the bottle
                let sip = (s(t * 2) + 1) / 2
                right.eulerAngles = SCNVector3(CGFloat(-2.0 - sip * 0.5), 0, CGFloat(-0.35 - sip * 0.1))
                left.eulerAngles = SCNVector3(0, 0, CGFloat(-0.4 - a(s(t * 7)) * 0.6))
                head.eulerAngles.x = CGFloat(-0.25 - sip * 0.15)
            case .sad:
                right.eulerAngles = SCNVector3(0.1, 0, 0.05)
                left.eulerAngles = SCNVector3(0.1, 0, -0.05)
            }
            for (i, b) in ears.enumerated() {   // bouncy hair buns
                let k: Float = m == .happy ? 0.12 : 0.04
                b.position.y = CGFloat(0.46 + s(t * (m == .happy ? 14 : 3) + Float(i)) * k * 0.4)
            }
        }
        if ghost {
            for (i, e) in ears.enumerated() {
                let sgn: Float = i == 0 ? -1 : 1
                let flop: Float
                switch m {
                case .happy: flop = s(t * 14 + Float(i)) * 0.35
                case .sad: flop = 0.9                       // droop forward
                case .walking: flop = 0.35 + s(t * 5 + Float(i)) * 0.15   // streaming back
                case .asking: flop = s(t * 2.2 + Float(i) * 1.3) * 0.12
                }
                e.eulerAngles.z = CGFloat(-sgn * (0.18 + (m == .sad ? 0.5 : 0)) + (i == 1 && m == .asking ? -0.25 : 0))
                e.eulerAngles.x = CGFloat(m == .walking ? -flop : flop)
            }
            var seg = wisp
            var k: Float = 0
            while let n = seg {
                n.eulerAngles.z = CGFloat(s(t * 2.6 - k) * 0.22)
                n.eulerAngles.x = CGFloat(m == .walking ? -0.3 : 0.1)
                seg = n.childNodes.first(where: { $0.geometry == nil }); k += 0.8
            }
            if m == .walking { root.eulerAngles.z = CGFloat(s(t * 3) * 0.08); bodyPivot.eulerAngles.x = 0.25 }
            else { bodyPivot.eulerAngles.x = 0 }
        }
        topper?.eulerAngles.z = CGFloat(s(t * (m == .happy ? 9 : 2.5)) * (m == .happy ? 0.35 : 0.12))
    }
}
