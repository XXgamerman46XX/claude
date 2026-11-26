import Foundation
import SwiftUI

/// Everything you keep between matches.
struct Profile: Codable {
    var coins: Int = 0
    var xp: Int = 0
    var owned: [String] = [WeaponID.blaster.rawValue]
    var weaponLevels: [String: Int] = [:]
    var loadout: [String] = [WeaponID.blaster.rawValue]   // up to 3 weapons
    var bestWave: [String: Int] = [:]                     // per arena id
    var totalKills: Int = 0
    var headshots: Int = 0
    var matchesPlayed: Int = 0
    var lookSensitivity: Double = 1.0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Profile()
        coins = try c.decodeIfPresent(Int.self, forKey: .coins) ?? d.coins
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? d.xp
        owned = try c.decodeIfPresent([String].self, forKey: .owned) ?? d.owned
        weaponLevels = try c.decodeIfPresent([String: Int].self, forKey: .weaponLevels) ?? d.weaponLevels
        loadout = try c.decodeIfPresent([String].self, forKey: .loadout) ?? d.loadout
        bestWave = try c.decodeIfPresent([String: Int].self, forKey: .bestWave) ?? d.bestWave
        totalKills = try c.decodeIfPresent(Int.self, forKey: .totalKills) ?? d.totalKills
        headshots = try c.decodeIfPresent(Int.self, forKey: .headshots) ?? d.headshots
        matchesPlayed = try c.decodeIfPresent(Int.self, forKey: .matchesPlayed) ?? d.matchesPlayed
        lookSensitivity = try c.decodeIfPresent(Double.self, forKey: .lookSensitivity) ?? d.lookSensitivity
        if loadout.isEmpty { loadout = [WeaponID.blaster.rawValue] }
    }

    // MARK: Levels

    static func xpNeeded(forLevel level: Int) -> Int {
        level <= 1 ? 0 : Int(150 * pow(Double(level - 1), 1.6))
    }

    var level: Int {
        var l = 1
        while xp >= Profile.xpNeeded(forLevel: l + 1) { l += 1 }
        return l
    }

    var levelProgress: Double {
        let lo = Profile.xpNeeded(forLevel: level), hi = Profile.xpNeeded(forLevel: level + 1)
        return Double(xp - lo) / Double(max(hi - lo, 1))
    }

    // MARK: Weapons

    func owns(_ w: WeaponID) -> Bool { owned.contains(w.rawValue) }
    func weaponLevel(_ w: WeaponID) -> Int { weaponLevels[w.rawValue] ?? 1 }
    var loadoutWeapons: [WeaponID] { loadout.compactMap(WeaponID.init(rawValue:)) }
}

struct MatchResult: Equatable {
    let arenaID: String
    let wave: Int          // highest wave reached
    let kills: Int
    let headshots: Int
    let coins: Int
    let xp: Int
}

final class ProfileStore: ObservableObject {
    @Published private(set) var profile: Profile
    private let key = "cubefire.profile.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let p = try? JSONDecoder().decode(Profile.self, from: data) {
            profile = p
        } else {
            profile = Profile()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func buy(_ w: WeaponID) {
        let s = w.stats
        guard !profile.owns(w), profile.coins >= s.price, profile.level >= s.unlockLevel else { return }
        profile.coins -= s.price
        profile.owned.append(w.rawValue)
        if profile.loadout.count < 3 { profile.loadout.append(w.rawValue) }
        save()
    }

    func upgrade(_ w: WeaponID) {
        let lvl = profile.weaponLevel(w)
        let cost = w.upgradeCost(from: lvl)
        guard profile.owns(w), lvl < WeaponID.maxLevel, profile.coins >= cost else { return }
        profile.coins -= cost
        profile.weaponLevels[w.rawValue] = lvl + 1
        save()
    }

    /// Adds or removes a weapon from the 3-slot loadout.
    func toggleEquip(_ w: WeaponID) {
        guard profile.owns(w) else { return }
        if let i = profile.loadout.firstIndex(of: w.rawValue) {
            if profile.loadout.count > 1 { profile.loadout.remove(at: i) }
        } else if profile.loadout.count < 3 {
            profile.loadout.append(w.rawValue)
        }
        save()
    }

    func setSensitivity(_ v: Double) {
        profile.lookSensitivity = v
        save()
    }

    /// Returns true if this was a new best wave on that arena.
    @discardableResult
    func record(_ r: MatchResult) -> Bool {
        profile.coins += r.coins
        profile.xp += r.xp
        profile.totalKills += r.kills
        profile.headshots += r.headshots
        profile.matchesPlayed += 1
        let best = profile.bestWave[r.arenaID] ?? 0
        let newBest = r.wave > best
        if newBest { profile.bestWave[r.arenaID] = r.wave }
        save()
        return newBest
    }
}
