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
    private let nameLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let hpLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let activePointer = SKShapeNode()

    private var renderedWeapon: WeaponKind?
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
        groundShadow.fillColor = SKColor(white: 0.0, alpha: 0.28)
        groundShadow.strokeColor = .clear
        groundShadow.position = CGPoint(x: 0, y: -15)
        groundShadow.zPosition = -2
        addChild(groundShadow)
    }

    private func buildBody() {
        let skin = SKColor(red: 1.00, green: 0.76, blue: 0.72, alpha: 1)
        let skinDark = SKColor(red: 0.48, green: 0.24, blue: 0.28, alpha: 1)
        let skinShade = SKColor(red: 0.94, green: 0.62, blue: 0.60, alpha: 1)
        let skinLight = SKColor(red: 1.00, green: 0.87, blue: 0.84, alpha: 0.65)

        // Curled worm tail behind
        tailSegment.path = CGPath(ellipseIn: CGRect(x: -18, y: -14, width: 17, height: 11.5), transform: nil)
        tailSegment.fillColor = skinShade
        tailSegment.strokeColor = skinDark
        tailSegment.lineWidth = 2.0
        bodyContainer.addChild(tailSegment)

        // Upright sculpted worm torso
        torsoSegment.path = CGPath(roundedRect: CGRect(x: -10.5, y: -14, width: 21, height: 25), cornerWidth: 10.5, cornerHeight: 10.5, transform: nil)
        torsoSegment.fillColor = skin
        torsoSegment.strokeColor = skinDark
        torsoSegment.lineWidth = 2.0
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
        headSegment.lineWidth = 2.0
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
        headband.strokeColor = SKColor(white: 0.08, alpha: 0.65)
        headband.lineWidth = 1.4
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
        bandanaTail.strokeColor = SKColor(white: 0.08, alpha: 0.5)
        bandanaTail.lineWidth = 1.2
        bodyContainer.addChild(bandanaTail)

        buildTeamAccessory()

        // Expressive glossy eyes with crisp catchlights
        for (eye, pupil, xPos) in [(leftEye, leftPupil, CGFloat(1.2)), (rightEye, rightPupil, CGFloat(7.8))] {
            eye.fillColor = .white
            eye.strokeColor = skinDark
            eye.lineWidth = 1.3
            eye.position = CGPoint(x: xPos, y: 12.2)

            pupil.fillColor = SKColor(white: 0.08, alpha: 1)
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
                dot.fillColor = SKColor(white: 0.08, alpha: 0.92)
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
            hat.fillColor = SKColor(red: 0.14, green: 0.34, blue: 0.78, alpha: 1)
            hat.strokeColor = SKColor(white: 0.08, alpha: 0.75)
            hat.lineWidth = 1.4
            bodyContainer.addChild(hat)

            let star = SKShapeNode(circleOfRadius: 2.1)
            star.fillColor = SKColor(red: 1.0, green: 0.86, blue: 0.28, alpha: 1)
            star.strokeColor = .clear
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
                ear.strokeColor = SKColor(white: 0.08, alpha: 0.65)
                ear.lineWidth = 1.3
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
        let stone = SKShapeNode(path: {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -12, y: -14))
            p.addLine(to: CGPoint(x: -12, y: 6))
            p.addArc(center: CGPoint(x: 0, y: 6), radius: 12, startAngle: .pi, endAngle: 0, clockwise: true)
            p.addLine(to: CGPoint(x: 12, y: -14))
            p.closeSubpath()
            return p
        }())
        stone.fillColor = SKColor(red: 0.62, green: 0.66, blue: 0.72, alpha: 1)
        stone.strokeColor = SKColor(red: 0.22, green: 0.24, blue: 0.28, alpha: 1)
        stone.lineWidth = 2.0
        tombstoneNode.addChild(stone)

        // Friendly little star emblem instead of grim cross (super cute & classic)
        let star = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        star.text = "✦"
        star.fontSize = 15
        star.fontColor = SKColor(white: 0.28, alpha: 0.9)
        star.verticalAlignmentMode = .center
        star.position = CGPoint(x: 0, y: 3)
        tombstoneNode.addChild(star)

        let teamStrip = SKShapeNode(rectOf: CGSize(width: 20, height: 3.5), cornerRadius: 1.5)
        teamStrip.fillColor = teamColor
        teamStrip.strokeColor = .clear
        teamStrip.position = CGPoint(x: 0, y: -10)
        tombstoneNode.addChild(teamStrip)

        addChild(tombstoneNode)
    }

    private func buildBadge(name: String) {
        badgeContainer.position = CGPoint(x: 0, y: 46)

        let pillWidth = max(106.0, CGFloat(name.count) * 8.4 + 26.0)
        badgeBg.path = CGPath(roundedRect: CGRect(x: -pillWidth * 0.5, y: -12, width: pillWidth, height: 34), cornerWidth: 10, cornerHeight: 10, transform: nil)
        badgeBg.fillColor = SKColor(red: 0.08, green: 0.10, blue: 0.17, alpha: 0.84)
        badgeBg.strokeColor = teamColor.withAlphaComponent(0.95)
        badgeBg.lineWidth = 2.0
        badgeContainer.addChild(badgeBg)

        nameLabel.text = name
        nameLabel.fontSize = 13
        nameLabel.fontColor = .white
        nameLabel.verticalAlignmentMode = .center
        nameLabel.position = CGPoint(x: 0, y: 11)
        badgeContainer.addChild(nameLabel)

        hpLabel.text = "100"
        hpLabel.fontSize = 14
        hpLabel.fontColor = teamColor
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
        activePointer.fillColor = SKColor(red: 1.0, green: 0.88, blue: 0.25, alpha: 1)
        activePointer.strokeColor = SKColor(white: 0.08, alpha: 0.85)
        activePointer.lineWidth = 2.0
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
            torsoSegment.fillColor = flash ? SKColor(red: 1, green: 0.42, blue: 0.42, alpha: 1) : SKColor(red: 1.0, green: 0.76, blue: 0.72, alpha: 1)
            headSegment.fillColor = torsoSegment.fillColor
        } else {
            torsoSegment.fillColor = SKColor(red: 1.0, green: 0.76, blue: 0.72, alpha: 1)
            headSegment.fillColor = torsoSegment.fillColor
        }

        // Held weapon only shown on active worm
        weaponPivot.isHidden = !isActive
        if isActive {
            weaponPivot.zRotation = worm.aimAngle
            if renderedWeapon != weapon {
                rebuildWeaponGraphic(for: weapon)
                renderedWeapon = weapon
            }
        }

        // Badge HP & Active pointer bob
        hpLabel.text = "\(worm.health)"
        hpLabel.fontColor = worm.health <= 25 ? SKColor(red: 1.0, green: 0.35, blue: 0.32, alpha: 1) : teamColor
        badgeBg.lineWidth = isActive ? 2.8 : 1.6

        activePointer.isHidden = !isActive
        if isActive {
            activePointer.position.y = 80 + CGFloat(sin(time * 6.5) * 5.0)
        }
    }

    private func rebuildWeaponGraphic(for weapon: WeaponKind) {
        weaponGraphic.removeAllChildren()

        switch weapon {
        case .bazooka:
            let tube = SKShapeNode(rectOf: CGSize(width: 30, height: 8.5), cornerRadius: 2.5)
            tube.fillColor = SKColor(red: 0.25, green: 0.40, blue: 0.26, alpha: 1)
            tube.strokeColor = SKColor(white: 0.1, alpha: 1)
            tube.lineWidth = 1.6
            tube.position = CGPoint(x: 4, y: 0)
            weaponGraphic.addChild(tube)

            let tip = SKShapeNode(rectOf: CGSize(width: 6.5, height: 10.5), cornerRadius: 1.5)
            tip.fillColor = SKColor(red: 0.94, green: 0.34, blue: 0.20, alpha: 1)
            tip.strokeColor = SKColor(white: 0.1, alpha: 1)
            tip.lineWidth = 1.3
            tip.position = CGPoint(x: 18, y: 0)
            weaponGraphic.addChild(tip)

        case .grenade:
            let body = SKShapeNode(circleOfRadius: 6.5)
            body.fillColor = SKColor(red: 0.26, green: 0.62, blue: 0.28, alpha: 1)
            body.strokeColor = SKColor(white: 0.1, alpha: 1)
            body.lineWidth = 1.5
            body.position = CGPoint(x: 11, y: 0)
            weaponGraphic.addChild(body)

            let pin = SKShapeNode(rectOf: CGSize(width: 5, height: 3))
            pin.fillColor = SKColor(red: 0.96, green: 0.86, blue: 0.32, alpha: 1)
            pin.strokeColor = .clear
            pin.position = CGPoint(x: 11, y: 7)
            weaponGraphic.addChild(pin)

        case .clusterBomb:
            let body = SKShapeNode(circleOfRadius: 7)
            body.fillColor = SKColor(red: 0.88, green: 0.22, blue: 0.34, alpha: 1)
            body.strokeColor = SKColor(white: 0.1, alpha: 1)
            body.lineWidth = 1.5
            body.position = CGPoint(x: 11, y: 0)
            weaponGraphic.addChild(body)

            let stripe = SKShapeNode(rectOf: CGSize(width: 12, height: 3))
            stripe.fillColor = SKColor(red: 1.0, green: 0.86, blue: 0.24, alpha: 1)
            stripe.strokeColor = .clear
            stripe.position = CGPoint(x: 11, y: 0)
            weaponGraphic.addChild(stripe)

        case .shotgun:
            let barrel = SKShapeNode(rectOf: CGSize(width: 28, height: 4.5), cornerRadius: 1.5)
            barrel.fillColor = SKColor(red: 0.30, green: 0.34, blue: 0.40, alpha: 1)
            barrel.strokeColor = SKColor(white: 0.08, alpha: 1)
            barrel.lineWidth = 1.3
            barrel.position = CGPoint(x: 12, y: 1)
            weaponGraphic.addChild(barrel)

            let stock = SKShapeNode(rectOf: CGSize(width: 12, height: 6), cornerRadius: 1.5)
            stock.fillColor = SKColor(red: 0.58, green: 0.36, blue: 0.20, alpha: 1)
            stock.strokeColor = SKColor(white: 0.08, alpha: 1)
            stock.lineWidth = 1.3
            stock.position = CGPoint(x: -2, y: -1.5)
            weaponGraphic.addChild(stock)

        case .airstrike:
            let radio = SKShapeNode(rectOf: CGSize(width: 9, height: 14), cornerRadius: 2)
            radio.fillColor = SKColor(red: 0.18, green: 0.24, blue: 0.34, alpha: 1)
            radio.strokeColor = SKColor(red: 0.35, green: 0.84, blue: 1.0, alpha: 1)
            radio.lineWidth = 1.5
            radio.position = CGPoint(x: 10, y: 1)
            weaponGraphic.addChild(radio)

            let antenna = SKShapeNode(rectOf: CGSize(width: 2, height: 11))
            antenna.fillColor = SKColor(white: 0.88, alpha: 1)
            antenna.strokeColor = .clear
            antenna.position = CGPoint(x: 12, y: 12)
            weaponGraphic.addChild(antenna)

        case .holyGrenade:
            let orb = SKShapeNode(circleOfRadius: 7.5)
            orb.fillColor = SKColor(red: 1.0, green: 0.84, blue: 0.22, alpha: 1)
            orb.strokeColor = SKColor(red: 0.62, green: 0.40, blue: 0.05, alpha: 1)
            orb.lineWidth = 1.8
            orb.position = CGPoint(x: 11, y: 0)
            weaponGraphic.addChild(orb)

            let cross = SKShapeNode(path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 11, y: 6))
                p.addLine(to: CGPoint(x: 11, y: 14))
                p.move(to: CGPoint(x: 8, y: 11))
                p.addLine(to: CGPoint(x: 14, y: 11))
                return p
            }())
            cross.strokeColor = SKColor(red: 1.0, green: 0.94, blue: 0.48, alpha: 1)
            cross.lineWidth = 2.0
            weaponGraphic.addChild(cross)
        }
    }
}
