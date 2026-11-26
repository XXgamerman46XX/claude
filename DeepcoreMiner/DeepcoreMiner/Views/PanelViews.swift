import SwiftUI

// MARK: Upgrades

struct UpgradesView: View {
    @EnvironmentObject var game: GameModel
    @State private var buyMode = 1

    var body: some View {
        VStack(spacing: 8) {
            Picker("Buy amount", selection: $buyMode) {
                Text("x1").tag(1)
                Text("x10").tag(10)
                Text("Max").tag(Int.max)
            }
            .pickerStyle(.segmented)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(UpgradeKind.allCases) { kind in
                        UpgradeRow(kind: kind, buyMode: buyMode)
                    }
                }
            }
        }
    }
}

struct UpgradeRow: View {
    @EnvironmentObject var game: GameModel
    let kind: UpgradeKind
    let buyMode: Int

    var body: some View {
        let core = game.core
        let level = core.level(kind)
        let cost = core.cost(kind)
        let maxed = core.isMaxed(kind)
        let affordable = core.coins >= cost
        HStack(spacing: 10) {
            Image(systemName: kind.icon)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.orange.opacity(0.25)))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(kind.title)  Lv \(level)").font(.subheadline.bold())
                Text(kind.effectText(level: level)).font(.caption).foregroundStyle(.orange)
                Text(kind.blurb).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                game.buy(kind, count: buyMode)
            } label: {
                VStack(spacing: 0) {
                    Text(maxed ? "MAX" : Fmt.num(cost)).font(.subheadline.bold().monospacedDigit())
                    if !maxed && buyMode > 1 {
                        Text(buyMode == Int.max ? "max" : "x\(buyMode)").font(.caption2)
                    }
                }
                .frame(minWidth: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(affordable ? .green : .gray)
            .disabled(!affordable || maxed)
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: Shaft map

struct ShaftMapView: View {
    @EnvironmentObject var game: GameModel

    var body: some View {
        let core = game.core
        ScrollView {
            VStack(spacing: 6) {
                ForEach(Biomes.all) { b in
                    BiomeRow(biome: b, core: core)
                }
            }
        }
    }
}

struct BiomeRow: View {
    let biome: Biome
    let core: GameCore

    var body: some View {
        let b = biome
        let unlocked = core.bestDepthEver >= b.firstDepth
        let cleared = core.deepestBossDefeated >= b.bossDepth
        let isHere = core.biome.index == b.index
        let reached = min(max(core.bestDepthEver - b.firstDepth + 1, 0), Balance.layersPerBiome)
        let progress = Double(reached) / Double(Balance.layersPerBiome)
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Color(hex: b.top), Color(hex: b.bottom)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 28, height: 36)
                .overlay {
                    if !unlocked { Image(systemName: "lock.fill").font(.caption2) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(unlocked ? b.name : "???").font(.subheadline.bold())
                Text("Depth \(b.firstDepth)–\(b.bossDepth)").font(.caption2).foregroundStyle(.secondary)
                ProgressView(value: progress).tint(cleared ? .green : .orange)
            }
            Spacer(minLength: 0)
            if cleared {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            } else if unlocked {
                Image(systemName: "crown").foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.white.opacity(isHere ? 0.14 : 0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isHere ? Color.yellow : Color.clear, lineWidth: 2))
    }
}

// MARK: Stats & codex

struct StatsView: View {
    @EnvironmentObject var game: GameModel
    @State private var confirmReset = false

    var body: some View {
        let core = game.core
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 6) {
                    statRow("Best depth", "\(core.bestDepthEver) / \(Balance.finalDepth)")
                    statRow("Core Shards", "\(core.shards)  (x\(Fmt.num(Balance.shardMultiplier(core.shards))))")
                    statRow("Relics", "\(core.relics)  (x\(Fmt.num(Balance.relicMultiplierTotal(core.relics))))")
                    statRow("Total multiplier", "x\(Fmt.num(core.globalMultiplier))")
                    statRow("Prestiges", "\(core.prestigeCount)")
                    statRow("Taps", "\(core.totalTaps)")
                    statRow("Lifetime coins", Fmt.num(core.lifetimeCoins))
                    statRow("Play time", Fmt.duration(core.playSeconds))
                }
                .padding(10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))

                Toggle("Auto-challenge bosses", isOn: Binding(
                    get: { game.core.autoChallenge },
                    set: { game.core.autoChallenge = $0 }))
                    .font(.subheadline)

                Button {
                    game.showPrestige = true
                } label: {
                    Label(core.canPrestige ? "Prestige: +\(core.pendingShards) shards" : "Prestige unlocks at depth \(Balance.prestigeMinDepth)",
                          systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(!core.canPrestige)

                Text("Ore Codex · \(core.oreCounts.count)/\(Biomes.allOres.count)").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                    ForEach(Biomes.allOres) { ore in
                        let count = core.oreCounts[ore.id] ?? 0
                        VStack(spacing: 2) {
                            Image(systemName: "diamond.fill")
                                .foregroundStyle(count > 0 ? Color(hex: ore.color) : .gray.opacity(0.3))
                            Text(count > 0 ? ore.name : "???").font(.caption2.bold()).lineLimit(1)
                            Text(count > 0 ? Fmt.num(Double(count)) : ore.rarityName)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(6)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                Button("Reset all progress", role: .destructive) { confirmReset = true }
                    .font(.caption)
                    .padding(.top, 8)
            }
        }
        .confirmationDialog("Erase your save and start over?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) { game.resetEverything() }
        }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold().monospacedDigit()
        }
        .font(.subheadline)
    }
}

// MARK: Sheets

struct PrestigeView: View {
    @EnvironmentObject var game: GameModel

    var body: some View {
        let core = game.core
        let gain = core.pendingShards
        VStack(spacing: 18) {
            Image(systemName: "sparkles").font(.system(size: 54)).foregroundStyle(.purple)
            Text("Surface & Smelt").font(.largeTitle.bold())
            Text("Return to the surface and smelt your haul into Core Shards. Your coins, upgrades and depth reset. Shards, Relics and your Ore Codex stay forever.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("+\(gain) Core Shards").font(.title2.bold())
                Text("Shard bonus: x\(Fmt.num(Balance.shardMultiplier(core.shards))) → x\(Fmt.num(Balance.shardMultiplier(core.shards + gain)))")
                    .font(.subheadline)
                Text("Dig deeper before smelting for more shards. This run's deepest: \(core.maxDepthThisRun)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                game.prestige()
            } label: {
                Text("Smelt for \(gain) shards").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(gain == 0)
            Button("Not yet") { game.showPrestige = false }
        }
        .padding(24)
        .presentationDetents([.medium, .large])
    }
}

struct VictoryView: View {
    @EnvironmentObject var game: GameModel

    var body: some View {
        let core = game.core
        VStack(spacing: 18) {
            Image(systemName: "crown.fill").font(.system(size: 64)).foregroundStyle(.yellow)
            Text("You reached the Core!").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("The Heart of the World is shattered. It took \(Fmt.duration(core.playSeconds)) of active digging, \(core.prestigeCount) prestiges and \(core.totalTaps) taps.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("The shaft keeps going. Every boss below 300 still drops a Relic. How deep can you go?")
                .multilineTextAlignment(.center)
            Button("Keep digging") { game.showVictory = false }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}

struct OfflineView: View {
    @EnvironmentObject var game: GameModel
    let report: OfflineReport

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gearshape.2.fill").font(.system(size: 48)).foregroundStyle(.orange)
            Text("Your bots kept digging").font(.title.bold())
            Text("Away for \(Fmt.duration(report.awaySeconds))").foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("+\(Fmt.num(report.coins)) coins").font(.title2.bold())
                Text("\(report.blocks) blocks broken")
                if report.depthTo != report.depthFrom {
                    Text("Depth \(report.depthFrom) → \(report.depthTo)")
                }
            }
            Text("Bots work at 50% speed while you're away, for up to 12 hours.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Collect") { game.offlineReport = nil }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}
