import SceneKit
import SwiftUI
import UIKit
import simd

struct HUDState: Equatable {
    var hp = 100
    var maxHP = 100
    var ammo = 0
    var reserve = 0              // -1 = infinite
    var reloadProgress: Double? = nil
    var weaponIndex = 0
    var weaponIcons: [String] = []
    var weaponName = ""
    var wave = 1
    var enemiesLeft = 0
    var kills = 0
    var coins = 0
    var hitMarker = false
    var headshotMarker = false
    var damageFlash = 0.0
    var countdown: Int? = nil
    var banner: String? = nil
    var bossHP: Double? = nil    // 0...1 when the Cube King is alive
}

private struct Gun {
    let id: WeaponID
    let stats: WeaponStats
    let damageMult: Double
    var mag: Int
    var reserve: Int
}

private final class Projectile {
    let node: SCNNode
    var pos: SIMD3<Float>
    let vel: SIMD3<Float>
    let damage: Double
    let fromPlayer: Bool
    let splash: Float
    var life: Float

    init(node: SCNNode, pos: SIMD3<Float>, vel: SIMD3<Float>, damage: Double, fromPlayer: Bool, splash: Float) {
        self.node = node
        self.pos = pos
        self.vel = vel
        self.damage = damage
        self.fromPlayer = fromPlayer
        self.splash = splash
        life = 4
    }
}

private final class Pickup {
    enum Kind { case health, ammo }
    let kind: Kind
    let node: SCNNode
    let pos: SIMD3<Float>
    var respawn: Double = 0

    init(kind: Kind, node: SCNNode, pos: SIMD3<Float>) {
        self.kind = kind
        self.node = node
        self.pos = pos
    }
}

/// Weak proxy so CADisplayLink doesn't keep the match alive forever.
private final class DisplayLinkProxy: NSObject {
    weak var target: MatchController?
    init(_ t: MatchController) {
        target = t
        super.init()
    }
    @objc func tick(_ link: CADisplayLink) { target?.frame(link) }
}

/// Runs one match: player, enemies, weapons, waves.
final class MatchController: ObservableObject {
    enum Phase: Equatable { case fighting, intermission, dead }

    @Published private(set) var hud = HUDState()
    @Published private(set) var phase: Phase = .intermission
    @Published private(set) var result: MatchResult?
    @Published var paused = false

    let map: ArenaMap
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let gunNode = SCNNode()
    private let store: ProfileStore
    private let sensitivity: Float

    // World
    private var heights: [[Int]] = []
    private var flow: [Int] = []
    private var flowFrom: (Int, Int) = (-1, -1)
    private var enemySpawns: [SIMD3<Float>] = []

    // Player
    private var feet = SIMD3<Float>(0, 0, 0)
    private var velY: Float = 0
    private var onGround = true
    private var yaw: Float = 0
    private var pitch: Float = 0
    private var hp: Double = 100
    private let maxHP: Double = 100
    private let eyeHeight: Float = 1.6
    private let playerRadius: Float = 0.3

    // Input (set by the touch controls)
    var moveInput = SIMD2<Float>(0, 0)
    var firing = false
    private var lookDelta = SIMD2<Float>(0, 0)
    private var jumpQueued = false

    // Weapons
    private var guns: [Gun] = []
    private var gunIndex = 0
    private var fireCooldown: Double = 0
    private var reloadLeft: Double? = nil
    private var gunKick: Float = 0

    // Match state
    private var enemies: [Enemy] = []
    private var projectiles: [Projectile] = []
    private var pickups: [Pickup] = []
    private var spawnQueue: [EnemyKind] = []
    private var spawnTimer: Double = 0
    private var wave = 0
    private var intermissionLeft: Double = 3
    private var kills = 0
    private var headshots = 0
    private var coinsEarned = 0
    private var xpEarned = 0
    private var hitMarkerLeft: Double = 0
    private var headshotMarkerLeft: Double = 0
    private var damageFlash: Double = 0
    private var bannerText: String? = nil
    private var bannerLeft: Double = 0
    private var hudTimer: Double = 0

    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)

    init(map: ArenaMap, store: ProfileStore) {
        self.map = map
        self.store = store
        sensitivity = Float(store.profile.lookSensitivity)
        buildWorld()
        buildGuns()
        showBanner("Get ready!", seconds: 2.5)
        publishHUD()
    }

    // MARK: Lifecycle

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTime = 0
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    deinit { displayLink?.invalidate() }

    /// Ends the match early (from the pause menu) and banks what you earned.
    func quit() {
        guard result == nil else { return }
        finish()
    }

    // MARK: Input

    func addLook(dx: Float, dy: Float) {
        lookDelta += SIMD2<Float>(dx, dy)
    }

    func jump() { jumpQueued = true }

    func reload() {
        guard reloadLeft == nil, phase != .dead else { return }
        let g = guns[gunIndex]
        guard g.mag < g.stats.magazine, g.reserve != 0 else { return }
        reloadLeft = g.stats.reloadTime
    }

    func selectWeapon(_ i: Int) {
        guard i != gunIndex, guns.indices.contains(i) else { return }
        gunIndex = i
        reloadLeft = nil
        fireCooldown = 0.25
        rebuildGunModel()
        lightHaptic.impactOccurred()
        publishHUD()
    }

    // MARK: World setup

    private func buildWorld() {
        heights = (0..<map.depth).map { z in (0..<map.width).map { x in ArenaMap.height(of: map.tile(x, z)) } }

        scene.background.contents = Voxel.color(map.sky)
        scene.fogColor = Voxel.color(map.sky)
        scene.fogStartDistance = 22
        scene.fogEndDistance = 55
        scene.rootNode.addChildNode(Voxel.buildArena(map))

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 550
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 900
        sun.eulerAngles = SCNVector3(-0.9, 0.6, 0)
        scene.rootNode.addChildNode(sun)

        let camera = SCNCamera()
        camera.fieldOfView = 72
        camera.zNear = 0.03
        camera.zFar = 120
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        cameraNode.addChildNode(gunNode)

        for z in 0..<map.depth {
            for x in 0..<map.width {
                let center = SIMD3<Float>(Float(x) + 0.5, 0, Float(z) + 0.5)
                switch map.tile(x, z) {
                case "P": feet = center
                case "e": enemySpawns.append(center)
                case "h": addPickup(.health, at: center)
                case "a": addPickup(.ammo, at: center)
                default: break
                }
            }
        }
        // Face the middle of the arena.
        let mid = SIMD3<Float>(Float(map.width) / 2, 0, Float(map.depth) / 2)
        let toMid = mid - feet
        if simd_length(toMid) > 0.5 { yaw = atan2(-toMid.x, -toMid.z) }
        updateCamera()
    }

    private func addPickup(_ kind: Pickup.Kind, at p: SIMD3<Float>) {
        let hex: UInt32 = kind == .health ? 0x4CFF6A : 0xFFD54F
        let node = Voxel.box(0.4, 0.4, 0.4, Voxel.material(hex, seed: 11, glow: true))
        if kind == .health {
            let crossM = Voxel.material(0xFFFFFF, seed: 12, glow: true, border: false)
            let a = Voxel.box(0.42, 0.1, 0.1, crossM)
            let b = Voxel.box(0.1, 0.42, 0.1, crossM)
            let c = Voxel.box(0.1, 0.1, 0.42, crossM)
            [a, b, c].forEach { node.addChildNode($0) }
        }
        node.position = SCNVector3(p.x, 0.6, p.z)
        node.runAction(.repeatForever(.rotateBy(x: 0, y: .pi, z: 0, duration: 1.6)))
        node.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.15, z: 0, duration: 0.8),
                                                 .moveBy(x: 0, y: -0.15, z: 0, duration: 0.8)])))
        scene.rootNode.addChildNode(node)
        pickups.append(Pickup(kind: kind, node: node, pos: p))
    }

    private func buildGuns() {
        let p = store.profile
        guns = p.loadoutWeapons.map { id in
            let s = id.stats
            return Gun(id: id, stats: s, damageMult: WeaponID.damageMultiplier(level: p.weaponLevel(id)),
                       mag: s.magazine, reserve: s.reserve)
        }
        if guns.isEmpty {
            let s = WeaponID.blaster.stats
            guns = [Gun(id: .blaster, stats: s, damageMult: 1, mag: s.magazine, reserve: s.reserve)]
        }
        rebuildGunModel()
    }

    private func rebuildGunModel() {
        gunNode.childNodes.forEach { $0.removeFromParentNode() }
        let s = guns[gunIndex].stats
        let main = Voxel.material(s.color, seed: 4)
        let dark = Voxel.material(0x2B2B33, seed: 6)
        let body = Voxel.box(0.09, 0.1, s.length, main)
        body.position = SCNVector3(0, 0, -s.length / 2)
        let grip = Voxel.box(0.07, 0.14, 0.08, dark)
        grip.position = SCNVector3(0, -0.1, -0.04)
        let barrel = Voxel.box(0.05, 0.05, 0.12, dark)
        barrel.position = SCNVector3(0, 0.01, -s.length - 0.05)
        let hand = Voxel.box(0.1, 0.1, 0.14, Voxel.material(0xE0B48A, seed: 7))
        hand.position = SCNVector3(0, -0.08, 0.05)
        [body, grip, barrel, hand].forEach { gunNode.addChildNode($0) }
        gunNode.position = SCNVector3(0.22, -0.2, -0.32)
    }

    // MARK: Loop

    fileprivate func frame(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTime == 0 ? 1.0 / 60 : min(now - lastTime, 0.05)
        lastTime = now
        guard !paused, phase != .dead else {
            lookDelta = .zero
            return
        }
        update(dt)
    }

    private func update(_ dt: Double) {
        let fdt = Float(dt)
        updatePlayer(fdt)
        updateWeapon(dt)
        updateWaves(dt)
        updateEnemies(dt)
        updateProjectiles(fdt)
        updatePickups(dt)

        hitMarkerLeft = max(0, hitMarkerLeft - dt)
        headshotMarkerLeft = max(0, headshotMarkerLeft - dt)
        damageFlash = max(0, damageFlash - dt * 2)
        if bannerLeft > 0 {
            bannerLeft -= dt
            if bannerLeft <= 0 { bannerText = nil }
        }
        hudTimer += dt
        if hudTimer >= 0.05 {
            hudTimer = 0
            publishHUD()
        }
    }

    // MARK: Player

    private func updatePlayer(_ dt: Float) {
        // Look
        let s = 0.0045 * sensitivity
        yaw -= lookDelta.x * s
        pitch = max(-1.35, min(1.35, pitch - lookDelta.y * s))
        lookDelta = .zero

        // Move
        let forward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
        let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        var wish = forward * moveInput.y + right * moveInput.x
        let len = simd_length(wish)
        if len > 1 { wish /= len }
        let speed: Float = 5.6
        let step = wish * speed * dt
        tryMove(dx: step.x, dz: 0)
        tryMove(dx: 0, dz: step.z)

        // Jump & gravity
        if jumpQueued && onGround {
            velY = 6.6
            onGround = false
        }
        jumpQueued = false
        velY -= 19 * dt
        feet.y += velY * dt
        let ground = groundHeight(x: feet.x, z: feet.z)
        if feet.y <= ground {
            feet.y = ground
            velY = 0
            onGround = true
        } else {
            onGround = false
        }
        updateCamera()
    }

    private func updateCamera() {
        cameraNode.position = SCNVector3(feet.x, feet.y + eyeHeight, feet.z)
        cameraNode.eulerAngles = SCNVector3(pitch, yaw, 0)
    }

    private func tileHeight(_ x: Float, _ z: Float) -> Int {
        let ix = Int(floor(x)), iz = Int(floor(z))
        guard iz >= 0, iz < heights.count, ix >= 0, ix < heights[iz].count else { return 9 }
        return heights[iz][ix]
    }

    /// Highest block under the player's footprint.
    private func groundHeight(x: Float, z: Float) -> Float {
        let r = playerRadius
        let hs = [tileHeight(x - r, z - r), tileHeight(x + r, z - r), tileHeight(x - r, z + r), tileHeight(x + r, z + r)]
        return Float(hs.max() ?? 0)
    }

    private func tryMove(dx: Float, dz: Float) {
        let nx = feet.x + dx, nz = feet.z + dz
        let r = playerRadius
        let corners = [(nx - r, nz - r), (nx + r, nz - r), (nx - r, nz + r), (nx + r, nz + r)]
        for (cx, cz) in corners where Float(tileHeight(cx, cz)) > feet.y + 0.05 {
            return
        }
        feet.x = nx
        feet.z = nz
    }

    private var eye: SIMD3<Float> { SIMD3<Float>(feet.x, feet.y + eyeHeight, feet.z) }

    private var aimDirection: SIMD3<Float> {
        SIMD3<Float>(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
    }

    private func damagePlayer(_ amount: Double) {
        guard phase != .dead else { return }
        hp -= amount
        damageFlash = 1
        heavyHaptic.impactOccurred(intensity: 0.7)
        if hp <= 0 {
            hp = 0
            finish()
        }
    }

    // MARK: Weapons

    private func updateWeapon(_ dt: Double) {
        fireCooldown -= dt
        gunKick = max(0, gunKick - Float(dt) * 6)
        gunNode.position = SCNVector3(0.22, -0.2 + gunKick * 0.03, -0.32 + gunKick * 0.08)
        gunNode.eulerAngles.x = gunKick * 0.25

        if let left = reloadLeft {
            let remaining = left - dt
            if remaining <= 0 {
                var g = guns[gunIndex]
                let need = g.stats.magazine - g.mag
                let take = g.reserve < 0 ? need : min(need, g.reserve)
                g.mag += take
                if g.reserve >= 0 { g.reserve -= take }
                guns[gunIndex] = g
                reloadLeft = nil
            } else {
                reloadLeft = remaining
            }
            return
        }

        guard firing, fireCooldown <= 0, phase != .dead else { return }
        if guns[gunIndex].mag <= 0 {
            reload()
            return
        }
        fire()
    }

    private func fire() {
        var g = guns[gunIndex]
        let s = g.stats
        g.mag -= 1
        guns[gunIndex] = g
        fireCooldown = s.fireInterval
        gunKick = 1
        lightHaptic.impactOccurred(intensity: 0.6)

        let origin = eye
        let f = aimDirection
        let r = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        let u = simd_cross(r, f)
        let muzzle = origin + f * 0.6 + r * 0.2 - SIMD3<Float>(0, 0.18, 0)
        let damage = s.damage * g.damageMult

        for _ in 0..<s.pellets {
            var dir = f
            if s.spread > 0 {
                dir += r * Float.random(in: -s.spread...s.spread) + u * Float.random(in: -s.spread...s.spread)
                dir = simd_normalize(dir)
            }
            if s.projectileSpeed > 0 {
                spawnProjectile(from: muzzle, dir: dir, speed: s.projectileSpeed, damage: damage,
                                fromPlayer: true, splash: s.splash, color: s.color, size: 0.18)
            } else {
                hitscan(origin: origin, dir: dir, range: s.range, damage: damage, pierce: s.pierce,
                        muzzle: muzzle, color: s.color)
            }
        }
        if guns[gunIndex].mag == 0 { reload() }
    }

    private func hitscan(origin: SIMD3<Float>, dir: SIMD3<Float>, range: Float, damage: Double,
                         pierce: Bool, muzzle: SIMD3<Float>, color: UInt32) {
        let wallT = rayWallDistance(from: origin, dir: dir, max: range)
        var hits: [(Float, Enemy)] = []
        for e in enemies where e.alive {
            let lo = SIMD3<Float>(e.pos.x - e.radius, e.pos.y, e.pos.z - e.radius)
            let hi = SIMD3<Float>(e.pos.x + e.radius, e.pos.y + e.height, e.pos.z + e.radius)
            if let t = rayBox(origin: origin, dir: dir, lo: lo, hi: hi), t < wallT {
                hits.append((t, e))
            }
        }
        hits.sort { $0.0 < $1.0 }
        var endT = wallT
        let targets = pierce ? hits : Array(hits.prefix(1))
        for (t, e) in targets {
            let hitPoint = origin + dir * t
            let head = hitPoint.y >= e.headY
            hurt(e, damage * (head ? 1.8 : 1), headshot: head, at: hitPoint)
            if !pierce { endT = t }
        }
        let end = origin + dir * endT
        spawnTracer(from: muzzle, to: end, color: color, thick: pierce ? 0.05 : 0.025)
        if targets.isEmpty || pierce { spawnSparks(at: end, color: 0xDDDDDD, count: 3) }
    }

    private func hurt(_ e: Enemy, _ amount: Double, headshot: Bool, at point: SIMD3<Float>) {
        guard e.alive else { return }
        e.hp -= amount
        e.flashTimer = 0.09
        e.rig.setFlash(true)
        hitMarkerLeft = 0.12
        if headshot { headshotMarkerLeft = 0.25 }
        spawnSparks(at: point, color: e.kind.palette.0, count: 4)
        if e.hp <= 0 { kill(e, headshot: headshot) }
    }

    private func kill(_ e: Enemy, headshot: Bool) {
        e.alive = false
        kills += 1
        if headshot { headshots += 1 }
        coinsEarned += e.kind.coins + (headshot ? 2 : 0)
        xpEarned += e.kind.xp
        let p = e.kind.palette
        spawnSparks(at: e.pos + SIMD3<Float>(0, e.height * 0.5, 0), color: p.0, count: 10)
        spawnSparks(at: e.pos + SIMD3<Float>(0, e.height * 0.85, 0), color: p.1, count: 6)
        e.rig.root.removeFromParentNode()
        if e.kind == .king { showBanner("Cube King defeated! +\(e.kind.coins) coins", seconds: 3) }
    }

    // MARK: Waves

    private func updateWaves(_ dt: Double) {
        switch phase {
        case .intermission:
            intermissionLeft -= dt
            if intermissionLeft <= 0 { startWave() }
        case .fighting:
            spawnTimer -= dt
            if !spawnQueue.isEmpty && spawnTimer <= 0 && enemies.filter({ $0.alive }).count < 14 {
                spawnEnemy(spawnQueue.removeFirst())
                spawnTimer = max(0.35, 1.0 - Double(wave) * 0.03)
            }
            enemies.removeAll { !$0.alive }
            if spawnQueue.isEmpty && enemies.isEmpty {
                let bonus = 15 + wave * 10
                coinsEarned += bonus
                xpEarned += 20 + wave * 8
                hp = min(maxHP, hp + 35)
                showBanner("Wave \(wave) cleared! +\(bonus) coins", seconds: 3)
                phase = .intermission
                intermissionLeft = 6
            }
        case .dead:
            break
        }
    }

    private func startWave() {
        wave += 1
        phase = .fighting
        var q: [EnemyKind] = []
        let count = 4 + wave * 2
        for i in 0..<count {
            if wave >= 3 && i % 3 == 1 { q.append(.rusher) }
            else if wave >= 4 && i % 5 == 4 { q.append(.brute) }
            else { q.append(.grunt) }
        }
        if wave >= 8 { q.append(contentsOf: Array(repeating: .brute, count: wave / 4)) }
        q.shuffle()
        if wave % 5 == 0 {
            q.insert(.king, at: min(2, q.count))
            showBanner("Wave \(wave): The Cube King approaches!", seconds: 3)
        } else {
            showBanner("Wave \(wave)", seconds: 2)
        }
        spawnQueue = q
        spawnTimer = 0.5
    }

    private func spawnEnemy(_ kind: EnemyKind) {
        let far = enemySpawns.filter { simd_distance($0, feet) > 7 }
        guard let spot = (far.isEmpty ? enemySpawns : far).randomElement() else { return }
        let e = Enemy(kind: kind, at: spot, wave: wave)
        scene.rootNode.addChildNode(e.rig.root)
        enemies.append(e)
        spawnSparks(at: spot + SIMD3<Float>(0, 1, 0), color: 0xFFFFFF, count: 6)
    }

    // MARK: Enemies

    private func updateEnemies(_ dt: Double) {
        let fdt = Float(dt)
        refreshFlowField()
        for e in enemies where e.alive {
            if e.flashTimer > 0 {
                e.flashTimer -= dt
                if e.flashTimer <= 0 { e.rig.setFlash(false) }
            }

            let to = SIMD3<Float>(feet.x - e.pos.x, 0, feet.z - e.pos.z)
            let dist = simd_length(to)
            e.losTimer -= dt
            if e.losTimer <= 0 {
                e.losTimer = 0.25
                let from = e.pos + SIMD3<Float>(0, 1.5 * e.kind.scale, 0)
                e.hasLOS = lineOfSight(from, eye)
            }

            // Turn to face the player.
            if dist > 0.01 {
                let targetYaw = atan2(-to.x, -to.z)
                var diff = targetYaw - e.yaw
                while diff > .pi { diff -= 2 * .pi }
                while diff < -.pi { diff += 2 * .pi }
                e.yaw += diff * min(1, fdt * 8)
            }

            // Decide where to go.
            var move = SIMD3<Float>(0, 0, 0)
            if e.kind.isMelee {
                move = dist < 2.5 && e.hasLOS ? to / max(dist, 0.001) : flowDirection(from: e.pos)
            } else if e.hasLOS && dist < e.kind.preferredRange {
                e.strafeTimer -= dt
                if e.strafeTimer <= 0 {
                    e.strafeTimer = Double.random(in: 1.2...2.8)
                    e.strafeDir = Bool.random() ? 1 : -1
                }
                let side = SIMD3<Float>(-to.z, 0, to.x) / max(dist, 0.001)
                move = side * e.strafeDir * 0.5
            } else {
                move = flowDirection(from: e.pos)
            }
            let moved = moveEnemy(e, by: move * e.kind.speed * fdt)
            e.walkPhase += moved * 6 / e.kind.scale
            e.rig.animateWalk(phase: e.walkPhase, amount: moved > 0.0001 ? 1 : 0)

            // Attack.
            e.cooldown -= dt
            if e.kind.isMelee {
                if dist < 1.3 + e.radius && e.cooldown <= 0 && abs(feet.y - e.pos.y) < 1.2 {
                    e.cooldown = e.kind.fireInterval
                    damagePlayer(e.damage)
                    e.rig.rightArm.runAction(.sequence([.rotateBy(x: -0.9, y: 0, z: 0, duration: 0.08),
                                                        .rotateBy(x: 0.9, y: 0, z: 0, duration: 0.15)]))
                }
            } else if e.hasLOS && dist < 28 && e.cooldown <= 0 {
                e.cooldown = e.kind.fireInterval * Double.random(in: 0.8...1.2)
                enemyShoot(e)
            }

            e.rig.root.position = SCNVector3(e.pos.x, e.pos.y, e.pos.z)
            e.rig.root.eulerAngles.y = e.yaw
        }
        separateEnemies()
    }

    private func enemyShoot(_ e: Enemy) {
        let forward = SIMD3<Float>(-sin(e.yaw), 0, -cos(e.yaw))
        let muzzle = e.pos + SIMD3<Float>(0, 1.22 * e.kind.scale, 0) + forward * 0.9 * e.kind.scale
        let target = SIMD3<Float>(feet.x, feet.y + 1.0, feet.z)
        let base = simd_normalize(target - muzzle)
        let n = e.kind.volley
        for i in 0..<n {
            var dir = base
            if n > 1 {
                let spreadAngle = (Float(i) - Float(n - 1) / 2) * 0.12
                let c = cos(spreadAngle), s = sin(spreadAngle)
                dir = simd_normalize(SIMD3<Float>(base.x * c + base.z * s, base.y, -base.x * s + base.z * c))
            }
            dir = simd_normalize(dir + SIMD3<Float>(Float.random(in: -0.03...0.03), Float.random(in: -0.02...0.02),
                                                    Float.random(in: -0.03...0.03)))
            let speed: Float = e.kind == .king ? 11 : 13
            spawnProjectile(from: muzzle, dir: dir, speed: speed, damage: e.damage, fromPlayer: false,
                            splash: 0, color: e.kind.palette.3, size: e.kind == .king ? 0.28 : 0.16)
        }
    }

    /// Moves an enemy, sliding along walls. Returns distance moved.
    private func moveEnemy(_ e: Enemy, by d: SIMD3<Float>) -> Float {
        let start = e.pos
        let r = min(e.radius, 0.4)
        func free(_ x: Float, _ z: Float) -> Bool {
            tileHeight(x - r, z - r) == 0 && tileHeight(x + r, z - r) == 0 &&
                tileHeight(x - r, z + r) == 0 && tileHeight(x + r, z + r) == 0
        }
        if free(e.pos.x + d.x, e.pos.z) { e.pos.x += d.x }
        if free(e.pos.x, e.pos.z + d.z) { e.pos.z += d.z }
        return simd_length(e.pos - start)
    }

    private func separateEnemies() {
        let alive = enemies.filter { $0.alive }
        guard alive.count > 1 else { return }
        for i in 0..<alive.count {
            for j in (i + 1)..<alive.count {
                let a = alive[i], b = alive[j]
                var d = SIMD3<Float>(b.pos.x - a.pos.x, 0, b.pos.z - a.pos.z)
                let minD = a.radius + b.radius + 0.1
                let len = simd_length(d)
                if len < minD {
                    if len < 0.001 { d = SIMD3<Float>(1, 0, 0) } else { d /= len }
                    let push = (minD - len) * 0.5
                    _ = moveEnemy(a, by: -d * push)
                    _ = moveEnemy(b, by: d * push)
                }
            }
        }
    }

    // MARK: Pathfinding (breadth-first flow field toward the player)

    private func refreshFlowField() {
        let px = Int(floor(feet.x)), pz = Int(floor(feet.z))
        guard (px, pz) != flowFrom else { return }
        flowFrom = (px, pz)
        let w = map.width, d = map.depth
        flow = Array(repeating: -1, count: w * d)
        guard px >= 0, px < w, pz >= 0, pz < d else { return }
        var queue = [(px, pz)]
        flow[pz * w + px] = 0
        var head = 0
        while head < queue.count {
            let (x, z) = queue[head]
            head += 1
            let cur = flow[z * w + x]
            for (nx, nz) in [(x + 1, z), (x - 1, z), (x, z + 1), (x, z - 1)] {
                guard nx >= 0, nx < w, nz >= 0, nz < d, heights[nz][nx] == 0, flow[nz * w + nx] < 0 else { continue }
                flow[nz * w + nx] = cur + 1
                queue.append((nx, nz))
            }
        }
    }

    private func flowDirection(from p: SIMD3<Float>) -> SIMD3<Float> {
        let w = map.width, d = map.depth
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        let direct = SIMD3<Float>(feet.x - p.x, 0, feet.z - p.z)
        guard x >= 0, x < w, z >= 0, z < d, !flow.isEmpty else { return safeNormalize(direct) }
        let cur = flow[z * w + x]
        if cur <= 1 { return safeNormalize(direct) }
        var best: (Int, Int)? = nil
        var bestVal = cur < 0 ? Int.max : cur
        for (nx, nz) in [(x + 1, z), (x - 1, z), (x, z + 1), (x, z - 1)] {
            guard nx >= 0, nx < w, nz >= 0, nz < d else { continue }
            let v = flow[nz * w + nx]
            if v >= 0 && v < bestVal {
                bestVal = v
                best = (nx, nz)
            }
        }
        guard let (bx, bz) = best else { return safeNormalize(direct) }
        let target = SIMD3<Float>(Float(bx) + 0.5, 0, Float(bz) + 0.5)
        return safeNormalize(SIMD3<Float>(target.x - p.x, 0, target.z - p.z))
    }

    private func safeNormalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let l = simd_length(v)
        return l < 0.0001 ? .zero : v / l
    }

    // MARK: Projectiles

    private func spawnProjectile(from p: SIMD3<Float>, dir: SIMD3<Float>, speed: Float, damage: Double,
                                 fromPlayer: Bool, splash: Float, color: UInt32, size: Float) {
        let node = Voxel.box(size, size, size, Voxel.material(color, seed: 13, glow: true, border: false))
        node.position = SCNVector3(p.x, p.y, p.z)
        scene.rootNode.addChildNode(node)
        projectiles.append(Projectile(node: node, pos: p, vel: dir * speed, damage: damage,
                                      fromPlayer: fromPlayer, splash: splash))
    }

    private func updateProjectiles(_ dt: Float) {
        for p in projectiles {
            p.life -= dt
            let steps = 3
            var done = p.life <= 0
            for _ in 0..<steps where !done {
                p.pos += p.vel * (dt / Float(steps))
                if isSolid(p.pos) {
                    done = true
                    if p.fromPlayer { explode(p) } else { spawnSparks(at: p.pos, color: 0xFFFFFF, count: 2) }
                    break
                }
                if p.fromPlayer {
                    if let e = enemies.first(where: { e in
                        e.alive && abs(p.pos.x - e.pos.x) < e.radius + 0.1 && abs(p.pos.z - e.pos.z) < e.radius + 0.1
                            && p.pos.y >= e.pos.y && p.pos.y <= e.pos.y + e.height
                    }) {
                        done = true
                        if p.splash > 0 { explode(p) } else { hurt(e, p.damage, headshot: false, at: p.pos) }
                        break
                    }
                } else {
                    let chest = SIMD3<Float>(feet.x, feet.y + 0.9, feet.z)
                    let d = p.pos - chest
                    if abs(d.x) < 0.45 && abs(d.z) < 0.45 && abs(d.y) < 0.95 {
                        done = true
                        damagePlayer(p.damage)
                        break
                    }
                }
            }
            if done {
                p.life = 0
                p.node.removeFromParentNode()
            } else {
                p.node.position = SCNVector3(p.pos.x, p.pos.y, p.pos.z)
                p.node.eulerAngles.y += dt * 10
            }
        }
        projectiles.removeAll { $0.life <= 0 }
    }

    private func explode(_ p: Projectile) {
        guard p.splash > 0 else { return }
        spawnSparks(at: p.pos, color: 0xFF7043, count: 14)
        spawnSparks(at: p.pos, color: 0xFFD54F, count: 8)
        heavyHaptic.impactOccurred(intensity: 0.5)
        for e in enemies where e.alive {
            let center = e.pos + SIMD3<Float>(0, e.height / 2, 0)
            let d = simd_distance(center, p.pos)
            if d < p.splash + e.radius {
                let falloff = Double(max(0.35, 1 - d / (p.splash + e.radius)))
                hurt(e, p.damage * falloff, headshot: false, at: center)
            }
        }
    }

    // MARK: Pickups

    private func updatePickups(_ dt: Double) {
        for p in pickups {
            if p.respawn > 0 {
                p.respawn -= dt
                if p.respawn <= 0 { p.node.isHidden = false }
                continue
            }
            let d = SIMD3<Float>(feet.x - p.pos.x, 0, feet.z - p.pos.z)
            guard simd_length(d) < 0.8, feet.y < 1 else { continue }
            switch p.kind {
            case .health:
                guard hp < maxHP else { continue }
                hp = min(maxHP, hp + 40)
                showBanner("+40 health", seconds: 1)
            case .ammo:
                for i in guns.indices where guns[i].reserve >= 0 {
                    guns[i].reserve += max(guns[i].stats.magazine, guns[i].stats.reserve / 2)
                }
                showBanner("Ammo refilled", seconds: 1)
            }
            lightHaptic.impactOccurred()
            p.node.isHidden = true
            p.respawn = 25
        }
    }

    // MARK: Ray helpers

    private func isSolid(_ p: SIMD3<Float>) -> Bool {
        p.y < 0 || p.y < Float(tileHeight(p.x, p.z))
    }

    private func rayWallDistance(from o: SIMD3<Float>, dir: SIMD3<Float>, max maxT: Float) -> Float {
        let step: Float = 0.08
        var t: Float = 0
        while t < maxT {
            t += step
            if isSolid(o + dir * t) { return t - step * 0.5 }
        }
        return maxT
    }

    private func lineOfSight(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
        let d = b - a
        let len = simd_length(d)
        guard len > 0.01 else { return true }
        return rayWallDistance(from: a, dir: d / len, max: len) >= len - 0.05
    }

    private func rayBox(origin o: SIMD3<Float>, dir d: SIMD3<Float>, lo: SIMD3<Float>, hi: SIMD3<Float>) -> Float? {
        var tmin: Float = 0
        var tmax = Float.greatestFiniteMagnitude
        for i in 0..<3 {
            if abs(d[i]) < 1e-6 {
                if o[i] < lo[i] || o[i] > hi[i] { return nil }
            } else {
                let inv = 1 / d[i]
                var t1 = (lo[i] - o[i]) * inv
                var t2 = (hi[i] - o[i]) * inv
                if t1 > t2 { swap(&t1, &t2) }
                tmin = max(tmin, t1)
                tmax = min(tmax, t2)
                if tmin > tmax { return nil }
            }
        }
        return tmin
    }

    // MARK: Effects

    private func spawnTracer(from a: SIMD3<Float>, to b: SIMD3<Float>, color: UInt32, thick: Float) {
        let len = simd_distance(a, b)
        guard len > 0.05 else { return }
        let node = Voxel.box(thick, thick, len, Voxel.material(color, seed: 14, glow: true, border: false))
        let mid = (a + b) / 2
        node.position = SCNVector3(mid.x, mid.y, mid.z)
        node.look(at: SCNVector3(b.x, b.y, b.z))
        scene.rootNode.addChildNode(node)
        node.runAction(.sequence([.fadeOut(duration: 0.09), .removeFromParentNode()]))
    }

    private func spawnSparks(at p: SIMD3<Float>, color: UInt32, count: Int) {
        let m = Voxel.material(color, seed: 15, glow: false, border: false)
        for _ in 0..<count {
            let s = Float.random(in: 0.06...0.13)
            let n = Voxel.box(s, s, s, m)
            n.position = SCNVector3(p.x, p.y, p.z)
            scene.rootNode.addChildNode(n)
            let v = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: 0.2...1.4), Float.random(in: -1...1))
            n.runAction(.sequence([
                .group([.moveBy(x: CGFloat(v.x), y: CGFloat(v.y), z: CGFloat(v.z), duration: 0.35),
                        .rotateBy(x: 3, y: 2, z: 1, duration: 0.35),
                        .fadeOut(duration: 0.35)]),
                .removeFromParentNode(),
            ]))
        }
    }

    private func showBanner(_ text: String, seconds: Double) {
        bannerText = text
        bannerLeft = seconds
    }

    // MARK: End & HUD

    private func finish() {
        phase = .dead
        firing = false
        moveInput = .zero
        let reached = max(wave, 1)
        xpEarned += kills > 0 ? reached * 10 : 0
        let r = MatchResult(arenaID: map.id, wave: reached, kills: kills, headshots: headshots,
                            coins: coinsEarned, xp: xpEarned)
        store.record(r)
        result = r
        publishHUD()
    }

    private func publishHUD() {
        let g = guns[gunIndex]
        var h = HUDState()
        h.hp = Int(hp.rounded(.up))
        h.maxHP = Int(maxHP)
        h.ammo = g.mag
        h.reserve = g.reserve
        if let left = reloadLeft { h.reloadProgress = 1 - left / g.stats.reloadTime }
        h.weaponIndex = gunIndex
        h.weaponIcons = guns.map { $0.stats.icon }
        h.weaponName = g.stats.name
        h.wave = max(wave, 1)
        h.enemiesLeft = spawnQueue.count + enemies.filter { $0.alive }.count
        h.kills = kills
        h.coins = coinsEarned
        h.hitMarker = hitMarkerLeft > 0
        h.headshotMarker = headshotMarkerLeft > 0
        h.damageFlash = (damageFlash * 10).rounded() / 10
        h.countdown = phase == .intermission ? Int(intermissionLeft.rounded(.up)) : nil
        h.banner = bannerText
        if let king = enemies.first(where: { $0.kind == .king && $0.alive }) {
            h.bossHP = (king.hp / king.maxHP * 50).rounded() / 50
        }
        if h != hud { hud = h }
    }
}
