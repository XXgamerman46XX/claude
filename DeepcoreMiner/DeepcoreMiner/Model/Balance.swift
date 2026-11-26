import Foundation

/// Every number that controls game pacing lives here.
/// These values were tuned with `tools/balance_sim.py` so that a player who
/// taps ~40 minutes a day and idles the rest reaches the Core in roughly 2–3 months.
/// If you change something here, mirror it in the sim and re-run it.
enum Balance {
    // MARK: World layout
    static let layersPerBiome = 25
    static let finalDepth = 300          // 12 biomes x 25 layers
    static let blocksPerLayer = 8

    // MARK: Block health
    static let hpBase = 10.0
    static let hpGrowthBase = 1.165      // per-layer HP growth in biome 1
    static let hpGrowthPerBiome = 0.003  // growth gets steeper every biome
    static let bossHPMultiplier = 30.0
    static let bossTimeLimit = 30.0      // seconds
    static let bossRewardMultiplier = 25.0

    // MARK: Ore value
    static let valueBase = 3.0
    static let valueGrowth = 1.135
    static let uncommonChance = 0.20
    static let rareChance = 0.04
    static let rarityValue: [Double] = [1, 4, 20]

    // MARK: Crits
    static let baseCritChance = 0.05
    static let critChancePerLevel = 0.01
    static let critMultiplier = 3.0

    // MARK: Prestige (Core Shards) and Relics
    static let prestigeMinDepth = 50
    static let shardExponent = 1.5
    static let shardBonusEach = 0.05     // +5% damage & value per shard
    static let relicMultiplier = 1.45    // x1.45 damage & value per first-time boss kill (permanent)

    // MARK: Auto clicker (only runs while the app is open)
    static let autoTapRates: [Double] = [1, 2, 5, 10, 20]   // taps per second

    // MARK: Offline
    static let offlineCapSeconds: Double = 16 * 3600
    static let offlineEfficiency = 0.75

    // MARK: Formulas
    private static let tableSize = 1500
    private static let hpTable: [Double] = {
        var t = [Double](repeating: 0, count: tableSize + 1)
        t[0] = hpBase
        t[1] = hpBase
        for d in 2...tableSize {
            t[d] = t[d - 1] * growth(atDepth: d)
        }
        return t
    }()

    static func growth(atDepth d: Int) -> Double {
        hpGrowthBase + hpGrowthPerBiome * Double((d - 1) / layersPerBiome)
    }

    static func isBoss(_ depth: Int) -> Bool { depth % layersPerBiome == 0 }

    static func baseHP(_ depth: Int) -> Double {
        let d = max(1, depth)
        if d <= tableSize { return hpTable[d] }
        return hpTable[tableSize] * pow(growth(atDepth: tableSize), Double(d - tableSize))
    }

    static func blockHP(_ depth: Int) -> Double {
        baseHP(depth) * (isBoss(depth) ? bossHPMultiplier : 1)
    }

    static func oreValue(depth: Int, rarity: Int) -> Double {
        valueBase * pow(valueGrowth, Double(max(depth, 1) - 1)) * rarityValue[rarity]
    }

    static func drillPower(level n: Int) -> Double { Double(1 + n) * pow(2, Double(n / 25)) }
    static func botDPS(level n: Int) -> Double { Double(n) * 0.8 * pow(2, Double(n / 25)) }
    static func refineryMultiplier(level n: Int) -> Double { pow(1.12, Double(n)) }
    static func critChance(level n: Int) -> Double { baseCritChance + critChancePerLevel * Double(n) }

    static func shards(forDepth d: Int) -> Int {
        d < prestigeMinDepth ? 0 : Int(pow(Double(d) / 10, shardExponent))
    }
    static func shardMultiplier(_ shards: Int) -> Double { 1 + shardBonusEach * Double(shards) }
    static func relicMultiplierTotal(_ relics: Int) -> Double { pow(relicMultiplier, Double(relics)) }
}
