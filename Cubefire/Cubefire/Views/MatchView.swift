import SceneKit
import SwiftUI

struct SceneKitView: UIViewRepresentable {
    let match: MatchController

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero)
        v.scene = match.scene
        v.pointOfView = match.cameraNode
        v.antialiasingMode = .multisampling2X
        v.preferredFramesPerSecond = 60
        v.isPlaying = true
        v.rendersContinuously = true
        v.backgroundColor = .black
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

struct MatchView: View {
    @StateObject private var match: MatchController
    let onExit: () -> Void

    init(map: ArenaMap, store: ProfileStore, onExit: @escaping () -> Void) {
        _match = StateObject(wrappedValue: MatchController(map: map, store: store))
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            SceneKitView(match: match).ignoresSafeArea()
            if match.result == nil {
                ControlsOverlay(match: match)
                HUDOverlay(hud: match.hud, onPause: { match.paused = true })
                    .allowsHitTesting(true)
            }
            if match.paused && match.result == nil {
                PauseMenu(resume: { match.paused = false }, quit: { match.quit() })
            }
            if let r = match.result {
                ResultsView(result: r, arena: match.map, onDone: onExit)
            }
        }
        .environmentObject(match)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { match.start() }
        .onDisappear { match.stop() }
    }
}

// MARK: Touch controls

struct ControlsOverlay: View {
    let match: MatchController
    @State private var stickOrigin: CGPoint? = nil
    @State private var stickOffset: CGSize = .zero
    @State private var lastLook: CGSize = .zero
    @State private var lastFireDrag: CGSize = .zero
    @State private var fireDown = false

    private let stickRadius: CGFloat = 60

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let buttonSize = min(max(min(w, h) * 0.2, 70), 110)
            ZStack {
                // Left half: movement joystick (appears where you touch).
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: w * 0.5, height: h)
                    .position(x: w * 0.25, y: h / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                if stickOrigin == nil { stickOrigin = v.startLocation }
                                var dx = v.translation.width, dy = v.translation.height
                                let len = sqrt(dx * dx + dy * dy)
                                if len > stickRadius { dx *= stickRadius / len; dy *= stickRadius / len }
                                stickOffset = CGSize(width: dx, height: dy)
                                match.moveInput = SIMD2<Float>(Float(dx / stickRadius), Float(-dy / stickRadius))
                            }
                            .onEnded { _ in
                                stickOrigin = nil
                                stickOffset = .zero
                                match.moveInput = .zero
                            }
                    )

                // Right half: drag to look around.
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: w * 0.5, height: h)
                    .position(x: w * 0.75, y: h / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let d = CGSize(width: v.translation.width - lastLook.width,
                                               height: v.translation.height - lastLook.height)
                                lastLook = v.translation
                                match.addLook(dx: Float(d.width), dy: Float(d.height))
                            }
                            .onEnded { _ in lastLook = .zero }
                    )

                // Joystick graphic
                if let o = stickOrigin {
                    Circle().stroke(Color.white.opacity(0.5), lineWidth: 3)
                        .frame(width: stickRadius * 2, height: stickRadius * 2)
                        .position(o)
                    Circle().fill(Color.white.opacity(0.55))
                        .frame(width: 50, height: 50)
                        .position(x: o.x + stickOffset.width, y: o.y + stickOffset.height)
                } else {
                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 2)
                        .frame(width: stickRadius * 2, height: stickRadius * 2)
                        .position(x: 30 + stickRadius + geo.safeAreaInsets.leading, y: h - stickRadius - 40)
                        .allowsHitTesting(false)
                }

                // Fire: hold to shoot, drag while holding to aim.
                Circle()
                    .fill(fireDown ? Color.red.opacity(0.75) : Color.red.opacity(0.45))
                    .overlay(Image(systemName: "scope").font(.system(size: buttonSize * 0.38, weight: .bold)))
                    .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 3))
                    .frame(width: buttonSize, height: buttonSize)
                    .position(x: w - buttonSize * 0.75 - 10, y: h - buttonSize * 0.9 - 10)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                if !fireDown { fireDown = true; match.firing = true }
                                let d = CGSize(width: v.translation.width - lastFireDrag.width,
                                               height: v.translation.height - lastFireDrag.height)
                                lastFireDrag = v.translation
                                match.addLook(dx: Float(d.width), dy: Float(d.height))
                            }
                            .onEnded { _ in
                                fireDown = false
                                match.firing = false
                                lastFireDrag = .zero
                            }
                    )

                roundButton("arrow.up", size: buttonSize * 0.62) { match.jump() }
                    .position(x: w - buttonSize * 1.85 - 10, y: h - buttonSize * 0.55 - 10)
                roundButton("arrow.triangle.2.circlepath", size: buttonSize * 0.5) { match.reload() }
                    .position(x: w - buttonSize * 0.75 - 10, y: h - buttonSize * 1.9 - 14)
            }
        }
    }

    private func roundButton(_ icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.black.opacity(0.4)))
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))
        }
    }
}

// MARK: HUD

struct HUDOverlay: View {
    let hud: HUDState
    let onPause: () -> Void

    var body: some View {
        ZStack {
            // Damage vignette
            if hud.damageFlash > 0 {
                RadialGradient(colors: [.clear, .red.opacity(0.55 * hud.damageFlash)],
                               center: .center, startRadius: 120, endRadius: 520)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Crosshair
            ZStack {
                Rectangle().frame(width: 2, height: 14)
                Rectangle().frame(width: 14, height: 2)
                if hud.hitMarker {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(hud.headshotMarker ? Color.yellow : Color.white)
                }
            }
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black, radius: 1)
            .allowsHitTesting(false)

            VStack(spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WAVE \(hud.wave)").font(.headline.weight(.heavy))
                        Text("\(hud.enemiesLeft) enemies left").font(.caption)
                        Label("\(hud.kills)", systemImage: "scope").font(.caption)
                    }
                    Spacer()
                    if let boss = hud.bossHP {
                        VStack(spacing: 2) {
                            Text("CUBE KING").font(.caption.weight(.heavy)).foregroundStyle(.yellow)
                            bar(boss, color: .yellow).frame(width: 180, height: 10)
                        }
                    }
                    Spacer()
                    Label("\(hud.coins)", systemImage: "circle.hexagongrid.fill")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.yellow)
                    Button(action: onPause) {
                        Image(systemName: "pause.fill")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .foregroundStyle(.white)
                }
                if let banner = hud.banner {
                    Text(banner)
                        .font(.title3.weight(.heavy))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                        .allowsHitTesting(false)
                }
                if let c = hud.countdown, hud.banner == nil {
                    Text("Next wave in \(c)")
                        .font(.headline)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .allowsHitTesting(false)
                }
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("\(hud.hp)", systemImage: "heart.fill").font(.headline.monospacedDigit())
                        bar(Double(hud.hp) / Double(max(hud.maxHP, 1)), color: hud.hp > 35 ? .green : .red)
                            .frame(width: 160, height: 12)
                    }
                    .allowsHitTesting(false)
                    Spacer()
                }
                .padding(.bottom, 150)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.8), radius: 2)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Ammo + weapon picker, bottom center
            VStack {
                Spacer()
                VStack(spacing: 6) {
                    if let p = hud.reloadProgress {
                        Text("Reloading").font(.caption.weight(.bold))
                        bar(p, color: .orange).frame(width: 110, height: 6)
                    } else {
                        Text(hud.reserve < 0 ? "\(hud.ammo) / ∞" : "\(hud.ammo) / \(hud.reserve)")
                            .font(.title3.weight(.heavy).monospacedDigit())
                    }
                    Text(hud.weaponName).font(.caption2)
                    WeaponPicker(icons: hud.weaponIcons, selected: hud.weaponIndex)
                }
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 2)
                .padding(.bottom, 12)
            }
        }
    }

    private func bar(_ value: Double, color: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.5))
                Capsule().fill(color).frame(width: g.size.width * max(0, min(1, value)))
            }
        }
    }
}

/// Tapping a weapon icon switches to it. Reads the match from the environment.
struct WeaponPicker: View {
    @EnvironmentObject var match: MatchController
    let icons: [String]
    let selected: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(icons.enumerated()), id: \.offset) { i, icon in
                Button {
                    match.selectWeapon(i)
                } label: {
                    Image(systemName: icon)
                        .font(.headline)
                        .frame(width: 46, height: 38)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(i == selected ? Color.orange.opacity(0.8) : Color.black.opacity(0.45)))
                }
                .foregroundStyle(.white)
            }
        }
    }
}

// MARK: Pause & results

struct PauseMenu: View {
    let resume: () -> Void
    let quit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Paused").font(.largeTitle.weight(.heavy))
                Button(action: resume) {
                    Text("Resume").frame(width: 200).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                Button(role: .destructive, action: quit) {
                    Text("Leave match (keep rewards)").frame(width: 200).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
            .foregroundStyle(.white)
        }
    }
}

struct ResultsView: View {
    let result: MatchResult
    let arena: ArenaMap
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("MATCH OVER").font(.largeTitle.weight(.heavy))
                Text(arena.name).foregroundStyle(.secondary)
                HStack(spacing: 28) {
                    stat("Wave", "\(result.wave)")
                    stat("Kills", "\(result.kills)")
                    stat("Headshots", "\(result.headshots)")
                }
                HStack(spacing: 28) {
                    stat("Coins", "+\(result.coins)").foregroundStyle(.yellow)
                    stat("XP", "+\(result.xp)").foregroundStyle(.cyan)
                }
                Button(action: onDone) {
                    Text("Continue").frame(width: 200).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .foregroundStyle(.white)
            .padding()
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title.weight(.heavy).monospacedDigit())
            Text(title).font(.caption)
        }
    }
}
