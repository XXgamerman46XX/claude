import Foundation

/// Arenas are drawn as text. Legend:
///   #  wall (3 blocks tall)     B  pillar (2 tall)     c  crate (1 tall, you can jump on it)
///   .  floor     P  your spawn     e  enemy spawn     h  health pickup     a  ammo pickup
struct ArenaMap: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let unlockLevel: Int
    let sky: UInt32
    let floor: UInt32
    let wall: UInt32
    let pillar: UInt32
    let crate: UInt32
    let rows: [String]

    var width: Int { rows.first?.count ?? 0 }
    var depth: Int { rows.count }

    func tile(_ x: Int, _ z: Int) -> Character {
        guard z >= 0, z < rows.count, x >= 0, x < width else { return "#" }
        let row = rows[z]
        return row[row.index(row.startIndex, offsetBy: x)]
    }

    static func height(of c: Character) -> Int {
        switch c {
        case "#": 3
        case "B": 2
        case "c": 1
        default: 0
        }
    }
}

enum Arenas {
    static let all: [ArenaMap] = [yard, temple, fortress]

    static let yard = ArenaMap(
        id: "yard", name: "Crate Yard", blurb: "Open ground, crates to hop on. Learn the ropes.",
        unlockLevel: 1, sky: 0x8EC9FF, floor: 0x6FAE4B, wall: 0x8D8D8D, pillar: 0xB0773F, crate: 0xC9964B,
        rows: """
        #####################
        #e.......e.........e#
        #...................#
        #..cc.....B.....cc..#
        #..c.............c..#
        #.......a...h.......#
        #....BB.......BB....#
        #....B.........B....#
        #e........c........e#
        #...h....c.c....a...#
        #.........P.........#
        #...a....c.c....h...#
        #e........c........e#
        #....B.........B....#
        #....BB.......BB....#
        #.......h...a.......#
        #..c.............c..#
        #..cc.....B.....cc..#
        #...................#
        #e.......e.........e#
        #####################
        """.split(separator: "\n").map(String.init))

    static let temple = ArenaMap(
        id: "temple", name: "Neon Temple", blurb: "Tight corridors and side rooms. Watch your flanks.",
        unlockLevel: 3, sky: 0x1B1035, floor: 0x2E2A4F, wall: 0x5A3FA0, pillar: 0x00C2C7, crate: 0xE0409B,
        rows: """
        #####################
        #e...#.......#....e.#
        #....#...a...#......#
        #..c.#.......#..c...#
        #....###...###......#
        #...................#
        ###.....B...B.....###
        #h......B...B......a#
        #.....c.......c.....#
        #e........P........e#
        #.....c.......c.....#
        #a......B...B......h#
        ###.....B...B.....###
        #...................#
        #....###...###......#
        #..c.#.......#..c...#
        #....#...h...#......#
        #e...#.......#....e.#
        #...................#
        #.........e.........#
        #####################
        """.split(separator: "\n").map(String.init))

    static let fortress = ArenaMap(
        id: "fortress", name: "Sky Fortress", blurb: "A walled keep in the middle. Hold it if you can.",
        unlockLevel: 6, sky: 0xFFB27A, floor: 0xC2B280, wall: 0x6D5D4B, pillar: 0x9E3D3D, crate: 0x8A6A45,
        rows: """
        #######################
        #e.........e.........e#
        #.##......###......##.#
        #.#.................#.#
        #.....c....h....c.....#
        #..B...............B..#
        #.....###.....###.....#
        #a....#.........#....a#
        #.....#....P....#.....#
        #e....#.........#....e#
        #.....##.......##.....#
        #.....................#
        #..cc.....BBB.....cc..#
        #h...................h#
        #.....c.........c.....#
        #..B......#.#......B..#
        #.........#a#.........#
        #.##...............##.#
        #.#.................#.#
        #e.........e.........e#
        #######################
        """.split(separator: "\n").map(String.init))
}
