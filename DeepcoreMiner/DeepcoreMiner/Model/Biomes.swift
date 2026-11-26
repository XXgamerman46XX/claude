import SwiftUI

struct Ore: Identifiable, Hashable {
    let id: String
    let name: String
    let color: UInt32
    let rarity: Int   // 0 common, 1 uncommon, 2 rare

    var rarityName: String { ["Common", "Uncommon", "Rare"][rarity] }
}

struct Biome: Identifiable {
    let index: Int
    let name: String
    let top: UInt32
    let bottom: UInt32
    let rock: UInt32
    let boss: String
    let ores: [Ore]

    var id: Int { index }
    var firstDepth: Int { index * Balance.layersPerBiome + 1 }
    var bossDepth: Int { (index + 1) * Balance.layersPerBiome }
}

enum Biomes {
    static let all: [Biome] = [
        make(0, "Topsoil", 0x6B4F2E, 0x3B2A18, 0x8A6A45, "Root Wyrm",
             [("Copper", 0xD9844A), ("Tin", 0xBFC5C9), ("Quartz", 0xF4EEF8)]),
        make(1, "Clay Pits", 0x8C4A32, 0x4A2418, 0xA65B3C, "Mudback Golem",
             [("Iron", 0x9AA0A6), ("Coal", 0x2B2B2B), ("Amber", 0xFFB300)]),
        make(2, "Granite Shelf", 0x5F6368, 0x2E3134, 0x80868B, "Granite Sentinel",
             [("Silver", 0xE0E0E0), ("Lead", 0x6D7B8D), ("Garnet", 0xB0123A)]),
        make(3, "Crystal Caves", 0x2C2F6B, 0x14163A, 0x4B4F9A, "Prism Spider",
             [("Amethyst", 0x9B59D0), ("Cobalt", 0x2F6FE0), ("Diamond", 0xB9F2FF)]),
        make(4, "Fungal Depths", 0x2E4A2E, 0x142414, 0x4F6B3A, "Mycelium Queen",
             [("Sporite", 0x7CFC9A), ("Nickel", 0xA8A9AD), ("Moonstone", 0xDCE6F2)]),
        make(5, "Frozen Veins", 0x3A6B8C, 0x162E40, 0x7FA9C4, "Rime Colossus",
             [("Frostite", 0xBFEFFF), ("Platinum", 0xE5E4E2), ("Sapphire", 0x1F62E0)]),
        make(6, "Magma Rifts", 0x8C2A12, 0x3A0A04, 0x5A2A1E, "Cinder Drake",
             [("Emberite", 0xFF6A00), ("Titanium", 0x9A9993), ("Ruby", 0xE0115F)]),
        make(7, "Obsidian Halls", 0x241A2E, 0x0C0810, 0x3A2E44, "Glass Warden",
             [("Obsidian", 0x7A5C9C), ("Tungsten", 0xC0C6CC), ("Starglass", 0xE8D8FF)]),
        make(8, "Abyssal Ruins", 0x0F3B44, 0x041418, 0x1F5560, "Drowned King",
             [("Relic Bronze", 0xCD7F32), ("Mithril", 0x9FE2D6), ("Abyss Pearl", 0xF8F4E3)]),
        make(9, "Void Pockets", 0x1A0B2E, 0x05010C, 0x2C1A48, "Hollow Eye",
             [("Voidstone", 0x8A2BE2), ("Iridium", 0xD8D8F0), ("Starlight", 0xFFF6A0)]),
        make(10, "Mantle Gate", 0x6B3A0A, 0x2A1402, 0x8A4E14, "The Gatekeeper",
             [("Mantlite", 0xFF9F43), ("Osmium", 0x7F9BB8), ("Sunstone", 0xFFD23F)]),
        make(11, "The Core", 0xFF5E1A, 0x5A0A00, 0xA8320F, "Heart of the World",
             [("Coreglass", 0xFFE0B2), ("Neutronium", 0xE0F7FF), ("Heartstone", 0xFF1744)]),
    ]

    static let allOres: [Ore] = all.flatMap { $0.ores }

    static func forDepth(_ depth: Int) -> Biome {
        let i = (max(depth, 1) - 1) / Balance.layersPerBiome
        return all[min(i, all.count - 1)]
    }

    private static func make(_ i: Int, _ name: String, _ top: UInt32, _ bottom: UInt32, _ rock: UInt32,
                             _ boss: String, _ ores: [(String, UInt32)]) -> Biome {
        let oreList = ores.enumerated().map { idx, o in
            Ore(id: "\(i)-\(idx)", name: o.0, color: o.1, rarity: idx)
        }
        return Biome(index: i, name: name, top: top, bottom: bottom, rock: rock, boss: boss, ores: oreList)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
