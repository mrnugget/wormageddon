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
    var isSubmunition: Bool = false
    var sheepDirection: CGFloat = 0 // non-zero for running Super-Schaf
    var sheepHopTimer: TimeInterval = 0
    var isStationary: Bool = false // true for placed Dynamite
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
    case teleportAiming(target: CGPoint)
    case ropeSwinging(anchor: CGPoint, length: CGFloat)
    case jetpackFlying(fuel: CGFloat)
    case blowtorching(remaining: TimeInterval)
    case retreat(remaining: TimeInterval)
    case projectileInFlight
    case settling(remaining: TimeInterval)
    case matchOver(winnerTeamIndex: Int?)
}

enum GameEvent {
    case explosion(center: CGPoint, radius: CGFloat, isHoly: Bool)
    case shotgunTracer(from: CGPoint, to: CGPoint)
    case shotgunSecondShotReady(position: CGPoint)
    case firePunchBurst(position: CGPoint, facing: CGFloat)
    case baseballHit(position: CGPoint, didHitEnemy: Bool)
    case ropeAttached(anchor: CGPoint)
    case ropeMissed(position: CGPoint)
    case teleported(from: CGPoint, to: CGPoint)
    case blowtorchSpark(position: CGPoint)
    case jetpackThrust(position: CGPoint)
    case sheepBaa(position: CGPoint)
    case dynamitePlaced(position: CGPoint)
    case wormDamaged(wormID: Int, amount: Int, position: CGPoint)
    case wormDrowned(wormID: Int, position: CGPoint)
    case wormJumped(position: CGPoint, isBackflip: Bool)
    case projectileFired(weapon: WeaponKind, position: CGPoint)
    case grenadeBounce(position: CGPoint)
    case crateCollected(position: CGPoint, label: String, isHealth: Bool)
    case crateDropped(position: CGPoint, isHealth: Bool)
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
    private var blowtorchCarveAccum: TimeInterval = 0
    private var jetpackPuffAccum: TimeInterval = 0
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
        spawnSupplyCrate(forceWeapon: true)
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

        let totalWorms = count * config.wormsPerTeam
        let spawnPoints = findSpawnPoints(count: totalWorms)

        var wormID = 1
        var slotOrder = Array(0..<spawnPoints.count)
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

    /// Picks well-spread spawn spots on any walkable ledge (ground, platforms, cave floors),
    /// never inside ceilings or over pits: a worm-wide flat surface with head room above.
    private func findSpawnPoints(count: Int) -> [CGPoint] {
        let r = WorldConstants.wormRadius
        var candidates: [CGPoint] = []

        var x: CGFloat = 70
        while x < WorldConstants.width - 70 {
            for sy in terrain.surfaceTops(atWorldX: x, clearance: r * 2.6)
            where sy > WorldConstants.initialWaterY + 60 && sy < WorldConstants.height - 120 {
                let center = CGPoint(x: x, y: sy + r + 2)
                let isLedge = [-14, -7, 7, 14].allSatisfy { dx -> Bool in
                    guard let side = terrain.surfaceY(atWorldX: x + CGFloat(dx), fromWorldY: sy + 12) else { return false }
                    return abs(side - sy) <= 10
                }
                if isLedge, !terrain.isSolidCircle(center: CGPoint(x: x, y: center.y + 6), radius: r) {
                    candidates.append(center)
                }
            }
            x += 12
        }

        if candidates.isEmpty {
            return (0..<count).map { i in
                CGPoint(x: 340 + CGFloat(i) * 200, y: 760)
            }
        }

        // Farthest-point sampling from a seeded random start spreads worms across all levels.
        var picked: [CGPoint] = [candidates[Int(rng.nextUInt64() % UInt64(candidates.count))]]
        var nearest = candidates.map { hypot($0.x - picked[0].x, $0.y - picked[0].y) }
        while picked.count < count {
            guard let best = nearest.indices.max(by: { nearest[$0] < nearest[$1] }), nearest[best] > 0 else {
                picked.append(candidates[picked.count % candidates.count]) // fewer spots than worms
                continue
            }
            let p = candidates[best]
            picked.append(p)
            for i in candidates.indices {
                nearest[i] = min(nearest[i], hypot(candidates[i].x - p.x, candidates[i].y - p.y))
            }
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

        for i in worms.indices {
            if worms[i].hurtTimer > 0 {
                worms[i].hurtTimer = max(0, worms[i].hurtTimer - dt)
            }
        }

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

        case .teleportAiming(let target):
            handleTeleportAiming(dt: dt, target: target, input: &input)

        case .ropeSwinging(let anchor, let length):
            handleRopeSwinging(dt: dt, anchor: anchor, length: length, input: &input)

        case .jetpackFlying(let fuel):
            handleJetpackFlying(dt: dt, fuel: fuel, input: &input)

        case .blowtorching(let remaining):
            handleBlowtorching(dt: dt, remaining: remaining, input: &input)

        case .retreat(let remaining):
            handleRetreatMovement(dt: dt, input: &input)
            if remaining - dt <= 0 {
                phase = projectiles.isEmpty ? .settling(remaining: 0.9) : .projectileInFlight
            } else {
                phase = .retreat(remaining: remaining - dt)
            }

        case .projectileInFlight:
            // Press Select again to detonate an active Super-Schaf early!
            if input.firePressed, let sheepIdx = projectiles.firstIndex(where: { $0.weapon == .sheep && $0.age > 0.35 }) {
                let sheep = projectiles.remove(at: sheepIdx)
                detonate(projectile: sheep)
            }

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

        updateWormsPhysics(dt: dt)
        updateProjectilesPhysics(dt: dt)
        updateCratesPhysics(dt: dt)

        if case .projectileInFlight = phase, projectiles.isEmpty {
            if shotgunShotsRemaining > 0, let active = activeWorm, active.isAlive {
                phase = .playerControl
            } else {
                phase = .settling(remaining: 0.95)
            }
        }

        if case .playerControl = phase {
            if let active = activeWorm, !active.isAlive {
                isWeaponBarOpen = false
                phase = .settling(remaining: 1.0)
            }
        }

        input.consumePulses()
    }

    // MARK: - Player Control & 2×5 Weapon Drawer

    private func handlePlayerControl(dt: TimeInterval, input: inout InputSnapshot) {
        turnTimeRemaining = max(0, turnTimeRemaining - dt)
        if turnTimeRemaining <= 0 {
            isWeaponBarOpen = false
            shotgunShotsRemaining = 0
            phase = .settling(remaining: 0.6)
            return
        }

        // Cannot swap weapons mid-shotgun burst (keeps 2nd shot crystal clear!)
        if input.toggleWeaponBarPressed && shotgunShotsRemaining == 0 {
            isWeaponBarOpen.toggle()
            if isWeaponBarOpen {
                weaponBarSelectionIndex = selectedWeapon.rawValue
            }
            return
        }

        if shotgunShotsRemaining == 0 {
            if input.prevWeaponPressed {
                cycleWeapon(delta: -1)
            } else if input.nextWeaponPressed {
                cycleWeapon(delta: 1)
            }
        }

        // 3×5 Weapon Drawer navigation (Left/Right columns, Up/Down rows)
        if isWeaponBarOpen {
            let cols = 5
            let total = WeaponKind.allCases.count
            let rows = (total + cols - 1) / cols
            if weaponBarNavCooldown <= 0 {
                if abs(input.moveX) > 0.35 {
                    let step = input.moveX > 0 ? 1 : -1
                    let row = weaponBarSelectionIndex / cols
                    let col = (weaponBarSelectionIndex % cols + step + cols) % cols
                    weaponBarSelectionIndex = min(total - 1, row * cols + col)
                    weaponBarNavCooldown = 0.20
                } else if abs(input.aimY) > 0.35 {
                    let rowDelta = input.aimY > 0 ? -1 : 1 // Up goes to row above, Down goes to row below
                    let curRow = weaponBarSelectionIndex / cols
                    let col = weaponBarSelectionIndex % cols
                    let nextRow = (curRow + rowDelta + rows) % rows
                    weaponBarSelectionIndex = min(total - 1, nextRow * cols + col)
                    weaponBarNavCooldown = 0.22
                }
            }
            if input.firePressed {
                let chosen = WeaponKind.allCases[weaponBarSelectionIndex]
                if currentTeam.canUse(chosen) {
                    selectedWeapon = chosen
                    isWeaponBarOpen = false
                    if chosen == .airstrike {
                        let startX = activeWorm?.position.x ?? WorldConstants.width * 0.5
                        phase = .airstrikeAiming(targetX: startX)
                    } else if chosen == .teleport {
                        let startPos = activeWorm?.position ?? CGPoint(x: WorldConstants.width * 0.5, y: WorldConstants.height * 0.5)
                        phase = .teleportAiming(target: CGPoint(x: startPos.x, y: min(WorldConstants.height - 80, startPos.y + 80)))
                    }
                }
            }
            return
        }

        guard let wormIdx = worms.firstIndex(where: { $0.id == activeWormID }), worms[wormIdx].isAlive else {
            return
        }

        moveAndJumpWorm(at: wormIdx, dt: dt, input: input)

        // Aiming
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

        // Firing
        if input.firePressed {
            if !currentTeam.canUse(selectedWeapon) {
                selectedWeapon = .bazooka
            }
            switch selectedWeapon {
            case .airstrike:
                phase = .airstrikeAiming(targetX: worms[wormIdx].position.x)
            case .teleport:
                let p = worms[wormIdx].position
                phase = .teleportAiming(target: CGPoint(x: p.x, y: min(WorldConstants.height - 80, p.y + 80)))
            case .shotgun:
                fireShotgun(from: wormIdx)
            case .sheep:
                launchSheep(from: wormIdx)
            case .firePunch:
                executeFirePunch(from: wormIdx)
            case .dynamite:
                placeDynamite(from: wormIdx)
            case .rope:
                fireRope(from: wormIdx)
            case .jetpack:
                startJetpack(from: wormIdx)
            case .baseballBat:
                swingBaseballBat(from: wormIdx)
            case .blowtorch:
                startBlowtorch(from: wormIdx)
            case .bazooka, .grenade, .clusterBomb, .holyGrenade, .bananaBomb:
                phase = .charging(power: 0.14)
            }
        }
    }

    private func handleRetreatMovement(dt: TimeInterval, input: inout InputSnapshot) {
        guard let wormIdx = worms.firstIndex(where: { $0.id == activeWormID }), worms[wormIdx].isAlive else {
            return
        }
        moveAndJumpWorm(at: wormIdx, dt: dt, input: input)
    }

    private func moveAndJumpWorm(at wormIdx: Int, dt: TimeInterval, input: InputSnapshot) {
        if abs(input.moveX) > 0.2 && worms[wormIdx].isGrounded {
            let dir: CGFloat = input.moveX > 0 ? 1 : -1
            worms[wormIdx].facing = dir
            walkWorm(at: wormIdx, direction: dir, speedScale: min(1.0, abs(input.moveX)), dt: dt)
        } else if abs(input.moveX) > 0.2 {
            // Gentle mid-air steering so jumps land cleanly on ledges & forks
            let dir: CGFloat = input.moveX > 0 ? 1 : -1
            worms[wormIdx].facing = dir
            worms[wormIdx].velocity.dx = max(-300, min(300, worms[wormIdx].velocity.dx + input.moveX * 140 * CGFloat(dt)))
        }

        if input.jumpPressed && worms[wormIdx].isGrounded {
            let dir = worms[wormIdx].facing
            worms[wormIdx].position.y += 5
            worms[wormIdx].velocity = CGVector(dx: dir * 245, dy: 425)
            worms[wormIdx].isGrounded = false
            worms[wormIdx].fallStartY = worms[wormIdx].position.y
            pendingEvents.append(.wormJumped(position: worms[wormIdx].position, isBackflip: false))
        } else if input.backflipPressed && worms[wormIdx].isGrounded {
            let dir = worms[wormIdx].facing
            worms[wormIdx].position.y += 6
            worms[wormIdx].velocity = CGVector(dx: -dir * 135, dy: 535)
            worms[wormIdx].isGrounded = false
            worms[wormIdx].fallStartY = worms[wormIdx].position.y
            pendingEvents.append(.wormJumped(position: worms[wormIdx].position, isBackflip: true))
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
            phase = .playerControl
            isWeaponBarOpen = true
            weaponBarSelectionIndex = selectedWeapon.rawValue
            return
        }

        let moveSpeed: CGFloat = 920
        let clampedX = max(180, min(WorldConstants.width - 180, targetX + input.moveX * moveSpeed * CGFloat(dt)))
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
            x: worm.position.x + dir.dx * (WorldConstants.wormRadius + 11),
            y: worm.position.y + 4 + dir.dy * (WorldConstants.wormRadius + 11)
        )

        let minSpeed: CGFloat = 320
        let maxSpeed: CGFloat = (weapon == .bazooka) ? 1160 : 980
        let speed = minSpeed + (maxSpeed - minSpeed) * power

        let fuse: TimeInterval?
        switch weapon {
        case .grenade, .clusterBomb: fuse = 3.0
        case .holyGrenade, .bananaBomb: fuse = 3.5
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
        let maxRange: CGFloat = 1040
        let end = CGPoint(x: start.x + dir.dx * maxRange, y: start.y + dir.dy * maxRange)

        let steps = 210
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
            pendingEvents.append(.shotgunSecondShotReady(position: worm.position))
            phase = .playerControl
        } else {
            phase = .retreat(remaining: 2.5)
        }
    }

    private func launchAirstrike(targetX: CGFloat) {
        guard let worm = activeWorm else { return }
        consumeAmmo(.airstrike)

        let dirX: CGFloat = airstrikeFromLeft ? 1 : -1
        for i in 0..<5 {
            let offset = CGFloat(i - 2) * 64
            let spawnX = targetX + offset - dirX * 320
            let spawnY = WorldConstants.height - 20 + CGFloat(i) * 32
            let proj = ProjectileState(
                id: nextProjectileID,
                weapon: .airstrike,
                ownerTeamIndex: worm.teamIndex,
                ownerWormID: worm.id,
                position: CGPoint(x: spawnX, y: spawnY),
                velocity: CGVector(dx: dirX * 220, dy: -230),
                fuseRemaining: nil,
                rotation: atan2(-230, dirX * 220)
            )
            nextProjectileID += 1
            projectiles.append(proj)
        }
        pendingEvents.append(.projectileFired(weapon: .airstrike, position: CGPoint(x: targetX, y: WorldConstants.height - 40)))
        phase = .projectileInFlight
    }

    private func launchSheep(from wormIdx: Int) {
        let worm = worms[wormIdx]
        consumeAmmo(.sheep)
        let dir = worm.facing
        let spawn = CGPoint(x: worm.position.x + dir * 24, y: worm.position.y + 8)
        let proj = ProjectileState(
            id: nextProjectileID,
            weapon: .sheep,
            ownerTeamIndex: worm.teamIndex,
            ownerWormID: worm.id,
            position: spawn,
            velocity: CGVector(dx: dir * 210, dy: 210),
            fuseRemaining: 5.5,
            sheepDirection: dir,
            sheepHopTimer: 0.45
        )
        nextProjectileID += 1
        projectiles.append(proj)
        pendingEvents.append(.sheepBaa(position: spawn))
        phase = .projectileInFlight
    }

    private func executeFirePunch(from wormIdx: Int) {
        let worm = worms[wormIdx]
        let dir = worm.facing
        let strikePoint = CGPoint(x: worm.position.x + dir * 28, y: worm.position.y + 18)

        // Active worm rises slightly with the uppercut
        worms[wormIdx].velocity = CGVector(dx: dir * 85, dy: 270)
        worms[wormIdx].isGrounded = false
        worms[wormIdx].fallStartY = worms[wormIdx].position.y

        terrain.carveCrater(worldCenter: strikePoint, worldRadius: WeaponKind.firePunch.explosionRadius)
        pendingEvents.append(.firePunchBurst(position: strikePoint, facing: dir))

        // Blast any nearby other worms sky-high!
        for i in worms.indices where i != wormIdx && worms[i].isAlive {
            let dist = hypot(worms[i].position.x - strikePoint.x, worms[i].position.y - strikePoint.y)
            if dist < 82 {
                applyDamage(to: i, amount: WeaponKind.firePunch.maxDamage, attackerTeam: worm.teamIndex)
                worms[i].velocity = CGVector(dx: dir * 360, dy: 560)
                worms[i].isGrounded = false
                worms[i].fallStartY = worms[i].position.y
            }
        }

        phase = .retreat(remaining: 2.5)
    }

    private func placeDynamite(from wormIdx: Int) {
        let worm = worms[wormIdx]
        consumeAmmo(.dynamite)
        let dropPos = CGPoint(x: worm.position.x + worm.facing * 18, y: worm.position.y - 2)
        let proj = ProjectileState(
            id: nextProjectileID,
            weapon: .dynamite,
            ownerTeamIndex: worm.teamIndex,
            ownerWormID: worm.id,
            position: dropPos,
            velocity: .zero,
            fuseRemaining: 4.0,
            isStationary: true
        )
        nextProjectileID += 1
        projectiles.append(proj)
        pendingEvents.append(.dynamitePlaced(position: dropPos))
        phase = .retreat(remaining: WorldConstants.retreatDuration)
    }

    // MARK: - Hedgewars Utilities & New Weapons (Rope, Jetpack, Baseball Bat, Blowtorch, Teleport)

    private func fireRope(from wormIdx: Int) {
        let worm = worms[wormIdx]
        let dir = worm.aimDirection
        let start = CGPoint(x: worm.position.x, y: worm.position.y + 6)
        let maxRange: CGFloat = 560
        let steps = 140

        for i in 6...steps {
            let dist = maxRange * (CGFloat(i) / CGFloat(steps))
            let p = CGPoint(x: start.x + dir.dx * dist, y: start.y + dir.dy * dist)
            if p.x < 10 || p.x > WorldConstants.width - 10 || p.y < waterY || p.y > WorldConstants.height - 10 {
                break
            }
            if terrain.isSolid(worldPoint: p) {
                worms[wormIdx].isGrounded = false
                worms[wormIdx].position.y += 4
                worms[wormIdx].velocity.dy = max(worms[wormIdx].velocity.dy, 120)
                worms[wormIdx].fallStartY = nil
                let length = max(56, min(maxRange, dist))
                pendingEvents.append(.ropeAttached(anchor: p))
                phase = .ropeSwinging(anchor: p, length: length)
                return
            }
        }
        pendingEvents.append(.ropeMissed(position: worm.position))
    }

    private func handleRopeSwinging(dt: TimeInterval, anchor: CGPoint, length: CGFloat, input: inout InputSnapshot) {
        turnTimeRemaining = max(0, turnTimeRemaining - dt)
        if turnTimeRemaining <= 0 {
            phase = .settling(remaining: 0.6)
            return
        }

        guard let idx = worms.firstIndex(where: { $0.id == activeWormID }), worms[idx].isAlive else {
            phase = .settling(remaining: 0.8)
            return
        }

        // Release rope on Select or Play/Pause (utility — does NOT end turn!)
        if input.firePressed || input.toggleWeaponBarPressed {
            worms[idx].velocity.dy += 110
            worms[idx].fallStartY = worms[idx].position.y
            phase = .playerControl
            if input.toggleWeaponBarPressed {
                isWeaponBarOpen = true
                weaponBarSelectionIndex = selectedWeapon.rawValue
            }
            return
        }

        // Reel rope shorter / longer with Up / Down
        let reelSpeed: CGFloat = 240
        let nextLength = max(52, min(560, length - input.aimY * reelSpeed * CGFloat(dt)))

        // Swing pump with Left / Right
        if abs(input.moveX) > 0.2 {
            worms[idx].facing = input.moveX > 0 ? 1 : -1
            worms[idx].velocity.dx += input.moveX * 480 * CGFloat(dt)
        }

        // Gentle velocity damping & pendulum tether constraint
        worms[idx].velocity.dx *= pow(0.88, CGFloat(dt))
        worms[idx].velocity.dy *= pow(0.94, CGFloat(dt))
        worms[idx].isGrounded = false
        worms[idx].fallStartY = nil

        let dx = worms[idx].position.x - anchor.x
        let dy = worms[idx].position.y - anchor.y
        let dist = max(1, hypot(dx, dy))
        if dist >= nextLength {
            let nx = dx / dist
            let ny = dy / dist
            let targetPos = CGPoint(x: anchor.x + nx * nextLength, y: anchor.y + ny * nextLength)
            if !terrain.isSolidCircle(center: targetPos, radius: WorldConstants.wormRadius * 0.72) {
                worms[idx].position = targetPos
            }
            // Strip outward radial velocity so worm swings in a crisp arc
            let vr = worms[idx].velocity.dx * nx + worms[idx].velocity.dy * ny
            if vr > 0 {
                worms[idx].velocity.dx -= vr * nx
                worms[idx].velocity.dy -= vr * ny
            }
        }

        phase = .ropeSwinging(anchor: anchor, length: nextLength)
    }

    private func startJetpack(from wormIdx: Int) {
        consumeAmmo(.jetpack)
        worms[wormIdx].isGrounded = false
        worms[wormIdx].position.y += 5
        worms[wormIdx].velocity.dy = 170
        worms[wormIdx].fallStartY = nil
        jetpackPuffAccum = 0
        pendingEvents.append(.jetpackThrust(position: worms[wormIdx].position))
        phase = .jetpackFlying(fuel: 1.0)
    }

    private func handleJetpackFlying(dt: TimeInterval, fuel: CGFloat, input: inout InputSnapshot) {
        turnTimeRemaining = max(0, turnTimeRemaining - dt)
        if turnTimeRemaining <= 0 {
            phase = .settling(remaining: 0.6)
            return
        }

        guard let idx = worms.firstIndex(where: { $0.id == activeWormID }), worms[idx].isAlive else {
            phase = .settling(remaining: 0.8)
            return
        }

        // Cut jetpack anytime with Select or Play/Pause (utility — does NOT end turn!)
        if input.firePressed || input.toggleWeaponBarPressed {
            worms[idx].fallStartY = worms[idx].position.y
            phase = .playerControl
            if input.toggleWeaponBarPressed {
                isWeaponBarOpen = true
                weaponBarSelectionIndex = selectedWeapon.rawValue
            }
            return
        }

        var remainingFuel = fuel
        var thrusting = false

        if input.aimY > 0.15 {
            worms[idx].velocity.dy = min(340, worms[idx].velocity.dy + 1240 * CGFloat(dt))
            worms[idx].isGrounded = false
            remainingFuel -= CGFloat(dt) * 0.18
            thrusting = true
        } else if input.aimY < -0.15 {
            worms[idx].velocity.dy = max(-220, worms[idx].velocity.dy - 260 * CGFloat(dt))
        } else {
            // Gentle hover assist so 5-year-olds don't plummet between button presses!
            worms[idx].velocity.dy = max(-180, worms[idx].velocity.dy + 360 * CGFloat(dt))
            remainingFuel -= CGFloat(dt) * 0.06
        }

        if abs(input.moveX) > 0.15 {
            worms[idx].facing = input.moveX > 0 ? 1 : -1
            worms[idx].velocity.dx = max(-290, min(290, worms[idx].velocity.dx + input.moveX * 780 * CGFloat(dt)))
            remainingFuel -= CGFloat(dt) * 0.10
            thrusting = true
        } else {
            worms[idx].velocity.dx *= pow(0.25, CGFloat(dt))
        }

        worms[idx].fallStartY = nil
        jetpackPuffAccum += dt
        if thrusting && jetpackPuffAccum >= 0.12 {
            jetpackPuffAccum = 0
            pendingEvents.append(.jetpackThrust(position: CGPoint(x: worms[idx].position.x, y: worms[idx].position.y - 12)))
        }

        if remainingFuel <= 0 {
            worms[idx].fallStartY = worms[idx].position.y
            phase = .playerControl
        } else {
            phase = .jetpackFlying(fuel: remainingFuel)
        }
    }

    private func swingBaseballBat(from wormIdx: Int) {
        let worm = worms[wormIdx]
        let dir = worm.facing
        let aimAngle = max(0.22, worm.aimAngle) // Always launches slightly upward for epic homeruns!
        let worldAngle = dir >= 0 ? aimAngle : (.pi - aimAngle)
        let launchDir = CGVector(dx: cos(worldAngle), dy: sin(worldAngle))
        let strikeCenter = CGPoint(x: worm.position.x + dir * 26, y: worm.position.y + 4)

        var hitAny = false
        for i in worms.indices where i != wormIdx && worms[i].isAlive {
            let dist = hypot(worms[i].position.x - strikeCenter.x, worms[i].position.y - strikeCenter.y)
            if dist <= 74 {
                hitAny = true
                applyDamage(to: i, amount: WeaponKind.baseballBat.maxDamage, attackerTeam: worm.teamIndex)
                worms[i].position.y += 5
                worms[i].velocity = CGVector(
                    dx: launchDir.dx * WeaponKind.baseballBat.knockbackSpeed,
                    dy: max(280, launchDir.dy * WeaponKind.baseballBat.knockbackSpeed)
                )
                worms[i].isGrounded = false
                worms[i].fallStartY = worms[i].position.y
            }
        }

        pendingEvents.append(.baseballHit(position: strikeCenter, didHitEnemy: hitAny))
        phase = .retreat(remaining: 2.5)
    }

    private func startBlowtorch(from wormIdx: Int) {
        consumeAmmo(.blowtorch)
        blowtorchCarveAccum = 0
        worms[wormIdx].aimAngle = max(-0.55, min(0.75, worms[wormIdx].aimAngle))
        pendingEvents.append(.blowtorchSpark(position: worms[wormIdx].position))
        phase = .blowtorching(remaining: 1.9)
    }

    private func handleBlowtorching(dt: TimeInterval, remaining: TimeInterval, input: inout InputSnapshot) {
        guard let idx = worms.firstIndex(where: { $0.id == activeWormID }), worms[idx].isAlive else {
            phase = .settling(remaining: 0.8)
            return
        }

        if input.firePressed || remaining - dt <= 0 {
            phase = .retreat(remaining: 1.8)
            return
        }

        // Allow steering digging angle gently while tunneling
        if abs(input.aimY) > 0.15 {
            worms[idx].aimAngle = max(-0.55, min(0.75, worms[idx].aimAngle + input.aimY * 1.1 * CGFloat(dt)))
        }

        let dir = worms[idx].aimDirection
        let digSpeed: CGFloat = 104
        let nextPos = CGPoint(
            x: max(36, min(WorldConstants.width - 36, worms[idx].position.x + dir.dx * digSpeed * CGFloat(dt))),
            y: max(waterY + 12, min(WorldConstants.height - 40, worms[idx].position.y + dir.dy * digSpeed * CGFloat(dt)))
        )

        blowtorchCarveAccum += dt
        if blowtorchCarveAccum >= 0.06 {
            blowtorchCarveAccum = 0
            let tip = CGPoint(x: nextPos.x + dir.dx * 16, y: nextPos.y + dir.dy * 16)
            terrain.carveCrater(worldCenter: tip, worldRadius: WeaponKind.blowtorch.explosionRadius)
            pendingEvents.append(.blowtorchSpark(position: tip))

            // Scorch any enemy caught in front of the torch!
            for i in worms.indices where i != idx && worms[i].isAlive {
                if hypot(worms[i].position.x - tip.x, worms[i].position.y - tip.y) < 34 {
                    applyDamage(to: i, amount: 4, attackerTeam: worms[idx].teamIndex)
                    worms[i].velocity = CGVector(dx: dir.dx * 210, dy: 180)
                    worms[i].isGrounded = false
                }
            }
        }

        worms[idx].position = nextPos
        worms[idx].velocity = .zero
        worms[idx].isGrounded = true
        worms[idx].walkPhase += CGFloat(dt) * 14.0
        phase = .blowtorching(remaining: remaining - dt)
    }

    func isValidTeleportTarget(_ point: CGPoint) -> Bool {
        guard point.x > 40, point.x < WorldConstants.width - 40,
              point.y > waterY + 26, point.y < WorldConstants.height - 40 else { return false }
        return !terrain.isSolidCircle(center: point, radius: WorldConstants.wormRadius + 2)
    }

    private func handleTeleportAiming(dt: TimeInterval, target: CGPoint, input: inout InputSnapshot) {
        turnTimeRemaining = max(0, turnTimeRemaining - dt)
        if turnTimeRemaining <= 0 {
            phase = .settling(remaining: 0.5)
            return
        }

        if input.toggleWeaponBarPressed {
            phase = .playerControl
            isWeaponBarOpen = true
            weaponBarSelectionIndex = selectedWeapon.rawValue
            return
        }

        let speed: CGFloat = 780
        let nx = max(60, min(WorldConstants.width - 60, target.x + input.moveX * speed * CGFloat(dt)))
        let ny = max(waterY + 34, min(WorldConstants.height - 60, target.y + input.aimY * speed * CGFloat(dt)))
        let nextTarget = CGPoint(x: nx, y: ny)

        if input.firePressed, isValidTeleportTarget(nextTarget),
           let idx = worms.firstIndex(where: { $0.id == activeWormID }), worms[idx].isAlive {
            let oldPos = worms[idx].position
            consumeAmmo(.teleport)
            worms[idx].position = nextTarget
            worms[idx].velocity = .zero
            worms[idx].isGrounded = false
            worms[idx].fallStartY = nil
            pendingEvents.append(.teleported(from: oldPos, to: nextTarget))
            phase = .settling(remaining: 1.0)
        } else {
            phase = .teleportAiming(target: nextTarget)
        }
    }

    // MARK: - Worm Movement & Physics

    private func walkWorm(at idx: Int, direction: CGFloat, speedScale: CGFloat, dt: TimeInterval) {
        let stepX = direction * WorldConstants.wormWalkSpeed * speedScale * CGFloat(dt)
        let candidateX = max(28, min(WorldConstants.width - 28, worms[idx].position.x + stepX))
        let currentY = worms[idx].position.y

        var foundY: CGFloat? = nil
        let r = WorldConstants.wormRadius

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

            if worms[i].position.y <= waterY + 4 {
                worms[i].isDrowned = true
                worms[i].health = 0
                worms[i].velocity = .zero
                pendingEvents.append(.wormDrowned(wormID: worms[i].id, position: CGPoint(x: worms[i].position.x, y: waterY)))
                continue
            }

            if worms[i].isGrounded {
                let underFoot = CGPoint(x: worms[i].position.x, y: worms[i].position.y - r - 3)
                if !terrain.isSolid(worldPoint: underFoot) {
                    worms[i].isGrounded = false
                    worms[i].fallStartY = worms[i].position.y
                } else {
                    continue
                }
            }

            worms[i].velocity.dy += WorldConstants.gravity * CGFloat(dt)
            let speed = hypot(worms[i].velocity.dx, worms[i].velocity.dy)
            if speed > 140 {
                worms[i].tumbleSpin += CGFloat(dt) * (worms[i].velocity.dx >= 0 ? -9.0 : 9.0)
            } else {
                worms[i].tumbleSpin = 0
            }

            let subSteps = max(1, Int(ceil(speed * CGFloat(dt) / 5.0)))
            let subDt = CGFloat(dt) / CGFloat(subSteps)

            for _ in 0..<subSteps {
                let nextPos = CGPoint(
                    x: worms[i].position.x + worms[i].velocity.dx * subDt,
                    y: worms[i].position.y + worms[i].velocity.dy * subDt
                )

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

                    // Moving away from terrain (e.g. first frames of a jump): don't snap back to grounded!
                    if vn > 0 {
                        worms[i].position = nextPos
                        continue
                    }

                    if vn < -220 {
                        let restitution: CGFloat = 0.32
                        worms[i].velocity.dx = (worms[i].velocity.dx - (1 + restitution) * vn * normal.dx) * 0.72
                        worms[i].velocity.dy = (worms[i].velocity.dy - (1 + restitution) * vn * normal.dy) * 0.72
                        worms[i].position.x += normal.dx * 2
                        worms[i].position.y += normal.dy * 2
                    } else if normal.dy > 0.38 {
                        applyFallDamageIfNeeded(wormIdx: i)
                        worms[i].velocity = .zero
                        worms[i].isGrounded = true
                        worms[i].tumbleSpin = 0
                        worms[i].fallStartY = nil
                        var lift = 0
                        while lift < 16 && terrain.isSolid(worldPoint: CGPoint(x: worms[i].position.x, y: worms[i].position.y - r + 2)) {
                            worms[i].position.y += 1
                            lift += 1
                        }
                        break
                    } else {
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
        if drop > 255 {
            let dmg = min(35, Int((drop - 240) / 14))
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

            // Stationary Dynamite falls straight down until it rests on ground
            if p.isStationary {
                let foot = CGPoint(x: p.position.x, y: p.position.y - 12)
                if !terrain.isSolid(worldPoint: foot) {
                    p.velocity.dy += WorldConstants.gravity * CGFloat(dt)
                    p.position.y += p.velocity.dy * CGFloat(dt)
                } else {
                    p.velocity = .zero
                }
                if p.position.y <= waterY {
                    projectiles.remove(at: i)
                    pendingEvents.append(.wormDrowned(wormID: -1, position: CGPoint(x: p.position.x, y: waterY)))
                    continue
                }
                projectiles[i] = p
                i += 1
                continue
            }

            // Running Super-Schaf hopping behavior!
            if p.weapon == .sheep {
                p.sheepHopTimer -= dt
                p.velocity.dx = p.sheepDirection * 215
                p.velocity.dy += WorldConstants.gravity * CGFloat(dt)

                let nextPos = CGPoint(
                    x: p.position.x + p.velocity.dx * CGFloat(dt),
                    y: p.position.y + p.velocity.dy * CGFloat(dt)
                )

                if nextPos.y <= waterY || nextPos.x < -120 || nextPos.x > WorldConstants.width + 120 {
                    projectiles.remove(at: i)
                    if nextPos.y <= waterY {
                        pendingEvents.append(.wormDrowned(wormID: -1, position: CGPoint(x: max(40, min(WorldConstants.width - 40, nextPos.x)), y: waterY)))
                    }
                    continue
                }

                // Detonate on direct enemy worm contact after 0.35s!
                if p.age > 0.35, worms.contains(where: { $0.isAlive && $0.id != p.ownerWormID && hypot($0.position.x - nextPos.x, $0.position.y - nextPos.y) <= WorldConstants.wormRadius + 14 }) {
                    p.position = nextPos
                    projectiles.remove(at: i)
                    detonate(projectile: p)
                    continue
                }

                if terrain.isSolid(worldPoint: CGPoint(x: nextPos.x, y: nextPos.y - 10)) {
                    let normal = terrain.surfaceNormal(at: nextPos)
                    if abs(normal.dx) > 0.72 && normal.dy < 0.35 {
                        // Sheer wall — bounce around and reverse!
                        p.sheepDirection *= -1
                        p.velocity.dx = p.sheepDirection * 215
                        p.velocity.dy = 250
                        pendingEvents.append(.sheepBaa(position: p.position))
                    } else {
                        // Climb gently or hop cheerfully!
                        p.position.x = nextPos.x
                        var lift: CGFloat = 0
                        while lift < 22 && terrain.isSolid(worldPoint: CGPoint(x: p.position.x, y: p.position.y - 10 + lift)) {
                            lift += 2
                        }
                        p.position.y += lift
                        if p.sheepHopTimer <= 0 {
                            p.velocity.dy = 310
                            p.sheepHopTimer = 0.58
                            pendingEvents.append(.grenadeBounce(position: p.position))
                        } else {
                            p.velocity.dy = max(0, p.velocity.dy)
                        }
                    }
                } else {
                    p.position = nextPos
                }

                projectiles[i] = p
                i += 1
                continue
            }

            // Standard ballistic projectiles (Bazooka, Granate, Streubombe, Bananenbombe, Luftangriff, Heilige Granate)
            p.velocity.dy += WorldConstants.gravity * CGFloat(dt)
            if p.weapon.affectedByWind {
                p.velocity.dx += wind * WorldConstants.maxWindAccel * CGFloat(dt)
            }

            let speed = hypot(p.velocity.dx, p.velocity.dy)
            if speed > 10 {
                if p.weapon == .bazooka || p.weapon == .airstrike || (p.weapon == .clusterBomb && p.isSubmunition) {
                    p.rotation = atan2(p.velocity.dy, p.velocity.dx)
                } else {
                    p.rotation += (p.velocity.dx >= 0 ? -1 : 1) * CGFloat(dt) * min(14, speed * 0.022)
                }
            }

            let subSteps = max(1, Int(ceil(speed * CGFloat(dt) / 6.0)))
            let subDt = CGFloat(dt) / CGFloat(subSteps)
            var detonatedOrRemoved = false

            for _ in 0..<subSteps {
                let nextPos = CGPoint(
                    x: p.position.x + p.velocity.dx * subDt,
                    y: p.position.y + p.velocity.dy * subDt
                )

                if nextPos.y <= waterY || nextPos.x < -180 || nextPos.x > WorldConstants.width + 180 || nextPos.y > WorldConstants.height + 650 {
                    projectiles.remove(at: i)
                    if nextPos.y <= waterY {
                        pendingEvents.append(.wormDrowned(wormID: -1, position: CGPoint(x: max(40, min(WorldConstants.width - 40, nextPos.x)), y: waterY)))
                    }
                    detonatedOrRemoved = true
                    break
                }

                let hitWorm = worms.first { w in
                    guard w.isAlive else { return false }
                    if w.id == p.ownerWormID && p.age < 0.16 { return false }
                    return hypot(w.position.x - nextPos.x, w.position.y - nextPos.y) <= WorldConstants.wormRadius + 5
                }

                let hitTerrain = terrain.isSolid(worldPoint: nextPos)

                if hitWorm != nil || hitTerrain {
                    if p.fuseRemaining == nil {
                        p.position = nextPos
                        projectiles.remove(at: i)
                        detonate(projectile: p)
                        detonatedOrRemoved = true
                        break
                    } else {
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
                            let bounce: CGFloat
                            switch p.weapon {
                            case .bananaBomb: bounce = 0.80 // Super bouncy banana chaos!
                            case .holyGrenade: bounce = 0.44
                            default: bounce = 0.56
                            }
                            let friction: CGFloat = (p.weapon == .bananaBomb) ? 0.94 : 0.86
                            p.velocity.dx = (p.velocity.dx - (1 + bounce) * vn * normal.dx) * friction
                            p.velocity.dy = (p.velocity.dy - (1 + bounce) * vn * normal.dy) * friction
                            if abs(vn) > 65 {
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
        let radius: CGFloat
        let maxDamage: Int
        let knockback: CGFloat

        if p.isSubmunition && p.weapon == .clusterBomb {
            radius = 44
            maxDamage = 24
            knockback = 330
        } else if p.isSubmunition && p.weapon == .bananaBomb {
            radius = 66
            maxDamage = 40
            knockback = 460
        } else {
            radius = p.weapon.explosionRadius
            maxDamage = p.weapon.maxDamage
            knockback = p.weapon.knockbackSpeed
        }

        triggerExplosion(
            at: p.position,
            radius: radius,
            maxDamage: maxDamage,
            knockback: knockback,
            ownerTeamIndex: p.ownerTeamIndex,
            isHoly: p.weapon == .holyGrenade
        )

        // Cluster bomb -> 5 impact bomblets
        if p.weapon == .clusterBomb && !p.isSubmunition {
            for k in 0..<5 {
                let spreadAngle = (.pi * 0.20) + (CGFloat(k) / 4.0) * (.pi * 0.60)
                let spd = rng.nextCGFloat(in: 280...440)
                let bomblet = ProjectileState(
                    id: nextProjectileID,
                    weapon: .clusterBomb,
                    ownerTeamIndex: p.ownerTeamIndex,
                    ownerWormID: -1,
                    position: CGPoint(x: p.position.x, y: p.position.y + 8),
                    velocity: CGVector(dx: cos(spreadAngle) * spd, dy: sin(spreadAngle) * spd),
                    fuseRemaining: nil,
                    isSubmunition: true
                )
                nextProjectileID += 1
                projectiles.append(bomblet)
            }
        }

        // Banana bomb -> 6 wildly bouncing mini-bananas with staggered short fuses!
        if p.weapon == .bananaBomb && !p.isSubmunition {
            for k in 0..<6 {
                let spreadAngle = (.pi * 0.16) + (CGFloat(k) / 5.0) * (.pi * 0.68)
                let spd = rng.nextCGFloat(in: 340...540)
                let miniBanana = ProjectileState(
                    id: nextProjectileID,
                    weapon: .bananaBomb,
                    ownerTeamIndex: p.ownerTeamIndex,
                    ownerWormID: -1,
                    position: CGPoint(x: p.position.x, y: p.position.y + 10),
                    velocity: CGVector(dx: cos(spreadAngle) * spd, dy: sin(spreadAngle) * spd),
                    fuseRemaining: 1.1 + Double(k) * 0.18,
                    isSubmunition: true
                )
                nextProjectileID += 1
                projectiles.append(miniBanana)
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

                let nx = dist > 1 ? dx / dist : 0
                let ny = dist > 1 ? dy / dist : 1
                let impulse = knockback * falloff
                worms[i].velocity.dx += nx * impulse * 0.92
                worms[i].velocity.dy += max(155 * falloff, ny * impulse + 190 * falloff)
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

    // MARK: - Supply Crates (Sky Drops for Super Weapons & Health!)

    private func maybeSpawnCrate() {
        guard crates.count < 4 else { return }
        spawnSupplyCrate(forceWeapon: false)
    }

    private func spawnSupplyCrate(forceWeapon: Bool) {
        // Pick an X position above actual solid land so crates land on islands/ledges rather than open sea
        var chosenX = rng.nextCGFloat(in: 280...(WorldConstants.width - 280))
        for _ in 0..<14 {
            let candidate = rng.nextCGFloat(in: 240...(WorldConstants.width - 240))
            if let sy = terrain.surfaceY(atWorldX: candidate), sy > waterY + 50 {
                chosenX = candidate
                break
            }
        }

        let isHealth = !forceWeapon && rng.nextDouble() < 0.30
        let kind: CrateKind
        if isHealth {
            kind = .health(amount: 30)
        } else {
            // Heavily weighted toward the 4 crate-only Super Weapons!
            let pool: [WeaponKind] = [
                .holyGrenade, .holyGrenade,
                .bananaBomb, .bananaBomb,
                .sheep, .sheep,
                .airstrike, .airstrike,
                .jetpack, .teleport, .dynamite, .clusterBomb
            ]
            let chosen = pool[Int(rng.nextUInt64() % UInt64(pool.count))]
            kind = .weapon(chosen)
        }

        let spawnPos = CGPoint(x: chosenX, y: WorldConstants.height - 60)
        crates.append(CrateState(
            id: nextCrateID,
            kind: kind,
            position: spawnPos
        ))
        nextCrateID += 1
        pendingEvents.append(.crateDropped(position: spawnPos, isHealth: isHealth))
    }

    private func updateCratesPhysics(dt: TimeInterval) {
        var idx = 0
        while idx < crates.count {
            var c = crates[idx]
            if c.position.y <= waterY + 6 {
                crates.remove(at: idx)
                continue
            }

            let foot = CGPoint(x: c.position.x, y: c.position.y - 18)
            if terrain.isSolid(worldPoint: foot) {
                c.isParachuting = false
                c.velocity = .zero
            } else if c.isParachuting {
                c.velocity.dx = wind * 62
                c.velocity.dy = -82
                c.position.x = max(80, min(WorldConstants.width - 80, c.position.x + c.velocity.dx * CGFloat(dt)))
                c.position.y += c.velocity.dy * CGFloat(dt)
            } else {
                c.velocity.dy += WorldConstants.gravity * CGFloat(dt)
                c.position.y += c.velocity.dy * CGFloat(dt)
            }

            var picked = false
            for wIdx in worms.indices {
                guard worms[wIdx].isAlive else { continue }
                if hypot(worms[wIdx].position.x - c.position.x, worms[wIdx].position.y - c.position.y) < 36 {
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

        if turnNumber >= WorldConstants.suddenDeathStartTurn {
            waterY += WorldConstants.suddenDeathWaterStep
            pendingEvents.append(.suddenDeathTriggered(waterY: waterY))
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

        let teamWorms = worms.filter { $0.teamIndex == teamIndex && $0.isAlive }
        guard !teamWorms.isEmpty else {
            advanceTurnOrEndMatch()
            return
        }
        let cursor = teams[teamIndex].nextWormCursor % teamWorms.count
        let chosenWorm = teamWorms[cursor]
        teams[teamIndex].nextWormCursor = (cursor + 1) % max(1, teamWorms.count)
        activeWormID = chosenWorm.id

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
