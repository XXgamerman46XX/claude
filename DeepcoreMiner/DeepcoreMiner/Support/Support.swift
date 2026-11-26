import UIKit

final class Haptics {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()

    func tap() { light.impactOccurred(intensity: 0.5) }
    func breakBlock(rare: Bool) { heavy.impactOccurred(intensity: rare ? 1.0 : 0.6) }
    func success() { notify.notificationOccurred(.success) }
    func warning() { notify.notificationOccurred(.warning) }
    func error() { notify.notificationOccurred(.error) }
}

enum Fmt {
    private static let suffixes = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]

    /// 1234 -> "1.23K", 5.6e15 -> "5.60Qa", beyond Dc uses aa, ab, ac...
    static func num(_ v: Double) -> String {
        if !v.isFinite { return "∞" }
        if v < 0 { return "-" + num(-v) }
        if v < 10 && v != v.rounded() { return String(format: "%.1f", v) }
        if v < 1000 { return String(format: "%.0f", v.rounded(.down)) }
        let tier = Int(floor(log10(v) / 3))
        let scaled = v / pow(1000, Double(tier))
        let suffix: String
        if tier < suffixes.count {
            suffix = suffixes[tier]
        } else {
            let n = tier - suffixes.count
            let a = Character(UnicodeScalar(UInt8(97 + (n / 26) % 26)))
            let b = Character(UnicodeScalar(UInt8(97 + n % 26)))
            suffix = String([a, b])
        }
        let digits = scaled < 10 ? "%.2f" : (scaled < 100 ? "%.1f" : "%.0f")
        return String(format: digits, scaled) + suffix
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}
