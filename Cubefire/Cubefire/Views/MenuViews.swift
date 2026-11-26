import SwiftUI

struct MenuRoot: View {
    @EnvironmentObject var store: ProfileStore
    @State private var playing: ArenaMap? = nil
    @State private var tab: Tab = .play

    enum Tab: String, CaseIterable, Identifiable {
        case play = "Play", armory = "Armory", profile = "Profile"
        var id: String { rawValue }
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.07, green: 0.08, blue: 0.16), Color(red: 0.16, green: 0.07, blue: 0.2)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                PixelConfetti().ignoresSafeArea().opacity(0.35)

                VStack(spacing: 10) {
                    header
                    Picker("Menu", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)
                    Group {
                        switch tab {
                        case .play: ArenaSelect(wide: wide) { playing = $0 }
                        case .armory: ArmoryView(wide: wide)
                        case .profile: ProfileView()
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $playing) { map in
            MatchView(map: map, store: store) { playing = nil }
        }
    }

    private var header: some View {
        let p = store.profile
        return HStack(spacing: 12) {
            Text("CUBEFIRE")
                .font(.system(size: 30, weight: .black, design: .monospaced))
                .foregroundStyle(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing))
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    Text("LV \(p.level)").font(.headline.weight(.heavy))
                    ProgressView(value: p.levelProgress).tint(.cyan).frame(width: 90)
                }
                Label("\(p.coins)", systemImage: "circle.hexagongrid.fill")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.yellow)
            }
        }
    }
}

struct ArenaSelect: View {
    @EnvironmentObject var store: ProfileStore
    let wide: Bool
    let onPlay: (ArenaMap) -> Void

    var body: some View {
        ScrollView {
            let columns = [GridItem(.adaptive(minimum: wide ? 240 : 300), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Arenas.all) { map in
                    ArenaCard(map: map, level: store.profile.level,
                              best: store.profile.bestWave[map.id] ?? 0) { onPlay(map) }
                }
            }
            Text("Survive endless waves. Every 5th wave brings the Cube King. Spend coins in the Armory between matches.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Text("Tip: plays best in landscape or with the phone unfolded.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct ArenaCard: View {
    let map: ArenaMap
    let level: Int
    let best: Int
    let onPlay: () -> Void

    var body: some View {
        let locked = level < map.unlockLevel
        VStack(alignment: .leading, spacing: 8) {
            ArenaPreview(map: map)
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    if locked {
                        ZStack {
                            Color.black.opacity(0.6)
                            Label("Unlocks at LV \(map.unlockLevel)", systemImage: "lock.fill").font(.headline)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            Text(map.name).font(.headline)
            Text(map.blurb).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Label("Best wave: \(best)", systemImage: "flag.checkered").font(.caption)
                Spacer()
                Button("Play", action: onPlay)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(locked)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
    }
}

/// Top-down pixel preview of an arena.
struct ArenaPreview: View {
    let map: ArenaMap

    var body: some View {
        Canvas { ctx, size in
            let cell = min(size.width / CGFloat(map.width), size.height / CGFloat(map.depth))
            let ox = (size.width - cell * CGFloat(map.width)) / 2
            let oy = (size.height - cell * CGFloat(map.depth)) / 2
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(uiColor: Voxel.color(map.sky))))
            for z in 0..<map.depth {
                for x in 0..<map.width {
                    let c = map.tile(x, z)
                    let hex: UInt32
                    switch c {
                    case "#": hex = map.wall
                    case "B": hex = map.pillar
                    case "c": hex = map.crate
                    case "h": hex = 0x4CFF6A
                    case "a": hex = 0xFFD54F
                    case "P": hex = 0x00E5FF
                    case "e": hex = 0xFF3B30
                    default: hex = map.floor
                    }
                    let r = CGRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(z) * cell, width: cell, height: cell)
                    ctx.fill(Path(r), with: .color(Color(uiColor: Voxel.color(hex))))
                }
            }
        }
    }
}

struct ArmoryView: View {
    @EnvironmentObject var store: ProfileStore
    let wide: Bool

    var body: some View {
        ScrollView {
            Text("Equip up to 3 weapons. Upgrades add +15% damage per level.")
                .font(.caption)
                .foregroundStyle(.secondary)
            let columns = [GridItem(.adaptive(minimum: wide ? 300 : 320), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(WeaponID.allCases) { w in
                    WeaponRow(weapon: w)
                }
            }
        }
    }
}

struct WeaponRow: View {
    @EnvironmentObject var store: ProfileStore
    let weapon: WeaponID

    var body: some View {
        let p = store.profile
        let s = weapon.stats
        let owned = p.owns(weapon)
        let lvl = p.weaponLevel(weapon)
        let equipped = p.loadout.contains(weapon.rawValue)
        let locked = p.level < s.unlockLevel
        HStack(spacing: 12) {
            Image(systemName: s.icon)
                .font(.title2)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: Voxel.color(s.color)).opacity(0.35)))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(s.name).font(.headline)
                    if owned { Text("LV \(lvl)").font(.caption.weight(.heavy)).foregroundStyle(.orange) }
                }
                Text(s.blurb).font(.caption).foregroundStyle(.secondary)
                Text(statLine(s, level: owned ? lvl : 1)).font(.caption2.monospacedDigit()).foregroundStyle(.cyan)
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                if !owned {
                    Button {
                        store.buy(weapon)
                    } label: {
                        Label(locked ? "LV \(s.unlockLevel)" : "\(s.price)",
                              systemImage: locked ? "lock.fill" : "circle.hexagongrid.fill")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .disabled(locked || p.coins < s.price)
                } else {
                    Button {
                        store.toggleEquip(weapon)
                    } label: {
                        Text(equipped ? "Equipped" : "Equip").font(.caption.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .tint(equipped ? .green : .gray)
                    if lvl < WeaponID.maxLevel {
                        let cost = weapon.upgradeCost(from: lvl)
                        Button {
                            store.upgrade(weapon)
                        } label: {
                            Label("\(cost)", systemImage: "arrow.up.circle.fill").font(.caption.weight(.bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(p.coins < cost)
                    } else {
                        Text("MAX").font(.caption.weight(.heavy)).foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(equipped ? 0.12 : 0.06)))
    }

    private func statLine(_ s: WeaponStats, level: Int) -> String {
        let dmg = s.damage * WeaponID.damageMultiplier(level: level)
        let perShot = s.pellets > 1 ? "\(Int(dmg))x\(s.pellets)" : "\(Int(dmg))"
        let rps = 1 / s.fireInterval
        return "DMG \(perShot) · \(String(format: "%.1f", rps))/s · MAG \(s.magazine)"
    }
}

struct ProfileView: View {
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        let p = store.profile
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                row("Level", "\(p.level)")
                row("Total kills", "\(p.totalKills)")
                row("Headshots", "\(p.headshots)")
                row("Matches", "\(p.matchesPlayed)")
                ForEach(Arenas.all) { m in
                    row("Best wave · \(m.name)", "\(p.bestWave[m.id] ?? 0)")
                }
                Divider().padding(.vertical, 4)
                Text("Look sensitivity: \(String(format: "%.1f", p.lookSensitivity))x").font(.subheadline)
                Slider(value: Binding(get: { store.profile.lookSensitivity },
                                      set: { store.setSensitivity($0) }),
                       in: 0.4...2.5, step: 0.1)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
            .frame(maxWidth: 520)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold().monospacedDigit()
        }
    }
}

/// Floating pixel squares in the menu background.
struct PixelConfetti: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                var rng = SeededRNG(seed: 42)
                let colors: [Color] = [.orange, .pink, .cyan, .yellow, .green, .purple]
                for i in 0..<40 {
                    let x = rng.unit() * size.width
                    let speed = 10 + rng.unit() * 30
                    let s = 4 + rng.unit() * 8
                    let y = (rng.unit() * size.height + CGFloat(t) * speed)
                        .truncatingRemainder(dividingBy: size.height + 20) - 10
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(colors[i % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
