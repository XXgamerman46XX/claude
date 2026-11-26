import SwiftUI

struct HeaderBar: View {
    @EnvironmentObject var game: GameModel

    var body: some View {
        let core = game.core
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.yellow)
                    Text(Fmt.num(core.coins))
                        .font(.title2.bold())
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Text("Depth \(core.depth) · \(core.biome.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Label(Fmt.num(core.tapDamage), systemImage: "hand.tap.fill")
                Label("\(Fmt.num(core.botDPS))/s", systemImage: "gearshape.2.fill")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            if core.canPrestige {
                Button {
                    game.showPrestige = true
                } label: {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .padding(8)
                        .background(Circle().fill(Color.purple.opacity(0.35)))
                }
                .accessibilityLabel("Prestige")
            }
        }
    }
}

struct MineView: View {
    @EnvironmentObject var game: GameModel

    var body: some View {
        let core = game.core
        let biome = core.biome
        GeometryReader { geo in
            let blockSize = min(min(geo.size.width, geo.size.height) * (core.isBossLayer ? 0.6 : 0.48), 300)
            ZStack {
                LinearGradient(colors: [Color(hex: biome.top), Color(hex: biome.bottom)],
                               startPoint: .top, endPoint: .bottom)
                PebbleBackground(seed: biome.index, tint: Color(hex: biome.rock))

                VStack(spacing: 10) {
                    if core.isBossLayer {
                        BossBar(name: biome.boss, timeLeft: core.bossTimeLeft ?? 0)
                    } else {
                        LayerProgress(layer: core.layerInBiome, blocks: core.blocksBroken,
                                      bossNext: core.bossIsNext)
                    }
                    Spacer(minLength: 0)
                    BlockView(ore: core.currentOre, rock: Color(hex: biome.rock),
                              hpFraction: core.blockHPFraction, isBoss: core.isBossLayer,
                              pulse: game.tapPulse)
                        .frame(width: blockSize, height: blockSize)
                    Text(core.isBossLayer ? biome.boss : "\(core.currentOre.name) · \(core.currentOre.rarityName)")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color(hex: core.currentOre.color))
                        .shadow(radius: 2)
                    HPBar(fraction: core.blockHPFraction, left: core.blockHPLeft,
                          color: core.isBossLayer ? .red : .green)
                    Spacer(minLength: 0)
                    if core.bossIsNext && !core.autoChallenge {
                        Button("Challenge \(biome.boss)") { game.challengeBoss() }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                }
                .padding(12)

                ForEach(game.floaters) { FloaterView(floater: $0) }
                    .allowsHitTesting(false)

                VStack {
                    if let t = game.toast {
                        ToastView(toast: t)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                }
                .padding(.top, 44)
                .animation(.spring(duration: 0.35), value: game.toast)
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .contentShape(Rectangle())
        .onTapGesture { game.tap() }
    }
}

struct BlockView: View {
    let ore: Ore
    let rock: Color
    let hpFraction: Double
    let isBoss: Bool
    let pulse: Int
    @State private var squash = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: isBoss ? 40 : 18)
        ZStack {
            shape.fill(LinearGradient(colors: [rock.opacity(1), rock.opacity(0.55)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            OreVeins(color: Color(hex: ore.color), count: 3 + ore.rarity * 3)
            Cracks(damage: 1 - hpFraction)
            if isBoss {
                HStack(spacing: 30) {
                    Circle().fill(.red).frame(width: 22, height: 22)
                    Circle().fill(.red).frame(width: 22, height: 22)
                }
                .shadow(color: .red, radius: 10)
                .offset(y: -18)
            }
        }
        .clipShape(shape)
        .overlay(shape.stroke(isBoss ? Color.red : Color.black.opacity(0.4), lineWidth: isBoss ? 4 : 2))
        .shadow(color: isBoss ? .red.opacity(0.6) : .black.opacity(0.5), radius: isBoss ? 18 : 8, y: 4)
        .scaleEffect(squash ? 0.92 : 1)
        .onChange(of: pulse) { _, _ in
            withAnimation(.spring(response: 0.08, dampingFraction: 0.5)) { squash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.45)) { squash = false }
            }
        }
    }
}

/// Gem flecks inside the block.
struct OreVeins: View {
    let color: Color
    let count: Int
    private static let spots: [(CGFloat, CGFloat, CGFloat)] = [
        (0.25, 0.30, 0.10), (0.70, 0.22, 0.08), (0.55, 0.62, 0.12), (0.20, 0.75, 0.07),
        (0.80, 0.70, 0.09), (0.45, 0.40, 0.06), (0.35, 0.55, 0.08), (0.65, 0.85, 0.06),
        (0.85, 0.45, 0.07),
    ]

    var body: some View {
        Canvas { ctx, size in
            for spot in Self.spots.prefix(count) {
                let r = spot.2 * size.width
                let rect = CGRect(x: spot.0 * size.width - r / 2, y: spot.1 * size.height - r / 2,
                                  width: r, height: r)
                var diamond = Path()
                diamond.move(to: CGPoint(x: rect.midX, y: rect.minY))
                diamond.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                diamond.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                diamond.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                diamond.closeSubpath()
                ctx.fill(diamond, with: .color(color))
                ctx.stroke(diamond, with: .color(.white.opacity(0.5)), lineWidth: 1)
            }
        }
    }
}

/// Cracks spread from the center as the block takes damage.
struct Cracks: View {
    let damage: Double
    private static let angles: [CGFloat] = [0.3, 1.4, 2.2, 3.5, 4.4, 5.3, 0.9, 2.9, 4.0, 5.8]

    var body: some View {
        Canvas { ctx, size in
            let n = Int((damage * Double(Self.angles.count)).rounded(.down))
            guard n > 0 else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            for (i, a) in Self.angles.prefix(n).enumerated() {
                let len: CGFloat = size.width * (0.25 + 0.04 * CGFloat(i % 4))
                let bend: CGFloat = a + 0.25
                var p = Path()
                p.move(to: c)
                let mid = CGPoint(x: c.x + cos(bend) * len * 0.5, y: c.y + sin(bend) * len * 0.5)
                p.addLine(to: mid)
                p.addLine(to: CGPoint(x: c.x + cos(a) * len, y: c.y + sin(a) * len))
                ctx.stroke(p, with: .color(.black.opacity(0.65)), lineWidth: 3)
            }
        }
    }
}

struct PebbleBackground: View {
    let seed: Int
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            var x = UInt64(seed &+ 7) &* 2654435761
            func rnd() -> CGFloat {
                x = x &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(x >> 33) / CGFloat(UInt32.max >> 1)
            }
            for _ in 0..<40 {
                let r = 4 + rnd() * 14
                let rect = CGRect(x: rnd() * size.width, y: rnd() * size.height, width: r, height: r * 0.7)
                ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.35)))
            }
        }
        .allowsHitTesting(false)
    }
}

struct HPBar: View {
    let fraction: Double
    let left: Double
    let color: Color

    var body: some View {
        ZStack {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.5))
                    Capsule().fill(color.gradient).frame(width: g.size.width * fraction)
                }
            }
            Text(Fmt.num(left)).font(.caption2.bold().monospacedDigit()).shadow(radius: 1)
        }
        .frame(height: 16)
        .frame(maxWidth: 260)
    }
}

struct LayerProgress: View {
    let layer: Int
    let blocks: Int
    let bossNext: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text("Layer \(layer)/\(Balance.layersPerBiome)" + (bossNext ? " · Boss next!" : ""))
                .font(.caption.bold())
            HStack(spacing: 4) {
                ForEach(0..<Balance.blocksPerLayer, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < blocks ? Color.yellow : Color.white.opacity(0.25))
                        .frame(width: 14, height: 6)
                }
            }
        }
        .padding(8)
        .background(.black.opacity(0.35), in: Capsule())
    }
}

struct BossBar: View {
    let name: String
    let timeLeft: Double

    var body: some View {
        VStack(spacing: 4) {
            Text("BOSS · \(name)").font(.caption.bold()).foregroundStyle(.red)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.5))
                    Capsule().fill(Color.orange.gradient)
                        .frame(width: g.size.width * max(0, timeLeft / Balance.bossTimeLimit))
                }
            }
            .frame(width: 180, height: 6)
            Text(String(format: "%.1fs", timeLeft)).font(.caption2.monospacedDigit())
        }
        .padding(8)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FloaterView: View {
    let floater: Floater
    @State private var go = false

    var body: some View {
        Text(floater.text)
            .font(floater.big ? .title2.weight(.heavy) : .headline.weight(.bold))
            .foregroundStyle(floater.color)
            .shadow(color: .black, radius: 2)
            .offset(x: floater.xOffset, y: go ? -130 : -30)
            .opacity(go ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.85)) { go = true }
            }
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        Label(toast.text, systemImage: toast.icon)
            .font(.subheadline.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, 12)
    }
}
