import Foundation

/// Long-term goals. Each unlocked achievement permanently adds
/// `Balance.achievementBonusEach` to damage and ore value.
struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let isUnlocked: (GameCore) -> Bool
}

enum Achievements {
    static let all: [Achievement] = depth + relics + prestige + codex + mastery + taps + wealth

    private static let depth: [Achievement] = [10, 25, 50, 75, 100, 150, 200, 250, 300].map { d in
        Achievement(id: "depth-\(d)", title: "Depth \(d)", detail: "Reach depth \(d).",
                    icon: "arrow.down.to.line", isUnlocked: { $0.bestDepthEver >= d })
    }

    private static let relics: [Achievement] = [(1, "Boss Breaker"), (4, "Relic Hunter"),
                                                (8, "Relic Hoarder"), (12, "Heartbreaker")].map { n, name in
        Achievement(id: "relics-\(n)", title: name, detail: "Own \(n) Relic\(n == 1 ? "" : "s").",
                    icon: "crown.fill", isUnlocked: { $0.relics >= n })
    }

    private static let prestige: [Achievement] = [(1, "Back to the Surface"), (3, "Smelter"),
                                                  (10, "Furnace Master"), (25, "Eternal Miner")].map { n, name in
        Achievement(id: "prestige-\(n)", title: name, detail: "Prestige \(n) time\(n == 1 ? "" : "s").",
                    icon: "sparkles", isUnlocked: { $0.prestigeCount >= n })
    }

    private static let codex: [Achievement] = [10, 20, 30, 36].map { n in
        Achievement(id: "codex-\(n)", title: n == 36 ? "Complete Codex" : "Collector \(n)",
                    detail: "Discover \(n) different ores.",
                    icon: "book.fill", isUnlocked: { $0.oreCounts.count >= n })
    }

    private static let mastery: [Achievement] = [1, 10, 36].map { n in
        Achievement(id: "mastery-\(n)", title: n == 36 ? "Grandmaster" : "Ore Master \(n)",
                    detail: "Master \(n) ore\(n == 1 ? "" : "s") (\(Fmt.num(Double(Balance.masteryThreshold))) of each).",
                    icon: "star.circle.fill", isUnlocked: { $0.masteredOres >= n })
    }

    private static let taps: [Achievement] = [1_000, 10_000, 100_000].map { n in
        Achievement(id: "taps-\(n)", title: "\(Fmt.num(Double(n))) Taps",
                    detail: "Tap \(Fmt.num(Double(n))) times yourself (auto clicker doesn't count).",
                    icon: "hand.tap.fill", isUnlocked: { $0.totalTaps >= n })
    }

    private static let wealth: [Achievement] = [1e6, 1e12, 1e18, 1e24, 1e30].map { v in
        Achievement(id: "coins-\(Int(log10(v)))", title: "\(Fmt.num(v)) Coins",
                    detail: "Earn \(Fmt.num(v)) coins in total.",
                    icon: "circle.hexagongrid.fill", isUnlocked: { $0.lifetimeCoins >= v })
    }
}
