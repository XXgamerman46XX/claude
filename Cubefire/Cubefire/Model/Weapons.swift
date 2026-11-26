import Foundation

enum WeaponID: String, CaseIterable, Identifiable, Codable {
    case blaster, scatter, pulse, rail, rocket

    var id: String { rawValue }
}

struct WeaponStats {
    let name: String
    let icon: String            // SF Symbol
    let blurb: String
    let damage: Double          // per pellet, at weapon level 1
    let fireInterval: Double    // seconds between shots
    let magazine: Int
    let reserve: Int            // spare ammo at match start; -1 = infinite
    let reloadTime: Double
    let pellets: Int
    let spread: Float           // radians
    let range: Float
    let splash: Float           // explosion radius, 0 = none
    let projectileSpeed: Float  // 0 = instant hit
    let pierce: Bool            // goes through enemies
    let price: Int
    let unlockLevel: Int
    let color: UInt32
    let length: Float           // barrel length for the 3D model
}

extension WeaponID {
    var stats: WeaponStats {
        switch self {
        case .blaster:
            WeaponStats(name: "Blaster", icon: "bolt.fill", blurb: "Reliable sidearm. Never runs dry.",
                        damage: 18, fireInterval: 0.26, magazine: 12, reserve: -1, reloadTime: 1.0,
                        pellets: 1, spread: 0.012, range: 60, splash: 0, projectileSpeed: 0, pierce: false,
                        price: 0, unlockLevel: 1, color: 0x4FC3F7, length: 0.32)
        case .scatter:
            WeaponStats(name: "Scatter Cannon", icon: "circle.grid.3x3.fill", blurb: "8 pellets. Devastating up close.",
                        damage: 11, fireInterval: 0.8, magazine: 6, reserve: 36, reloadTime: 1.6,
                        pellets: 8, spread: 0.085, range: 26, splash: 0, projectileSpeed: 0, pierce: false,
                        price: 400, unlockLevel: 2, color: 0xFF8A3D, length: 0.42)
        case .pulse:
            WeaponStats(name: "Pulse Rifle", icon: "waveform.path", blurb: "Fast automatic fire.",
                        damage: 13, fireInterval: 0.095, magazine: 30, reserve: 180, reloadTime: 1.4,
                        pellets: 1, spread: 0.025, range: 70, splash: 0, projectileSpeed: 0, pierce: false,
                        price: 900, unlockLevel: 4, color: 0x7CFC9A, length: 0.5)
        case .rail:
            WeaponStats(name: "Railgun", icon: "scope", blurb: "Pierces every enemy in a line. Aim for heads.",
                        damage: 95, fireInterval: 1.1, magazine: 5, reserve: 30, reloadTime: 1.8,
                        pellets: 1, spread: 0, range: 120, splash: 0, projectileSpeed: 0, pierce: true,
                        price: 1800, unlockLevel: 7, color: 0xB388FF, length: 0.62)
        case .rocket:
            WeaponStats(name: "Cube Launcher", icon: "flame.fill", blurb: "Explosive rockets hit everything nearby.",
                        damage: 90, fireInterval: 1.0, magazine: 4, reserve: 20, reloadTime: 2.0,
                        pellets: 1, spread: 0.005, range: 80, splash: 3.2, projectileSpeed: 22, pierce: false,
                        price: 3000, unlockLevel: 10, color: 0xFF5252, length: 0.55)
        }
    }

    static let maxLevel = 10

    /// Damage multiplier for an upgraded weapon (+15% per level).
    static func damageMultiplier(level: Int) -> Double { 1 + 0.15 * Double(max(level, 1) - 1) }

    /// Coins to go from `level` to `level + 1`.
    func upgradeCost(from level: Int) -> Int {
        Int(Double(max(stats.price, 300)) * 0.6 * pow(1.55, Double(level - 1)))
    }
}
