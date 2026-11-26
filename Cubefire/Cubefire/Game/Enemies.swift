import SceneKit
import simd

enum EnemyKind {
    case grunt, rusher, brute, king

    var name: String {
        switch self {
        case .grunt: "Grunt"
        case .rusher: "Rusher"
        case .brute: "Brute"
        case .king: "Cube King"
        }
    }
    var baseHP: Double {
        switch self {
        case .grunt: 60
        case .rusher: 40
        case .brute: 220
        case .king: 1400
        }
    }
    var speed: Float {
        switch self {
        case .grunt: 2.6
        case .rusher: 4.8
        case .brute: 1.8
        case .king: 1.6
        }
    }
    var scale: Float {
        switch self {
        case .grunt: 1.0
        case .rusher: 0.85
        case .brute: 1.35
        case .king: 2.1
        }
    }
    var isMelee: Bool { self == .rusher }
    var baseDamage: Double {
        switch self {
        case .grunt: 7
        case .rusher: 12
        case .brute: 8
        case .king: 10
        }
    }
    var fireInterval: Double {
        switch self {
        case .grunt: 1.7
        case .rusher: 0.8
        case .brute: 2.4
        case .king: 1.9
        }
    }
    /// Shots per volley.
    var volley: Int {
        switch self {
        case .grunt, .rusher: 1
        case .brute: 3
        case .king: 5
        }
    }
    var preferredRange: Float {
        switch self {
        case .grunt: 9
        case .rusher: 0
        case .brute: 7
        case .king: 10
        }
    }
    var coins: Int {
        switch self {
        case .grunt: 8
        case .rusher: 10
        case .brute: 25
        case .king: 200
        }
    }
    var xp: Int {
        switch self {
        case .grunt: 10
        case .rusher: 12
        case .brute: 30
        case .king: 250
        }
    }
    /// body, skin, legs, eyes, gun
    var palette: (UInt32, UInt32, UInt32, UInt32, UInt32) {
        switch self {
        case .grunt: (0x3D7A3D, 0x8FD46B, 0x2B3A55, 0xFF3B30, 0x333333)
        case .rusher: (0xD9452B, 0xFFB085, 0x3A2A2A, 0xFFE14D, 0x222222)
        case .brute: (0x5B4B8A, 0x9C8AD6, 0x2A2440, 0xFF3B30, 0x444444)
        case .king: (0xC9A227, 0xF2D16B, 0x6B1E1E, 0x00E5FF, 0x8A1C1C)
        }
    }
}

final class Enemy {
    let kind: EnemyKind
    let rig: CharacterRig
    var pos: SIMD3<Float>
    var hp: Double
    let maxHP: Double
    let damage: Double
    var cooldown: Double
    var losTimer: Double = 0
    var hasLOS = false
    var yaw: Float = 0
    var walkPhase: Float = 0
    var strafeDir: Float = 1
    var strafeTimer: Double = 0
    var flashTimer: Double = 0
    var alive = true

    var radius: Float { 0.32 * kind.scale }
    var height: Float { 1.86 * kind.scale }
    var headY: Float { pos.y + 1.36 * kind.scale }

    init(kind: EnemyKind, at pos: SIMD3<Float>, wave: Int) {
        self.kind = kind
        self.pos = pos
        let hpScale = 1 + 0.14 * Double(wave - 1)
        let dmgScale = 1 + 0.06 * Double(wave - 1)
        maxHP = kind.baseHP * hpScale
        hp = maxHP
        damage = kind.baseDamage * dmgScale
        cooldown = Double.random(in: 0.8...2.0)
        let p = kind.palette
        rig = CharacterRig(body: p.0, skin: p.1, legs: p.2, eyes: p.3, gun: p.4, scale: kind.scale)
        rig.root.position = SCNVector3(pos.x, pos.y, pos.z)
        if kind.isMelee { rig.root.childNodes.last?.isHidden = true }   // rushers carry no gun
    }
}
