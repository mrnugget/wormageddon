import SpriteKit

final class WormNode: SKNode {
    let wormID: Int
    let teamColor: SKColor
    let accessory: TeamAccessoryStyle

    private let groundShadow = SKShapeNode(ellipseOf: CGSize(width: 26, height: 8))
    private let bodyContainer = SKNode()
    private let tailSegment = SKShapeNode()
    private let torsoSegment = SKShapeNode()
    private let bellyHighlight = SKShapeNode()
    private let headSegment = SKShapeNode()
    private let rosyCheek = SKShapeNode(ellipseOf: CGSize(width: 5.5, height: 3.4))
    private let smileMouth = SKShapeNode()
    private let panicMouth = SKShapeNode(circleOfRadius: 3.0)
    private let headband = SKShapeNode()
    private let bandanaTail = SKShapeNode()
    private let leftEye = SKShapeNode(circleOfRadius: 4.3)
    private let rightEye = SKShapeNode(circleOfRadius: 4.3)
    private let leftPupil = SKShapeNode(circleOfRadius: 2.0)
    private let rightPupil = SKShapeNode(circleOfRadius: 2.0)
    private let weaponPivot = SKNode()
    private let weaponGraphic = SKNode()

    private let tombstoneNode = SKNode()

    private let badgeContainer = SKNode()
    private let badgeBg = SKShapeNode()
    private let nameLabel = Art.label(20, .bold)
    private let hpLabel = Art.label(20, .heavy)
    private let activePointer = SKShapeNode()

    private var renderedWeapon: WeaponKind?
    private static let skin = SKColor(red: 1.0, green: 0.74, blue: 0.72, alpha: 1)
    private var showingTombstone = false

    init(worm: WormState, team: TeamDescriptor) {
        self.wormID = worm.id
        self.teamColor = team.color
        self.accessory = team.accessory
        super.init()

        buildShadow()
        buildBody()
        buildTombstone()
        buildBadge(name: worm.name)
        buildActivePointer()

        tombstoneNode.isHidden = true
        activePointer.isHidden = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildShadow() {
        groundShadow.fillColor = Art.ink.withAlphaComponent(0.35)
        groundShadow.strokeColor = .clear
        groundShadow.position = CGPoint(x: 0, y: -15)
        groundShadow.zPosition = -2
        addChild(groundShadow)
    }

    private func buildBody() {
        // Same gouache world as the Painter assets: warm pink skin, plum ink line
        let skin = WormNode.skin
        let skinDark = Art.ink
        let skinShade = SKColor(red: 0.93, green: 0.55, blue: 0.60, alpha: 1)
        let skinLight = SKColor(red: 1.00, green: 0.92, blue: 0.86, alpha: 0.75)

        // Curled worm tail behind
        tailSegment.path = CGPath(ellipseIn: CGRect(x: -18, y: -14, width: 17, height: 11.5), transform: nil)
        tailSegment.fillColor = skinShade
        tailSegment.strokeColor = skinDark
        tailSegment.lineWidth = 2.8
        bodyContainer.addChild(tailSegment)

        // Upright sculpted worm torso
        torsoSegment.path = CGPath(roundedRect: CGRect(x: -10.5, y: -14, width: 21, height: 25), cornerWidth: 10.5, cornerHeight: 10.5, transform: nil)
        torsoSegment.fillColor = skin
        torsoSegment.strokeColor = skinDark
        torsoSegment.lineWidth = 2.8
        bodyContainer.addChild(torsoSegment)

        // Soft glossy highlight along front curve
        bellyHighlight.path = CGPath(ellipseIn: CGRect(x: -2, y: -10, width: 8, height: 15), transform: nil)
        bellyHighlight.fillColor = skinLight
        bellyHighlight.strokeColor = .clear
        bodyContainer.addChild(bellyHighlight)

        // Head
        headSegment.path = CGPath(ellipseIn: CGRect(x: -10.5, y: 2.5, width: 22, height: 21), transform: nil)
        headSegment.fillColor = skin
        headSegment.strokeColor = skinDark
        headSegment.lineWidth = 2.8
        bodyContainer.addChild(headSegment)

        // Rosy cheek
        rosyCheek.fillColor = SKColor(red: 1.0, green: 0.44, blue: 0.50, alpha: 0.36)
        rosyCheek.strokeColor = .clear
        rosyCheek.position = CGPoint(x: 6.5, y: 8.0)
        bodyContainer.addChild(rosyCheek)

        // Expressive smile & airborne "O!" mouth
        let smilePath = CGMutablePath()
        smilePath.move(to: CGPoint(x: 3.5, y: 6.8))
        smilePath.addQuadCurve(to: CGPoint(x: 8.8, y: 7.4), control: CGPoint(x: 6.4, y: 4.4))
        smileMouth.path = smilePath
        smileMouth.strokeColor = skinDark
        smileMouth.lineWidth = 1.6
        smileMouth.lineCap = .round
        bodyContainer.addChild(smileMouth)

        panicMouth.fillColor = SKColor(red: 0.45, green: 0.14, blue: 0.18, alpha: 1)
        panicMouth.strokeColor = skinDark
        panicMouth.lineWidth = 1.2
        panicMouth.position = CGPoint(x: 6.5, y: 6.5)
        panicMouth.isHidden = true
        bodyContainer.addChild(panicMouth)

        // Team headband + fluttering bandana tails
        headband.path = CGPath(roundedRect: CGRect(x: -11, y: 15, width: 23, height: 6.0), cornerWidth: 3.0, cornerHeight: 3.0, transform: nil)
        headband.fillColor = teamColor
        headband.strokeColor = Art.ink
        headband.lineWidth = 2.0
        bodyContainer.addChild(headband)

        let tailPath = CGMutablePath()
        tailPath.move(to: CGPoint(x: -9.5, y: 17))
        tailPath.addLine(to: CGPoint(x: -21, y: 21.5))
        tailPath.addLine(to: CGPoint(x: -18, y: 16.5))
        tailPath.addLine(to: CGPoint(x: -22, y: 12))
        tailPath.addLine(to: CGPoint(x: -9.5, y: 15))
        tailPath.closeSubpath()
        bandanaTail.path = tailPath
        bandanaTail.fillColor = teamColor
        bandanaTail.strokeColor = Art.ink
        bandanaTail.lineWidth = 1.8
        bodyContainer.addChild(bandanaTail)

        buildTeamAccessory()

        // Expressive glossy eyes with crisp catchlights
        for (eye, pupil, xPos) in [(leftEye, leftPupil, CGFloat(1.2)), (rightEye, rightPupil, CGFloat(7.8))] {
            eye.fillColor = .white
            eye.strokeColor = skinDark
            eye.lineWidth = 1.3
            eye.position = CGPoint(x: xPos, y: 12.2)

            pupil.fillColor = Art.ink
            pupil.strokeColor = .clear
            pupil.position = CGPoint(x: 1.2, y: 0)

            let glint = SKShapeNode(circleOfRadius: 0.85)
            glint.fillColor = .white
            glint.strokeColor = .clear
            glint.position = CGPoint(x: 0.8, y: 0.9)
            pupil.addChild(glint)

            eye.addChild(pupil)
            bodyContainer.addChild(eye)
        }

        // Weapon pivot mounted at chest
        weaponPivot.position = CGPoint(x: 3.5, y: 2.0)
        weaponPivot.addChild(weaponGraphic)
        bodyContainer.addChild(weaponPivot)

        addChild(bodyContainer)
    }

    private func buildTeamAccessory() {
        switch accessory {
        case .ladybugDots:
            // Miraculous ladybug polka dots on the crimson headband!
            for (x, y) in [(-6.5, 18.0), (0.0, 18.2), (6.5, 17.8)] as [(CGFloat, CGFloat)] {
                let dot = SKShapeNode(circleOfRadius: 1.8)
                dot.fillColor = Art.ink
                dot.strokeColor = .clear
                dot.position = CGPoint(x: x, y: y)
                bodyContainer.addChild(dot)
            }

        case .wizardStar:
            // Hogwarts-style miniature pointed wizard cap + golden star!
            let hatPath = CGMutablePath()
            hatPath.move(to: CGPoint(x: -10, y: 20))
            hatPath.addLine(to: CGPoint(x: -2, y: 33))
            hatPath.addLine(to: CGPoint(x: 9, y: 20))
            hatPath.closeSubpath()
            let hat = SKShapeNode(path: hatPath)
            hat.fillColor = SKColor(red: 0.20, green: 0.36, blue: 0.82, alpha: 1)
            hat.strokeColor = Art.ink
            hat.lineWidth = 2.0
            bodyContainer.addChild(hat)

            let star = SKShapeNode(circleOfRadius: 2.1)
            star.fillColor = Art.sun
            star.strokeColor = Art.ink
            star.lineWidth = 1
            star.position = CGPoint(x: 0, y: 24.5)
            bodyContainer.addChild(star)

        case .kittyEars:
            // Cute sleek Gabby/Bluey ear headband notches!
            for xOff in [-5.5, 4.5] as [CGFloat] {
                let earPath = CGMutablePath()
                earPath.move(to: CGPoint(x: xOff - 3.8, y: 20))
                earPath.addLine(to: CGPoint(x: xOff, y: 28))
                earPath.addLine(to: CGPoint(x: xOff + 3.8, y: 20))
                earPath.closeSubpath()
                let ear = SKShapeNode(path: earPath)
                ear.fillColor = teamColor
                ear.strokeColor = Art.ink
                ear.lineWidth = 2.0
                bodyContainer.addChild(ear)

                let inner = SKShapeNode(circleOfRadius: 1.5)
                inner.fillColor = SKColor(red: 1.0, green: 0.76, blue: 0.82, alpha: 0.9)
                inner.strokeColor = .clear
                inner.position = CGPoint(x: xOff, y: 22.8)
                bodyContainer.addChild(inner)
            }
        }
    }

    private func buildTombstone() {
        let stone = SKSpriteNode(imageNamed: "grave_marker")
        stone.setScale(36 / max(1, stone.size.height))
        stone.anchorPoint = CGPoint(x: 0.5, y: 0.05)
        stone.position = CGPoint(x: 0, y: -16)
        tombstoneNode.addChild(stone)

        let teamStrip = SKShapeNode(rectOf: CGSize(width: 18, height: 5), cornerRadius: 2.5)
        teamStrip.fillColor = teamColor
        teamStrip.strokeColor = Art.ink
        teamStrip.lineWidth = 1.5
        teamStrip.position = CGPoint(x: 0, y: -1)
        tombstoneNode.addChild(teamStrip)

        addChild(tombstoneNode)
    }

    private func buildBadge(name: String) {
        badgeContainer.position = CGPoint(x: 0, y: 46)

        let pillWidth = max(96.0, CGFloat(name.count) * 8.6 + 28.0)
        badgeBg.path = CGPath(roundedRect: CGRect(x: -pillWidth * 0.5, y: -13, width: pillWidth, height: 36), cornerWidth: 12, cornerHeight: 12, transform: nil)
        badgeBg.fillColor = Art.inkDeep.withAlphaComponent(0.9)
        badgeBg.strokeColor = teamColor
        badgeBg.lineWidth = 2.2
        badgeContainer.addChild(badgeBg)

        nameLabel.text = name
        nameLabel.fontSize = 13.5
        nameLabel.fontColor = Art.cream
        nameLabel.verticalAlignmentMode = .center
        nameLabel.position = CGPoint(x: 0, y: 12)
        badgeContainer.addChild(nameLabel)

        let hpChip = SKShapeNode(rectOf: CGSize(width: 44, height: 16), cornerRadius: 8)
        hpChip.fillColor = teamColor.withAlphaComponent(0.55)
        hpChip.strokeColor = .clear
        hpChip.position = CGPoint(x: 0, y: -4)
        badgeContainer.addChild(hpChip)

        hpLabel.text = "100"
        hpLabel.fontSize = 14
        hpLabel.fontColor = Art.cream
        hpLabel.verticalAlignmentMode = .center
        hpLabel.position = CGPoint(x: 0, y: -4)
        badgeContainer.addChild(hpLabel)

        addChild(badgeContainer)
    }

    private func buildActivePointer() {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: -11, y: 15))
        p.addLine(to: CGPoint(x: 11, y: 15))
        p.closeSubpath()
        activePointer.path = p
        activePointer.fillColor = Art.sun
        activePointer.strokeColor = Art.ink
        activePointer.lineWidth = 3.5
        activePointer.lineJoin = .round
        activePointer.position = CGPoint(x: 0, y: 80)
        addChild(activePointer)
    }

    func sync(with worm: WormState, isActive: Bool, weapon: WeaponKind, time: TimeInterval) {
        position = worm.position

        if worm.isDrowned {
            isHidden = true
            return
        }
        isHidden = false

        if !worm.isAlive {
            if !showingTombstone {
                showingTombstone = true
                bodyContainer.isHidden = true
                badgeContainer.isHidden = true
                activePointer.isHidden = true
                groundShadow.isHidden = false
                tombstoneNode.isHidden = false
                tombstoneNode.zRotation = 0
            }
            return
        }

        showingTombstone = false
        bodyContainer.isHidden = false
        badgeContainer.isHidden = false
        tombstoneNode.isHidden = true
        groundShadow.isHidden = !worm.isGrounded

        // Facing & gentle walk squish / idle breathe
        let walkSquish = sin(worm.walkPhase) * 0.08
        let breathe = sin(time * 3.4 + Double(worm.id)) * 0.03
        bodyContainer.xScale = worm.facing * (1.0 - walkSquish)
        bodyContainer.yScale = 1.0 + walkSquish + CGFloat(breathe)
        bodyContainer.zRotation = worm.isGrounded ? 0 : worm.tumbleSpin

        // Bandana flutter
        bandanaTail.zRotation = CGFloat(sin(time * 8.0 + Double(worm.id)) * 0.14)

        // Pupils look toward aimAngle
        let px = cos(worm.aimAngle) * 1.6
        let py = sin(worm.aimAngle) * 1.6
        leftPupil.position = CGPoint(x: px, y: py)
        rightPupil.position = CGPoint(x: px, y: py)

        // Facial expression: surprised "O" mouth when flying or hurt!
        let isSurprised = !worm.isGrounded || worm.hurtTimer > 0
        smileMouth.isHidden = isSurprised
        panicMouth.isHidden = !isSurprised

        // Hurt flash
        if worm.hurtTimer > 0 {
            let flash = Int(worm.hurtTimer * 24) % 2 == 0
            torsoSegment.fillColor = flash ? Art.coral : WormNode.skin
            headSegment.fillColor = torsoSegment.fillColor
        } else {
            torsoSegment.fillColor = WormNode.skin
            headSegment.fillColor = torsoSegment.fillColor
        }

        // Held weapon only shown on active worm
        weaponPivot.isHidden = !isActive
        if isActive {
            weaponPivot.zRotation = (weapon == .jetpack) ? 0 : worm.aimAngle
            if renderedWeapon != weapon {
                rebuildWeaponGraphic(for: weapon)
                renderedWeapon = weapon
            }
        }

        // Badge HP & Active pointer bob
        hpLabel.text = "\(worm.health)"
        hpLabel.fontColor = worm.health <= 25 ? Art.coral : Art.cream
        badgeBg.lineWidth = isActive ? 3.5 : 2.2

        activePointer.isHidden = !isActive
        if isActive {
            activePointer.position.y = 80 + CGFloat(sin(time * 6.5) * 5.0)
        }
    }

    private func rebuildWeaponGraphic(for weapon: WeaponKind) {
        weaponGraphic.removeAllChildren()
        // Every held weapon uses its bold, simplified small Painter sprite.
        let sprite = SKSpriteNode(imageNamed: weapon.smallIconName)
        let side: CGFloat = (weapon == .bazooka || weapon == .shotgun || weapon == .blowtorch) ? 34 : 28
        sprite.setScale(side / max(1, max(sprite.size.width, sprite.size.height)))
        if weapon == .jetpack {
            sprite.position = CGPoint(x: -12, y: 2)
            sprite.zPosition = -1
        } else {
            sprite.position = CGPoint(x: side * 0.45, y: 2)
        }
        // Level diagonal-up-right tools with the aim vector.
        sprite.zRotation = (weapon == .bazooka || weapon == .blowtorch) ? -0.55 : (weapon == .shotgun ? -0.2 : 0)
        weaponGraphic.addChild(sprite)
    }
}
