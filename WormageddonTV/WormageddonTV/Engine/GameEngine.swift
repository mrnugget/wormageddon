import Foundation
import CoreGraphics
import SpriteKit

struct WormState: Identifiable {
    let id: Int
    let teamIndex: Int
    let name: String
    var position: CGPoint
    var velocity: CGVector = .zero
    var facing: CGFloat = 1 // +1 right, -1 left
    var aimAngle: CGFloat = 0.28 // Radians relative to horizontal facing direction (-1.35 ... +1.45)
    var health: Int = 100
    var isGrounded: Bool = false
    var isDrowned: Bool = false
    var walkPhase: CGFloat = 0
    var hurtTimer: TimeInterval = 0
    var fallStartY: CGFloat? = nil
    var tumbleSpin: CGFloat = 0

    var isAlive: Bool { health > 0 && !isDrowned }

    /// World aim angle in radians (0 = right, pi = left, pi/2 = up)
    var worldAimAngle: CGFloat {
        facing >= 0 ? aimAngle : (.pi - aimAngle)
    }

    var aimDirection: CGVector {
        CGVector(dx: cos(worldAimAngle), dy: sin(worldAimAngle))
    }
}

struct TeamState {
    let descriptor: TeamDescriptor
    var ammo: [WeaponKind: Int] // Missing key means infinite ammo
    var nextWormCursor: Int = 0
    var kills: Int = 0
    var totalDamageDealt: Int = 0

    func ammoCount(for weapon: WeaponKind) -> Int? {
        guard weapon.startingAmmo != nil else { return nil }
        return ammo[weapon] ?? 0
    }

    func canUse(_ weapon: WeaponKind) -> Bool {
        guard let count = ammoCount(for: weapon) else { return true }
        return count > 0
    }
}

struct ProjectileState: Identifiable {
    let id: Int
    let weapon: WeaponKind
    let ownerTeamIndex: Int
    let ownerWormID: Int
    var position: CGPoint
    var velocity: CGVector
    var fuseRemaining: TimeInterval? // nil = impact detonation
    var isClusterBomblet: Bool = false
    var age: TimeInterval = 0
    var rotation: CGFloat = 0
    var hasPlayedHolyChoir: Bool = false
}

enum CrateKind {
    case health(amount: Int)
    case weapon(WeaponKind)

    var label: String {
        switch self {
        case .health(let amt): return "+\(amt) LP"
        case .weapon(let w): return "+1 \(w.name)"
        }
    }
}

struct CrateState: Identifiable {
    let id: Int
    let kind: CrateKind
    var position: CGPoint
    var velocity: CGVector = .zero
    var isParachuting: Bool = true
    var isCollected: Bool = false
}

enum TurnPhase: Equatable {
    case turnBanner(remaining: TimeInterval)
    case playerControl
    case charging(power: CGFloat)
    case airstrikeAiming(targetX: CGFloat)
    case projectileInFlight
    case settling(remaining: TimeInterval)
    case matchOver(winnerTeamIndex: Int?)
}

enum GameEvent {
    case explosion(center: CGPoint, radius: CGFloat, isHoly: Bool)
    case shotgunTracer(from: CGPoint, to: CGPoint)
    case wormDamaged(wormID: Int, amount: Int, position: CGPoint)
    case wormDrowned(wormID: Int, position: CGPoint)
    case wormJumped(position: CGPoint, isBackflip: Bool)
    case projectileFired(weapon: WeaponKind, position: CGPoint)
    case grenadeBounce(position: CGPoint)
    case crateCollected(position: CGPoint, label: String, isHealth: Bool)
    case turnStarted(teamIndex: Int, wormName: String)
    case suddenDeathTriggered(waterY: CGFloat)
    case holyChoir(position: CGPoint)
    case matchEnded(winnerTeamIndex: Int?)
}

final class GameEngine {
    let config: MatchConfig
    let terrain: TerrainMap

    private(set) var teams: [TeamState] = []
    private(set) var worms: [WormState] = []
    private(set) var projectiles: [ProjectileState] = []
    private(set) var crates: [CrateState] = []

    private(set) var currentTeamIndex: Int = 0
    private(set) var activeWormID: Int = 0
    private(set) var turnNumber: Int = 1
    private(set) var turnTimeRemaining: TimeInterval
    private(set) var wind: CGFloat = 0 // -1.0 ... +1.0
    private(set) var waterY: CGFloat = WorldConstants.initialWaterY
    private(set) var selectedWeapon: WeaponKind = .bazooka
    private(set) var isWeaponBarOpen: Bool = false
    private(set) var weaponBarSelectionIndex: Int = 0
    private(set) var phase: TurnPhase = .turnBanner(remaining: 1.8)
    private(set) var shotgunShotsRemaining: Int = 0
    private(set) var lastExplosionPoint: CGPoint? = nil

    private var rng: SeededRNG
    private var nextProjectileID: Int = 1
    private var nextCrateID: Int = 1
    private var weaponBarNavCooldown: TimeInterval = 0
    private var airstrikeFromLeft: Bool = true
    private var pendingEvents: [GameEvent] = []

    var activeWorm: WormState? {
        worms.first(where: { $0.id == activeWormID })
    }

    var currentTeam: TeamState {
        teams[currentTeamIndex]
    }

    init(config: MatchConfig) {
        self.config = config
        self.turnTimeRemaining = config.turnDuration
        self.rng = SeededRNG(seed: config.seed)
        self.terrain = TerrainMap(style: config.mapStyle, theme: config.mapTheme, seed: config.seed)

        setupTeamsAndWorms()
        rollWind()
        startTurn(teamIndex: 0, isFirstTurn: true)
    }

    func drainEvents() -> [GameEvent] {
        let out = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        return out
    }

    // MARK: - Setup

    private func setupTeamsAndWorms() {
        let count = max(2, min(3, config.playerCount))
        teams = (0..<count).map { idx in
            let desc = TeamDescriptor.all[idx]
            var ammo: [WeaponKind: Int] = [:]
            for weapon in WeaponKind.allCases {
                if let start = weapon.startingAmmo {
                    ammo[weapon] = start
                }
            }
            return TeamState(descriptor: desc, ammo: ammo)
        }

        // Gather valid spawn X coordinates evenly distributed across solid ground above water
        let totalWorms = count * config.wormsPerTeam
        let spawnPoints = findSpawnPoints(count: totalWorms)

        // Interleave teams across spawn slots so teams start mixed across the map
        var wormID = 1
        var slotOrder = Array(0..<spawnPoints.count)
        // Deterministic Fisher-Yates shuffle
        for i in stride(from: slotOrder.count - 1, through: 1, by: -1) {
            let j = Int(rng.nextUInt64() % UInt64(i + 1))
            slotOrder.swapAt(i, j)
        }

        var slotCursor = 0
        for wIdx in 0..<config.wormsPerTeam {
            for tIdx in 0..<count {
                let point = spawnPoints[slotOrder[slotCursor % slotOrder.count]]
                slotCursor += 1
                let nameList = teams[tIdx].descriptor.wormNames
                let name = nameList[wIdx % nameList.count]
                let facing: CGFloat = point.x < WorldConstants.width * 0.5 ? 1 : -1
                worms.append(WormState(
                    id: wormID,
                    teamIndex: tIdx,
                    name: name,
                    position: point,
                    facing: facing,
                    isGrounded: true
                ))
                wormID += 1
            }
        }
    }

    private func findSpawnPoints(count: Int) -> [CGPoint] {
        var candidates: [CGPoint] = []
        let margin: CGFloat = 150
        let sampleCount = 72
        let usableWidth = WorldConstants.width - margin * 2

        for i in 0..<sampleCount {
            let x = margin + usableWidth * (CGFloat(i) / CGFloat(sampleCount - 1))
            if let sy = terrain.surfaceY(atWorldX: x), sy > WorldConstants.initialWaterY + 34, sy < WorldConstants.height - 160 {
                // Verify terrain isn't a tiny needle spike by checking neighbors
                if let syL = terrain.surfaceY(atWorldX: x - 14),
                   let syR = terrain.surfaceY(atWorldX: x + 14),
                   abs(syL - sy) < 36, abs(syR - sy) < 36 {
                    candidates.append(CGPoint(x: x, y: sy + WorldConstants.wormRadius + 2))
                }
            }
        }

        if candidates.isEmpty {
            // Fallback safe positions
            return (0..<count).map { i in
                CGPoint(x: 320 + CGFloat(i) * 160, y: 600)
            }
        }

        // Pick `count` well-spaced points from candidates
        var picked: [CGPoint] = []
        let strideStep = max(1, candidates.count / max(1, count))
        for i in 0..<count {
            let idx = min(candidates.count - 1, i * strideStep + strideStep / 2)
            picked.append(candidates[idx])
        }
        return picked
    }

    // MARK: - Main Simulation Tick

    func update(dt rawDt: TimeInterval, input: inout InputSnapshot) {
        let dt = min(rawDt, 1.0 / 30.0)
        guard dt > 0 else { return }

        if weaponBarNavCooldown > 0 {
            weaponBarNavCooldown = max(0, weaponBarNavCooldown - dt)
        }

        if case .matchOver = phase {
            input.consumePulses()
            return
        }

        // Always update hurt timers
        for i in worms.indices {
            if worms[i].hurtTimer > 0 {
                worms[i].hurtTimer = max(0, worms[i].hurtTimer - dt)
            }
        }

        // Handle turn phases
        switch phase {
        case .turnBanner(let remaining):
            if remaining - dt <= 0 || input.hasAnyAction {
                phase = .playerControl
            } else {
                phase = .turnBanner(remaining: remaining - dt)
            }

        case .playerControl:
            handlePlayerControl(dt: dt, input: &input)

        case .charging(let power):
            handleCharging(dt: dt, currentPower: power, input: &input)

        case .airstrikeAiming(let targetX):
            handleAirstrikeAiming(dt: dt, targetX: targetX, input: &input)

        case .projectileInFlight:
            break

        case .settling(let remaining):
            if !anyBodiesMoving() {
                if remaining - dt <= 0 {
                    advanceTurnOrEndMatch()
                } else {
                    phase = .settling(remaining: remaining - dt)
                }
            }

        case .matchOver:
            break
        }

        // Simulate physics for all worms, projectiles, and crates
        updateWormsPhysics(dt: dt)
        updateProjectilesPhysics(dt: dt)
        updateCratesPhysics(dt: dt)

        // Transition out of projectileInFlight once all projectiles have detonated/exited
        if case .projectileInFlight = phase, projectiles.isEmpty {
            if shotgunShotsRemaining > 0, let active = activeWorm, active.isAlive {
                phase = .playerControl
            } else {
                phase = .settling(remaining: 0.95)
            }
        }

        // Check if active worm died mid-control
        if case .playerControl = phase {
            if let active = activeWorm, !active.isAlive {
                isWeaponBarOpen = false
                phase = .settling(remaining: 1.0)
            }
        }

        input.consumePulses()
    }

    // MARK: - Player Control & Weapons

    private func handlePlayerControl(dt: TimeInterval, input: inout InputSnapshot) {
        // Turn timer counts down during player control
        turnTimeRemaining = max(0, turnTimeRemaining - dt)
        if turnTimeRemaining <= 0 {
            isWeaponBarOpen = false
            shotgunShotsRemaining = 0
            phase = .settling(remaining: 0.6)
            return
        }

        // Weapon bar toggle
        if input.toggleWeaponBarPressed {
            isWeaponBarOpen.toggle()
            if isWeaponBarOpen {
                weaponBarSelectionIndex = selectedWeapon.rawValue
            }
            return
        }

        // Quick weapon cycling (L1/R1 on controller)
        if input.prevWeaponPressed {
            cycleWeapon(delta: -1)
        } else if input.nextWeaponPressed {
            cycleWeapon(delta: 1)
        }

        // If weapon bar is open, Left/Right navigates weapons and Select confirms
        if isWeaponBarOpen {
            if abs(input.moveX) > 0.35 && weaponBarNavCooldown <= 0 {
                let step = input.moveX > 0 ? 1 : -1
                let count = WeaponKind.allCases.count
                weaponBarSelectionIndex = (weaponBarSelectionIndex + step + count) % count
                weaponBarNavCooldown = 0.22
            }
            if input.firePressed {
                let chosen = WeaponKind.allCases[weaponBarSelectionIndex]
                if currentTeam.canUse(chosen) {
                    selectedWeapon = chosen
                    isWeaponBarOpen = false
                    if chosen == .airstrike {
                        let startX = activeWorm?.position.x ?? WorldConstants.width * 0.5
                        phase = .airstrikeAiming(targetX: startX)
                    }
                }
            }
            return
        }

        guard let wormIdx = worms.firstIndex(where: { $0.id == activeWormID }), worms[wormIdx].isAlive else {
            return
        }

        // Movement (walking on ground)
        if abs(input.moveX) > 0.2 && worms[wormIdx].isGrounded {
            let dir: CGFloat = input.moveX > 0 ? 1 : -1
            worms[wormIdx].facing = dir
            walkWorm(at: wormIdx, direction: dir, speedScale: min(1.0, abs(input.moveX)), dt: dt)
        } else if abs(input.moveX) > 0.2 {
            // Slight air steering / turning
            worms[wormIdx].facing = input.moveX > 0 ? 1 : -1
        }

        // Aiming: direct right-stick aim OR up/down angle adjustment
        if hypot(input.directAimX, input.directAimY) > 0.35 {
            let facing: CGFloat = input.directAimX >= 0 ? 1 : -1
            worms[wormIdx].facing = facing
            let localX = abs(input.directAimX)
            let targetAngle = atan2(input.directAimY, max(0.05, localX))
            worms[wormIdx].aimAngle = max(-1.35, min(1.45, targetAngle))
        } else if abs(input.aimY) > 0.15 {
            let aimSpeed: CGFloat = 1.65
            worms[wormIdx].aimAngle = max(-1.35, min(1.45, worms[wormIdx].aimAngle + input.aimY * aimSpeed * CGFloat(dt)))
        }

        // Jumping
        if input.jumpPressed && worms[wormIdx].isGrounded {
            let dir = worms[wormIdx].facing
            worms[wormIdx].velocity = CGVector(dx: dir * 185, dy: 345)
            worms[wormIdx].isGrounded = false
            worms[wormIdx].fallStartY = worms[wormIdx].position.y
            pendingEvents.append(.wormJumped(position: worms[wormIdx].position, isBackflip: false))
        } else if input.backflipPressed && worms[wormIdx].isGrounded {
            let dir = worms[wormIdx].facing
            worms[wormIdx].velocity = CGVector(dx: -dir * 105, dy: 430)
            worms[wormIdx].isGrounded = false
            worms[wormIdx].fallStartY = worms[wormIdx].position.y
            pendingEvents.append(.wormJumped(position: worms[wormIdx].position, isBackflip: true))
        }

        // Firing
        if input.firePressed {
            if !currentTeam.canUse(selectedWeapon) {
                selectedWeapon = .bazooka
            }
            if selectedWeapon == .airstrike {
                phase = .airstrikeAiming(targetX: worms[wormIdx].position.x)
            } else if selectedWeapon == .shotgun {
                fireShotgun(from: wormIdx)
            } else if selectedWeapon.usesChargePower {
                phase = .charging(power: 0.14)
            }
        }
    }

    private func handleCharging(dt: TimeInterval, currentPower: CGFloat, input: inout InputSnapshot) {
        let chargeRate: CGFloat = 0.78
        let nextPower = min(1.0, currentPower + chargeRate * CGFloat(dt))

        if input.fireReleased || !input.fireHeld || nextPower >= 1.0 {
            fireChargedWeapon(power: nextPower)
        } else {
            phase = .charging(power: nextPower)
        }
    }

    private func handleAirstrikeAiming(dt: TimeInterval, targetX: CGFloat, input: inout InputSnapshot) {
        turnTimeRemaining = max(0, turnTimeRemaining - dt)
        if turnTimeRemaining <= 0 {
            phase = .settling(remaining: 0.5)
            return
        }

        if input.toggleWeaponBarPressed {
            // Cancel airstrike back to normal control
            phase = .playerControl
            isWeaponBarOpen = true
            weaponBarSelectionIndex = selectedWeapon.rawValue
            return
        }

        let moveSpeed: CGFloat = 680
        let clampedX = max(140, min(WorldConstants.width - 140, targetX + input.moveX * moveSpeed * CGFloat(dt)))
        if input.aimY > 0.4 {
            airstrikeFromLeft = true
        } else if input.aimY < -0.4 {
            airstrikeFromLeft = false
        }

        if input.firePressed {
            launchAirstrike(targetX: clampedX)
        } else {
            phase = .airstrikeAiming(targetX: clampedX)
        }
    }

    private func cycleWeapon(delta: Int) {
        let all = WeaponKind.allCases
        for step in 1...all.count {
            let idx = (selectedWeapon.rawValue + delta * step + all.count * 4) % all.count
            let candidate = all[idx]
            if currentTeam.canUse(candidate) {
                selectedWeapon = candidate
                weaponBarSelectionIndex = idx
                return
            }
        }
    }

    // MARK: - Firing Weapons

    private func consumeAmmo(_ weapon: WeaponKind) {
        guard weapon.startingAmmo != nil else { return }
        let current = teams[currentTeamIndex].ammo[weapon] ?? 0
        teams[currentTeamIndex].ammo[weapon] = max(0, current - 1)
    }

    private func fireChargedWeapon(power: CGFloat) {
        guard let worm = activeWorm, worm.isAlive else {
            phase = .settling(remaining: 0.5)
            return
        }

        let weapon = selectedWeapon
        consumeAmmo(weapon)

        let dir = worm.aimDirection
        let muzzle = CGPoint(
            x: worm.position.x + dir.dx * (WorldConstants.wormRadius + 10),
            y: worm.position.y + 4 + dir.dy * (WorldConstants.wormRadius + 10)
        )

        let minSpeed: CGFloat = 290
        let maxSpeed: CGFloat = (weapon == .bazooka) ? 1020 : 880
        let speed = minSpeed + (maxSpeed - minSpeed) * power

        let fuse: TimeInterval?
        switch weapon {
        case .grenade, .clusterBomb: fuse = 3.0
        case .holyGrenade: fuse = 3.5
        default: fuse = nil
        }

        let proj = ProjectileState(
            id: nextProjectileID,
            weapon: weapon,
            ownerTeamIndex: worm.teamIndex,
            ownerWormID: worm.id,
            position: muzzle,
            velocity: CGVector(dx: dir.dx * speed, dy: dir.dy * speed),
            fuseRemaining: fuse,
            rotation: atan2(dir.dy, dir.dx)
        )
        nextProjectileID += 1
        projectiles.append(proj)
        pendingEvents.append(.projectileFired(weapon: weapon, position: muzzle))
        phase = .projectileInFlight
    }

    private func fireShotgun(from wormIdx: Int) {
        let worm = worms[wormIdx]
        if shotgunShotsRemaining == 0 {
            shotgunShotsRemaining = 2
        }
        shotgunShotsRemaining -= 1

        let dir = worm.aimDirection
        let start = CGPoint(
            x: worm.position.x + dir.dx * (WorldConstants.wormRadius + 6),
            y: worm.position.y + 4 + dir.dy * (WorldConstants.wormRadius + 6)
        )
        let maxRange: CGFloat = 860
        let end = CGPoint(x: start.x + dir.dx * maxRange, y: start.y + dir.dy * maxRange)

        // Step along ray to find first worm or terrain hit
        let steps = 180
        var hitPoint = end
        var hitSomething = false

        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            if p.x < 0 || p.x > WorldConstants.width || p.y < 0 || p.y > WorldConstants.height {
                hitPoint = p
                break
            }
            if let hitWorm = worms.first(where: { $0.isAlive && $0.id != worm.id && hypot($0.position.x - p.x, $0.position.y - p.y) <= WorldConstants.wormRadius + 4 }) {
                hitPoint = hitWorm.position
                hitSomething = true
                break
            }
            if terrain.isSolid(worldPoint: p) {
                hitPoint = p
                hitSomething = true
                break
            }
        }

        pendingEvents.append(.projectileFired(weapon: .shotgun, position: start))
        pendingEvents.append(.shotgunTracer(from: start, to: hitPoint))

        if hitSomething {
            triggerExplosion(
                at: hitPoint,
                radius: WeaponKind.shotgun.explosionRadius,
                maxDamage: WeaponKind.shotgun.maxDamage,
                knockback: WeaponKind.shotgun.knockbackSpeed,
                ownerTeamIndex: worm.teamIndex,
                isHoly: false
            )
        }

        if shotgunShotsRemaining > 0 {
            phase = .playerControl
        } else {
            phase = .settling(remaining: 0.95)
        }
    }

    private func launchAirstrike(targetX: CGFloat) {
        guard let worm = activeWorm else { return }
        consumeAmmo(.airstrike)

        let dirX: CGFloat = airstrikeFromLeft ? 1 : -1
        for i in 0..<5 {
            let offset = CGFloat(i - 2) * 52
            let spawnX = targetX + offset - dirX * 260
            let spawnY = WorldConstants.height - 20 + CGFloat(i) * 28
            let proj = ProjectileState(
                id: nextProjectileID,
                weapon: .airstrike,
                ownerTeamIndex: worm.teamIndex,
                ownerWormID: worm.id,
                position: CGPoint(x: spawnX, y: spawnY),
                velocity: CGVector(dx: dirX * 195, dy: -210),
                fuseRemaining: nil,
                rotation: atan2(-210, dirX * 195)
            )
            nextProjectileID += 1
            projectiles.append(proj)
        }
        pendingEvents.append(.projectileFired(weapon: .airstrike, position: CGPoint(x: targetX, y: WorldConstants.height - 40)))
        phase = .projectileInFlight
    }

    // MARK: - Worm Movement & Physics

    private func walkWorm(at idx: Int, direction: CGFloat, speedScale: CGFloat, dt: TimeInterval) {
        let stepX = direction * WorldConstants.wormWalkSpeed * speedScale * CGFloat(dt)
        let candidateX = max(24, min(WorldConstants.width - 24, worms[idx].position.x + stepX))
        let currentY = worms[idx].position.y

        // Try climbing up to wormMaxStepUp or stepping down smoothly
        var foundY: CGFloat? = nil
        let r = WorldConstants.wormRadius

        // Check foot support around candidateX
        for dy in stride(from: Int(WorldConstants.wormMaxStepUp), through: -Int(WorldConstants.wormMaxStepUp), by: -2) {
            let testY = currentY + CGFloat(dy)
            let feet = CGPoint(x: candidateX, y: testY - r)
            let body = CGPoint(x: candidateX, y: testY)
            if terrain.isSolid(worldPoint: feet) && !terrain.isSolid(worldPoint: body) {
                foundY = testY + 1
                break
            }
        }

        if let y = foundY {
            worms[idx].position = CGPoint(x: candidateX, y: y)
            worms[idx].walkPhase += CGFloat(dt) * 12.0
            worms[idx].isGrounded = true
        } else {
            // Might be walking off a ledge! Check if body at candidateX is clear of terrain
            let nextBody = CGPoint(x: candidateX, y: currentY)
            if !terrain.isSolidCircle(center: nextBody, radius: r * 0.7) {
                worms[idx].position.x = candidateX
                worms[idx].walkPhase += CGFloat(dt) * 12.0
                worms[idx].isGrounded = false
                worms[idx].fallStartY = currentY
            }
        }
    }

    private func updateWormsPhysics(dt: TimeInterval) {
        let r = WorldConstants.wormRadius

        for i in worms.indices {
            guard worms[i].isAlive else { continue }

            // Check water drowning
            if worms[i].position.y <= waterY + 4 {
                worms[i].isDrowned = true
                worms[i].health = 0
                worms[i].velocity = .zero
                pendingEvents.append(.wormDrowned(wormID: worms[i].id, position: CGPoint(x: worms[i].position.x, y: waterY)))
                continue
            }

            // If grounded, verify ground still exists underneath (e.g., crater carved below!)
            if worms[i].isGrounded {
                let underFoot = CGPoint(x: worms[i].position.x, y: worms[i].position.y - r - 3)
                if !terrain.isSolid(worldPoint: underFoot) {
                    worms[i].isGrounded = false
                    worms[i].fallStartY = worms[i].position.y
                } else {
                    continue
                }
            }

            // Airborne physics
            worms[i].velocity.dy += WorldConstants.gravity * CGFloat(dt)
            let speed = hypot(worms[i].velocity.dx, worms[i].velocity.dy)
            if speed > 140 {
                worms[i].tumbleSpin += CGFloat(dt) * (worms[i].velocity.dx >= 0 ? -9.0 : 9.0)
            } else {
                worms[i].tumbleSpin = 0
            }

            // Sub-step movement to prevent tunneling through thin terrain
            let subSteps = max(1, Int(ceil(speed * CGFloat(dt) / 5.0)))
            let subDt = CGFloat(dt) / CGFloat(subSteps)

            for _ in 0..<subSteps {
                let nextPos = CGPoint(
                    x: worms[i].position.x + worms[i].velocity.dx * subDt,
                    y: worms[i].position.y + worms[i].velocity.dy * subDt
                )

                // Out of horizontal bounds -> drown
                if nextPos.x < -30 || nextPos.x > WorldConstants.width + 30 || nextPos.y <= waterY + 4 {
                    worms[i].position = nextPos
                    worms[i].isDrowned = true
                    worms[i].health = 0
                    worms[i].velocity = .zero
                    pendingEvents.append(.wormDrowned(wormID: worms[i].id, position: CGPoint(x: max(40, min(WorldConstants.width - 40, nextPos.x)), y: waterY)))
                    break
                }

                if terrain.isSolidCircle(center: nextPos, radius: r * 0.85) {
                    let normal = terrain.surfaceNormal(at: nextPos)
                    let vn = worms[i].velocity.dx * normal.dx + worms[i].velocity.dy * normal.dy

                    if vn < -220 {
                        // Bounce off steep impact
                        let restitution: CGFloat = 0.32
                        worms[i].velocity.dx = (worms[i].velocity.dx - (1 + restitution) * vn * normal.dx) * 0.72
                        worms[i].velocity.dy = (worms[i].velocity.dy - (1 + restitution) * vn * normal.dy) * 0.72
                        worms[i].position.x += normal.dx * 2
                        worms[i].position.y += normal.dy * 2
                    } else if normal.dy > 0.38 {
                        // Landed on walkable ground!
                        applyFallDamageIfNeeded(wormIdx: i)
                        worms[i].velocity = .zero
                        worms[i].isGrounded = true
                        worms[i].tumbleSpin = 0
                        worms[i].fallStartY = nil
                        // Push slightly up out of terrain if embedded
                        var lift = 0
                        while lift < 16 && terrain.isSolid(worldPoint: CGPoint(x: worms[i].position.x, y: worms[i].position.y - r + 2)) {
                            worms[i].position.y += 1
                            lift += 1
                        }
                        break
                    } else {
                        // Wall slide
                        worms[i].velocity.dx *= -0.25
                        worms[i].position.x += normal.dx * 2
                        break
                    }
                } else {
                    worms[i].position = nextPos
                }
            }
        }
    }

    private func applyFallDamageIfNeeded(wormIdx: Int) {
        guard let startY = worms[wormIdx].fallStartY else { return }
        let drop = startY - worms[wormIdx].position.y
        if drop > 235 {
            let dmg = min(35, Int((drop - 220) / 14))
            if dmg > 0 {
                applyDamage(to: wormIdx, amount: dmg, attackerTeam: nil)
            }
        }
    }

    // MARK: - Projectile Physics & Explosions

    private func updateProjectilesPhysics(dt: TimeInterval) {
        var i = 0
        while i < projectiles.count {
            var p = projectiles[i]
            p.age += dt

            // Gravity + Wind
            p.velocity.dy += WorldConstants.gravity * CGFloat(dt)
            if p.weapon.affectedByWind {
                p.velocity.dx += wind * WorldConstants.maxWindAccel * CGFloat(dt)
            }

            // Fuse countdown
            if let fuse = p.fuseRemaining {
                let nextFuse = fuse - dt
                p.fuseRemaining = nextFuse

                if p.weapon == .holyGrenade && nextFuse <= 0.75 && !p.hasPlayedHolyChoir {
                    p.hasPlayedHolyChoir = true
                    pendingEvents.append(.holyChoir(position: p.position))
                }

                if nextFuse <= 0 {
                    projectiles.remove(at: i)
                    detonate(projectile: p)
                    continue
                }
            }

            let speed = hypot(p.velocity.dx, p.velocity.dy)
            if speed > 10 {
                if p.weapon == .bazooka || p.weapon == .airstrike || p.isClusterBomblet {
                    p.rotation = atan2(p.velocity.dy, p.velocity.dx)
                } else {
                    p.rotation += (p.velocity.dx >= 0 ? -1 : 1) * CGFloat(dt) * min(12, speed * 0.02)
                }
            }

            // Sub-step to avoid tunneling
            let subSteps = max(1, Int(ceil(speed * CGFloat(dt) / 6.0)))
            let subDt = CGFloat(dt) / CGFloat(subSteps)
            var detonatedOrRemoved = false

            for _ in 0..<subSteps {
                let nextPos = CGPoint(
                    x: p.position.x + p.velocity.dx * subDt,
                    y: p.position.y + p.velocity.dy * subDt
                )

                // Offscreen / Water splash removal
                if nextPos.y <= waterY || nextPos.x < -160 || nextPos.x > WorldConstants.width + 160 || nextPos.y > WorldConstants.height + 500 {
                    projectiles.remove(at: i)
                    if nextPos.y <= waterY {
                        pendingEvents.append(.wormDrowned(wormID: -1, position: CGPoint(x: max(40, min(WorldConstants.width - 40, nextPos.x)), y: waterY)))
                    }
                    detonatedOrRemoved = true
                    break
                }

                // Worm collision check (skip self for first 0.14s)
                let hitWorm = worms.first { w in
                    guard w.isAlive else { return false }
                    if w.id == p.ownerWormID && p.age < 0.16 { return false }
                    return hypot(w.position.x - nextPos.x, w.position.y - nextPos.y) <= WorldConstants.wormRadius + 5
                }

                let hitTerrain = terrain.isSolid(worldPoint: nextPos)

                if hitWorm != nil || hitTerrain {
                    if p.fuseRemaining == nil {
                        // Impact weapon (Bazooka, Airstrike, Cluster bomblet)
                        p.position = nextPos
                        projectiles.remove(at: i)
                        detonate(projectile: p)
                        detonatedOrRemoved = true
                        break
                    } else {
                        // Fuse weapon bounces off terrain / worms!
                        let normal: CGVector
                        if let hw = hitWorm {
                            let dx = nextPos.x - hw.position.x
                            let dy = nextPos.y - hw.position.y
                            let len = max(0.001, hypot(dx, dy))
                            normal = CGVector(dx: dx / len, dy: dy / len)
                        } else {
                            normal = terrain.surfaceNormal(at: nextPos)
                        }

                        let vn = p.velocity.dx * normal.dx + p.velocity.dy * normal.dy
                        if vn < 0 {
                            let bounce: CGFloat = (p.weapon == .holyGrenade) ? 0.42 : 0.56
                            p.velocity.dx = (p.velocity.dx - (1 + bounce) * vn * normal.dx) * 0.86
                            p.velocity.dy = (p.velocity.dy - (1 + bounce) * vn * normal.dy) * 0.86
                            if abs(vn) > 70 {
                                pendingEvents.append(.grenadeBounce(position: nextPos))
                            }
                        }
                        p.position.x += normal.dx * 2.5
                        p.position.y += normal.dy * 2.5
                        break
                    }
                } else {
                    p.position = nextPos
                }
            }

            if !detonatedOrRemoved {
                projectiles[i] = p
                i += 1
            }
        }
    }

    private func detonate(projectile p: ProjectileState) {
        let radius: CGFloat = p.isClusterBomblet ? 38 : p.weapon.explosionRadius
        let maxDamage: Int = p.isClusterBomblet ? 24 : p.weapon.maxDamage
        let knockback: CGFloat = p.isClusterBomblet ? 310 : p.weapon.knockbackSpeed

        triggerExplosion(
            at: p.position,
            radius: radius,
            maxDamage: maxDamage,
            knockback: knockback,
            ownerTeamIndex: p.ownerTeamIndex,
            isHoly: p.weapon == .holyGrenade
        )

        // Cluster bomb spawns 5 impact bomblets!
        if p.weapon == .clusterBomb && !p.isClusterBomblet {
            for k in 0..<5 {
                let spreadAngle = (.pi * 0.22) + (CGFloat(k) / 4.0) * (.pi * 0.56)
                let spd = rng.nextCGFloat(in: 260...410)
                let bomblet = ProjectileState(
                    id: nextProjectileID,
                    weapon: .clusterBomb,
                    ownerTeamIndex: p.ownerTeamIndex,
                    ownerWormID: -1,
                    position: CGPoint(x: p.position.x, y: p.position.y + 8),
                    velocity: CGVector(dx: cos(spreadAngle) * spd, dy: sin(spreadAngle) * spd),
                    fuseRemaining: nil,
                    isClusterBomblet: true
                )
                nextProjectileID += 1
                projectiles.append(bomblet)
            }
        }
    }

    func triggerExplosion(
        at center: CGPoint,
        radius: CGFloat,
        maxDamage: Int,
        knockback: CGFloat,
        ownerTeamIndex: Int?,
        isHoly: Bool
    ) {
        lastExplosionPoint = center
        terrain.carveCrater(worldCenter: center, worldRadius: radius)
        pendingEvents.append(.explosion(center: center, radius: radius, isHoly: isHoly))

        let blastRadius = radius * 1.48

        for i in worms.indices {
            guard worms[i].isAlive else { continue }
            let dx = worms[i].position.x - center.x
            let dy = worms[i].position.y - center.y
            let dist = hypot(dx, dy)

            if dist < blastRadius {
                let falloff = max(0.15, 1.0 - (dist / blastRadius))
                let dmg = max(1, Int(round(CGFloat(maxDamage) * falloff)))
                applyDamage(to: i, amount: dmg, attackerTeam: ownerTeamIndex)

                // Knockback impulse upward & outward
                let nx = dist > 1 ? dx / dist : 0
                let ny = dist > 1 ? dy / dist : 1
                let impulse = knockback * falloff
                worms[i].velocity.dx += nx * impulse * 0.92
                worms[i].velocity.dy += max(150 * falloff, ny * impulse + 185 * falloff)
                worms[i].isGrounded = false
                worms[i].fallStartY = worms[i].position.y
            }
        }
    }

    private func applyDamage(to wormIdx: Int, amount: Int, attackerTeam: Int?) {
        let wasAlive = worms[wormIdx].isAlive
        worms[wormIdx].health = max(0, worms[wormIdx].health - amount)
        worms[wormIdx].hurtTimer = 0.55
        pendingEvents.append(.wormDamaged(wormID: worms[wormIdx].id, amount: amount, position: worms[wormIdx].position))

        if let atk = attackerTeam, atk != worms[wormIdx].teamIndex {
            teams[atk].totalDamageDealt += amount
            if wasAlive && !worms[wormIdx].isAlive {
                teams[atk].kills += 1
            }
        }
    }

    // MARK: - Supply Crates

    private func maybeSpawnCrate() {
        guard turnNumber > 1, turnNumber % 3 == 0, crates.count < 2 else { return }
        let x = rng.nextCGFloat(in: 240...(WorldConstants.width - 240))
        let kind: CrateKind
        if rng.nextDouble() < 0.58 {
            kind = .health(amount: 25)
        } else {
            let specials: [WeaponKind] = [.clusterBomb, .airstrike, .holyGrenade]
            let chosen = specials[Int(rng.nextUInt64() % UInt64(specials.count))]
            kind = .weapon(chosen)
        }
        crates.append(CrateState(
            id: nextCrateID,
            kind: kind,
            position: CGPoint(x: x, y: WorldConstants.height - 30)
        ))
        nextCrateID += 1
    }

    private func updateCratesPhysics(dt: TimeInterval) {
        var idx = 0
        while idx < crates.count {
            var c = crates[idx]
            if c.position.y <= waterY + 6 {
                crates.remove(at: idx)
                continue
            }

            let foot = CGPoint(x: c.position.x, y: c.position.y - 14)
            if terrain.isSolid(worldPoint: foot) {
                c.isParachuting = false
                c.velocity = .zero
            } else if c.isParachuting {
                c.velocity.dx = wind * 58
                c.velocity.dy = -72
                c.position.x = max(80, min(WorldConstants.width - 80, c.position.x + c.velocity.dx * CGFloat(dt)))
                c.position.y += c.velocity.dy * CGFloat(dt)
            } else {
                c.velocity.dy += WorldConstants.gravity * CGFloat(dt)
                c.position.y += c.velocity.dy * CGFloat(dt)
            }

            // Check worm pickup
            var picked = false
            for wIdx in worms.indices {
                guard worms[wIdx].isAlive else { continue }
                if hypot(worms[wIdx].position.x - c.position.x, worms[wIdx].position.y - c.position.y) < 30 {
                    switch c.kind {
                    case .health(let amt):
                        worms[wIdx].health = min(100, worms[wIdx].health + amt)
                        pendingEvents.append(.crateCollected(position: c.position, label: c.kind.label, isHealth: true))
                    case .weapon(let w):
                        let tIdx = worms[wIdx].teamIndex
                        teams[tIdx].ammo[w] = (teams[tIdx].ammo[w] ?? 0) + 1
                        pendingEvents.append(.crateCollected(position: c.position, label: c.kind.label, isHealth: false))
                    }
                    picked = true
                    break
                }
            }

            if picked {
                crates.remove(at: idx)
            } else {
                crates[idx] = c
                idx += 1
            }
        }
    }

    // MARK: - Turn Progression & Victory

    private func anyBodiesMoving() -> Bool {
        if !projectiles.isEmpty { return true }
        for w in worms where w.isAlive {
            if !w.isGrounded || hypot(w.velocity.dx, w.velocity.dy) > 12 {
                return true
            }
        }
        return false
    }

    func aliveTeamIndices() -> [Int] {
        teams.indices.filter { tIdx in
            worms.contains(where: { $0.teamIndex == tIdx && $0.isAlive })
        }
    }

    func teamHealthTotal(_ teamIndex: Int) -> Int {
        worms.filter { $0.teamIndex == teamIndex && $0.isAlive }.reduce(0) { $0 + $1.health }
    }

    private func advanceTurnOrEndMatch() {
        let aliveTeams = aliveTeamIndices()
        if aliveTeams.count <= 1 {
            let winner = aliveTeams.first
            phase = .matchOver(winnerTeamIndex: winner)
            pendingEvents.append(.matchEnded(winnerTeamIndex: winner))
            return
        }

        turnNumber += 1

        // Sudden Death rising water!
        if turnNumber >= WorldConstants.suddenDeathStartTurn {
            waterY += WorldConstants.suddenDeathWaterStep
            pendingEvents.append(.suddenDeathTriggered(waterY: waterY))
            // Immediately check if rising water drowned anyone
            for i in worms.indices where worms[i].isAlive && worms[i].position.y <= waterY + 4 {
                worms[i].isDrowned = true
                worms[i].health = 0
                pendingEvents.append(.wormDrowned(wormID: worms[i].id, position: CGPoint(x: worms[i].position.x, y: waterY)))
            }
            let remainingAfterFlood = aliveTeamIndices()
            if remainingAfterFlood.count <= 1 {
                let winner = remainingAfterFlood.first
                phase = .matchOver(winnerTeamIndex: winner)
                pendingEvents.append(.matchEnded(winnerTeamIndex: winner))
                return
            }
        }

        // Next alive team
        var nextTeam = (currentTeamIndex + 1) % teams.count
        for _ in 0..<teams.count {
            if aliveTeamIndices().contains(nextTeam) {
                break
            }
            nextTeam = (nextTeam + 1) % teams.count
        }

        rollWind()
        maybeSpawnCrate()
        startTurn(teamIndex: nextTeam, isFirstTurn: false)
    }

    private func startTurn(teamIndex: Int, isFirstTurn: Bool) {
        currentTeamIndex = teamIndex
        turnTimeRemaining = config.turnDuration
        shotgunShotsRemaining = 0
        isWeaponBarOpen = false
        lastExplosionPoint = nil

        // Pick next alive worm on this team
        let teamWorms = worms.filter { $0.teamIndex == teamIndex && $0.isAlive }
        guard !teamWorms.isEmpty else {
            advanceTurnOrEndMatch()
            return
        }
        let cursor = teams[teamIndex].nextWormCursor % teamWorms.count
        let chosenWorm = teamWorms[cursor]
        teams[teamIndex].nextWormCursor = (cursor + 1) % max(1, teamWorms.count)
        activeWormID = chosenWorm.id

        // Make sure selected weapon has ammo for the new team
        if !currentTeam.canUse(selectedWeapon) {
            selectedWeapon = .bazooka
        }
        weaponBarSelectionIndex = selectedWeapon.rawValue

        phase = .turnBanner(remaining: isFirstTurn ? 1.5 : 1.9)
        pendingEvents.append(.turnStarted(teamIndex: teamIndex, wormName: chosenWorm.name))
    }

    private func rollWind() {
        wind = rng.nextCGFloat(in: -1.0...1.0)
    }
}
