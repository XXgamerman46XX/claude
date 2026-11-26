import SceneKit
import UIKit

/// Small deterministic random generator, so textures look the same every launch.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(UInt64(1) << 53) }
}

/// Pixel-art textures, materials and blocky models.
enum Voxel {
    private static var textureCache: [String: UIImage] = [:]
    private static var materialCache: [String: SCNMaterial] = [:]

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    /// A 16x16 noisy pixel texture in the given colour, with a darker 1-pixel border.
    static func pixelTexture(_ hex: UInt32, seed: Int, border: Bool = true) -> UIImage {
        let key = "\(hex)-\(seed)-\(border)"
        if let t = textureCache[key] { return t }
        let size = 16
        var rng = SeededRNG(seed: UInt64(truncatingIfNeeded: seed &* 7919) &+ UInt64(hex) &+ 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color(hex).getRed(&r, green: &g, blue: &b, alpha: &a)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            for y in 0..<size {
                for x in 0..<size {
                    var f = 0.86 + rng.unit() * 0.24
                    if border && (x == 0 || y == 0 || x == size - 1 || y == size - 1) { f *= 0.72 }
                    UIColor(red: min(r * f, 1), green: min(g * f, 1), blue: min(b * f, 1), alpha: 1).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        textureCache[key] = image
        return image
    }

    private static func makeMaterial(_ hex: UInt32, seed: Int, repeatX: Float, repeatY: Float,
                                     glow: Bool, border: Bool) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = pixelTexture(hex, seed: seed, border: border)
        m.diffuse.magnificationFilter = .nearest
        m.diffuse.minificationFilter = .nearest
        m.diffuse.mipFilter = .none
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(repeatX, repeatY, 1)
        m.lightingModel = .lambert
        if glow { m.emission.contents = color(hex) }
        return m
    }

    /// Shared material (cached). Use for static blocks.
    static func material(_ hex: UInt32, seed: Int = 1, repeatX: Float = 1, repeatY: Float = 1,
                         glow: Bool = false, border: Bool = true) -> SCNMaterial {
        let key = "\(hex)-\(seed)-\(repeatX)-\(repeatY)-\(glow)-\(border)"
        if let m = materialCache[key] { return m }
        let m = makeMaterial(hex, seed: seed, repeatX: repeatX, repeatY: repeatY, glow: glow, border: border)
        materialCache[key] = m
        return m
    }

    /// Unshared material, for things that flash when hit.
    static func ownMaterial(_ hex: UInt32, seed: Int = 1, glow: Bool = false) -> SCNMaterial {
        makeMaterial(hex, seed: seed, repeatX: 1, repeatY: 1, glow: glow, border: true)
    }

    static func box(_ w: Float, _ h: Float, _ l: Float, _ material: SCNMaterial) -> SCNNode {
        let g = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(l), chamferRadius: 0)
        g.materials = [material]
        return SCNNode(geometry: g)
    }

    /// The arena: floor plus every block, merged into one node so it draws fast.
    static func buildArena(_ map: ArenaMap) -> SCNNode {
        let root = SCNNode()
        let w = Float(map.width), d = Float(map.depth)

        let floor = SCNBox(width: CGFloat(w), height: 0.2, length: CGFloat(d), chamferRadius: 0)
        floor.materials = [material(map.floor, seed: 3, repeatX: w, repeatY: d, border: true)]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(w / 2, -0.1, d / 2)
        root.addChildNode(floorNode)

        let blocks = SCNNode()
        for z in 0..<map.depth {
            for x in 0..<map.width {
                let c = map.tile(x, z)
                let h = ArenaMap.height(of: c)
                guard h > 0 else { continue }
                let hex: UInt32 = c == "#" ? map.wall : (c == "B" ? map.pillar : map.crate)
                for level in 0..<h {
                    let seed = (x * 31 + z * 17 + level * 7) % 4
                    let b = box(1, 1, 1, material(hex, seed: seed))
                    b.position = SCNVector3(Float(x) + 0.5, Float(level) + 0.5, Float(z) + 0.5)
                    blocks.addChildNode(b)
                }
            }
        }
        root.addChildNode(blocks.flattenedClone())
        return root
    }
}

/// A blocky character with limbs we can animate.
final class CharacterRig {
    let root = SCNNode()
    let leftLeg = SCNNode()
    let rightLeg = SCNNode()
    let leftArm = SCNNode()
    let rightArm = SCNNode()
    private(set) var flashMaterials: [SCNMaterial] = []

    init(body: UInt32, skin: UInt32, legs: UInt32, eyes: UInt32, gun: UInt32, scale: Float) {
        let bodyM = Voxel.ownMaterial(body, seed: 1)
        let skinM = Voxel.ownMaterial(skin, seed: 2)
        let legM = Voxel.ownMaterial(legs, seed: 3)
        flashMaterials = [bodyM, skinM, legM]

        // Legs swing from the hip.
        for (pivot, x) in [(leftLeg, Float(-0.13)), (rightLeg, Float(0.13))] {
            pivot.position = SCNVector3(x, 0.7, 0)
            let leg = Voxel.box(0.22, 0.7, 0.24, legM)
            leg.position = SCNVector3(0, -0.35, 0)
            pivot.addChildNode(leg)
            root.addChildNode(pivot)
        }

        let torso = Voxel.box(0.56, 0.66, 0.32, bodyM)
        torso.position = SCNVector3(0, 1.03, 0)
        root.addChildNode(torso)

        let head = Voxel.box(0.5, 0.5, 0.5, skinM)
        head.position = SCNVector3(0, 1.61, 0)
        root.addChildNode(head)
        let eyeM = Voxel.material(eyes, seed: 9, glow: true, border: false)
        for x in [Float(-0.11), Float(0.11)] {
            let eye = Voxel.box(0.1, 0.08, 0.03, eyeM)
            eye.position = SCNVector3(x, 1.65, -0.26)
            root.addChildNode(eye)
        }

        // Arms point forward (toward -Z) holding a gun.
        for (pivot, x) in [(leftArm, Float(-0.37)), (rightArm, Float(0.37))] {
            pivot.position = SCNVector3(x, 1.3, 0)
            pivot.eulerAngles.x = -.pi / 2 + 0.25
            let arm = Voxel.box(0.18, 0.6, 0.18, bodyM)
            arm.position = SCNVector3(0, -0.3, 0)
            pivot.addChildNode(arm)
            root.addChildNode(pivot)
        }
        let gunNode = Voxel.box(0.12, 0.14, 0.55, Voxel.material(gun, seed: 5))
        gunNode.position = SCNVector3(0.37, 1.22, -0.62)
        root.addChildNode(gunNode)

        root.scale = SCNVector3(scale, scale, scale)
    }

    func setFlash(_ on: Bool) {
        for m in flashMaterials {
            m.emission.contents = on ? UIColor(red: 1, green: 0.25, blue: 0.2, alpha: 1) : UIColor.black
        }
    }

    /// phase in radians; amount 0...1
    func animateWalk(phase: Float, amount: Float) {
        let swing = sin(phase) * 0.7 * amount
        leftLeg.eulerAngles.x = swing
        rightLeg.eulerAngles.x = -swing
    }
}
