import Foundation

/// One-time move of data from the app's pre-release identity (SipPal, com.salahu.sippal).
enum Migration {
    static func run() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "migratedFromSipPal") else { return }
        if let old = UserDefaults.standard.persistentDomain(forName: "com.salahu.sippal") {
            for (k, v) in old where d.object(forKey: k) == nil { d.set(v, forKey: k) }
        }
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldDir = support.appendingPathComponent("SipPal"), newDir = support.appendingPathComponent("Pawse")
        if fm.fileExists(atPath: oldDir.path), !fm.fileExists(atPath: newDir.path) {
            try? fm.moveItem(at: oldDir, to: newDir)
        }
        d.set(true, forKey: "migratedFromSipPal")
    }
}
