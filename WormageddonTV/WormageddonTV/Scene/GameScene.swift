import SpriteKit
import SwiftUI

/// "Sonnenfleck" art direction: hand-painted gouache storybook islands.
/// One warm plum ink line, golden top-left light, lagoon rim light, and a
/// small shared palette used by every layer (Painter assets, worms, terrain,
/// sky, HUD and SwiftUI menus).
enum Art {
    static let ink = SKColor(red: 0.231, green: 0.133, blue: 0.271, alpha: 1)       // #3B2245
    static let inkDeep = SKColor(red: 0.145, green: 0.086, blue: 0.180, alpha: 1)   // panels
    static let inkSoft = SKColor(red: 0.290, green: 0.196, blue: 0.345, alpha: 1)   // cards, tracks
    static let cream = SKColor(red: 1.0, green: 0.953, blue: 0.863, alpha: 1)       // #FFF3DC
    static let coral = SKColor(red: 0.949, green: 0.329, blue: 0.357, alpha: 1)     // #F2545B
    static let sun = SKColor(red: 1.0, green: 0.788, blue: 0.290, alpha: 1)         // #FFC94A
    static let leaf = SKColor(red: 0.361, green: 0.769, blue: 0.420, alpha: 1)      // #5CC46B
    static let lagoon = SKColor(red: 0.169, green: 0.702, blue: 0.753, alpha: 1)    // #2BB3C0
    static let sky = SKColor(red: 0.298, green: 0.553, blue: 0.965, alpha: 1)       // #4C8DF6

    /// SF Rounded, matching the SwiftUI menus.
    static func font(_ size: CGFloat, _ weight: UIFont.Weight = .heavy) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: rounded, size: size)
    }

    /// HUD label in SF Rounded.
    static func label(_ size: CGFloat, _ weight: UIFont.Weight = .heavy, color: SKColor = cream) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: font(size, weight).fontName)
        label.fontSize = size
        label.fontColor = color
        return label
    }

    static func outlinedText(_ text: String, size: CGFloat, color: SKColor, outline: SKColor = ink) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        return NSAttributedString(string: text, attributes: [
            .font: font(size, .black),
            .foregroundColor: color,
            .strokeColor: outline,
            .strokeWidth: -5.0,
            .paragraphStyle: para
        ])
    }

    /// Rounded "ink plate" panel with a soft offset shadow, the HUD's one panel style.
    /// Sits at z -1 so labels added next to it at z 0 always draw on top.
    static func panel(_ rect: CGRect, radius: CGFloat, fillAlpha: CGFloat = 0.88, stroke: SKColor = cream.withAlphaComponent(0.20), lineWidth: CGFloat = 2.4) -> SKShapeNode {
        let panel = SKShapeNode(path: CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        panel.fillColor = inkDeep.withAlphaComponent(fillAlpha)
        panel.strokeColor = stroke
        panel.lineWidth = lineWidth
        panel.zPosition = -1
        let shadow = SKShapeNode(path: CGPath(roundedRect: rect.offsetBy(dx: 0, dy: -5), cornerWidth: radius, cornerHeight: radius, transform: nil))
        shadow.fillColor = SKColor(red: 0.08, green: 0.03, blue: 0.10, alpha: 0.32)
        shadow.strokeColor = .clear
        shadow.zPosition = -0.5
        panel.addChild(shadow)
        return panel
    }
}

extension Color {
    init(art: SKColor) { self.init(uiColor: art) }
}

extension WeaponKind {
    /// Bold, simplified Painter sprite for small sizes (HUD chip, held weapon, projectile).
    var smallIconName: String { iconName + "_small" }
}

protocol GameSceneDelegate: AnyObject {
    func gameSceneDidRequestPause()
    func gameSceneDidFinishMatch(winnerTeamIndex: Int?, teams: [TeamState])
}

private struct SurfaceProp {
    let node: SKNode
    let anchor: CGPoint
}

final class GameScene: SKScene {
    weak var gameDelegate: GameSceneDelegate?

    private(set) var engine: GameEngine
    private var lastUpdateTime: TimeInterval = 0
    private var elapsedTime: TimeInterval = 0
    private var renderedTerrainRevision: Int = -1
    private var shakeIntensity: CGFloat = 0

    // Input provider supplied by GameViewController
    var inputProvider: (() -> InputSnapshot)?
    var isGameControllerConnected: Bool = false

    // Layers
    private let worldLayer = SKNode()
    private let skyLayer = SKNode()
    private let cloudLayer = SKNode()
    private let propLayer = SKNode()
    private let terrainSprite = SKSpriteNode()
    private var terrainInkLayers: [SKSpriteNode] = []
    private let terrainPaintMask = SKSpriteNode()
    private let entityLayer = SKNode()
    private let fxLayer = SKNode()
    private let waterBackWave = SKShapeNode()
    private let waterFrontWave = SKShapeNode()
    private let hudCamera = SKCameraNode()

    // Entity node maps
    private var wormNodes: [Int: WormNode] = [:]
    private var projectileNodes: [Int: SKNode] = [:]
    private var crateNodes: [Int: SKNode] = [:]
    private var surfaceProps: [SurfaceProp] = []
    private var clouds: [(node: SKNode, speedFactor: CGFloat)] = []
    private var skyBirds: [(node: SKNode, speed: CGFloat, phase: Double)] = []
    private var twinklingStars: [(node: SKShapeNode, phase: Double)] = []
    private var windMotes: [SKShapeNode] = []

    // Aiming & charge indicators (world space)
    private let aimCrosshair = SKNode()
    private var aimDots: [SKShapeNode] = []
    private let powerMeterNode = SKNode()
    private let powerMeterFill = SKShapeNode()
    private let airstrikeOverlay = SKNode()
    private let airstrikeBeam = SKShapeNode()
    private let airstrikeReticle = SKShapeNode()

    // HUD Nodes (camera space — always anchored to 1920x1080 viewport!)
    private let hudLayer = SKNode()
    private var teamScoreBars: [(fill: SKShapeNode, hpLabel: SKLabelNode, bg: SKShapeNode, maxHP: Int)] = []
    private let timerBadge = SKShapeNode()
    private let timerLabel = Art.label(20, .heavy)
    private let weaponChipBg = SKShapeNode()
    private let weaponChipIcon = SKSpriteNode()
    private let weaponChipTitle = Art.label(20, .bold)
    private let weaponChipAmmo = Art.label(20, .semibold)
    private let windBarFill = SKShapeNode()
    private let windTextLabel = Art.label(20, .bold)
    private let turnBannerNode = SKNode()
    private let turnBannerBg = SKShapeNode()
    private let turnBannerTitle = Art.label(20, .heavy)
    private let turnBannerSubtitle = Art.label(20, .semibold)
    private let statusPillNode = SKNode()
    private let statusPillBg = SKShapeNode()
    private let statusPillLabel = Art.label(20, .heavy)
    private let controlsHintLabel = Art.label(20, .semibold)

    // 2×5 Illustrated Weapon Drawer Overlay
    private let weaponBarContainer = SKNode()
    private var weaponBarSlots: [(bg: SKShapeNode, ammoLabel: SKLabelNode, kind: WeaponKind)] = []
    private let weaponBarSelectedTitle = Art.label(20, .heavy)
    private let weaponBarHintLabel = Art.label(20, .semibold)

    private var lastChipWeapon: WeaponKind?
    private var didNotifyMatchEnd = false
    var isGameplayPaused = false

    init(config: MatchConfig) {
        self.engine = GameEngine(config: config)
        super.init(size: CGSize(width: WorldConstants.viewportWidth, height: WorldConstants.viewportHeight))
        self.scaleMode = .aspectFit
        self.anchorPoint = CGPoint(x: 0, y: 0)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        removeAllChildren()
        backgroundColor = engine.config.mapTheme.skyTop

        addChild(worldLayer)
        worldLayer.addChild(skyLayer)
        worldLayer.addChild(cloudLayer)

        terrainSprite.anchorPoint = CGPoint(x: 0, y: 0)
        terrainSprite.position = .zero
        terrainSprite.size = CGSize(width: WorldConstants.width, height: WorldConstants.height)
        terrainSprite.zPosition = 10
        worldLayer.addChild(terrainSprite)

        // Plum ink outline + soft drop shadow around the destructible terrain, built
        // from tinted copies of the terrain texture so craters get outlined too.
        terrainInkLayers.removeAll()
        let inkOffsets: [(CGPoint, SKColor, CGFloat)] = [
            (CGPoint(x: 0, y: -9), SKColor(red: 0.10, green: 0.04, blue: 0.14, alpha: 1), 0.30),
            (CGPoint(x: -3.5, y: 0), Art.ink, 1), (CGPoint(x: 3.5, y: 0), Art.ink, 1),
            (CGPoint(x: 0, y: 3.5), Art.ink, 1), (CGPoint(x: 0, y: -3.5), Art.ink, 1),
            (CGPoint(x: -2.5, y: 2.5), Art.ink, 1), (CGPoint(x: 2.5, y: 2.5), Art.ink, 1),
            (CGPoint(x: -2.5, y: -2.5), Art.ink, 1), (CGPoint(x: 2.5, y: -2.5), Art.ink, 1)
        ]
        for (offset, color, alpha) in inkOffsets {
            let ink = SKSpriteNode()
            ink.anchorPoint = .zero
            ink.size = terrainSprite.size
            ink.position = offset
            ink.color = color
            ink.colorBlendFactor = 1
            ink.alpha = alpha
            ink.zPosition = 9.5
            worldLayer.addChild(ink)
            terrainInkLayers.append(ink)
        }

        // Hand-painted gouache brushwork multiplied over the procedural terrain,
        // clipped to the live terrain texture so craters stay clean.
        terrainPaintMask.anchorPoint = .zero
        terrainPaintMask.size = terrainSprite.size
        let paintCrop = SKCropNode()
        paintCrop.maskNode = terrainPaintMask
        paintCrop.zPosition = 10.5
        let paintTex = SKTexture(imageNamed: "terrain_paint")
        let tile: CGFloat = 400
        var ty: CGFloat = 0
        var row = 0
        while ty < WorldConstants.height {
            var tx: CGFloat = 0
            var col = 0
            while tx < WorldConstants.width {
                let t = SKSpriteNode(texture: paintTex, size: CGSize(width: tile, height: tile))
                t.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                t.position = CGPoint(x: tx + tile * 0.5, y: ty + tile * 0.5)
                // Mirror alternate tiles so the seams line up
                t.xScale = col % 2 == 0 ? 1 : -1
                t.yScale = row % 2 == 0 ? 1 : -1
                t.blendMode = .multiply
                paintCrop.addChild(t)
                tx += tile
                col += 1
            }
            ty += tile
            row += 1
        }
        worldLayer.addChild(paintCrop)

        propLayer.zPosition = 12
        worldLayer.addChild(propLayer)

        entityLayer.zPosition = 20
        worldLayer.addChild(entityLayer)

        fxLayer.zPosition = 30
        worldLayer.addChild(fxLayer)

        waterBackWave.zPosition = 18
        waterFrontWave.zPosition = 26
        worldLayer.addChild(waterBackWave)
        worldLayer.addChild(waterFrontWave)

        buildBackdrop()
        buildSurfaceProps()
        buildAimingIndicators()
        buildWormNodes()
        syncTerrainTextureIfNeeded()

        // Camera starts centered on the active worm inside the 2880x1500 world
        let startTarget = engine.activeWorm?.position ?? CGPoint(x: WorldConstants.width * 0.5, y: WorldConstants.height * 0.45)
        hudCamera.position = clampedCameraPosition(for: startTarget, scale: 1.0)
        hudCamera.setScale(1.0)
        addChild(hudCamera)
        self.camera = hudCamera

        hudLayer.zPosition = 100
        hudCamera.addChild(hudLayer)
        buildHUD()
        buildWeaponBar()
        updateHUD()
    }

    // MARK: - Backdrop Construction (2880 × 1500 World)

    private func buildBackdrop() {
        let theme = engine.config.mapTheme

        let skyTex = makeSkyGradientTexture(top: theme.skyTop, mid: theme.skyMid, bottom: theme.skyBottom)
        let skySprite = SKSpriteNode(texture: skyTex, size: CGSize(width: WorldConstants.width + 600, height: WorldConstants.height + 500))
        skySprite.position = CGPoint(x: WorldConstants.width * 0.5, y: WorldConstants.height * 0.5)
        skySprite.zPosition = 0
        skyLayer.addChild(skySprite)

        // Twinkling upper-sky stars (small four-point sparkles in warm cream)
        twinklingStars.removeAll()
        if theme.showsStars {
            var rng = SeededRNG(seed: engine.config.seed ^ 0x51A4)
            for _ in 0..<64 {
                let r = rng.nextCGFloat(in: 2.2...4.4)
                let star = SKShapeNode(path: sparklePath(radius: r))
                star.fillColor = Art.cream.withAlphaComponent(0.9)
                star.strokeColor = .clear
                star.position = CGPoint(
                    x: rng.nextCGFloat(in: 60...(WorldConstants.width - 60)),
                    y: rng.nextCGFloat(in: (WorldConstants.height * 0.55)...(WorldConstants.height - 36))
                )
                star.zPosition = 1
                skyLayer.addChild(star)
                twinklingStars.append((star, rng.nextDouble() * .pi * 2))
            }
        }

        // Painted sun / moon: soft halo rings plus a cream disc with a plum ink rim
        let sunPos = CGPoint(x: WorldConstants.width * 0.76, y: WorldConstants.height * 0.78)
        for (radius, alpha) in [(260, 0.06), (180, 0.11), (120, 0.20)] as [(CGFloat, CGFloat)] {
            let glow = SKShapeNode(circleOfRadius: radius)
            glow.fillColor = theme.sunColor.withAlphaComponent(alpha)
            glow.strokeColor = .clear
            glow.position = sunPos
            glow.zPosition = 1
            skyLayer.addChild(glow)
        }
        let sunDisc = SKShapeNode(circleOfRadius: 74)
        sunDisc.fillColor = theme.sunColor
        sunDisc.strokeColor = Art.ink.withAlphaComponent(0.35)
        sunDisc.lineWidth = 4
        sunDisc.position = sunPos
        sunDisc.zPosition = 2
        skyLayer.addChild(sunDisc)
        let sunShine = SKShapeNode(ellipseOf: CGSize(width: 54, height: 34))
        sunShine.fillColor = SKColor.white.withAlphaComponent(0.45)
        sunShine.strokeColor = .clear
        sunShine.position = CGPoint(x: sunPos.x - 20, y: sunPos.y + 24)
        sunShine.zRotation = 0.5
        sunShine.zPosition = 2.1
        skyLayer.addChild(sunShine)

        // Two painted parallax island ranges (one Painter strip, tinted per mood)
        addHorizonStrip(scale: 2.25, baseY: 70, color: theme.farHillColor, z: 2.5, flipped: false, xOffset: -260)
        addHorizonStrip(scale: 1.55, baseY: 56, color: theme.hillColor, z: 3, flipped: true, xOffset: 120)

        // Painted gouache clouds drifting with the wind
        cloudLayer.zPosition = 5
        clouds.removeAll()
        let cloudTint = theme.showsStars ? theme.skyMid : theme.sunColor
        for i in 0..<10 {
            let cloud = SKSpriteNode(imageNamed: "bg_cloud")
            cloud.setScale(CGFloat(0.55 + Double(i % 3) * 0.28))
            cloud.color = cloudTint
            cloud.colorBlendFactor = theme.showsStars ? 0.45 : 0.12
            cloud.alpha = theme.showsStars ? 0.62 : 0.92
            if i % 2 == 1 { cloud.xScale *= -1 }
            cloud.position = CGPoint(
                x: CGFloat(i) * 310 + 80,
                y: WorldConstants.height - 140 - CGFloat((i * 67) % 330)
            )
            cloudLayer.addChild(cloud)
            clouds.append((cloud, CGFloat(0.65 + Double(i % 4) * 0.25)))
        }

        // Distant gliding birds in soft plum ink
        skyBirds.removeAll()
        for i in 0..<5 {
            let bird = makeBirdNode()
            bird.position = CGPoint(
                x: 240 + CGFloat(i) * 520,
                y: WorldConstants.height - 260 - CGFloat((i * 83) % 240)
            )
            bird.zPosition = 6
            cloudLayer.addChild(bird)
            skyBirds.append((bird, CGFloat(34 + i * 7), Double(i) * 1.3))
        }

        // Drifting pollen motes across the larger world
        windMotes.removeAll()
        for i in 0..<42 {
            let mote = SKShapeNode(circleOfRadius: CGFloat(2.0 + Double(i % 3) * 0.9))
            mote.fillColor = Art.cream.withAlphaComponent(0.42)
            mote.strokeColor = .clear
            mote.position = CGPoint(
                x: CGFloat((i * 113) % Int(WorldConstants.width)),
                y: CGFloat(150 + (i * 57) % Int(WorldConstants.height - 200))
            )
            mote.zPosition = 14
            worldLayer.addChild(mote)
            windMotes.append(mote)
        }
    }

    private func addHorizonStrip(scale: CGFloat, baseY: CGFloat, color: SKColor, z: CGFloat, flipped: Bool, xOffset: CGFloat) {
        let probe = SKTexture(imageNamed: "bg_far_islands")
        let stripW = probe.size().width * scale
        var x = xOffset
        var i = 0
        while x < WorldConstants.width + 300 {
            let strip = SKSpriteNode(texture: probe)
            strip.anchorPoint = CGPoint(x: 0, y: 0)
            strip.setScale(scale)
            let flip = (i % 2 == 1) != flipped
            if flip {
                strip.xScale = -scale
                strip.position = CGPoint(x: x + stripW, y: baseY)
            } else {
                strip.position = CGPoint(x: x, y: baseY)
            }
            strip.color = color.withAlphaComponent(1)
            strip.colorBlendFactor = 0.82
            strip.alpha = max(0.55, color.cgColor.alpha)
            strip.zPosition = z
            skyLayer.addChild(strip)
            x += stripW - 2
            i += 1
        }
    }

    private func sparklePath(radius r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        p.addQuadCurve(to: CGPoint(x: 0, y: -r), control: .zero)
        p.addQuadCurve(to: CGPoint(x: -r, y: 0), control: .zero)
        p.addQuadCurve(to: CGPoint(x: 0, y: r), control: .zero)
        p.closeSubpath()
        return p
    }

    private func makeBirdNode() -> SKNode {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -12, y: 2))
        p.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: -5, y: 8))
        p.addQuadCurve(to: CGPoint(x: 12, y: 2), control: CGPoint(x: 5, y: 8))
        let bird = SKShapeNode(path: p)
        bird.strokeColor = Art.ink.withAlphaComponent(0.55)
        bird.lineWidth = 2.6
        bird.lineCap = .round
        return bird
    }

    private func makeSkyGradientTexture(top: SKColor, mid: SKColor, bottom: SKColor) -> SKTexture {
        let h = 256
        var pixels = [UInt8](repeating: 255, count: h * 4)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        var r3: CGFloat = 0, g3: CGFloat = 0, b3: CGFloat = 0, a3: CGFloat = 0
        top.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        mid.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        bottom.getRed(&r3, green: &g3, blue: &b3, alpha: &a3)

        for y in 0..<h {
            let t = CGFloat(y) / CGFloat(h - 1)
            let r: CGFloat
            let g: CGFloat
            let b: CGFloat
            if t < 0.55 {
                let u = t / 0.55
                r = r1 + (r2 - r1) * u
                g = g1 + (g2 - g1) * u
                b = b1 + (b2 - b1) * u
            } else {
                let u = (t - 0.55) / 0.45
                r = r2 + (r3 - r2) * u
                g = g2 + (g3 - g2) * u
                b = b2 + (b3 - b2) * u
            }
            let off = y * 4
            pixels[off] = UInt8(max(0, min(255, Int(r * 255))))
            pixels[off + 1] = UInt8(max(0, min(255, Int(g * 255))))
            pixels[off + 2] = UInt8(max(0, min(255, Int(b * 255))))
            pixels[off + 3] = 255
        }
        let data = Data(pixels)
        if let provider = CGDataProvider(data: data as CFData),
           let cg = CGImage(
            width: 1,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
           ) {
            return SKTexture(cgImage: cg)
        }
        return SKTexture()
    }

    // MARK: - Destructible Painted Island Props (Painter Assets)

    private func buildSurfaceProps() {
        propLayer.removeAllChildren()
        surfaceProps.removeAll()
        // Hedgewars maps bring their own painted scenery; island props would clash.
        guard !engine.config.mapStyle.isHedgewarsArt else { return }

        var rng = SeededRNG(seed: engine.config.seed ^ 0xF10E)
        var towersPlaced = 0
        var lastTowerX: CGFloat = -999
        var lastTallX: CGFloat = -999

        var x: CGFloat = 120
        while x < WorldConstants.width - 120 {
            x += rng.nextCGFloat(in: 40...84)
            guard let sy = engine.terrain.surfaceY(atWorldX: x),
                  sy > WorldConstants.initialWaterY + 34,
                  let syL = engine.terrain.surfaceY(atWorldX: x - 20),
                  let syR = engine.terrain.surfaceY(atWorldX: x + 20),
                  abs(syL - syR) < 22 else { continue }

            let nearWorm = engine.worms.contains { hypot($0.position.x - x, $0.position.y - sy) < 34 }
            if nearWorm { continue }

            // (asset, target height range, sways in the breeze)
            let roll = rng.nextDouble()
            let pick: (String, ClosedRange<CGFloat>, Bool)
            if towersPlaced < 2 && sy > 500 && (x - lastTowerX) > 740 && roll < 0.22 {
                pick = ("prop_tower", 118...138, false)
                towersPlaced += 1
                lastTowerX = x
                lastTallX = x
            } else if roll < 0.42 && (x - lastTallX) > 120 {
                pick = Bool(rng.nextDouble() < 0.5) ? ("prop_tree", 96...132, true) : ("prop_palm", 118...152, true)
                lastTallX = x
            } else if roll < 0.68 {
                pick = ("prop_flowers", 30...44, false)
            } else if roll < 0.84 {
                pick = ("prop_rocks", 30...46, false)
            } else {
                continue
            }

            let sprite = SKSpriteNode(imageNamed: pick.0)
            let targetH = rng.nextCGFloat(in: pick.1)
            sprite.setScale(targetH / max(1, sprite.size.height))
            if rng.nextDouble() < 0.5 { sprite.xScale *= -1 }
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0.03)
            sprite.position = CGPoint(x: x, y: sy - 5)
            sprite.zPosition = pick.2 ? 0 : 1
            if pick.2 {
                let amp = CGFloat(0.022 + rng.nextDouble() * 0.02)
                let dur = 1.6 + rng.nextDouble() * 0.9
                let sway = SKAction.sequence([
                    .rotate(toAngle: amp, duration: dur, shortestUnitArc: true),
                    .rotate(toAngle: -amp, duration: dur, shortestUnitArc: true)
                ])
                sway.timingMode = .easeInEaseOut
                sprite.run(.repeatForever(sway))
            }
            propLayer.addChild(sprite)
            surfaceProps.append(SurfaceProp(node: sprite, anchor: CGPoint(x: x, y: sy - 10)))
        }
    }

    private func pruneDestroyedProps() {
        var i = 0
        while i < surfaceProps.count {
            let prop = surfaceProps[i]
            if !engine.terrain.isSolid(worldPoint: prop.anchor) {
                prop.node.removeAllActions()
                prop.node.run(.sequence([
                    .group([
                        .moveBy(x: CGFloat.random(in: -34...34), y: 42, duration: 0.42),
                        .rotate(byAngle: CGFloat.random(in: -1.6...1.6), duration: 0.42),
                        .fadeOut(withDuration: 0.42)
                    ]),
                    .removeFromParent()
                ]))
                surfaceProps.remove(at: i)
            } else {
                i += 1
            }
        }
    }

    // MARK: - Aiming & World Indicators

    private func buildAimingIndicators() {
        // Crosshair: sunflower ring on a thick plum ink ring so it pops on sky and terrain
        let inkRing = SKShapeNode(circleOfRadius: 14)
        inkRing.strokeColor = Art.ink
        inkRing.lineWidth = 7
        inkRing.fillColor = Art.cream.withAlphaComponent(0.18)
        aimCrosshair.addChild(inkRing)

        let ring = SKShapeNode(circleOfRadius: 14)
        ring.strokeColor = Art.sun
        ring.lineWidth = 3.2
        ring.fillColor = .clear
        aimCrosshair.addChild(ring)

        let tickPath: CGPath = {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -22, y: 0)); p.addLine(to: CGPoint(x: -9, y: 0))
            p.move(to: CGPoint(x: 9, y: 0)); p.addLine(to: CGPoint(x: 22, y: 0))
            p.move(to: CGPoint(x: 0, y: -22)); p.addLine(to: CGPoint(x: 0, y: -9))
            p.move(to: CGPoint(x: 0, y: 9)); p.addLine(to: CGPoint(x: 0, y: 22))
            return p
        }()
        let tickInk = SKShapeNode(path: tickPath)
        tickInk.strokeColor = Art.ink
        tickInk.lineWidth = 6.5
        tickInk.lineCap = .round
        aimCrosshair.addChild(tickInk)
        let ticks = SKShapeNode(path: tickPath)
        ticks.strokeColor = Art.cream
        ticks.lineWidth = 2.6
        ticks.lineCap = .round
        aimCrosshair.addChild(ticks)

        let center = SKShapeNode(circleOfRadius: 3)
        center.fillColor = Art.coral
        center.strokeColor = Art.ink
        center.lineWidth = 1.6
        aimCrosshair.addChild(center)
        aimCrosshair.zPosition = 28
        worldLayer.addChild(aimCrosshair)

        // Dotted sightline between worm and crosshair
        aimDots.removeAll()
        for i in 0..<3 {
            let dot = SKShapeNode(circleOfRadius: CGFloat(3.8 - Double(i) * 0.5))
            dot.fillColor = Art.cream
            dot.strokeColor = Art.ink
            dot.lineWidth = 1.8
            dot.zPosition = 27
            worldLayer.addChild(dot)
            aimDots.append(dot)
        }

        powerMeterNode.zPosition = 29
        powerMeterNode.addChild(powerMeterFill)
        worldLayer.addChild(powerMeterNode)

        airstrikeOverlay.zPosition = 32
        airstrikeBeam.strokeColor = Art.sky.withAlphaComponent(0.85)
        airstrikeBeam.lineWidth = 4
        airstrikeOverlay.addChild(airstrikeBeam)

        let retInk = SKShapeNode(circleOfRadius: 42)
        retInk.strokeColor = Art.ink
        retInk.lineWidth = 9
        retInk.fillColor = Art.coral.withAlphaComponent(0.20)
        airstrikeReticle.addChild(retInk)
        let ret = SKShapeNode(circleOfRadius: 42)
        ret.strokeColor = Art.coral
        ret.lineWidth = 4
        ret.fillColor = .clear
        airstrikeReticle.addChild(ret)
        let plane = SKSpriteNode(imageNamed: WeaponKind.airstrike.smallIconName)
        plane.setScale(44 / max(1, plane.size.height))
        plane.position = CGPoint(x: 0, y: 70)
        airstrikeReticle.addChild(plane)
        airstrikeOverlay.addChild(airstrikeReticle)
        airstrikeOverlay.isHidden = true
        worldLayer.addChild(airstrikeOverlay)
    }

    private func buildWormNodes() {
        wormNodes.removeAll()
        for worm in engine.worms {
            let desc = engine.teams[worm.teamIndex].descriptor
            let node = WormNode(worm: worm, team: desc)
            entityLayer.addChild(node)
            wormNodes[worm.id] = node
        }
    }

    // MARK: - HUD (Anchored to 1920 × 1080 tvOS Viewport)

    private func buildHUD() {
        let halfW = WorldConstants.viewportWidth * 0.5
        let halfH = WorldConstants.viewportHeight * 0.5
        let safeX: CGFloat = 84
        let safeY: CGFloat = 58

        // Top-Left: Team Scoreboard (ink plates with a team-color health bar)
        teamScoreBars.removeAll()
        for (idx, team) in engine.teams.enumerated() {
            let maxHP = engine.config.wormsPerTeam * 100
            let yOffset = halfH - safeY - 24 - CGFloat(idx) * 52
            let xLeft = -halfW + safeX

            let bg = Art.panel(CGRect(x: -170, y: -21, width: 340, height: 42), radius: 14, stroke: team.descriptor.color)
            bg.position = CGPoint(x: xLeft + 170, y: yOffset)
            hudLayer.addChild(bg)

            let dot = SKShapeNode(circleOfRadius: 9)
            dot.fillColor = team.descriptor.color
            dot.strokeColor = Art.cream
            dot.lineWidth = 2
            dot.position = CGPoint(x: xLeft + 22, y: yOffset + 4)
            hudLayer.addChild(dot)

            let name = Art.label(16, .bold)
            name.text = "S\(idx + 1) · \(team.descriptor.name)"
            name.horizontalAlignmentMode = .left
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: xLeft + 40, y: yOffset + 5)
            hudLayer.addChild(name)

            let hpLabel = Art.label(17, .heavy, color: team.descriptor.color)
            hpLabel.text = "\(maxHP)"
            hpLabel.horizontalAlignmentMode = .right
            hpLabel.verticalAlignmentMode = .center
            hpLabel.position = CGPoint(x: xLeft + 326, y: yOffset + 5)
            hudLayer.addChild(hpLabel)

            let track = SKShapeNode(rect: CGRect(x: xLeft + 40, y: yOffset - 14, width: 286, height: 8), cornerRadius: 4)
            track.fillColor = Art.inkSoft
            track.strokeColor = .clear
            hudLayer.addChild(track)

            let fill = SKShapeNode()
            fill.fillColor = team.descriptor.color
            fill.strokeColor = .clear
            fill.position = CGPoint(x: xLeft + 40, y: yOffset - 14)
            hudLayer.addChild(fill)

            teamScoreBars.append((fill, hpLabel, bg, maxHP))
        }

        // Top-Right: Wind Gauge
        let windX = halfW - safeX - 140
        let windY = halfH - safeY - 26
        let windBg = Art.panel(CGRect(x: -140, y: -30, width: 280, height: 60), radius: 16)
        windBg.position = CGPoint(x: windX, y: windY)
        hudLayer.addChild(windBg)

        windTextLabel.fontSize = 16
        windTextLabel.fontColor = Art.cream
        windTextLabel.verticalAlignmentMode = .center
        windTextLabel.position = CGPoint(x: windX, y: windY + 12)
        hudLayer.addChild(windTextLabel)

        let windTrack = SKShapeNode(rectOf: CGSize(width: 236, height: 12), cornerRadius: 6)
        windTrack.fillColor = Art.inkSoft
        windTrack.strokeColor = .clear
        windTrack.position = CGPoint(x: windX, y: windY - 12)
        hudLayer.addChild(windTrack)

        windBarFill.position = CGPoint(x: windX, y: windY - 12)
        windBarFill.strokeColor = .clear
        hudLayer.addChild(windBarFill)

        let centerTick = SKShapeNode(rectOf: CGSize(width: 3, height: 18), cornerRadius: 1.5)
        centerTick.fillColor = Art.cream
        centerTick.strokeColor = .clear
        centerTick.position = CGPoint(x: windX, y: windY - 12)
        hudLayer.addChild(centerTick)

        // Bottom-Left: Turn Timer + Active Weapon Chip (bold small sprite)
        let blX = -halfW + safeX
        let blY = -halfH + safeY + 34

        timerBadge.path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 88, height: 72), cornerWidth: 18, cornerHeight: 18, transform: nil)
        timerBadge.fillColor = Art.inkDeep.withAlphaComponent(0.9)
        timerBadge.strokeColor = Art.cream.withAlphaComponent(0.25)
        timerBadge.lineWidth = 3
        timerBadge.position = CGPoint(x: blX, y: blY - 36)
        timerBadge.zPosition = -1
        hudLayer.addChild(timerBadge)

        timerLabel.fontSize = 36
        timerLabel.fontColor = Art.cream
        timerLabel.verticalAlignmentMode = .center
        timerLabel.position = CGPoint(x: blX + 44, y: blY)
        hudLayer.addChild(timerLabel)

        weaponChipBg.path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 340, height: 72), cornerWidth: 18, cornerHeight: 18, transform: nil)
        weaponChipBg.fillColor = Art.inkDeep.withAlphaComponent(0.9)
        weaponChipBg.lineWidth = 3
        weaponChipBg.position = CGPoint(x: blX + 100, y: blY - 36)
        weaponChipBg.zPosition = -1
        hudLayer.addChild(weaponChipBg)

        let chipDisc = SKShapeNode(circleOfRadius: 28)
        chipDisc.fillColor = Art.cream
        chipDisc.strokeColor = Art.ink
        chipDisc.lineWidth = 2
        chipDisc.position = CGPoint(x: blX + 138, y: blY)
        hudLayer.addChild(chipDisc)

        weaponChipIcon.position = CGPoint(x: blX + 138, y: blY)
        weaponChipIcon.zPosition = 1
        hudLayer.addChild(weaponChipIcon)

        weaponChipTitle.fontSize = 21
        weaponChipTitle.fontColor = Art.cream
        weaponChipTitle.horizontalAlignmentMode = .left
        weaponChipTitle.verticalAlignmentMode = .center
        weaponChipTitle.position = CGPoint(x: blX + 178, y: blY + 12)
        hudLayer.addChild(weaponChipTitle)

        weaponChipAmmo.fontSize = 15
        weaponChipAmmo.horizontalAlignmentMode = .left
        weaponChipAmmo.verticalAlignmentMode = .center
        weaponChipAmmo.position = CGPoint(x: blX + 178, y: blY - 13)
        hudLayer.addChild(weaponChipAmmo)

        // Bottom-Right: Control Hint Strip
        let hintBg = Art.panel(CGRect(x: -400, y: -21, width: 800, height: 42), radius: 21, fillAlpha: 0.78, stroke: Art.cream.withAlphaComponent(0.14), lineWidth: 1.6)
        hintBg.position = CGPoint(x: halfW - safeX - 400, y: blY - 12)
        hudLayer.addChild(hintBg)

        controlsHintLabel.fontSize = 15.5
        controlsHintLabel.fontColor = Art.cream.withAlphaComponent(0.95)
        controlsHintLabel.verticalAlignmentMode = .center
        controlsHintLabel.position = hintBg.position
        hudLayer.addChild(controlsHintLabel)

        // Top-Center: Turn Announcement Banner (cream ribbon with team-colored ink)
        turnBannerNode.position = CGPoint(x: 0, y: halfH - safeY - 60)
        turnBannerBg.path = CGPath(roundedRect: CGRect(x: -360, y: -46, width: 720, height: 92), cornerWidth: 24, cornerHeight: 24, transform: nil)
        turnBannerBg.fillColor = Art.cream
        turnBannerBg.lineWidth = 5
        turnBannerNode.addChild(turnBannerBg)
        let bannerShadow = SKShapeNode(path: CGPath(roundedRect: CGRect(x: -360, y: -53, width: 720, height: 92), cornerWidth: 24, cornerHeight: 24, transform: nil))
        bannerShadow.fillColor = Art.ink.withAlphaComponent(0.45)
        bannerShadow.strokeColor = .clear
        bannerShadow.zPosition = -1
        turnBannerNode.addChild(bannerShadow)

        turnBannerTitle.fontSize = 28
        turnBannerTitle.fontColor = Art.ink
        turnBannerTitle.verticalAlignmentMode = .center
        turnBannerTitle.position = CGPoint(x: 0, y: 13)
        turnBannerTitle.zPosition = 1
        turnBannerNode.addChild(turnBannerTitle)

        turnBannerSubtitle.fontSize = 18
        turnBannerSubtitle.fontColor = Art.inkSoft
        turnBannerSubtitle.verticalAlignmentMode = .center
        turnBannerSubtitle.position = CGPoint(x: 0, y: -19)
        turnBannerSubtitle.zPosition = 1
        turnBannerNode.addChild(turnBannerSubtitle)
        hudLayer.addChild(turnBannerNode)

        // Top-Center Persistent Status Pill (Shotgun 2nd shot / Dynamite retreat)
        statusPillNode.position = CGPoint(x: 0, y: halfH - safeY - 34)
        statusPillBg.path = CGPath(roundedRect: CGRect(x: -290, y: -24, width: 580, height: 48), cornerWidth: 24, cornerHeight: 24, transform: nil)
        statusPillBg.strokeColor = Art.ink
        statusPillBg.lineWidth = 4
        statusPillNode.addChild(statusPillBg)

        statusPillLabel.fontSize = 20
        statusPillLabel.fontColor = Art.cream
        statusPillLabel.verticalAlignmentMode = .center
        statusPillLabel.zPosition = 1
        statusPillNode.addChild(statusPillLabel)
        statusPillNode.isHidden = true
        hudLayer.addChild(statusPillNode)
    }

    // MARK: - 2×5 Painted Weapon Drawer (large Painter icons)

    private func buildWeaponBar() {
        weaponBarContainer.position = CGPoint(x: 0, y: -28)
        weaponBarContainer.zPosition = 130
        weaponBarContainer.isHidden = true

        let backdrop = Art.panel(CGRect(x: -580, y: -250, width: 1160, height: 500), radius: 36, fillAlpha: 0.96, stroke: Art.cream.withAlphaComponent(0.28), lineWidth: 3)
        weaponBarContainer.addChild(backdrop)

        // Header ribbon
        let ribbon = SKShapeNode(rectOf: CGSize(width: 340, height: 50), cornerRadius: 25)
        ribbon.fillColor = Art.sun
        ribbon.strokeColor = Art.ink
        ribbon.lineWidth = 4
        ribbon.position = CGPoint(x: 0, y: 250)
        weaponBarContainer.addChild(ribbon)

        let header = Art.label(24, .black, color: Art.ink)
        header.text = "WAFFENKAMMER"
        header.verticalAlignmentMode = .center
        header.position = CGPoint(x: 0, y: 250)
        weaponBarContainer.addChild(header)

        weaponBarSlots.removeAll()
        let weapons = WeaponKind.allCases
        let cols = 5
        let cardW: CGFloat = 200
        let cardH: CGFloat = 164
        let gapX: CGFloat = 18
        let totalW = CGFloat(cols) * cardW + CGFloat(cols - 1) * gapX
        let startX = -totalW * 0.5 + cardW * 0.5
        let rowY: [CGFloat] = [104, -76]

        for (i, weapon) in weapons.enumerated() {
            let row = i / cols
            let col = i % cols
            let x = startX + CGFloat(col) * (cardW + gapX)
            let y = rowY[min(row, rowY.count - 1)]

            let slotBg = SKShapeNode(rectOf: CGSize(width: cardW, height: cardH), cornerRadius: 22)
            slotBg.fillColor = Art.inkSoft
            slotBg.lineWidth = 3
            slotBg.position = CGPoint(x: x, y: y)
            weaponBarContainer.addChild(slotBg)

            // Cream "paper" medallion behind the painted icon
            let medallion = SKShapeNode(circleOfRadius: 46)
            medallion.fillColor = Art.cream.withAlphaComponent(0.16)
            medallion.strokeColor = weapon.accentColor.withAlphaComponent(0.55)
            medallion.lineWidth = 2.5
            medallion.position = CGPoint(x: 0, y: 14)
            slotBg.addChild(medallion)

            let icon = SKSpriteNode(imageNamed: weapon.iconName)
            let iconScale = 92 / max(icon.size.width, icon.size.height)
            icon.setScale(iconScale)
            icon.position = CGPoint(x: 0, y: 14)
            slotBg.addChild(icon)

            // Feature tag pill (top-left), e.g. "2 SCHÜSSE", "HÜPFT!", "WEGRENNEN!"
            let tagW = CGFloat(weapon.tagBadge.count) * 6.6 + 16
            let tagBg = SKShapeNode(rectOf: CGSize(width: tagW, height: 22), cornerRadius: 11)
            tagBg.fillColor = weapon == .shotgun ? Art.sun : weapon.accentColor
            tagBg.strokeColor = Art.ink
            tagBg.lineWidth = 2
            tagBg.position = CGPoint(x: -cardW * 0.5 + tagW * 0.5 + 8, y: cardH * 0.5 - 16)
            slotBg.addChild(tagBg)

            let tagLabel = Art.label(10.5, .black, color: Art.ink)
            tagLabel.text = weapon.tagBadge
            tagLabel.verticalAlignmentMode = .center
            tagBg.addChild(tagLabel)

            // Ammo pill (top-right)
            let ammoBg = SKShapeNode(rectOf: CGSize(width: 40, height: 24), cornerRadius: 12)
            ammoBg.fillColor = Art.inkDeep
            ammoBg.strokeColor = Art.cream.withAlphaComponent(0.4)
            ammoBg.lineWidth = 1.5
            ammoBg.position = CGPoint(x: cardW * 0.5 - 28, y: cardH * 0.5 - 17)
            slotBg.addChild(ammoBg)

            let ammo = Art.label(14, .heavy)
            ammo.text = "∞"
            ammo.verticalAlignmentMode = .center
            ammoBg.addChild(ammo)

            let title = Art.label(17, .heavy)
            title.text = weapon.name
            title.verticalAlignmentMode = .center
            title.position = CGPoint(x: 0, y: -56)
            slotBg.addChild(title)

            weaponBarSlots.append((slotBg, ammo, weapon))
        }

        // Bottom info strip for the highlighted weapon
        weaponBarSelectedTitle.fontSize = 21
        weaponBarSelectedTitle.fontColor = Art.sun
        weaponBarSelectedTitle.verticalAlignmentMode = .center
        weaponBarSelectedTitle.position = CGPoint(x: 0, y: -188)
        weaponBarContainer.addChild(weaponBarSelectedTitle)

        weaponBarHintLabel.fontSize = 17
        weaponBarHintLabel.fontColor = Art.cream.withAlphaComponent(0.92)
        weaponBarHintLabel.verticalAlignmentMode = .center
        weaponBarHintLabel.position = CGPoint(x: 0, y: -216)
        weaponBarContainer.addChild(weaponBarHintLabel)

        hudLayer.addChild(weaponBarContainer)
    }

    // MARK: - Frame Loop

    override func update(_ currentTime: TimeInterval) {
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }
        let dt = min(0.05, max(0, currentTime - lastUpdateTime))
        lastUpdateTime = currentTime

        guard !isGameplayPaused else { return }

        elapsedTime += dt

        var input = inputProvider?() ?? InputSnapshot()
        if input.pausePressed {
            isGameplayPaused = true
            gameDelegate?.gameSceneDidRequestPause()
            return
        }

        engine.update(dt: dt, input: &input)
        handleEngineEvents(engine.drainEvents())

        syncTerrainTextureIfNeeded()
        updateEnvironment(dt: dt)
        syncWorms()
        syncProjectiles()
        syncCrates()
        updateAimingAndOverlays()
        updateCamera(dt: dt)
        updateHUD()
    }

    private func syncTerrainTextureIfNeeded() {
        guard renderedTerrainRevision != engine.terrain.revision else { return }
        renderedTerrainRevision = engine.terrain.revision
        let tex = engine.terrain.makeTexture()
        terrainSprite.texture = tex
        for ink in terrainInkLayers { ink.texture = tex }
        terrainPaintMask.texture = tex
        pruneDestroyedProps()
    }

    private func updateEnvironment(dt: TimeInterval) {
        for item in twinklingStars {
            let tw = 0.45 + 0.55 * sin(elapsedTime * 2.2 + item.phase)
            item.node.alpha = CGFloat(tw)
        }

        let baseDrift = engine.wind * 75 + (engine.wind >= 0 ? 14 : -14)
        for item in clouds {
            item.node.position.x += baseDrift * item.speedFactor * CGFloat(dt)
            if item.node.position.x > WorldConstants.width + 200 {
                item.node.position.x = -200
            } else if item.node.position.x < -200 {
                item.node.position.x = WorldConstants.width + 200
            }
        }

        for bird in skyBirds {
            bird.node.position.x += bird.speed * CGFloat(dt)
            bird.node.position.y += CGFloat(sin(elapsedTime * 3.8 + bird.phase) * 14.0 * dt)
            bird.node.yScale = CGFloat(0.75 + 0.35 * sin(elapsedTime * 6.5 + bird.phase))
            if bird.node.position.x > WorldConstants.width + 80 {
                bird.node.position.x = -80
            }
        }

        for mote in windMotes {
            mote.position.x += (engine.wind * 230) * CGFloat(dt)
            mote.position.y -= 18 * CGFloat(dt)
            if mote.position.x > WorldConstants.width + 20 { mote.position.x = -20 }
            if mote.position.x < -20 { mote.position.x = WorldConstants.width + 20 }
            if mote.position.y < engine.waterY { mote.position.y = WorldConstants.height - 20 }
        }

        updateWaterWave(node: waterBackWave, baseY: engine.waterY + 8, phase: elapsedTime * 1.9, amp: 6.0, color: engine.config.mapTheme.waterColor.withAlphaComponent(0.55))
        updateWaterWave(node: waterFrontWave, baseY: engine.waterY, phase: elapsedTime * 2.7 + 1.4, amp: 7.5, color: engine.config.mapTheme.waterColor)
    }

    private func updateWaterWave(node: SKShapeNode, baseY: CGFloat, phase: TimeInterval, amp: CGFloat, color: SKColor) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -160, y: -160))
        let step: CGFloat = 56
        var x: CGFloat = -160
        while x <= WorldConstants.width + 180 {
            let y = baseY + sin(x * 0.014 + CGFloat(phase)) * amp
            p.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        p.addLine(to: CGPoint(x: WorldConstants.width + 180, y: -160))
        p.closeSubpath()
        node.path = p
        node.fillColor = color
        node.strokeColor = Art.cream.withAlphaComponent(node === waterFrontWave ? 0.85 : 0.4)
        node.lineWidth = node === waterFrontWave ? 4 : 3
    }

    // MARK: - Entity Synchronization

    private func syncWorms() {
        for worm in engine.worms {
            guard let node = wormNodes[worm.id] else { continue }
            let isActive = (worm.id == engine.activeWormID)
            node.sync(with: worm, isActive: isActive, weapon: engine.selectedWeapon, time: elapsedTime)
        }
    }

    private func syncProjectiles() {
        let activeIDs = Set(engine.projectiles.map(\.id))

        for (id, node) in projectileNodes where !activeIDs.contains(id) {
            node.removeFromParent()
            projectileNodes.removeValue(forKey: id)
        }

        for proj in engine.projectiles {
            let node: SKNode
            if let existing = projectileNodes[proj.id] {
                node = existing
            } else {
                node = makeProjectileNode(for: proj)
                entityLayer.addChild(node)
                projectileNodes[proj.id] = node
            }
            node.position = proj.position
            if let body = node.childNode(withName: "body") {
                if proj.weapon == .sheep {
                    body.xScale = proj.sheepDirection >= 0 ? 1 : -1
                    body.zRotation = CGFloat(sin(elapsedTime * 14.0) * 0.14)
                } else if proj.weapon == .dynamite {
                    let pulse = 1.0 + CGFloat(sin(elapsedTime * 18.0) * 0.08)
                    body.setScale(pulse)
                } else {
                    body.zRotation = proj.rotation
                }
            }
            if let fuse = proj.fuseRemaining, let label = node.childNode(withName: "fuseLabel") as? SKLabelNode {
                let sec = max(1, Int(ceil(fuse)))
                label.text = "\(sec)"
                label.fontColor = fuse < 1.0 ? Art.coral : Art.cream
            }
            if (proj.weapon == .bazooka || proj.weapon == .airstrike || (proj.weapon == .clusterBomb && proj.isSubmunition)) && Int(elapsedTime * 60) % 2 == 0 {
                spawnSmokePuff(at: proj.position, radius: proj.isSubmunition ? 4 : 6, alpha: 0.52)
            } else if proj.weapon == .dynamite && Int(elapsedTime * 60) % 5 == 0 {
                spawnSmokePuff(at: CGPoint(x: proj.position.x, y: proj.position.y + 18), radius: 4, alpha: 0.65)
            }
        }
    }

    private func makeProjectileNode(for proj: ProjectileState) -> SKNode {
        let root = SKNode()
        let body = SKNode()
        body.name = "body"

        // Flying projectiles use the bold small sprites plus a soft cream halo so
        // they always separate from sky, terrain and water.
        func sprite(_ name: String, maxSide: CGFloat) -> SKSpriteNode {
            let s = SKSpriteNode(imageNamed: name)
            s.setScale(maxSide / max(1, max(s.size.width, s.size.height)))
            return s
        }

        switch proj.weapon {
        case .bazooka, .airstrike:
            let rocket = sprite("proj_rocket", maxSide: proj.weapon == .airstrike ? 38 : 42)
            if proj.weapon == .airstrike {
                rocket.color = Art.sky
                rocket.colorBlendFactor = 0.45
            }
            body.addChild(rocket)

        case .grenade, .clusterBomb, .holyGrenade, .bananaBomb, .dynamite:
            let sz: CGFloat = proj.isSubmunition ? 24 : (proj.weapon == .dynamite ? 40 : (proj.weapon == .holyGrenade ? 38 : 34))
            let halo = SKShapeNode(circleOfRadius: sz * 0.55)
            halo.fillColor = Art.cream.withAlphaComponent(0.28)
            halo.strokeColor = .clear
            root.addChild(halo)
            body.addChild(sprite(proj.weapon.smallIconName, maxSide: sz))

        case .sheep:
            body.addChild(sprite(WeaponKind.sheep.smallIconName, maxSide: 50))

        case .shotgun, .firePunch:
            break
        }

        root.addChild(body)

        if proj.fuseRemaining != nil {
            let fuseBg = SKShapeNode(circleOfRadius: 13)
            fuseBg.fillColor = Art.inkDeep
            fuseBg.strokeColor = Art.cream
            fuseBg.lineWidth = 2
            fuseBg.position = CGPoint(x: 0, y: 34)
            root.addChild(fuseBg)

            let fuseLabel = Art.label(17, .black)
            fuseLabel.name = "fuseLabel"
            fuseLabel.verticalAlignmentMode = .center
            fuseLabel.position = CGPoint(x: 0, y: 34)
            root.addChild(fuseLabel)
        }

        return root
    }

    private func syncCrates() {
        let activeIDs = Set(engine.crates.map(\.id))
        for (id, node) in crateNodes where !activeIDs.contains(id) {
            node.removeFromParent()
            crateNodes.removeValue(forKey: id)
        }

        for crate in engine.crates {
            let node: SKNode
            if let existing = crateNodes[crate.id] {
                node = existing
            } else {
                node = makeCrateNode(for: crate)
                entityLayer.addChild(node)
                crateNodes[crate.id] = node
            }
            node.position = crate.position
            if let chute = node.childNode(withName: "chute") {
                chute.isHidden = !crate.isParachuting
                if crate.isParachuting {
                    node.zRotation = CGFloat(sin(elapsedTime * 3.2 + Double(crate.id)) * 0.12)
                } else {
                    node.zRotation = 0
                }
            }
        }
    }

    private func makeCrateNode(for crate: CrateState) -> SKNode {
        let root = SKNode()

        // Striped coral/cream parachute with plum ink, matching the painted crates
        let chute = SKNode()
        chute.name = "chute"
        let canopyPath: CGPath = {
            let p = CGMutablePath()
            p.addArc(center: CGPoint(x: 0, y: 42), radius: 32, startAngle: 0, endAngle: .pi, clockwise: false)
            p.addQuadCurve(to: CGPoint(x: 32, y: 42), control: CGPoint(x: 0, y: 32))
            p.closeSubpath()
            return p
        }()
        let canopy = SKShapeNode(path: canopyPath)
        canopy.fillColor = Art.cream
        canopy.strokeColor = Art.ink
        canopy.lineWidth = 3
        chute.addChild(canopy)
        let stripe = SKShapeNode(path: {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -9, y: 38))
            p.addLine(to: CGPoint(x: -6, y: 73))
            p.addLine(to: CGPoint(x: 6, y: 73))
            p.addLine(to: CGPoint(x: 9, y: 38))
            p.closeSubpath()
            return p
        }())
        stripe.fillColor = Art.coral
        stripe.strokeColor = .clear
        stripe.zPosition = 0.1
        chute.addChild(stripe)
        let canopyInk = SKShapeNode(path: canopyPath)
        canopyInk.fillColor = .clear
        canopyInk.strokeColor = Art.ink
        canopyInk.lineWidth = 3
        canopyInk.zPosition = 0.2
        chute.addChild(canopyInk)

        let strings = SKShapeNode(path: {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -30, y: 40)); p.addLine(to: CGPoint(x: -12, y: 16))
            p.move(to: CGPoint(x: 30, y: 40)); p.addLine(to: CGPoint(x: 12, y: 16))
            p.move(to: CGPoint(x: 0, y: 36)); p.addLine(to: CGPoint(x: 0, y: 18))
            return p
        }())
        strings.strokeColor = Art.ink.withAlphaComponent(0.8)
        strings.lineWidth = 1.8
        chute.addChild(strings)
        root.addChild(chute)

        let isHealth: Bool
        if case .health = crate.kind { isHealth = true } else { isHealth = false }

        let sprite = SKSpriteNode(imageNamed: isHealth ? "crate_med" : "crate_weapon")
        sprite.setScale(40 / max(1, sprite.size.height))
        sprite.zPosition = 0.5
        root.addChild(sprite)

        return root
    }

    private func updateAimingAndOverlays() {
        let weaponUsesAim: Bool
        switch engine.selectedWeapon {
        case .bazooka, .grenade, .clusterBomb, .shotgun, .holyGrenade, .bananaBomb:
            weaponUsesAim = true
        case .airstrike, .sheep, .firePunch, .dynamite:
            weaponUsesAim = false
        }

        let showAim: Bool
        switch engine.phase {
        case .playerControl, .charging:
            showAim = !engine.isWeaponBarOpen && weaponUsesAim
        default:
            showAim = false
        }

        if showAim, let worm = engine.activeWorm, worm.isAlive {
            aimCrosshair.isHidden = false
            let dir = worm.aimDirection
            let dist: CGFloat = 86
            aimCrosshair.position = CGPoint(x: worm.position.x + dir.dx * dist, y: worm.position.y + 4 + dir.dy * dist)
            aimCrosshair.zRotation = CGFloat(elapsedTime * 1.4)

            for (idx, dot) in aimDots.enumerated() {
                let frac = CGFloat(idx + 1) / CGFloat(aimDots.count + 1)
                dot.isHidden = false
                dot.position = CGPoint(x: worm.position.x + dir.dx * dist * frac, y: worm.position.y + 4 + dir.dy * dist * frac)
            }
        } else {
            aimCrosshair.isHidden = true
            for dot in aimDots { dot.isHidden = true }
        }

        if case .charging(let power) = engine.phase, let worm = engine.activeWorm, worm.isAlive {
            powerMeterNode.isHidden = false
            powerMeterNode.position = CGPoint(x: worm.position.x, y: worm.position.y + 4)
            powerMeterNode.zRotation = worm.worldAimAngle

            let length = 26 + power * 108
            let tipHalfH = 4.0 + power * 11.0
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 20, y: -3.5))
            path.addLine(to: CGPoint(x: 20 + length, y: -tipHalfH))
            path.addLine(to: CGPoint(x: 20 + length, y: tipHalfH))
            path.addLine(to: CGPoint(x: 20, y: 3.5))
            path.closeSubpath()
            powerMeterFill.path = path
            // Leaf → sunflower → coral as the charge builds, outlined in plum ink
            let low = power < 0.5 ? Art.leaf : Art.sun
            let high = power < 0.5 ? Art.sun : Art.coral
            let t = power < 0.5 ? power * 2 : (power - 0.5) * 2
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            low.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            high.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            powerMeterFill.fillColor = SKColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
            powerMeterFill.strokeColor = Art.ink
            powerMeterFill.lineWidth = 3.4
        } else {
            powerMeterNode.isHidden = true
        }

        if case .airstrikeAiming(let targetX) = engine.phase {
            airstrikeOverlay.isHidden = false
            let groundY = engine.terrain.surfaceY(atWorldX: targetX) ?? engine.waterY
            let beamPath = CGMutablePath()
            beamPath.move(to: CGPoint(x: targetX, y: WorldConstants.height))
            beamPath.addLine(to: CGPoint(x: targetX, y: groundY))
            airstrikeBeam.path = beamPath
            airstrikeReticle.position = CGPoint(x: targetX, y: max(groundY, engine.waterY + 24))
            airstrikeReticle.setScale(1.0 + CGFloat(sin(elapsedTime * 8.0) * 0.10))
        } else {
            airstrikeOverlay.isHidden = true
        }
    }

    // MARK: - Smooth Camera Panning & Zoom Across 2880 × 1500 World

    private func clampedCameraPosition(for target: CGPoint, scale: CGFloat) -> CGPoint {
        let halfVisibleW = (WorldConstants.viewportWidth * scale) * 0.5
        let halfVisibleH = (WorldConstants.viewportHeight * scale) * 0.5
        let minX = min(WorldConstants.width * 0.5, halfVisibleW)
        let maxX = max(WorldConstants.width * 0.5, WorldConstants.width - halfVisibleW)
        let minY = min(WorldConstants.height * 0.5, halfVisibleH)
        let maxY = max(WorldConstants.height * 0.5, WorldConstants.height - halfVisibleH)
        return CGPoint(
            x: max(minX, min(maxX, target.x)),
            y: max(minY, min(maxY, target.y))
        )
    }

    private func updateCamera(dt: TimeInterval) {
        var target = CGPoint(x: WorldConstants.width * 0.5, y: WorldConstants.height * 0.45)
        var targetScale: CGFloat = 1.04

        switch engine.phase {
        case .projectileInFlight:
            if let proj = engine.projectiles.first {
                target = proj.position
                targetScale = 1.08
            }
        case .airstrikeAiming(let targetX):
            target = CGPoint(x: targetX, y: WorldConstants.height * 0.48)
            targetScale = 1.36 // Wide dramatic overview of the 50% larger world!
        case .retreat:
            if let worm = engine.activeWorm {
                target = worm.position
                targetScale = 1.02
            }
        case .settling:
            if let exp = engine.lastExplosionPoint {
                target = exp
                targetScale = 1.08
            } else if let worm = engine.activeWorm {
                target = worm.position
                targetScale = 1.04
            }
        default:
            if let worm = engine.activeWorm, worm.isAlive {
                target = worm.position
                targetScale = engine.isWeaponBarOpen ? 1.15 : 1.02
            }
        }

        let lerp = min(1.0, CGFloat(dt) * 4.5)
        let newScale = hudCamera.xScale + (targetScale - hudCamera.xScale) * lerp
        hudCamera.setScale(newScale)

        let clampedTarget = clampedCameraPosition(for: target, scale: newScale)
        var camPos = CGPoint(
            x: hudCamera.position.x + (clampedTarget.x - hudCamera.position.x) * lerp,
            y: hudCamera.position.y + (clampedTarget.y - hudCamera.position.y) * lerp
        )

        if shakeIntensity > 0.5 {
            camPos.x += CGFloat.random(in: -shakeIntensity...shakeIntensity)
            camPos.y += CGFloat.random(in: -shakeIntensity...shakeIntensity)
            shakeIntensity *= pow(0.02, CGFloat(dt))
        } else {
            shakeIntensity = 0
        }

        hudCamera.position = camPos
    }

    // MARK: - HUD Refresh (German + Clear Multi-Shot & Retreat)

    private func updateHUD() {
        for (idx, item) in teamScoreBars.enumerated() {
            let hp = engine.teamHealthTotal(idx)
            item.hpLabel.text = "\(hp)"
            let frac = max(0, min(1, CGFloat(hp) / CGFloat(max(1, item.maxHP))))
            let barW = max(0, 286 * frac)
            item.fill.path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: barW, height: 8), cornerWidth: 4, cornerHeight: 4, transform: nil)
            let isCurrent = (idx == engine.currentTeamIndex)
            item.bg.lineWidth = isCurrent ? 4 : 1.6
            item.bg.alpha = hp > 0 ? 1.0 : 0.42
        }

        // Timer (shows retreat countdown while fleeing Dynamite!)
        let displaySecs: Int
        let urgent: Bool
        if case .retreat(let rem) = engine.phase {
            displaySecs = max(1, Int(ceil(rem)))
            urgent = true
        } else {
            displaySecs = max(0, Int(ceil(engine.turnTimeRemaining)))
            urgent = displaySecs <= 5 && engine.phase == .playerControl
        }
        timerLabel.text = "\(displaySecs)"
        timerLabel.fontColor = urgent ? Art.coral : Art.cream
        timerBadge.strokeColor = urgent ? Art.coral : Art.cream.withAlphaComponent(0.25)

        // Active Weapon Chip with Painter Icon & Clear Multi-Shot Pips
        let w = engine.selectedWeapon
        if lastChipWeapon != w {
            let tex = SKTexture(imageNamed: w.smallIconName)
            weaponChipIcon.texture = tex
            let s = 46 / max(tex.size().width, tex.size().height)
            weaponChipIcon.size = CGSize(width: tex.size().width * s, height: tex.size().height * s)
            lastChipWeapon = w
        }
        weaponChipTitle.text = w.name
        weaponChipBg.strokeColor = w.accentColor.withAlphaComponent(0.88)

        if w == .shotgun {
            if engine.shotgunShotsRemaining == 1 {
                weaponChipAmmo.text = "● ○  Noch 1 Schuss!"
                weaponChipAmmo.fontColor = Art.sun
            } else {
                weaponChipAmmo.text = "● ●  2 Schüsse pro Zug"
                weaponChipAmmo.fontColor = Art.cream.withAlphaComponent(0.85)
            }
        } else if let ammo = engine.currentTeam.ammoCount(for: w) {
            weaponChipAmmo.text = "Vorrat: ×\(ammo) · \(w.tagBadge)"
            weaponChipAmmo.fontColor = Art.cream.withAlphaComponent(0.85)
        } else {
            weaponChipAmmo.text = "Vorrat: ∞ · \(w.tagBadge)"
            weaponChipAmmo.fontColor = Art.cream.withAlphaComponent(0.85)
        }

        // Wind gauge
        let windPct = Int(round(abs(engine.wind) * 100))
        if windPct < 4 {
            windTextLabel.text = "WINDSTILLE •"
        } else {
            let arrow = engine.wind > 0 ? "→" : "←"
            windTextLabel.text = "WIND \(windPct)% \(arrow)"
        }
        let fillW = abs(engine.wind) * 112
        let fillX = engine.wind >= 0 ? 0 : -fillW
        windBarFill.path = CGPath(roundedRect: CGRect(x: fillX, y: -6, width: fillW, height: 12), cornerWidth: 6, cornerHeight: 6, transform: nil)
        windBarFill.fillColor = engine.wind >= 0 ? Art.lagoon : Art.sun

        // Turn Banner
        if case .turnBanner = engine.phase {
            turnBannerNode.isHidden = false
            let desc = engine.currentTeam.descriptor
            turnBannerBg.strokeColor = desc.color
            turnBannerTitle.text = "SPIELER \(desc.index + 1) – \(desc.name.uppercased())"
            let wormName = engine.activeWorm?.name ?? ""
            turnBannerSubtitle.text = "\(wormName) ist dran · Fernbedienung weitergeben!"
        } else {
            turnBannerNode.isHidden = true
        }

        // Persistent Status Pill for Multi-Shot Shotgun or Dynamite Retreat!
        if case .retreat(let rem) = engine.phase {
            statusPillNode.isHidden = false
            statusPillBg.fillColor = Art.coral
            statusPillLabel.text = "DYNAMIT TICKT! SCHNELL WEGRENNEN! (\(max(1, Int(ceil(rem))))s)"
        } else if engine.shotgunShotsRemaining == 1 && engine.phase == .playerControl {
            statusPillNode.isHidden = false
            statusPillBg.fillColor = SKColor(red: 0.93, green: 0.55, blue: 0.20, alpha: 1)
            statusPillLabel.text = "SCHROTFLINTE · NOCH 1 SCHUSS ÜBRIG! (● ○)"
        } else {
            statusPillNode.isHidden = true
        }

        // 2×5 Illustrated Weapon Drawer
        weaponBarContainer.isHidden = !engine.isWeaponBarOpen
        if engine.isWeaponBarOpen {
            for (i, slot) in weaponBarSlots.enumerated() {
                let isSelected = (i == engine.weaponBarSelectionIndex)
                let canUse = engine.currentTeam.canUse(slot.kind)
                slot.bg.lineWidth = isSelected ? 6 : 2.5
                slot.bg.strokeColor = isSelected ? Art.sun : Art.ink
                slot.bg.fillColor = isSelected ? slot.kind.accentColor.withAlphaComponent(0.42) : Art.inkSoft
                slot.bg.setScale(isSelected ? 1.06 : 1.0)
                slot.bg.zPosition = isSelected ? 5 : 1
                slot.bg.alpha = canUse ? 1.0 : 0.34
                if let count = engine.currentTeam.ammoCount(for: slot.kind) {
                    slot.ammoLabel.text = "×\(count)"
                } else {
                    slot.ammoLabel.text = "∞"
                }
            }
            let highlighted = WeaponKind.allCases[engine.weaponBarSelectionIndex]
            weaponBarSelectedTitle.text = "\(highlighted.name.uppercased())  ·  \(highlighted.tagBadge)"
            weaponBarHintLabel.text = highlighted.hint
        }

        // Context-sensitive Controls Hint
        if engine.isWeaponBarOpen {
            controlsHintLabel.text = "← → ↑ ↓ Waffe wählen  ·  Auswahl drücken: Nehmen  ·  Play/Pause: Schließen"
        } else if case .airstrikeAiming = engine.phase {
            controlsHintLabel.text = "← / → Ziel verschieben  ·  Auswahl drücken: 5 Raketen rufen!  ·  Play/Pause: Abbruch"
        } else if case .retreat = engine.phase {
            controlsHintLabel.text = "← / → Schnell wegrennen!  ·  2×↑ Hüpfen!"
        } else if case .projectileInFlight = engine.phase, engine.projectiles.contains(where: { $0.weapon == .sheep }) {
            controlsHintLabel.text = "Super-Schaf läuft!  ·  Auswahl drücken für Sofort-Knall!"
        } else if isGameControllerConnected {
            controlsHintLabel.text = "Stick/Kreuz: Laufen & Zielen  ·  R2/X: Schießen  ·  A: Hüpfen  ·  B: Salto  ·  L1/R1/Y: Waffen"
        } else {
            controlsHintLabel.text = "Klicken: ←/→ Laufen · ↑/↓ Zielen · Auswahl halten: Schießen · 2×↑ Hüpfen · Play/Pause: Waffen"
        }
    }

    // MARK: - VFX & Audio Event Handling

    private func handleEngineEvents(_ events: [GameEvent]) {
        for event in events {
            switch event {
            case .explosion(let center, let radius, let isHoly):
                spawnExplosionFX(at: center, radius: radius, isHoly: isHoly)
                shakeIntensity = max(shakeIntensity, isHoly ? 32 : radius * 0.24)
                SoundEngine.shared.play(isHoly ? .holyExplosion : .explosion)

            case .shotgunTracer(let from, let to):
                spawnShotgunTracer(from: from, to: to)

            case .shotgunSecondShotReady(let pos):
                spawnFloatingText("NOCH 1 SCHUSS!", at: CGPoint(x: pos.x, y: pos.y + 52), color: SKColor(red: 1.0, green: 0.86, blue: 0.30, alpha: 1), fontSize: 28)

            case .firePunchBurst(let pos, _):
                spawnExplosionFX(at: pos, radius: 52, isHoly: false)
                spawnSparkleBurst(at: pos, color: SKColor(red: 1.0, green: 0.45, blue: 0.14, alpha: 1))
                spawnFloatingText("FEUERFAUST!", at: CGPoint(x: pos.x, y: pos.y + 42), color: SKColor(red: 1.0, green: 0.62, blue: 0.18, alpha: 1), fontSize: 30)
                shakeIntensity = max(shakeIntensity, 16)
                SoundEngine.shared.play(.firePunch)

            case .sheepBaa(let pos):
                spawnFloatingText("MÄH!!", at: CGPoint(x: pos.x, y: pos.y + 40), color: .white, fontSize: 28)
                SoundEngine.shared.play(.sheepBaa)

            case .dynamitePlaced(let pos):
                spawnFloatingText("LAUF WEG!", at: CGPoint(x: pos.x, y: pos.y + 46), color: SKColor(red: 1.0, green: 0.34, blue: 0.28, alpha: 1), fontSize: 30)
                SoundEngine.shared.play(.dynamitePlace)

            case .wormDamaged(_, let amount, let pos):
                spawnFloatingText("-\(amount)", at: CGPoint(x: pos.x, y: pos.y + 40), color: SKColor(red: 1.0, green: 0.36, blue: 0.32, alpha: 1), fontSize: 30)
                SoundEngine.shared.play(.hurt)

            case .wormDrowned(let wormID, let pos):
                spawnWaterSplash(at: pos)
                if wormID > 0 {
                    spawnFloatingText("PLATSCH!", at: CGPoint(x: pos.x, y: pos.y + 46), color: SKColor(red: 0.48, green: 0.90, blue: 1.0, alpha: 1), fontSize: 28)
                }
                SoundEngine.shared.play(.splash)

            case .wormJumped(let pos, _):
                spawnSmokePuff(at: CGPoint(x: pos.x, y: pos.y - 12), radius: 8, alpha: 0.45)
                SoundEngine.shared.play(.jump)

            case .projectileFired(let weapon, let pos):
                spawnSmokePuff(at: pos, radius: 13, alpha: 0.72)
                SoundEngine.shared.play(weapon == .shotgun ? .shotgun : .bazookaFire)

            case .grenadeBounce:
                SoundEngine.shared.play(.grenadeBounce)

            case .crateCollected(let pos, let label, let isHealth):
                let col = isHealth ? SKColor(red: 0.34, green: 0.96, blue: 0.56, alpha: 1) : SKColor(red: 1.0, green: 0.88, blue: 0.30, alpha: 1)
                spawnSparkleBurst(at: pos, color: col)
                spawnFloatingText(label, at: CGPoint(x: pos.x, y: pos.y + 28), color: col, fontSize: 26)
                SoundEngine.shared.play(.cratePickup)

            case .turnStarted:
                SoundEngine.shared.play(.turnStart)

            case .suddenDeathTriggered:
                spawnFloatingText("WASSER STEIGT!", at: CGPoint(x: WorldConstants.width * 0.5, y: WorldConstants.height * 0.65), color: SKColor(red: 1.0, green: 0.38, blue: 0.34, alpha: 1), fontSize: 44)

            case .holyChoir(let pos):
                spawnSparkleBurst(at: pos, color: SKColor(red: 1.0, green: 0.92, blue: 0.34, alpha: 1))
                spawnFloatingText("HALLELUJA!", at: CGPoint(x: pos.x, y: pos.y + 48), color: SKColor(red: 1.0, green: 0.92, blue: 0.34, alpha: 1), fontSize: 38)
                SoundEngine.shared.play(.holyChoir)

            case .matchEnded(let winnerTeamIndex):
                SoundEngine.shared.play(.victory)
                if !didNotifyMatchEnd {
                    didNotifyMatchEnd = true
                    gameDelegate?.gameSceneDidFinishMatch(winnerTeamIndex: winnerTeamIndex, teams: engine.teams)
                }
            }
        }
    }

    private func spawnSparkleBurst(at center: CGPoint, color: SKColor) {
        let colors = [color, Art.cream, Art.sun]
        for i in 0..<14 {
            let star = SKShapeNode(path: sparklePath(radius: CGFloat.random(in: 6...10)))
            star.fillColor = colors[i % colors.count]
            star.strokeColor = .clear
            star.position = center
            fxLayer.addChild(star)
            let angle = CGFloat(i) / 14.0 * .pi * 2 + CGFloat.random(in: -0.2...0.2)
            let dist = CGFloat.random(in: 38...88)
            star.run(.sequence([
                .group([
                    .moveBy(x: cos(angle) * dist, y: sin(angle) * dist + 20, duration: 0.52),
                    .scale(to: 0.2, duration: 0.52),
                    .fadeOut(withDuration: 0.52)
                ]),
                .removeFromParent()
            ]))
        }
    }

    private func spawnExplosionFX(at center: CGPoint, radius: CGFloat, isHoly: Bool) {
        let ring = SKShapeNode(circleOfRadius: radius * 0.3)
        ring.position = center
        ring.strokeColor = isHoly ? Art.sun : Art.cream
        ring.fillColor = .clear
        ring.lineWidth = isHoly ? 7 : 4.5
        fxLayer.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 3.6, duration: 0.32), .fadeOut(withDuration: 0.32)]),
            .removeFromParent()
        ]))

        let core = SKShapeNode(circleOfRadius: radius * 0.85)
        core.position = center
        core.fillColor = isHoly ? Art.sun : SKColor(red: 1.0, green: 0.58, blue: 0.22, alpha: 1)
        core.strokeColor = Art.ink
        core.lineWidth = 4
        fxLayer.addChild(core)
        core.run(.sequence([
            .group([.scale(to: 1.45, duration: 0.22), .fadeOut(withDuration: 0.26)]),
            .removeFromParent()
        ]))

        let smokeCount = isHoly ? 16 : 9
        for _ in 0..<smokeCount {
            let off = CGPoint(
                x: center.x + CGFloat.random(in: -radius * 0.55...radius * 0.55),
                y: center.y + CGFloat.random(in: -radius * 0.55...radius * 0.55)
            )
            spawnSmokePuff(at: off, radius: CGFloat.random(in: 14...28), alpha: 0.65)
        }

        let debrisCount = isHoly ? 28 : 16
        for _ in 0..<debrisCount {
            let chunk = SKShapeNode(circleOfRadius: CGFloat.random(in: 3...6.5))
            chunk.fillColor = Bool.random() ? Art.sun : SKColor(red: 0.55, green: 0.36, blue: 0.26, alpha: 1)
            chunk.strokeColor = Art.ink
            chunk.lineWidth = 1.5
            chunk.position = center
            fxLayer.addChild(chunk)

            let angle = CGFloat.random(in: 0...(.pi * 2))
            let dist = CGFloat.random(in: radius * 0.8...radius * 2.5)
            let dx = cos(angle) * dist
            let dy = sin(angle) * dist + 45
            let dur = TimeInterval.random(in: 0.35...0.70)
            chunk.run(.sequence([
                .group([
                    .moveBy(x: dx, y: dy, duration: dur),
                    .fadeOut(withDuration: dur)
                ]),
                .removeFromParent()
            ]))
        }
    }

    private func spawnSmokePuff(at point: CGPoint, radius: CGFloat, alpha: CGFloat) {
        let puff = SKShapeNode(circleOfRadius: radius)
        puff.position = point
        puff.fillColor = Art.cream.withAlphaComponent(alpha)
        puff.strokeColor = .clear
        fxLayer.addChild(puff)
        puff.run(.sequence([
            .group([
                .moveBy(x: engine.wind * 28, y: CGFloat.random(in: 22...48), duration: 0.55),
                .scale(to: 1.8, duration: 0.55),
                .fadeOut(withDuration: 0.55)
            ]),
            .removeFromParent()
        ]))
    }

    private func spawnShotgunTracer(from start: CGPoint, to end: CGPoint) {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        let line = SKShapeNode(path: path)
        line.strokeColor = Art.sun
        line.lineWidth = 4.2
        fxLayer.addChild(line)
        line.run(.sequence([
            .fadeOut(withDuration: 0.16),
            .removeFromParent()
        ]))
    }

    private func spawnWaterSplash(at point: CGPoint) {
        for _ in 0..<18 {
            let drop = SKShapeNode(circleOfRadius: CGFloat.random(in: 3.5...7.5))
            drop.fillColor = Art.cream.withAlphaComponent(0.92)
            drop.strokeColor = Art.lagoon
            drop.lineWidth = 1.5
            drop.position = point
            fxLayer.addChild(drop)
            let dx = CGFloat.random(in: -80...80)
            let dy = CGFloat.random(in: 50...155)
            drop.run(.sequence([
                .group([
                    .moveBy(x: dx, y: dy, duration: 0.36),
                    .fadeOut(withDuration: 0.48)
                ]),
                .removeFromParent()
            ]))
        }
    }

    private func spawnFloatingText(_ text: String, at point: CGPoint, color: SKColor, fontSize: CGFloat) {
        // Comic pop text: palette fill with a thick plum ink outline + drop shadow
        let label = SKLabelNode(attributedText: Art.outlinedText(text, size: fontSize, color: color))
        label.position = point

        let shadow = SKLabelNode(attributedText: Art.outlinedText(text, size: fontSize, color: Art.ink, outline: Art.ink))
        shadow.position = CGPoint(x: 0, y: -4)
        shadow.alpha = 0.55
        shadow.zPosition = -1
        label.addChild(shadow)

        label.setScale(0.6)
        label.run(.scale(to: 1.0, duration: 0.14))
        fxLayer.addChild(label)
        label.run(.sequence([
            .group([
                .moveBy(x: 0, y: 64, duration: 1.15),
                .sequence([.wait(forDuration: 0.60), .fadeOut(withDuration: 0.55)])
            ]),
            .removeFromParent()
        ]))
    }
}
