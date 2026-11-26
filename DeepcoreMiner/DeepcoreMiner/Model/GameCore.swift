import Foundation

/// Things that happened during a tap or tick, for the UI to react to.
enum GameEvent {
    case hit(amount: Double, crit: Bool)
    case blockBroken(coins: Double, ore: Ore)
    case enteredBiome(Biome)
    case bossStarted(Biome)
    case bossDefeated(Biome, relicEarned: Bool)
    case bossFailed(Biome)
    case coreReached
}

struct OfflineReport: Identifiable {
    let id = UUID()
    let awaySeconds: Double
    let coins: Double
    let blocks: Int
    let depthFrom: Int
    let depthTo: Int
}

/// The whole game state and rules. Pure value type: no UI, easy to save and to simulate offline.
struct GameCore: Codable {
    // Current run
    var coins: Double = 0
    var depth: Int = 1
    var blocksBroken: Int = 0
    var blockHPLeft: Double = Balance.blockHP(1)
    var blockRarity: Int = 0
    var bossTimeLeft: Double? = nil
    var levels: [String: Int] = [:]
    var maxDepthThisRun: Int = 1

    // Permanent progress
    var bestDepthEver: Int = 1
    var deepestBossDefeated: Int = 0
    var shards: Int = 0
    var prestigeCount: Int = 0
    var oreCounts: [String: Int] = [:]
    var totalTaps: Int = 0
    var lifetimeCoins: Double = 0
    var playSeconds: Double = 0
    var coreReached: Bool = false
    var achievements: Set<String> = []
    var bossFailStreak: Int = 0

    // Settings
    var autoChallenge: Bool = true
    var autoTapEnabled: Bool = false
    var autoTapRate: Double = 5      // taps per second
    var lastSaved: Date = Date()

    init() {}

    /// Lenient decoding so adding new fields later never wipes an old save.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameCore()
        coins = try c.decodeIfPresent(Double.self, forKey: .coins) ?? d.coins
        depth = try c.decodeIfPresent(Int.self, forKey: .depth) ?? d.depth
        blocksBroken = try c.decodeIfPresent(Int.self, forKey: .blocksBroken) ?? d.blocksBroken
        blockHPLeft = try c.decodeIfPresent(Double.self, forKey: .blockHPLeft) ?? Balance.blockHP(depth)
        blockRarity = try c.decodeIfPresent(Int.self, forKey: .blockRarity) ?? d.blockRarity
        bossTimeLeft = try c.decodeIfPresent(Double.self, forKey: .bossTimeLeft)
        levels = try c.decodeIfPresent([String: Int].self, forKey: .levels) ?? d.levels
        maxDepthThisRun = try c.decodeIfPresent(Int.self, forKey: .maxDepthThisRun) ?? depth
        bestDepthEver = try c.decodeIfPresent(Int.self, forKey: .bestDepthEver) ?? depth
        deepestBossDefeated = try c.decodeIfPresent(Int.self, forKey: .deepestBossDefeated) ?? d.deepestBossDefeated
        shards = try c.decodeIfPresent(Int.self, forKey: .shards) ?? d.shards
        prestigeCount = try c.decodeIfPresent(Int.self, forKey: .prestigeCount) ?? d.prestigeCount
        oreCounts = try c.decodeIfPresent([String: Int].self, forKey: .oreCounts) ?? d.oreCounts
        totalTaps = try c.decodeIfPresent(Int.self, forKey: .totalTaps) ?? d.totalTaps
        lifetimeCoins = try c.decodeIfPresent(Double.self, forKey: .lifetimeCoins) ?? d.lifetimeCoins
        playSeconds = try c.decodeIfPresent(Double.self, forKey: .playSeconds) ?? d.playSeconds
        coreReached = try c.decodeIfPresent(Bool.self, forKey: .coreReached) ?? d.coreReached
        achievements = try c.decodeIfPresent(Set<String>.self, forKey: .achievements) ?? d.achievements
        bossFailStreak = try c.decodeIfPresent(Int.self, forKey: .bossFailStreak) ?? d.bossFailStreak
        autoChallenge = try c.decodeIfPresent(Bool.self, forKey: .autoChallenge) ?? d.autoChallenge
        autoTapEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoTapEnabled) ?? d.autoTapEnabled
        autoTapRate = try c.decodeIfPresent(Double.self, forKey: .autoTapRate) ?? d.autoTapRate
        if !Balance.autoTapRates.contains(autoTapRate) { autoTapRate = d.autoTapRate }
        lastSaved = try c.decodeIfPresent(Date.self, forKey: .lastSaved) ?? d.lastSaved
        if blockRarity < 0 || blockRarity > 2 { blockRarity = 0 }
    }

    // MARK: Derived values

    func level(_ k: UpgradeKind) -> Int { levels[k.rawValue] ?? 0 }
    var relics: Int { deepestBossDefeated / Balance.layersPerBiome }
    var achievementMultiplier: Double { 1 + Balance.achievementBonusEach * Double(achievements.count) }
    var masteredOres: Int { oreCounts.values.filter { $0 >= Balance.masteryThreshold }.count }
    var masteryMultiplier: Double { 1 + Balance.masteryBonusEach * Double(masteredOres) }
    var globalMultiplier: Double {
        Balance.shardMultiplier(shards) * Balance.relicMultiplierTotal(relics) * achievementMultiplier
    }
    var bossTimeLimit: Double {
        Balance.bossTimeLimit + Balance.overclockSecondsPerLevel * Double(level(.overclock))
    }
    /// True when you keep losing to a boss and a prestige would help.
    var shouldSuggestPrestige: Bool { bossFailStreak >= 2 && canPrestige }

    /// Unlocks any achievements whose goal is now met. Returns the new ones.
    mutating func checkAchievements() -> [Achievement] {
        let fresh = Achievements.all.filter { !achievements.contains($0.id) && $0.isUnlocked(self) }
        for a in fresh { achievements.insert(a.id) }
        return fresh
    }
    var tapDamage: Double { Balance.drillPower(level: level(.drill)) * globalMultiplier }
    var botDPS: Double { Balance.botDPS(level: level(.bots)) * globalMultiplier }
    var critChance: Double { Balance.critChance(level: level(.sharpBits)) }
    var biome: Biome { Biomes.forDepth(depth) }
    var currentOre: Ore { biome.ores[blockRarity] }
    var isBossLayer: Bool { Balance.isBoss(depth) }
    var blockMaxHP: Double { Balance.blockHP(depth) }
    var blockHPFraction: Double { max(0, min(1, blockHPLeft / blockMaxHP)) }
    var pendingShards: Int { Balance.shards(forDepth: maxDepthThisRun) }
    var canPrestige: Bool { pendingShards > 0 }
    var bossIsNext: Bool { !isBossLayer && Balance.isBoss(depth + 1) }
    var layerInBiome: Int { (depth - 1) % Balance.layersPerBiome + 1 }

    var blockValue: Double {
        Balance.oreValue(depth: depth, rarity: blockRarity)
            * Balance.refineryMultiplier(level: level(.refinery))
            * masteryMultiplier
            * globalMultiplier
            * (isBossLayer ? Balance.bossRewardMultiplier : 1)
    }

    func cost(_ k: UpgradeKind) -> Double { k.cost(atLevel: level(k)) }

    func isMaxed(_ k: UpgradeKind) -> Bool {
        guard let m = k.maxLevel else { return false }
        return level(k) >= m
    }

    // MARK: Actions

    /// A tap from your finger (`manual`) or from the auto clicker.
    mutating func tap(manual: Bool = true) -> [GameEvent] {
        if manual { totalTaps += 1 }
        let crit = Double.random(in: 0..<1) < critChance
        let dmg = tapDamage * (crit ? Balance.critMultiplier : 1)
        return [.hit(amount: dmg, crit: crit)] + applyDamage(dmg)
    }

    mutating func tick(dt: Double) -> [GameEvent] {
        playSeconds += dt
        if let t = bossTimeLeft {
            let remaining = t - dt
            if remaining <= 0 { return failBoss() }
            bossTimeLeft = remaining
        }
        let dmg = botDPS * dt
        return dmg > 0 ? applyDamage(dmg) : []
    }

    /// Buys up to `count` levels. Returns how many were bought.
    @discardableResult
    mutating func buy(_ k: UpgradeKind, count: Int) -> Int {
        var bought = 0
        while bought < count && !isMaxed(k) {
            let c = cost(k)
            guard coins >= c else { break }
            coins -= c
            levels[k.rawValue] = level(k) + 1
            bought += 1
        }
        return bought
    }

    /// Manually start the boss fight when auto-challenge is off.
    mutating func challengeBoss() -> [GameEvent] {
        guard bossIsNext else { return [] }
        return advanceLayer()
    }

    /// "Surface & Smelt": reset the run, keep shards, relics, codex and stats.
    mutating func prestige() {
        let gain = pendingShards
        guard gain > 0 else { return }
        shards += gain
        bossFailStreak = 0
        prestigeCount += 1
        coins = 0
        levels = [:]
        depth = 1
        blocksBroken = 0
        maxDepthThisRun = 1
        bossTimeLeft = nil
        spawnBlock()
    }

    /// Runs the bots while the app was closed.
    mutating func simulateOffline(seconds: Double) -> OfflineReport? {
        let simSeconds = min(seconds, Balance.offlineCapSeconds) * Balance.offlineEfficiency
        guard simSeconds >= 1, botDPS > 0 else { return nil }
        let startCoins = coins
        let startDepth = depth
        let startPlay = playSeconds
        var blocks = 0
        var t = 0.0
        while t < simSeconds {
            let step = min(1.0, simSeconds - t)
            for e in tick(dt: step) {
                if case .blockBroken = e { blocks += 1 }
            }
            t += step
        }
        playSeconds = startPlay
        return OfflineReport(awaySeconds: seconds, coins: coins - startCoins, blocks: blocks,
                             depthFrom: startDepth, depthTo: depth)
    }

    // MARK: Internals

    private mutating func applyDamage(_ amount: Double) -> [GameEvent] {
        var events: [GameEvent] = []
        var left = amount
        var safety = 0
        while left > 0 && safety < 200 {
            safety += 1
            if left >= blockHPLeft {
                left -= blockHPLeft
                events += breakBlock()
            } else {
                blockHPLeft -= left
                left = 0
            }
        }
        return events
    }

    private mutating func breakBlock() -> [GameEvent] {
        var events: [GameEvent] = []
        let ore = currentOre
        let value = blockValue
        coins += value
        lifetimeCoins += value
        oreCounts[ore.id, default: 0] += 1
        events.append(.blockBroken(coins: value, ore: ore))

        if isBossLayer {
            let b = biome
            let firstTime = depth > deepestBossDefeated
            if firstTime { deepestBossDefeated = depth }
            bossTimeLeft = nil
            bossFailStreak = 0
            events.append(.bossDefeated(b, relicEarned: firstTime))
            if depth == Balance.finalDepth && !coreReached {
                coreReached = true
                events.append(.coreReached)
            }
            events += advanceLayer()
        } else {
            blocksBroken += 1
            if blocksBroken >= Balance.blocksPerLayer {
                if bossIsNext && !autoChallenge {
                    blocksBroken = 0   // keep farming this layer
                    spawnBlock()
                } else {
                    events += advanceLayer()
                }
            } else {
                spawnBlock()
            }
        }
        return events
    }

    private mutating func advanceLayer() -> [GameEvent] {
        var events: [GameEvent] = []
        let oldBiome = biome.index
        depth += 1
        blocksBroken = 0
        maxDepthThisRun = max(maxDepthThisRun, depth)
        bestDepthEver = max(bestDepthEver, depth)
        if biome.index != oldBiome { events.append(.enteredBiome(biome)) }
        spawnBlock()
        if isBossLayer {
            bossTimeLeft = bossTimeLimit
            events.append(.bossStarted(biome))
        }
        return events
    }

    private mutating func spawnBlock() {
        blockHPLeft = blockMaxHP
        if isBossLayer {
            blockRarity = 2
        } else {
            let r = Double.random(in: 0..<1)
            if r < Balance.rareChance { blockRarity = 2 }
            else if r < Balance.rareChance + Balance.uncommonChance { blockRarity = 1 }
            else { blockRarity = 0 }
        }
    }

    private mutating func failBoss() -> [GameEvent] {
        let b = biome
        bossTimeLeft = nil
        bossFailStreak += 1
        depth -= 1
        blocksBroken = 0
        spawnBlock()
        return [.bossFailed(b)]
    }
}
