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
    private var twinklingStars: [(node: SKShapeNode, phase: Double)] = []
    private var windMotes: [SKShapeNode] = []

    // Aiming & charge indicators (world space)
    private let aimCrosshair = SKNode()
    private let powerMeterNode = SKNode()
    private let powerMeterFill = SKShapeNode()
    private let airstrikeOverlay = SKNode()
    private let airstrikeBeam = SKShapeNode()
    private let airstrikeReticle = SKShapeNode()

    // HUD Nodes (camera space)
    private let hudLayer = SKNode()
    private var teamScoreBars: [(fill: SKShapeNode, hpLabel: SKLabelNode, bg: SKShapeNode, maxHP: Int)] = []
    private let timerBadge = SKShapeNode()
    private let timerLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let weaponChipBg = SKShapeNode()
    private let weaponChipTitle = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let weaponChipAmmo = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let windBarFill = SKShapeNode()
    private let windTextLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let turnBannerNode = SKNode()
    private let turnBannerBg = SKShapeNode()
    private let turnBannerTitle = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let turnBannerSubtitle = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let controlsHintLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")

    // Weapon bar overlay
    private let weaponBarContainer = SKNode()
    private var weaponBarSlots: [(bg: SKShapeNode, ammoLabel: SKLabelNode, kind: WeaponKind)] = []
    private let weaponBarHintLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")

    private var didNotifyMatchEnd = false
    var isGameplayPaused = false

    init(config: MatchConfig) {
        self.engine = GameEngine(config: config)
        super.init(size: CGSize(width: WorldConstants.width, height: WorldConstants.height))
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

        // Camera & HUD
        hudCamera.position = CGPoint(x: WorldConstants.width * 0.5, y: WorldConstants.height * 0.5)
        hudCamera.setScale(1.0)
        addChild(hudCamera)
        self.camera = hudCamera

        hudLayer.zPosition = 100
        hudCamera.addChild(hudLayer)
        buildHUD()
        buildWeaponBar()
        updateHUD()
    }

    // MARK: - Backdrop Construction

    private func buildBackdrop() {
        let theme = engine.config.mapTheme

        // Rich 3-stop painterly sky gradient
        let skyTex = makeSkyGradientTexture(top: theme.skyTop, mid: theme.skyMid, bottom: theme.skyBottom)
        let skySprite = SKSpriteNode(texture: skyTex, size: CGSize(width: WorldConstants.width + 400, height: WorldConstants.height + 300))
        skySprite.position = CGPoint(x: WorldConstants.width * 0.5, y: WorldConstants.height * 0.5)
        skySprite.zPosition = 0
        skyLayer.addChild(skySprite)

        // Twinkling upper-sky stars for twilight / magical night themes
        twinklingStars.removeAll()
        if theme.showsStars {
            var rng = SeededRNG(seed: engine.config.seed ^ 0x51A4)
            for _ in 0..<42 {
                let r = rng.nextCGFloat(in: 1.2...2.8)
                let star = SKShapeNode(circleOfRadius: r)
                star.fillColor = SKColor(red: 1.0, green: 0.97, blue: 0.88, alpha: 0.85)
                star.strokeColor = .clear
                star.position = CGPoint(
                    x: rng.nextCGFloat(in: 40...(WorldConstants.width - 40)),
                    y: rng.nextCGFloat(in: (WorldConstants.height * 0.52)...(WorldConstants.height - 28))
                )
                star.zPosition = 1
                skyLayer.addChild(star)
                twinklingStars.append((star, rng.nextDouble() * .pi * 2))
            }
        }

        // Layered luminous sun / moon halo
        let sunPos = CGPoint(x: WorldConstants.width * 0.78, y: WorldConstants.height * 0.76)
        for (radius, alpha) in [(175, 0.08), (118, 0.14), (78, 0.22)] as [(CGFloat, CGFloat)] {
            let glow = SKShapeNode(circleOfRadius: radius)
            glow.fillColor = theme.sunColor.withAlphaComponent(alpha)
            glow.strokeColor = .clear
            glow.position = sunPos
            glow.zPosition = 1
            skyLayer.addChild(glow)
        }

        let sunDisc = SKShapeNode(circleOfRadius: 54)
        sunDisc.fillColor = theme.sunColor
        sunDisc.strokeColor = .clear
        sunDisc.position = sunPos
        sunDisc.zPosition = 2
        skyLayer.addChild(sunDisc)

        // Far misty mountain silhouettes (smooth Bezier slopes)
        let farPath = makeMountainPath(points: [
            (-120, 290), (120, 480), (420, 340), (760, 560),
            (1080, 390), (1440, 540), (1760, 360), (2060, 450)
        ])
        let farRidge = SKShapeNode(path: farPath)
        farRidge.fillColor = theme.farHillColor
        farRidge.strokeColor = .clear
        farRidge.zPosition = 2.5
        skyLayer.addChild(farRidge)

        // Closer mountain silhouette ridge
        let nearPath = makeMountainPath(points: [
            (-120, 220), (180, 370), (470, 250), (780, 430),
            (1100, 280), (1420, 420), (1710, 290), (2060, 240)
        ])
        let nearRidge = SKShapeNode(path: nearPath)
        nearRidge.fillColor = theme.hillColor
        nearRidge.strokeColor = .clear
        nearRidge.zPosition = 3
        skyLayer.addChild(nearRidge)

        // Seamless fluffy drifting clouds
        cloudLayer.zPosition = 5
        clouds.removeAll()
        for i in 0..<7 {
            let cloud = makeCloudNode(scale: CGFloat(0.78 + Double(i % 3) * 0.34))
            cloud.position = CGPoint(
                x: CGFloat(i) * 310 + 80,
                y: WorldConstants.height - 130 - CGFloat((i * 53) % 210)
            )
            cloudLayer.addChild(cloud)
            clouds.append((cloud, CGFloat(0.65 + Double(i % 4) * 0.25)))
        }

        // Subtle wind motes / firefly dust drifting across the sky
        windMotes.removeAll()
        for i in 0..<26 {
            let mote = SKShapeNode(circleOfRadius: CGFloat(1.8 + Double(i % 3) * 0.9))
            mote.fillColor = SKColor(red: 1.0, green: 0.96, blue: 0.85, alpha: 0.38)
            mote.strokeColor = .clear
            mote.position = CGPoint(
                x: CGFloat((i * 97) % Int(WorldConstants.width)),
                y: CGFloat(140 + (i * 41) % Int(WorldConstants.height - 180))
            )
            mote.zPosition = 14
            worldLayer.addChild(mote)
            windMotes.append(mote)
        }
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

    // MARK: - Destructible Surface Foliage & Wildflowers

    private func buildSurfaceProps() {
        propLayer.removeAllChildren()
        surfaceProps.removeAll()

        var rng = SeededRNG(seed: engine.config.seed ^ 0xF10E)
        let palette = engine.config.mapTheme.flowerPalette
        let grassCol = engine.config.mapTheme.grassHighlight

        var x: CGFloat = 110
        while x < WorldConstants.width - 110 {
            x += rng.nextCGFloat(in: 36...78)
            guard let sy = engine.terrain.surfaceY(atWorldX: x),
                  sy > WorldConstants.initialWaterY + 26,
                  let syL = engine.terrain.surfaceY(atWorldX: x - 12),
                  let syR = engine.terrain.surfaceY(atWorldX: x + 12),
                  abs(syL - syR) < 16 else { continue }

            // Avoid crowding worms directly
            let nearWorm = engine.worms.contains { hypot($0.position.x - x, $0.position.y - sy) < 42 }
            if nearWorm { continue }

            let roll = rng.nextDouble()
            let prop: SKNode
            if roll < 0.22 {
                prop = makeStylizedTree(scale: rng.nextCGFloat(in: 0.72...1.08), grassColor: SKColor(
                    red: CGFloat(grassCol.r) / 255.0 * 0.78,
                    green: CGFloat(grassCol.g) / 255.0 * 0.78,
                    blue: CGFloat(grassCol.b) / 255.0 * 0.85,
                    alpha: 1
                ))
            } else if roll < 0.68 {
                let flowerColor = palette[Int(rng.nextUInt64() % UInt64(palette.count))]
                prop = makeWildflowerCluster(petalColor: flowerColor)
            } else {
                prop = makeGrassTuft(color: SKColor(
                    red: CGFloat(grassCol.r) / 255.0,
                    green: CGFloat(grassCol.g) / 255.0,
                    blue: CGFloat(grassCol.b) / 255.0,
                    alpha: 0.95
                ))
            }

            prop.position = CGPoint(x: x, y: sy - 2)
            propLayer.addChild(prop)
            surfaceProps.append(SurfaceProp(node: prop, anchor: CGPoint(x: x, y: sy - 8)))
        }
    }

    private func pruneDestroyedProps() {
        var i = 0
        while i < surfaceProps.count {
            let prop = surfaceProps[i]
            if !engine.terrain.isSolid(worldPoint: prop.anchor) {
                prop.node.run(.sequence([
                    .group([
                        .moveBy(x: CGFloat.random(in: -22...22), y: 28, duration: 0.35),
                        .rotate(byAngle: CGFloat.random(in: -1.4...1.4), duration: 0.35),
                        .fadeOut(withDuration: 0.35)
                    ]),
                    .removeFromParent()
                ]))
                surfaceProps.remove(at: i)
            } else {
                i += 1
            }
        }
    }

    private func makeStylizedTree(scale: CGFloat, grassColor: SKColor) -> SKNode {
        let tree = SKNode()
        let trunk = SKShapeNode(rect: CGRect(x: -3.5, y: 0, width: 7, height: 18), cornerRadius: 2)
        trunk.fillColor = SKColor(red: 0.42, green: 0.27, blue: 0.18, alpha: 1)
        trunk.strokeColor = .clear
        tree.addChild(trunk)

        for (y, w, h, shade) in [(12, 30, 22, 0.88), (24, 24, 20, 1.0), (35, 16, 16, 1.12)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w * 0.5, y: y))
            p.addLine(to: CGPoint(x: 0, y: y + h))
            p.addLine(to: CGPoint(x: w * 0.5, y: y))
            p.closeSubpath()
            let tier = SKShapeNode(path: p)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            grassColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            tier.fillColor = SKColor(red: min(1, r * shade), green: min(1, g * shade), blue: min(1, b * shade), alpha: 1)
            tier.strokeColor = SKColor(white: 0.08, alpha: 0.25)
            tier.lineWidth = 1.0
            tree.addChild(tier)
        }
        tree.setScale(scale)
        return tree
    }

    private func makeWildflowerCluster(petalColor: SKColor) -> SKNode {
        let cluster = SKNode()
        for (x, h) in [(-5, 11), (1, 15), (7, 9)] as [(CGFloat, CGFloat)] {
            let stem = SKShapeNode(rect: CGRect(x: x - 0.8, y: 0, width: 1.6, height: h))
            stem.fillColor = SKColor(red: 0.24, green: 0.62, blue: 0.30, alpha: 1)
            stem.strokeColor = .clear
            cluster.addChild(stem)

            let blossom = SKShapeNode(circleOfRadius: 3.3)
            blossom.fillColor = petalColor
            blossom.strokeColor = .clear
            blossom.position = CGPoint(x: x, y: h + 1)
            cluster.addChild(blossom)

            let center = SKShapeNode(circleOfRadius: 1.2)
            center.fillColor = SKColor(red: 1.0, green: 0.90, blue: 0.30, alpha: 1)
            center.strokeColor = .clear
            center.position = blossom.position
            cluster.addChild(center)
        }
        return cluster
    }

    private func makeGrassTuft(color: SKColor) -> SKNode {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -7, y: 0)); p.addLine(to: CGPoint(x: -10, y: 10)); p.addLine(to: CGPoint(x: -3, y: 2))
        p.addLine(to: CGPoint(x: 0, y: 13)); p.addLine(to: CGPoint(x: 3, y: 2))
        p.addLine(to: CGPoint(x: 9, y: 9)); p.addLine(to: CGPoint(x: 6, y: 0))
        p.closeSubpath()
        let tuft = SKShapeNode(path: p)
        tuft.fillColor = color
        tuft.strokeColor = .clear
        return tuft
    }

    // MARK: - Aiming & World Indicators

    private func buildAimingIndicators() {
        let ring = SKShapeNode(circleOfRadius: 12)
        ring.strokeColor = SKColor(red: 1.0, green: 0.92, blue: 0.28, alpha: 0.95)
        ring.lineWidth = 2.6
        ring.fillColor = .clear
        aimCrosshair.addChild(ring)

        let ticks = SKShapeNode(path: {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -18, y: 0)); p.addLine(to: CGPoint(x: -8, y: 0))
            p.move(to: CGPoint(x: 8, y: 0)); p.addLine(to: CGPoint(x: 18, y: 0))
            p.move(to: CGPoint(x: 0, y: -18)); p.addLine(to: CGPoint(x: 0, y: -8))
            p.move(to: CGPoint(x: 0, y: 8)); p.addLine(to: CGPoint(x: 0, y: 18))
            return p
        }())
        ticks.strokeColor = .white
        ticks.lineWidth = 2.2
        aimCrosshair.addChild(ticks)
        aimCrosshair.zPosition = 28
        worldLayer.addChild(aimCrosshair)

        powerMeterNode.zPosition = 29
        powerMeterNode.addChild(powerMeterFill)
        worldLayer.addChild(powerMeterNode)

        airstrikeOverlay.zPosition = 32
        airstrikeBeam.strokeColor = SKColor(red: 0.35, green: 0.85, blue: 1.0, alpha: 0.72)
        airstrikeBeam.lineWidth = 3.0
        airstrikeOverlay.addChild(airstrikeBeam)

        let ret = SKShapeNode(circleOfRadius: 34)
        ret.strokeColor = SKColor(red: 1.0, green: 0.35, blue: 0.30, alpha: 0.95)
        ret.fillColor = SKColor(red: 1.0, green: 0.35, blue: 0.30, alpha: 0.18)
        ret.lineWidth = 3.5
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

    // MARK: - HUD (tvOS Overscan Safe, German)

    private func buildHUD() {
        let halfW = WorldConstants.width * 0.5
        let halfH = WorldConstants.height * 0.5
        let safeX: CGFloat = 86
        let safeY: CGFloat = 60

        // Top-Left: Team Scoreboard
        teamScoreBars.removeAll()
        for (idx, team) in engine.teams.enumerated() {
            let maxHP = engine.config.wormsPerTeam * 100
            let yOffset = halfH - safeY - 22 - CGFloat(idx) * 46
            let xLeft = -halfW + safeX

            let bg = SKShapeNode(rectOf: CGSize(width: 320, height: 36), cornerRadius: 10)
            bg.fillColor = SKColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 0.80)
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
        windBg.fillColor = SKColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 0.82)
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

        // Bottom-Left: Turn Timer + Active Weapon Chip
        let blX = -halfW + safeX
        let blY = -halfH + safeY + 28

        timerBadge.path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 88, height: 64), cornerWidth: 14, cornerHeight: 14, transform: nil)
        timerBadge.fillColor = SKColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 0.88)
        timerBadge.strokeColor = SKColor(white: 1.0, alpha: 0.28)
        timerBadge.lineWidth = 2.5
        timerBadge.position = CGPoint(x: blX, y: blY - 32)
        hudLayer.addChild(timerBadge)

        timerLabel.fontSize = 34
        timerLabel.fontColor = .white
        timerLabel.verticalAlignmentMode = .center
        timerLabel.position = CGPoint(x: blX + 44, y: blY)
        hudLayer.addChild(timerLabel)

        weaponChipBg.path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 244, height: 64), cornerWidth: 14, cornerHeight: 14, transform: nil)
        weaponChipBg.fillColor = SKColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 0.88)
        weaponChipBg.strokeColor = SKColor(white: 1.0, alpha: 0.25)
        weaponChipBg.lineWidth = 2.2
        weaponChipBg.position = CGPoint(x: blX + 102, y: blY - 32)
        hudLayer.addChild(weaponChipBg)

        weaponChipTitle.fontSize = 20
        weaponChipTitle.fontColor = .white
        weaponChipTitle.horizontalAlignmentMode = .left
        weaponChipTitle.verticalAlignmentMode = .center
        weaponChipTitle.position = CGPoint(x: blX + 120, y: blY + 10)
        hudLayer.addChild(weaponChipTitle)

        weaponChipAmmo.fontSize = 15
        weaponChipAmmo.fontColor = SKColor(red: 0.85, green: 0.90, blue: 0.96, alpha: 0.85)
        weaponChipAmmo.horizontalAlignmentMode = .left
        weaponChipAmmo.verticalAlignmentMode = .center
        weaponChipAmmo.position = CGPoint(x: blX + 120, y: blY - 12)
        hudLayer.addChild(weaponChipAmmo)

        // Bottom-Right / Center: Compact Control Hint Strip
        let hintBg = SKShapeNode(rectOf: CGSize(width: 840, height: 38), cornerRadius: 12)
        hintBg.fillColor = SKColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 0.74)
        hintBg.strokeColor = SKColor(white: 1.0, alpha: 0.14)
        hintBg.lineWidth = 1.4
        hintBg.position = CGPoint(x: 195, y: blY - 10)
        hudLayer.addChild(hintBg)

        controlsHintLabel.fontSize = 15.5
        controlsHintLabel.fontColor = SKColor(white: 0.93, alpha: 0.94)
        controlsHintLabel.verticalAlignmentMode = .center
        controlsHintLabel.position = hintBg.position
        hudLayer.addChild(controlsHintLabel)

        // Top-Center: Turn Announcement Banner
        turnBannerNode.position = CGPoint(x: 0, y: halfH - safeY - 56)
        turnBannerBg.path = CGPath(roundedRect: CGRect(x: -350, y: -42, width: 700, height: 84), cornerWidth: 18, cornerHeight: 18, transform: nil)
        turnBannerBg.fillColor = SKColor(red: 0.07, green: 0.09, blue: 0.16, alpha: 0.93)
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
    }

    private func buildWeaponBar() {
        weaponBarContainer.position = CGPoint(x: 0, y: -WorldConstants.height * 0.5 + 215)
        weaponBarContainer.zPosition = 120
        weaponBarContainer.isHidden = true

        let dockBg = SKShapeNode(rectOf: CGSize(width: 1020, height: 158), cornerRadius: 22)
        dockBg.fillColor = SKColor(red: 0.06, green: 0.08, blue: 0.15, alpha: 0.94)
        dockBg.strokeColor = SKColor(white: 1.0, alpha: 0.25)
        dockBg.lineWidth = 2.5
        weaponBarContainer.addChild(dockBg)

        weaponBarSlots.removeAll()
        let weapons = WeaponKind.allCases
        let slotW: CGFloat = 148
        let spacing: CGFloat = 14
        let totalW = CGFloat(weapons.count) * slotW + CGFloat(weapons.count - 1) * spacing
        let startX = -totalW * 0.5 + slotW * 0.5

        for (i, weapon) in weapons.enumerated() {
            let x = startX + CGFloat(i) * (slotW + spacing)
            let slotBg = SKShapeNode(rectOf: CGSize(width: slotW, height: 96), cornerRadius: 14)
            slotBg.fillColor = SKColor(white: 1.0, alpha: 0.08)
            slotBg.strokeColor = weapon.accentColor.withAlphaComponent(0.55)
            slotBg.lineWidth = 2.2
            slotBg.position = CGPoint(x: x, y: 14)
            weaponBarContainer.addChild(slotBg)

            let badge = SKShapeNode(rectOf: CGSize(width: 58, height: 28), cornerRadius: 7)
            badge.fillColor = weapon.accentColor
            badge.strokeColor = .clear
            badge.position = CGPoint(x: 0, y: 20)
            slotBg.addChild(badge)

            let code = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            code.text = weapon.shortLabel
            code.fontSize = 15
            code.fontColor = SKColor(white: 0.07, alpha: 1)
            code.verticalAlignmentMode = .center
            badge.addChild(code)

            let title = SKLabelNode(fontNamed: "AvenirNext-Bold")
            title.text = weapon.name
            title.fontSize = 14.5
            title.fontColor = .white
            title.verticalAlignmentMode = .center
            title.position = CGPoint(x: 0, y: -8)
            slotBg.addChild(title)

            let ammo = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            ammo.text = "∞"
            ammo.fontSize = 14
            ammo.fontColor = SKColor(white: 0.85, alpha: 1)
            ammo.verticalAlignmentMode = .center
            ammo.position = CGPoint(x: 0, y: -30)
            slotBg.addChild(ammo)

            weaponBarSlots.append((slotBg, ammo, weapon))
        }

        weaponBarHintLabel.fontSize = 17
        weaponBarHintLabel.fontColor = SKColor(red: 0.88, green: 0.93, blue: 1.0, alpha: 0.95)
        weaponBarHintLabel.verticalAlignmentMode = .center
        weaponBarHintLabel.position = CGPoint(x: 0, y: -52)
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
        // Twinkling stars
        for item in twinklingStars {
            let tw = 0.45 + 0.55 * sin(elapsedTime * 2.2 + item.phase)
            item.node.alpha = CGFloat(tw)
        }

        // Drift clouds with wind
        let baseDrift = engine.wind * 75 + (engine.wind >= 0 ? 12 : -12)
        for item in clouds {
            item.node.position.x += baseDrift * item.speedFactor * CGFloat(dt)
            if item.node.position.x > WorldConstants.width + 180 {
                item.node.position.x = -180
            } else if item.node.position.x < -180 {
                item.node.position.x = WorldConstants.width + 180
            }
        }

        // Drift wind motes
        for mote in windMotes {
            mote.position.x += (engine.wind * 220) * CGFloat(dt)
            mote.position.y -= 18 * CGFloat(dt)
            if mote.position.x > WorldConstants.width + 20 { mote.position.x = -20 }
            if mote.position.x < -20 { mote.position.x = WorldConstants.width + 20 }
            if mote.position.y < engine.waterY { mote.position.y = WorldConstants.height - 20 }
        }

        // Animated sparkling ocean waves
        updateWaterWave(node: waterBackWave, baseY: engine.waterY + 7, phase: elapsedTime * 1.9, amp: 5.5, color: engine.config.mapTheme.waterColor.withAlphaComponent(0.55))
        updateWaterWave(node: waterFrontWave, baseY: engine.waterY, phase: elapsedTime * 2.7 + 1.4, amp: 7.0, color: engine.config.mapTheme.waterColor)
    }

    private func updateWaterWave(node: SKShapeNode, baseY: CGFloat, phase: TimeInterval, amp: CGFloat, color: SKColor) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -120, y: -120))
        let step: CGFloat = 48
        var x: CGFloat = -120
        while x <= WorldConstants.width + 140 {
            let y = baseY + sin(x * 0.015 + CGFloat(phase)) * amp
            p.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        p.addLine(to: CGPoint(x: WorldConstants.width + 140, y: -120))
        p.closeSubpath()
        node.path = p
        node.fillColor = color
        node.strokeColor = SKColor(white: 1.0, alpha: 0.42)
        node.lineWidth = 2.6
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
                body.zRotation = proj.rotation
            }
            if let fuse = proj.fuseRemaining, let label = node.childNode(withName: "fuseLabel") as? SKLabelNode {
                let sec = max(1, Int(ceil(fuse)))
                label.text = "\(sec)"
                label.fontColor = fuse < 1.0 ? SKColor(red: 1.0, green: 0.30, blue: 0.25, alpha: 1) : .white
            }
            if (proj.weapon == .bazooka || proj.weapon == .airstrike || proj.isClusterBomblet) && Int(elapsedTime * 60) % 2 == 0 {
                spawnSmokePuff(at: proj.position, radius: proj.isClusterBomblet ? 4 : 6, alpha: 0.52)
            }
        }
    }

    private func makeProjectileNode(for proj: ProjectileState) -> SKNode {
        let root = SKNode()
        let body = SKNode()
        body.name = "body"

        switch proj.weapon {
        case .bazooka, .airstrike:
            let shell = SKShapeNode(rectOf: CGSize(width: 22, height: 8), cornerRadius: 3)
            shell.fillColor = proj.weapon == .airstrike ? SKColor(red: 0.28, green: 0.72, blue: 0.98, alpha: 1) : SKColor(red: 0.90, green: 0.30, blue: 0.20, alpha: 1)
            shell.strokeColor = SKColor(white: 0.1, alpha: 1)
            shell.lineWidth = 1.6
            body.addChild(shell)

            let flame = SKShapeNode(circleOfRadius: 4.5)
            flame.fillColor = SKColor(red: 1.0, green: 0.82, blue: 0.22, alpha: 0.95)
            flame.strokeColor = .clear
            flame.position = CGPoint(x: -12, y: 0)
            body.addChild(flame)

        case .grenade:
            let g = SKShapeNode(circleOfRadius: 7.5)
            g.fillColor = SKColor(red: 0.28, green: 0.66, blue: 0.26, alpha: 1)
            g.strokeColor = SKColor(white: 0.08, alpha: 1)
            g.lineWidth = 1.6
            body.addChild(g)

        case .clusterBomb:
            let g = SKShapeNode(circleOfRadius: proj.isClusterBomblet ? 5.5 : 8.5)
            g.fillColor = SKColor(red: 0.92, green: 0.25, blue: 0.36, alpha: 1)
            g.strokeColor = SKColor(red: 1.0, green: 0.85, blue: 0.25, alpha: 1)
            g.lineWidth = 1.6
            body.addChild(g)

        case .holyGrenade:
            let orb = SKShapeNode(circleOfRadius: 10)
            orb.fillColor = SKColor(red: 1.0, green: 0.84, blue: 0.22, alpha: 1)
            orb.strokeColor = SKColor(white: 1.0, alpha: 0.95)
            orb.lineWidth = 2.0
            body.addChild(orb)

            let glow = SKShapeNode(circleOfRadius: 16)
            glow.fillColor = SKColor(red: 1.0, green: 0.92, blue: 0.45, alpha: 0.28)
            glow.strokeColor = .clear
            body.addChild(glow)

        case .shotgun:
            break
        }

        root.addChild(body)

        if proj.fuseRemaining != nil {
            let fuseLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            fuseLabel.name = "fuseLabel"
            fuseLabel.fontSize = 18
            fuseLabel.fontColor = .white
            fuseLabel.position = CGPoint(x: 0, y: 18)
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
            node.childNode(withName: "chute")?.isHidden = !crate.isParachuting
        }
    }

    private func makeCrateNode(for crate: CrateState) -> SKNode {
        let root = SKNode()

        let chute = SKNode()
        chute.name = "chute"
        let canopy = SKShapeNode(path: {
            let p = CGMutablePath()
            p.addArc(center: CGPoint(x: 0, y: 30), radius: 22, startAngle: 0, endAngle: .pi, clockwise: false)
            p.closeSubpath()
            return p
        }())
        canopy.fillColor = SKColor(white: 0.96, alpha: 0.92)
        canopy.strokeColor = SKColor(white: 0.25, alpha: 0.7)
        canopy.lineWidth = 1.6
        chute.addChild(canopy)

        let strings = SKShapeNode(path: {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -18, y: 30)); p.addLine(to: CGPoint(x: -9, y: 10))
            p.move(to: CGPoint(x: 18, y: 30)); p.addLine(to: CGPoint(x: 9, y: 10))
            return p
        }())
        strings.strokeColor = SKColor(white: 0.85, alpha: 0.75)
        strings.lineWidth = 1.2
        chute.addChild(strings)
        root.addChild(chute)

        let isHealth: Bool
        if case .health = crate.kind { isHealth = true } else { isHealth = false }

        let box = SKShapeNode(rectOf: CGSize(width: 24, height: 24), cornerRadius: 5)
        box.fillColor = isHealth ? SKColor(white: 0.96, alpha: 1) : SKColor(red: 0.72, green: 0.46, blue: 0.22, alpha: 1)
        box.strokeColor = SKColor(white: 0.15, alpha: 1)
        box.lineWidth = 2.0
        root.addChild(box)

        if isHealth {
            let plus = SKShapeNode(path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: -6, y: 0)); p.addLine(to: CGPoint(x: 6, y: 0))
                p.move(to: CGPoint(x: 0, y: -6)); p.addLine(to: CGPoint(x: 0, y: 6))
                return p
            }())
            plus.strokeColor = SKColor(red: 0.92, green: 0.18, blue: 0.26, alpha: 1)
            plus.lineWidth = 4.0
            root.addChild(plus)
        } else {
            let star = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            star.text = "★"
            star.fontSize = 15
            star.fontColor = SKColor(red: 1.0, green: 0.86, blue: 0.24, alpha: 1)
            star.verticalAlignmentMode = .center
            root.addChild(star)
        }

        return root
    }

    private func updateAimingAndOverlays() {
        let showAim: Bool
        switch engine.phase {
        case .playerControl, .charging:
            showAim = !engine.isWeaponBarOpen && engine.selectedWeapon != .airstrike
        default:
            showAim = false
        }

        if showAim, let worm = engine.activeWorm, worm.isAlive {
            aimCrosshair.isHidden = false
            let dir = worm.aimDirection
            let dist: CGFloat = 78
            aimCrosshair.position = CGPoint(x: worm.position.x + dir.dx * dist, y: worm.position.y + 4 + dir.dy * dist)
            aimCrosshair.zRotation = CGFloat(elapsedTime * 1.4)
        } else {
            aimCrosshair.isHidden = true
        }

        if case .charging(let power) = engine.phase, let worm = engine.activeWorm, worm.isAlive {
            powerMeterNode.isHidden = false
            powerMeterNode.position = CGPoint(x: worm.position.x, y: worm.position.y + 4)
            powerMeterNode.zRotation = worm.worldAimAngle

            let length = 24 + power * 96
            let tipHalfH = 3.5 + power * 10.0
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 20, y: -3))
            path.addLine(to: CGPoint(x: 20 + length, y: -tipHalfH))
            path.addLine(to: CGPoint(x: 20 + length, y: tipHalfH))
            path.addLine(to: CGPoint(x: 20, y: 3))
            path.closeSubpath()
            powerMeterFill.path = path
            powerMeterFill.fillColor = SKColor(
                red: min(1.0, 0.35 + power * 0.9),
                green: max(0.15, 0.95 - power * 0.72),
                blue: 0.12,
                alpha: 0.92
            )
            powerMeterFill.strokeColor = .white
            powerMeterFill.lineWidth = 1.6
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
            airstrikeReticle.position = CGPoint(x: targetX, y: max(groundY, engine.waterY + 20))
            airstrikeReticle.setScale(1.0 + CGFloat(sin(elapsedTime * 8.0) * 0.10))
        } else {
            airstrikeOverlay.isHidden = true
        }
    }

    // MARK: - Camera Tracking & Shake

    private func updateCamera(dt: TimeInterval) {
        var target = CGPoint(x: WorldConstants.width * 0.5, y: WorldConstants.height * 0.5)
        var targetScale: CGFloat = 1.0

        switch engine.phase {
        case .projectileInFlight:
            if let proj = engine.projectiles.first {
                target = proj.position
                targetScale = 0.92
            }
        case .airstrikeAiming(let targetX):
            target = CGPoint(x: targetX, y: WorldConstants.height * 0.52)
            targetScale = 1.0
        case .settling:
            if let exp = engine.lastExplosionPoint {
                target = exp
                targetScale = 0.94
            } else if let worm = engine.activeWorm {
                target = worm.position
                targetScale = 0.92
            }
        default:
            if let worm = engine.activeWorm, worm.isAlive {
                target = worm.position
                targetScale = 0.90
            }
        }

        let halfVisibleW = (WorldConstants.width * targetScale) * 0.5
        let halfVisibleH = (WorldConstants.height * targetScale) * 0.5
        let clampedX = max(halfVisibleW, min(WorldConstants.width - halfVisibleW, target.x))
        let clampedY = max(halfVisibleH, min(WorldConstants.height - halfVisibleH, target.y))

        let lerp = min(1.0, CGFloat(dt) * 4.8)
        let newScale = hudCamera.xScale + (targetScale - hudCamera.xScale) * lerp
        hudCamera.setScale(newScale)

        var camPos = CGPoint(
            x: hudCamera.position.x + (clampedX - hudCamera.position.x) * lerp,
            y: hudCamera.position.y + (clampedY - hudCamera.position.y) * lerp
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

    // MARK: - HUD Refresh (German)

    private func updateHUD() {
        // Team bars
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

        // Timer
        let secs = max(0, Int(ceil(engine.turnTimeRemaining)))
        timerLabel.text = "\(secs)"
        let urgent = secs <= 5 && engine.phase == .playerControl
        timerLabel.fontColor = urgent ? SKColor(red: 1.0, green: 0.32, blue: 0.28, alpha: 1) : .white
        timerBadge.strokeColor = urgent ? SKColor(red: 1.0, green: 0.32, blue: 0.28, alpha: 1) : SKColor(white: 1.0, alpha: 0.28)

        // Active Weapon Chip
        let w = engine.selectedWeapon
        weaponChipTitle.text = w.name
        weaponChipBg.strokeColor = w.accentColor.withAlphaComponent(0.85)
        if w == .shotgun && engine.shotgunShotsRemaining > 0 {
            weaponChipAmmo.text = "Schüsse übrig: \(engine.shotgunShotsRemaining)"
        } else if let ammo = engine.currentTeam.ammoCount(for: w) {
            weaponChipAmmo.text = "Vorrat: \(ammo)"
        } else {
            weaponChipAmmo.text = "Vorrat: ∞"
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

        // Weapon Bar
        weaponBarContainer.isHidden = !engine.isWeaponBarOpen
        if engine.isWeaponBarOpen {
            for (i, slot) in weaponBarSlots.enumerated() {
                let isSelected = (i == engine.weaponBarSelectionIndex)
                let canUse = engine.currentTeam.canUse(slot.kind)
                slot.bg.lineWidth = isSelected ? 4.0 : 1.8
                slot.bg.strokeColor = isSelected ? .white : slot.kind.accentColor.withAlphaComponent(0.45)
                slot.bg.fillColor = isSelected ? slot.kind.accentColor.withAlphaComponent(0.28) : SKColor(white: 1.0, alpha: 0.06)
                slot.bg.alpha = canUse ? 1.0 : 0.35
                if let count = engine.currentTeam.ammoCount(for: slot.kind) {
                    slot.ammoLabel.text = "×\(count)"
                } else {
                    slot.ammoLabel.text = "∞"
                }
            }
            let highlighted = WeaponKind.allCases[engine.weaponBarSelectionIndex]
            weaponBarHintLabel.text = "\(highlighted.name): \(highlighted.hint)  ·  Auswahl: Nehmen"
        }

        // Context-sensitive Controls Hint (German)
        if engine.isWeaponBarOpen {
            controlsHintLabel.text = "← / → Waffe wählen  ·  Auswahl: Nehmen  ·  Play/Pause: Schließen"
        } else if case .airstrikeAiming = engine.phase {
            controlsHintLabel.text = "← / → Ziel verschieben  ·  Auswahl: Angriff starten!  ·  Play/Pause: Abbruch"
        } else if isGameControllerConnected {
            controlsHintLabel.text = "Stick/Kreuz: Laufen & Zielen  ·  R2/X: Schießen  ·  A: Hüpfen  ·  B: Salto  ·  L1/R1/Y: Waffen"
        } else {
            controlsHintLabel.text = "← / → Laufen  ·  ↑ / ↓ Zielen  ·  Auswahl halten: Schießen  ·  2×↑ Hüpfen  ·  Play/Pause: Waffen"
        }
    }

    // MARK: - VFX & Audio Event Handling

    private func handleEngineEvents(_ events: [GameEvent]) {
        for event in events {
            switch event {
            case .explosion(let center, let radius, let isHoly):
                spawnExplosionFX(at: center, radius: radius, isHoly: isHoly)
                shakeIntensity = max(shakeIntensity, isHoly ? 28 : radius * 0.22)
                SoundEngine.shared.play(isHoly ? .holyExplosion : .explosion)

            case .shotgunTracer(let from, let to):
                spawnShotgunTracer(from: from, to: to)

            case .wormDamaged(_, let amount, let pos):
                spawnFloatingText("-\(amount)", at: CGPoint(x: pos.x, y: pos.y + 38), color: SKColor(red: 1.0, green: 0.36, blue: 0.32, alpha: 1), fontSize: 29)
                SoundEngine.shared.play(.hurt)

            case .wormDrowned(let wormID, let pos):
                spawnWaterSplash(at: pos)
                if wormID > 0 {
                    spawnFloatingText("PLATSCH!", at: CGPoint(x: pos.x, y: pos.y + 44), color: SKColor(red: 0.48, green: 0.90, blue: 1.0, alpha: 1), fontSize: 26)
                }
                SoundEngine.shared.play(.splash)

            case .wormJumped(let pos, _):
                spawnSmokePuff(at: CGPoint(x: pos.x, y: pos.y - 12), radius: 8, alpha: 0.45)
                SoundEngine.shared.play(.jump)

            case .projectileFired(let weapon, let pos):
                spawnSmokePuff(at: pos, radius: 12, alpha: 0.7)
                SoundEngine.shared.play(weapon == .shotgun ? .shotgun : .bazookaFire)

            case .grenadeBounce:
                SoundEngine.shared.play(.grenadeBounce)

            case .crateCollected(let pos, let label, let isHealth):
                let col = isHealth ? SKColor(red: 0.34, green: 0.96, blue: 0.56, alpha: 1) : SKColor(red: 1.0, green: 0.88, blue: 0.30, alpha: 1)
                spawnSparkleBurst(at: pos, color: col)
                spawnFloatingText(label, at: CGPoint(x: pos.x, y: pos.y + 26), color: col, fontSize: 25)
                SoundEngine.shared.play(.cratePickup)

            case .turnStarted:
                SoundEngine.shared.play(.turnStart)

            case .suddenDeathTriggered:
                spawnFloatingText("WASSER STEIGT!", at: CGPoint(x: WorldConstants.width * 0.5, y: WorldConstants.height * 0.65), color: SKColor(red: 1.0, green: 0.38, blue: 0.34, alpha: 1), fontSize: 40)

            case .holyChoir(let pos):
                spawnSparkleBurst(at: pos, color: SKColor(red: 1.0, green: 0.92, blue: 0.34, alpha: 1))
                spawnFloatingText("HALLELUJA!", at: CGPoint(x: pos.x, y: pos.y + 46), color: SKColor(red: 1.0, green: 0.92, blue: 0.34, alpha: 1), fontSize: 36)
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
        line.lineWidth = 4.0
        fxLayer.addChild(line)
        line.run(.sequence([
            .fadeOut(withDuration: 0.16),
            .removeFromParent()
        ]))
    }

    private func spawnWaterSplash(at point: CGPoint) {
        for _ in 0..<16 {
            let drop = SKShapeNode(circleOfRadius: CGFloat.random(in: 3.5...7))
            drop.fillColor = SKColor(red: 0.68, green: 0.94, blue: 1.0, alpha: 0.92)
            drop.strokeColor = .clear
            drop.position = point
            fxLayer.addChild(drop)
            let dx = CGFloat.random(in: -75...75)
            let dy = CGFloat.random(in: 45...145)
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
                .moveBy(x: 0, y: 58, duration: 1.05),
                .sequence([.wait(forDuration: 0.55), .fadeOut(withDuration: 0.50)])
            ]),
            .removeFromParent()
        ]))
    }
}
