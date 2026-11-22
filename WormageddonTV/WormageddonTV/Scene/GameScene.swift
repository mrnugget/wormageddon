import SpriteKit

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
    private let timerLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let weaponChipBg = SKShapeNode()
    private let weaponChipIcon = SKSpriteNode()
    private let weaponChipTitle = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let weaponChipAmmo = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let windBarFill = SKShapeNode()
    private let windTextLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let turnBannerNode = SKNode()
    private let turnBannerBg = SKShapeNode()
    private let turnBannerTitle = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let turnBannerSubtitle = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let statusPillNode = SKNode()
    private let statusPillBg = SKShapeNode()
    private let statusPillLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let controlsHintLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")

    // 2×5 Illustrated Weapon Drawer Overlay
    private let weaponBarContainer = SKNode()
    private var weaponBarSlots: [(bg: SKShapeNode, ammoLabel: SKLabelNode, kind: WeaponKind)] = []
    private let weaponBarSelectedTitle = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let weaponBarHintLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")

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

        // Twinkling upper-sky stars
        twinklingStars.removeAll()
        if theme.showsStars {
            var rng = SeededRNG(seed: engine.config.seed ^ 0x51A4)
            for _ in 0..<72 {
                let r = rng.nextCGFloat(in: 1.4...3.0)
                let star = SKShapeNode(circleOfRadius: r)
                star.fillColor = SKColor(red: 1.0, green: 0.97, blue: 0.88, alpha: 0.88)
                star.strokeColor = .clear
                star.position = CGPoint(
                    x: rng.nextCGFloat(in: 60...(WorldConstants.width - 60)),
                    y: rng.nextCGFloat(in: (WorldConstants.height * 0.52)...(WorldConstants.height - 36))
                )
                star.zPosition = 1
                skyLayer.addChild(star)
                twinklingStars.append((star, rng.nextDouble() * .pi * 2))
            }
        }

        // Layered luminous sun / moon halo
        let sunPos = CGPoint(x: WorldConstants.width * 0.76, y: WorldConstants.height * 0.78)
        for (radius, alpha) in [(240, 0.07), (162, 0.13), (108, 0.22)] as [(CGFloat, CGFloat)] {
            let glow = SKShapeNode(circleOfRadius: radius)
            glow.fillColor = theme.sunColor.withAlphaComponent(alpha)
            glow.strokeColor = .clear
            glow.position = sunPos
            glow.zPosition = 1
            skyLayer.addChild(glow)
        }

        let sunDisc = SKShapeNode(circleOfRadius: 72)
        sunDisc.fillColor = theme.sunColor
        sunDisc.strokeColor = .clear
        sunDisc.position = sunPos
        sunDisc.zPosition = 2
        skyLayer.addChild(sunDisc)

        // Two sweeping parallax mountain ranges spanning the 2880pt horizon
        let farPath = makeMountainPath(points: [
            (-160, 360), (220, 620), (620, 420), (1040, 740),
            (1480, 480), (1920, 700), (2360, 440), (2740, 630), (3080, 380)
        ])
        let farRidge = SKShapeNode(path: farPath)
        farRidge.fillColor = theme.farHillColor
        farRidge.strokeColor = .clear
        farRidge.zPosition = 2.5
        skyLayer.addChild(farRidge)

        let nearPath = makeMountainPath(points: [
            (-160, 260), (260, 480), (680, 310), (1120, 560),
            (1580, 350), (2040, 540), (2480, 340), (3080, 280)
        ])
        let nearRidge = SKShapeNode(path: nearPath)
        nearRidge.fillColor = theme.hillColor
        nearRidge.strokeColor = .clear
        nearRidge.zPosition = 3
        skyLayer.addChild(nearRidge)

        // Seamless fluffy drifting clouds
        cloudLayer.zPosition = 5
        clouds.removeAll()
        for i in 0..<11 {
            let cloud = makeCloudNode(scale: CGFloat(0.95 + Double(i % 3) * 0.42))
            cloud.position = CGPoint(
                x: CGFloat(i) * 280 + 80,
                y: WorldConstants.height - 150 - CGFloat((i * 67) % 310)
            )
            cloudLayer.addChild(cloud)
            clouds.append((cloud, CGFloat(0.65 + Double(i % 4) * 0.25)))
        }

        // Distant gliding silhouette birds for lively sky detail
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

        // Subtle wind motes / firefly dust across the larger world
        windMotes.removeAll()
        for i in 0..<42 {
            let mote = SKShapeNode(circleOfRadius: CGFloat(2.0 + Double(i % 3) * 0.9))
            mote.fillColor = SKColor(red: 1.0, green: 0.96, blue: 0.85, alpha: 0.38)
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

    private func makeBirdNode() -> SKNode {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -11, y: 2))
        p.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: -5, y: 7))
        p.addQuadCurve(to: CGPoint(x: 11, y: 2), control: CGPoint(x: 5, y: 7))
        let bird = SKShapeNode(path: p)
        bird.strokeColor = SKColor(white: 0.12, alpha: 0.42)
        bird.lineWidth = 2.2
        bird.lineCap = .round
        return bird
    }

    private func makeMountainPath(points: [(CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: points[0].0, y: 0))
        p.addLine(to: CGPoint(x: points[0].0, y: points[0].1))
        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            let midX = (prev.0 + curr.0) * 0.5
            p.addCurve(
                to: CGPoint(x: curr.0, y: curr.1),
                control1: CGPoint(x: midX, y: prev.1),
                control2: CGPoint(x: midX, y: curr.1)
            )
        }
        p.addLine(to: CGPoint(x: points.last!.0, y: 0))
        p.closeSubpath()
        return p
    }

    private func makeCloudNode(scale: CGFloat) -> SKNode {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -66, y: -18))
        p.addCurve(to: CGPoint(x: -54, y: 18), control1: CGPoint(x: -82, y: -14), control2: CGPoint(x: -76, y: 16))
        p.addCurve(to: CGPoint(x: -6, y: 34), control1: CGPoint(x: -44, y: 36), control2: CGPoint(x: -22, y: 40))
        p.addCurve(to: CGPoint(x: 42, y: 20), control1: CGPoint(x: 14, y: 44), control2: CGPoint(x: 36, y: 36))
        p.addCurve(to: CGPoint(x: 68, y: -18), control1: CGPoint(x: 72, y: 18), control2: CGPoint(x: 84, y: -12))
        p.closeSubpath()

        let cloud = SKShapeNode(path: p)
        cloud.fillColor = SKColor(white: 1.0, alpha: 0.22)
        cloud.strokeColor = .clear
        cloud.setScale(scale)
        return cloud
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

    // MARK: - Destructible Illustrated Island Props (Painter Assets!)

    private func buildSurfaceProps() {
        propLayer.removeAllChildren()
        surfaceProps.removeAll()

        var rng = SeededRNG(seed: engine.config.seed ^ 0xF10E)
        var towersPlaced = 0
        var lastTowerX: CGFloat = -999

        var x: CGFloat = 120
        while x < WorldConstants.width - 120 {
            x += rng.nextCGFloat(in: 38...78)
            guard let sy = engine.terrain.surfaceY(atWorldX: x),
                  sy > WorldConstants.initialWaterY + 34,
                  let syL = engine.terrain.surfaceY(atWorldX: x - 20),
                  let syR = engine.terrain.surfaceY(atWorldX: x + 20),
                  abs(syL - syR) < 22 else { continue }

            let nearWorm = engine.worms.contains { hypot($0.position.x - x, $0.position.y - sy) < 30 }
            if nearWorm { continue }

            let roll = rng.nextDouble()
            let sprite: SKSpriteNode

            if towersPlaced < 2 && sy > 500 && (x - lastTowerX) > 740 && roll < 0.28 {
                sprite = SKSpriteNode(imageNamed: "prop_tower")
                let s = rng.nextCGFloat(in: 0.72...0.86)
                sprite.size = CGSize(width: 96 * s, height: 132 * s)
                towersPlaced += 1
                lastTowerX = x
            } else if roll < 0.56 {
                sprite = SKSpriteNode(imageNamed: "prop_tree")
                let s = rng.nextCGFloat(in: 0.72...1.08)
                sprite.size = CGSize(width: 92 * s, height: 108 * s)
            } else {
                sprite = SKSpriteNode(imageNamed: "prop_flowers")
                let s = rng.nextCGFloat(in: 0.68...0.96)
                sprite.size = CGSize(width: 68 * s, height: 54 * s)
            }

            sprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)
            sprite.position = CGPoint(x: x, y: sy - 4)
            propLayer.addChild(sprite)
            surfaceProps.append(SurfaceProp(node: sprite, anchor: CGPoint(x: x, y: sy - 10)))
        }
    }

    private func pruneDestroyedProps() {
        var i = 0
        while i < surfaceProps.count {
            let prop = surfaceProps[i]
            if !engine.terrain.isSolid(worldPoint: prop.anchor) {
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
        let ring = SKShapeNode(circleOfRadius: 13)
        ring.strokeColor = SKColor(red: 1.0, green: 0.92, blue: 0.28, alpha: 0.96)
        ring.lineWidth = 2.8
        ring.fillColor = .clear
        aimCrosshair.addChild(ring)

        let ticks = SKShapeNode(path: {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -19, y: 0)); p.addLine(to: CGPoint(x: -8, y: 0))
            p.move(to: CGPoint(x: 8, y: 0)); p.addLine(to: CGPoint(x: 19, y: 0))
            p.move(to: CGPoint(x: 0, y: -19)); p.addLine(to: CGPoint(x: 0, y: -8))
            p.move(to: CGPoint(x: 0, y: 8)); p.addLine(to: CGPoint(x: 0, y: 19))
            return p
        }())
        ticks.strokeColor = .white
        ticks.lineWidth = 2.2
        aimCrosshair.addChild(ticks)
        aimCrosshair.zPosition = 28
        worldLayer.addChild(aimCrosshair)

        // Subtle dotted sightline between worm and crosshair
        aimDots.removeAll()
        for i in 0..<3 {
            let dot = SKShapeNode(circleOfRadius: CGFloat(3.2 - Double(i) * 0.5))
            dot.fillColor = SKColor(red: 1.0, green: 0.95, blue: 0.65, alpha: 0.65)
            dot.strokeColor = .clear
            dot.zPosition = 27
            worldLayer.addChild(dot)
            aimDots.append(dot)
        }

        powerMeterNode.zPosition = 29
        powerMeterNode.addChild(powerMeterFill)
        worldLayer.addChild(powerMeterNode)

        airstrikeOverlay.zPosition = 32
        airstrikeBeam.strokeColor = SKColor(red: 0.35, green: 0.85, blue: 1.0, alpha: 0.72)
        airstrikeBeam.lineWidth = 3.5
        airstrikeOverlay.addChild(airstrikeBeam)

        let ret = SKShapeNode(circleOfRadius: 42)
        ret.strokeColor = SKColor(red: 1.0, green: 0.35, blue: 0.30, alpha: 0.95)
        ret.fillColor = SKColor(red: 1.0, green: 0.35, blue: 0.30, alpha: 0.18)
        ret.lineWidth = 3.8
        airstrikeReticle.addChild(ret)
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

        // Top-Left: Team Scoreboard
        teamScoreBars.removeAll()
        for (idx, team) in engine.teams.enumerated() {
            let maxHP = engine.config.wormsPerTeam * 100
            let yOffset = halfH - safeY - 22 - CGFloat(idx) * 46
            let xLeft = -halfW + safeX

            let bg = SKShapeNode(rectOf: CGSize(width: 320, height: 36), cornerRadius: 10)
            bg.fillColor = SKColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 0.82)
            bg.strokeColor = team.descriptor.color.withAlphaComponent(0.65)
            bg.lineWidth = 2.0
            bg.position = CGPoint(x: xLeft + 160, y: yOffset)
            hudLayer.addChild(bg)

            let name = SKLabelNode(fontNamed: "AvenirNext-Bold")
            name.text = "S\(idx + 1) \(team.descriptor.name)"
            name.fontSize = 15
            name.fontColor = .white
            name.horizontalAlignmentMode = .left
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: xLeft + 14, y: yOffset + 6)
            hudLayer.addChild(name)

            let hpLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            hpLabel.text = "\(maxHP)"
            hpLabel.fontSize = 15
            hpLabel.fontColor = team.descriptor.color
            hpLabel.horizontalAlignmentMode = .right
            hpLabel.verticalAlignmentMode = .center
            hpLabel.position = CGPoint(x: xLeft + 306, y: yOffset + 6)
            hudLayer.addChild(hpLabel)

            let track = SKShapeNode(rect: CGRect(x: xLeft + 14, y: yOffset - 12, width: 292, height: 7), cornerRadius: 3.5)
            track.fillColor = SKColor(white: 1.0, alpha: 0.14)
            track.strokeColor = .clear
            hudLayer.addChild(track)

            let fill = SKShapeNode()
            fill.fillColor = team.descriptor.color
            fill.strokeColor = .clear
            fill.position = CGPoint(x: xLeft + 14, y: yOffset - 12)
            hudLayer.addChild(fill)

            teamScoreBars.append((fill, hpLabel, bg, maxHP))
        }

        // Top-Right: Wind Gauge
        let windX = halfW - safeX - 135
        let windY = halfH - safeY - 24
        let windBg = SKShapeNode(rectOf: CGSize(width: 270, height: 54), cornerRadius: 12)
        windBg.fillColor = SKColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 0.84)
        windBg.strokeColor = SKColor(white: 1.0, alpha: 0.22)
        windBg.lineWidth = 2.0
        windBg.position = CGPoint(x: windX, y: windY)
        hudLayer.addChild(windBg)

        windTextLabel.fontSize = 15
        windTextLabel.fontColor = SKColor(red: 0.74, green: 0.92, blue: 1.0, alpha: 1)
        windTextLabel.verticalAlignmentMode = .center
        windTextLabel.position = CGPoint(x: windX, y: windY + 11)
        hudLayer.addChild(windTextLabel)

        let windTrack = SKShapeNode(rectOf: CGSize(width: 230, height: 10), cornerRadius: 5)
        windTrack.fillColor = SKColor(white: 1.0, alpha: 0.14)
        windTrack.strokeColor = .clear
        windTrack.position = CGPoint(x: windX, y: windY - 12)
        hudLayer.addChild(windTrack)

        let centerTick = SKShapeNode(rectOf: CGSize(width: 2.5, height: 16))
        centerTick.fillColor = SKColor(white: 1.0, alpha: 0.7)
        centerTick.strokeColor = .clear
        centerTick.position = CGPoint(x: windX, y: windY - 12)
        hudLayer.addChild(centerTick)

        windBarFill.position = CGPoint(x: windX, y: windY - 12)
        windBarFill.strokeColor = .clear
        hudLayer.addChild(windBarFill)

        // Bottom-Left: Turn Timer + Active Weapon Chip with Painter Icon
        let blX = -halfW + safeX
        let blY = -halfH + safeY + 30

        timerBadge.path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 88, height: 68), cornerWidth: 15, cornerHeight: 15, transform: nil)
        timerBadge.fillColor = SKColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 0.88)
        timerBadge.strokeColor = SKColor(white: 1.0, alpha: 0.28)
        timerBadge.lineWidth = 2.5
        timerBadge.position = CGPoint(x: blX, y: blY - 34)
        hudLayer.addChild(timerBadge)

        timerLabel.fontSize = 34
        timerLabel.fontColor = .white
        timerLabel.verticalAlignmentMode = .center
        timerLabel.position = CGPoint(x: blX + 44, y: blY)
        hudLayer.addChild(timerLabel)

        weaponChipBg.path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 318, height: 68), cornerWidth: 15, cornerHeight: 15, transform: nil)
        weaponChipBg.fillColor = SKColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 0.88)
        weaponChipBg.strokeColor = SKColor(white: 1.0, alpha: 0.28)
        weaponChipBg.lineWidth = 2.4
        weaponChipBg.position = CGPoint(x: blX + 102, y: blY - 34)
        hudLayer.addChild(weaponChipBg)

        weaponChipIcon.size = CGSize(width: 50, height: 50)
        weaponChipIcon.position = CGPoint(x: blX + 136, y: blY)
        hudLayer.addChild(weaponChipIcon)

        weaponChipTitle.fontSize = 20
        weaponChipTitle.fontColor = .white
        weaponChipTitle.horizontalAlignmentMode = .left
        weaponChipTitle.verticalAlignmentMode = .center
        weaponChipTitle.position = CGPoint(x: blX + 170, y: blY + 11)
        hudLayer.addChild(weaponChipTitle)

        weaponChipAmmo.fontSize = 15
        weaponChipAmmo.fontColor = SKColor(red: 0.88, green: 0.92, blue: 0.98, alpha: 0.90)
        weaponChipAmmo.horizontalAlignmentMode = .left
        weaponChipAmmo.verticalAlignmentMode = .center
        weaponChipAmmo.position = CGPoint(x: blX + 170, y: blY - 12)
        hudLayer.addChild(weaponChipAmmo)

        // Bottom-Right: Control Hint Strip
        let hintBg = SKShapeNode(rectOf: CGSize(width: 820, height: 40), cornerRadius: 12)
        hintBg.fillColor = SKColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 0.78)
        hintBg.strokeColor = SKColor(white: 1.0, alpha: 0.16)
        hintBg.lineWidth = 1.4
        hintBg.position = CGPoint(x: halfW - safeX - 410, y: blY - 10)
        hudLayer.addChild(hintBg)

        controlsHintLabel.fontSize = 15.5
        controlsHintLabel.fontColor = SKColor(white: 0.94, alpha: 0.95)
        controlsHintLabel.verticalAlignmentMode = .center
        controlsHintLabel.position = hintBg.position
        hudLayer.addChild(controlsHintLabel)

        // Top-Center: Turn Announcement Banner
        turnBannerNode.position = CGPoint(x: 0, y: halfH - safeY - 56)
        turnBannerBg.path = CGPath(roundedRect: CGRect(x: -350, y: -42, width: 700, height: 84), cornerWidth: 18, cornerHeight: 18, transform: nil)
        turnBannerBg.fillColor = SKColor(red: 0.07, green: 0.09, blue: 0.16, alpha: 0.94)
        turnBannerBg.strokeColor = .white
        turnBannerBg.lineWidth = 3.0
        turnBannerNode.addChild(turnBannerBg)

        turnBannerTitle.fontSize = 27
        turnBannerTitle.fontColor = .white
        turnBannerTitle.verticalAlignmentMode = .center
        turnBannerTitle.position = CGPoint(x: 0, y: 12)
        turnBannerNode.addChild(turnBannerTitle)

        turnBannerSubtitle.fontSize = 18
        turnBannerSubtitle.fontColor = SKColor(white: 0.88, alpha: 1)
        turnBannerSubtitle.verticalAlignmentMode = .center
        turnBannerSubtitle.position = CGPoint(x: 0, y: -18)
        turnBannerNode.addChild(turnBannerSubtitle)
        hudLayer.addChild(turnBannerNode)

        // Top-Center Persistent Status Pill (for Shotgun 2nd Shot / Dynamite Retreat!)
        statusPillNode.position = CGPoint(x: 0, y: halfH - safeY - 34)
        statusPillBg.path = CGPath(roundedRect: CGRect(x: -280, y: -22, width: 560, height: 44), cornerWidth: 22, cornerHeight: 22, transform: nil)
        statusPillBg.fillColor = SKColor(red: 0.95, green: 0.36, blue: 0.18, alpha: 0.94)
        statusPillBg.strokeColor = .white
        statusPillBg.lineWidth = 2.4
        statusPillNode.addChild(statusPillBg)

        statusPillLabel.fontSize = 20
        statusPillLabel.fontColor = .white
        statusPillLabel.verticalAlignmentMode = .center
        statusPillNode.addChild(statusPillLabel)
        statusPillNode.isHidden = true
        hudLayer.addChild(statusPillNode)
    }

    // MARK: - 2×5 Illustrated Weapon Drawer (Painter Icons!)

    private func buildWeaponBar() {
        weaponBarContainer.position = CGPoint(x: 0, y: -28)
        weaponBarContainer.zPosition = 130
        weaponBarContainer.isHidden = true

        // Dark translucent backdrop dimmer so the weapon arsenal really pops!
        let backdrop = SKShapeNode(rectOf: CGSize(width: 1120, height: 460), cornerRadius: 28)
        backdrop.fillColor = SKColor(red: 0.05, green: 0.07, blue: 0.14, alpha: 0.95)
        backdrop.strokeColor = SKColor(white: 1.0, alpha: 0.24)
        backdrop.lineWidth = 2.8
        weaponBarContainer.addChild(backdrop)

        let header = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        header.text = "WAFFENKAMMER"
        header.fontSize = 24
        header.fontColor = SKColor(red: 1.0, green: 0.86, blue: 0.38, alpha: 1)
        header.verticalAlignmentMode = .center
        header.position = CGPoint(x: 0, y: 192)
        weaponBarContainer.addChild(header)

        weaponBarSlots.removeAll()
        let weapons = WeaponKind.allCases
        let cols = 5
        let cardW: CGFloat = 196
        let cardH: CGFloat = 148
        let gapX: CGFloat = 16
        let gapY: CGFloat = 16
        let totalW = CGFloat(cols) * cardW + CGFloat(cols - 1) * gapX
        let startX = -totalW * 0.5 + cardW * 0.5
        let rowY: [CGFloat] = [88, -76]

        for (i, weapon) in weapons.enumerated() {
            let row = i / cols
            let col = i % cols
            let x = startX + CGFloat(col) * (cardW + gapX)
            let y = rowY[min(row, rowY.count - 1)]

            let slotBg = SKShapeNode(rectOf: CGSize(width: cardW, height: cardH), cornerRadius: 18)
            slotBg.fillColor = SKColor(white: 1.0, alpha: 0.08)
            slotBg.strokeColor = weapon.accentColor.withAlphaComponent(0.55)
            slotBg.lineWidth = 2.2
            slotBg.position = CGPoint(x: x, y: y)
            weaponBarContainer.addChild(slotBg)

            // Soft circular glow behind the Painter icon
            let glow = SKShapeNode(circleOfRadius: 36)
            glow.fillColor = weapon.accentColor.withAlphaComponent(0.20)
            glow.strokeColor = .clear
            glow.position = CGPoint(x: 0, y: 12)
            slotBg.addChild(glow)

            // Illustrated Painter weapon icon!
            let icon = SKSpriteNode(imageNamed: weapon.iconName)
            icon.size = CGSize(width: 78, height: 78)
            icon.position = CGPoint(x: 0, y: 12)
            slotBg.addChild(icon)

            // Feature tag pill (top-left) — e.g. "2 SCHÜSSE", "HÜPFT!", "WEGRENNEN!"
            let tagW = CGFloat(weapon.tagBadge.count) * 6.4 + 14
            let tagBg = SKShapeNode(rectOf: CGSize(width: tagW, height: 20), cornerRadius: 6)
            tagBg.fillColor = weapon == .shotgun
                ? SKColor(red: 1.0, green: 0.62, blue: 0.14, alpha: 0.96)
                : weapon.accentColor.withAlphaComponent(0.88)
            tagBg.strokeColor = .clear
            tagBg.position = CGPoint(x: -cardW * 0.5 + tagW * 0.5 + 8, y: cardH * 0.5 - 17)
            slotBg.addChild(tagBg)

            let tagLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            tagLabel.text = weapon.tagBadge
            tagLabel.fontSize = 10.5
            tagLabel.fontColor = SKColor(white: 0.06, alpha: 1)
            tagLabel.verticalAlignmentMode = .center
            tagBg.addChild(tagLabel)

            // Ammo pill (top-right)
            let ammoBg = SKShapeNode(rectOf: CGSize(width: 38, height: 22), cornerRadius: 7)
            ammoBg.fillColor = SKColor(white: 0.0, alpha: 0.55)
            ammoBg.strokeColor = SKColor(white: 1.0, alpha: 0.22)
            ammoBg.lineWidth = 1.2
            ammoBg.position = CGPoint(x: cardW * 0.5 - 27, y: cardH * 0.5 - 18)
            slotBg.addChild(ammoBg)

            let ammo = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            ammo.text = "∞"
            ammo.fontSize = 13.5
            ammo.fontColor = .white
            ammo.verticalAlignmentMode = .center
            ammoBg.addChild(ammo)

            // Weapon Name
            let title = SKLabelNode(fontNamed: "AvenirNext-Bold")
            title.text = weapon.name
            title.fontSize = 16.5
            title.fontColor = .white
            title.verticalAlignmentMode = .center
            title.position = CGPoint(x: 0, y: -48)
            slotBg.addChild(title)

            weaponBarSlots.append((slotBg, ammo, weapon))
        }

        // Bottom info strip for highlighted weapon
        weaponBarSelectedTitle.fontSize = 20
        weaponBarSelectedTitle.fontColor = SKColor(red: 1.0, green: 0.90, blue: 0.45, alpha: 1)
        weaponBarSelectedTitle.verticalAlignmentMode = .center
        weaponBarSelectedTitle.position = CGPoint(x: 0, y: -176)
        weaponBarContainer.addChild(weaponBarSelectedTitle)

        weaponBarHintLabel.fontSize = 17
        weaponBarHintLabel.fontColor = SKColor(red: 0.90, green: 0.94, blue: 1.0, alpha: 0.95)
        weaponBarHintLabel.verticalAlignmentMode = .center
        weaponBarHintLabel.position = CGPoint(x: 0, y: -202)
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
        terrainSprite.texture = engine.terrain.makeTexture()
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
        node.strokeColor = SKColor(white: 1.0, alpha: 0.44)
        node.lineWidth = 2.8
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
                label.fontColor = fuse < 1.0 ? SKColor(red: 1.0, green: 0.30, blue: 0.25, alpha: 1) : .white
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

        switch proj.weapon {
        case .bazooka, .airstrike:
            let shell = SKShapeNode(rectOf: CGSize(width: 24, height: 9), cornerRadius: 3.5)
            shell.fillColor = proj.weapon == .airstrike ? SKColor(red: 0.28, green: 0.74, blue: 0.98, alpha: 1) : SKColor(red: 0.92, green: 0.30, blue: 0.20, alpha: 1)
            shell.strokeColor = SKColor(white: 0.1, alpha: 1)
            shell.lineWidth = 1.6
            body.addChild(shell)

            let flame = SKShapeNode(circleOfRadius: 5)
            flame.fillColor = SKColor(red: 1.0, green: 0.84, blue: 0.22, alpha: 0.95)
            flame.strokeColor = .clear
            flame.position = CGPoint(x: -13, y: 0)
            body.addChild(flame)

        case .grenade, .clusterBomb, .holyGrenade, .bananaBomb, .dynamite:
            let sprite = SKSpriteNode(imageNamed: proj.weapon.iconName)
            let sz: CGFloat = proj.isSubmunition ? 22 : (proj.weapon == .dynamite ? 36 : 30)
            sprite.size = CGSize(width: sz, height: sz)
            body.addChild(sprite)

        case .sheep:
            let sprite = SKSpriteNode(imageNamed: "weapon_sheep")
            sprite.size = CGSize(width: 44, height: 44)
            body.addChild(sprite)

        case .shotgun, .firePunch:
            break
        }

        root.addChild(body)

        if proj.fuseRemaining != nil {
            let fuseLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            fuseLabel.name = "fuseLabel"
            fuseLabel.fontSize = 20
            fuseLabel.fontColor = .white
            fuseLabel.position = CGPoint(x: 0, y: 26)
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

        let chute = SKNode()
        chute.name = "chute"
        let canopy = SKShapeNode(path: {
            let p = CGMutablePath()
            p.addArc(center: CGPoint(x: 0, y: 36), radius: 26, startAngle: 0, endAngle: .pi, clockwise: false)
            p.closeSubpath()
            return p
        }())
        canopy.fillColor = SKColor(white: 0.97, alpha: 0.94)
        canopy.strokeColor = SKColor(white: 0.25, alpha: 0.72)
        canopy.lineWidth = 1.8
        chute.addChild(canopy)

        let strings = SKShapeNode(path: {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -22, y: 36)); p.addLine(to: CGPoint(x: -11, y: 14))
            p.move(to: CGPoint(x: 22, y: 36)); p.addLine(to: CGPoint(x: 11, y: 14))
            return p
        }())
        strings.strokeColor = SKColor(white: 0.88, alpha: 0.8)
        strings.lineWidth = 1.4
        chute.addChild(strings)
        root.addChild(chute)

        let isHealth: Bool
        if case .health = crate.kind { isHealth = true } else { isHealth = false }

        let sprite = SKSpriteNode(imageNamed: isHealth ? "crate_med" : "crate_weapon")
        sprite.size = CGSize(width: 34, height: 34)
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
            powerMeterFill.fillColor = SKColor(
                red: min(1.0, 0.35 + power * 0.9),
                green: max(0.15, 0.95 - power * 0.72),
                blue: 0.12,
                alpha: 0.94
            )
            powerMeterFill.strokeColor = .white
            powerMeterFill.lineWidth = 1.8
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
            let barW = max(0, 292 * frac)
            item.fill.path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: barW, height: 7), cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
            let isCurrent = (idx == engine.currentTeamIndex)
            item.bg.lineWidth = isCurrent ? 3.2 : 1.4
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
        timerLabel.fontColor = urgent ? SKColor(red: 1.0, green: 0.34, blue: 0.28, alpha: 1) : .white
        timerBadge.strokeColor = urgent ? SKColor(red: 1.0, green: 0.34, blue: 0.28, alpha: 1) : SKColor(white: 1.0, alpha: 0.28)

        // Active Weapon Chip with Painter Icon & Clear Multi-Shot Pips
        let w = engine.selectedWeapon
        if lastChipWeapon != w {
            weaponChipIcon.texture = SKTexture(imageNamed: w.iconName)
            lastChipWeapon = w
        }
        weaponChipTitle.text = w.name
        weaponChipBg.strokeColor = w.accentColor.withAlphaComponent(0.88)

        if w == .shotgun {
            if engine.shotgunShotsRemaining == 1 {
                weaponChipAmmo.text = "● ○  Noch 1 Schuss!"
                weaponChipAmmo.fontColor = SKColor(red: 1.0, green: 0.84, blue: 0.28, alpha: 1)
            } else {
                weaponChipAmmo.text = "● ●  2 Schüsse pro Zug"
                weaponChipAmmo.fontColor = SKColor(red: 0.88, green: 0.94, blue: 1.0, alpha: 0.92)
            }
        } else if let ammo = engine.currentTeam.ammoCount(for: w) {
            weaponChipAmmo.text = "Vorrat: ×\(ammo) · \(w.tagBadge)"
            weaponChipAmmo.fontColor = SKColor(red: 0.88, green: 0.92, blue: 0.98, alpha: 0.88)
        } else {
            weaponChipAmmo.text = "Vorrat: ∞ · \(w.tagBadge)"
            weaponChipAmmo.fontColor = SKColor(red: 0.88, green: 0.92, blue: 0.98, alpha: 0.88)
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
        windBarFill.path = CGPath(roundedRect: CGRect(x: fillX, y: -5, width: fillW, height: 10), cornerWidth: 5, cornerHeight: 5, transform: nil)
        windBarFill.fillColor = engine.wind >= 0
            ? SKColor(red: 0.28, green: 0.80, blue: 1.0, alpha: 0.95)
            : SKColor(red: 1.0, green: 0.65, blue: 0.24, alpha: 0.95)

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
            statusPillBg.fillColor = SKColor(red: 0.92, green: 0.22, blue: 0.22, alpha: 0.94)
            statusPillLabel.text = "DYNAMIT TICKT! SCHNELL WEGRENNEN! (\(max(1, Int(ceil(rem))))s)"
        } else if engine.shotgunShotsRemaining == 1 && engine.phase == .playerControl {
            statusPillNode.isHidden = false
            statusPillBg.fillColor = SKColor(red: 0.94, green: 0.56, blue: 0.14, alpha: 0.95)
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
                slot.bg.lineWidth = isSelected ? 4.4 : 1.8
                slot.bg.strokeColor = isSelected ? .white : slot.kind.accentColor.withAlphaComponent(0.42)
                slot.bg.fillColor = isSelected ? slot.kind.accentColor.withAlphaComponent(0.30) : SKColor(white: 1.0, alpha: 0.07)
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
        let colors = [color, .white, SKColor(red: 1.0, green: 0.88, blue: 0.34, alpha: 1)]
        for i in 0..<14 {
            let star = SKShapeNode(circleOfRadius: CGFloat.random(in: 3...5.5))
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
        ring.strokeColor = isHoly ? SKColor(red: 1.0, green: 0.94, blue: 0.45, alpha: 1) : .white
        ring.fillColor = .clear
        ring.lineWidth = isHoly ? 7 : 4.5
        fxLayer.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 3.6, duration: 0.32), .fadeOut(withDuration: 0.32)]),
            .removeFromParent()
        ]))

        let core = SKShapeNode(circleOfRadius: radius * 0.85)
        core.position = center
        core.fillColor = isHoly ? SKColor(red: 1.0, green: 0.92, blue: 0.42, alpha: 0.95) : SKColor(red: 1.0, green: 0.58, blue: 0.14, alpha: 0.95)
        core.strokeColor = .clear
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
            chunk.fillColor = Bool.random() ? SKColor(red: 1.0, green: 0.82, blue: 0.26, alpha: 1) : SKColor(red: 0.46, green: 0.32, blue: 0.24, alpha: 1)
            chunk.strokeColor = .clear
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
        puff.fillColor = SKColor(white: 0.94, alpha: alpha)
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
        line.strokeColor = SKColor(red: 1.0, green: 0.95, blue: 0.60, alpha: 0.95)
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
            drop.fillColor = SKColor(red: 0.68, green: 0.94, blue: 1.0, alpha: 0.92)
            drop.strokeColor = .clear
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
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = fontSize
        label.fontColor = color
        label.position = point

        let shadow = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        shadow.text = text
        shadow.fontSize = fontSize
        shadow.fontColor = SKColor(white: 0, alpha: 0.72)
        shadow.position = CGPoint(x: 2, y: -2)
        shadow.zPosition = -1
        label.addChild(shadow)

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
