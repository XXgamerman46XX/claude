import Foundation

enum UpgradeKind: String, CaseIterable, Identifiable {
    case drill, bots, refinery, sharpBits, overclock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drill: "Drill Power"
        case .bots: "Mining Bots"
        case .refinery: "Ore Refinery"
        case .sharpBits: "Sharp Bits"
        case .overclock: "Boss Overclock"
        }
    }

    var icon: String {
        switch self {
        case .drill: "hammer.fill"
        case .bots: "gearshape.2.fill"
        case .refinery: "flame.fill"
        case .sharpBits: "bolt.fill"
        case .overclock: "timer"
        }
    }

    var blurb: String {
        switch self {
        case .drill: "Damage per tap. Doubles every 25 levels."
        case .bots: "Dig for you, even while you're away."
        case .refinery: "Every ore sells for more."
        case .sharpBits: "Chance for a 3x critical tap."
        case .overclock: "More time to break each boss."
        }
    }

    var baseCost: Double {
        switch self {
        case .drill: 15
        case .bots: 50
        case .refinery: 200
        case .sharpBits: 500
        case .overclock: 10_000
        }
    }

    var costGrowth: Double {
        switch self {
        case .drill: 1.10
        case .bots: 1.11
        case .refinery: 1.22
        case .sharpBits: 1.9
        case .overclock: 6
        }
    }

    var maxLevel: Int? {
        switch self {
        case .sharpBits: 20
        case .overclock: 15
        default: nil
        }
    }

    func cost(atLevel n: Int) -> Double { baseCost * pow(costGrowth, Double(n)) }

    func effectText(level n: Int) -> String {
        switch self {
        case .drill: "\(Fmt.num(Balance.drillPower(level: n))) base dmg / tap"
        case .bots: "\(Fmt.num(Balance.botDPS(level: n))) base dmg / sec"
        case .refinery: "x\(Fmt.num(Balance.refineryMultiplier(level: n))) ore value"
        case .sharpBits: "\(Int((Balance.critChance(level: n) * 100).rounded()))% crit chance"
        case .overclock: "\(Int(Balance.bossTimeLimit + Balance.overclockSecondsPerLevel * Double(n)))s boss timer"
        }
    }
}
