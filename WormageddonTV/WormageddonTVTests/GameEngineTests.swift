import XCTest
import UIKit
@testable import WormageddonTV

final class GameEngineTests: XCTestCase {

    func testAllMapStylesGenerateWalkableTerrain() {
        for style in MapStyle.allCases {
            let terrain = TerrainMap(style: style, theme: .alpineSunset, seed: 42)
            var foundLand = false
            for x in stride(from: CGFloat(180), through: WorldConstants.width - 180, by: 40) {
                if let sy = terrain.surfaceY(atWorldX: x), sy > WorldConstants.initialWaterY + 25 {
                    foundLand = true
                    break
                }
            }
            XCTAssertTrue(foundLand, "Expected solid land above water for style \(style.rawValue)")
        }
    }

    func testCraterCarvingRemovesSolidTerrain() {
        let terrain = TerrainMap(style: .fortress, theme: .emeraldIsles, seed: 99)
        let centerX: CGFloat = WorldConstants.width * 0.5
        guard let topY = terrain.surfaceY(atWorldX: centerX) else {
            XCTFail("Expected solid surface at map center")
            return
        }
        let target = CGPoint(x: centerX, y: topY - 24)
        XCTAssertTrue(terrain.isSolid(worldPoint: target))

        let revBefore = terrain.revision
        let removed = terrain.carveCrater(worldCenter: target, worldRadius: 48)
        XCTAssertGreaterThan(removed, 200)
        XCTAssertEqual(terrain.revision, revBefore + 1)
        XCTAssertFalse(terrain.isSolid(worldPoint: target))
    }

    func testHedgewarsMapsSpawnTwelveWormsOnLedgesAndCarve() {
        let r = WorldConstants.wormRadius
        for style in MapStyle.allCases where style.isHedgewarsArt {
            var config = MatchConfig()
            config.playerCount = 3
            config.wormsPerTeam = 4
            config.mapStyle = style
            config.seed = 4242
            let engine = GameEngine(config: config)
            XCTAssertEqual(engine.worms.count, 12)

            XCTAssertNotNil(UIImage(named: style.hedgewarsAssetName ?? ""), "\(style.rawValue) artwork missing from asset catalog")

            var spots = Set<String>()
            for worm in engine.worms {
                let p = worm.position
                XCTAssertFalse(engine.terrain.isSolidCircle(center: p, radius: r * 0.8), "\(style.rawValue): worm stuck in terrain at \(p)")
                XCTAssertTrue(engine.terrain.isSolid(worldPoint: CGPoint(x: p.x, y: p.y - r - 3)), "\(style.rawValue): worm floating at \(p)")
                XCTAssertGreaterThan(p.y, WorldConstants.initialWaterY + 40)
                spots.insert("\(Int(p.x)),\(Int(p.y))")
            }
            XCTAssertEqual(spots.count, 12, "\(style.rawValue): worms share spawn spots")

            // Blasting the floor under a worm makes it fall.
            let victim = engine.worms[0]
            engine.terrain.carveCrater(worldCenter: CGPoint(x: victim.position.x, y: victim.position.y - r - 20), worldRadius: 44)
            XCTAssertFalse(engine.terrain.isSolid(worldPoint: CGPoint(x: victim.position.x, y: victim.position.y - r - 3)))
        }
    }

    func testThreePlayerSetupAndTurnRotation() {
        var config = MatchConfig()
        config.playerCount = 3
        config.wormsPerTeam = 2
        config.seed = 12345
        let engine = GameEngine(config: config)

        XCTAssertEqual(engine.teams.count, 3)
        XCTAssertEqual(engine.worms.count, 6)
        XCTAssertEqual(engine.currentTeamIndex, 0)

        // Dismiss turn banner
        var input = InputSnapshot()
        input.moveX = 0.5
        engine.update(dt: 1.0 / 60.0, input: &input)
        XCTAssertEqual(engine.phase, .playerControl)

        // Let turn timer expire to verify rotation 0 -> 1 -> 2
        for _ in 0..<2800 {
            var idle = InputSnapshot()
            engine.update(dt: 1.0 / 60.0, input: &idle)
            if engine.currentTeamIndex == 1 { break }
        }
        XCTAssertEqual(engine.currentTeamIndex, 1)
    }

    func testBazookaChargeFireAndExplosion() {
        var config = MatchConfig()
        config.playerCount = 2
        config.wormsPerTeam = 2
        config.seed = 777
        let engine = GameEngine(config: config)

        // Dismiss banner
        var dismiss = InputSnapshot()
        dismiss.aimY = 0.5
        engine.update(dt: 1.0 / 60.0, input: &dismiss)

        // Start charging bazooka
        var pressFire = InputSnapshot()
        pressFire.firePressed = true
        pressFire.fireHeld = true
        engine.update(dt: 1.0 / 60.0, input: &pressFire)

        if case .charging = engine.phase {
            // Hold for 0.4s
            for _ in 0..<24 {
                var hold = InputSnapshot()
                hold.fireHeld = true
                engine.update(dt: 1.0 / 60.0, input: &hold)
            }
            // Release to launch
            var release = InputSnapshot()
            release.fireReleased = true
            release.fireHeld = false
            engine.update(dt: 1.0 / 60.0, input: &release)
        } else {
            XCTFail("Expected charging phase after pressing fire with Bazooka")
        }

        XCTAssertEqual(engine.phase, .projectileInFlight)
        XCTAssertEqual(engine.projectiles.count, 1)

        // Step simulation until rocket impacts or exits and turn advances
        var sawExplosion = false
        for _ in 0..<600 {
            var idle = InputSnapshot()
            engine.update(dt: 1.0 / 60.0, input: &idle)
            for ev in engine.drainEvents() {
                if case .explosion = ev { sawExplosion = true }
            }
            if engine.currentTeamIndex == 1 { break }
        }
        XCTAssertTrue(sawExplosion || engine.currentTeamIndex == 1, "Rocket should either explode or finish flight and advance turn")
    }

    func testExplosionDamagesNearbyWormsAndDetectsVictory() {
        var config = MatchConfig()
        config.playerCount = 2
        config.wormsPerTeam = 1
        config.seed = 555
        let engine = GameEngine(config: config)

        guard let targetWorm = engine.worms.first(where: { $0.teamIndex == 1 }) else {
            XCTFail("Missing team 1 worm")
            return
        }

        // Two direct blasts should eliminate the 100 HP enemy worm
        engine.triggerExplosion(at: targetWorm.position, radius: 70, maxDamage: 65, knockback: 100, ownerTeamIndex: 0, isHoly: false)
        engine.triggerExplosion(at: targetWorm.position, radius: 70, maxDamage: 65, knockback: 100, ownerTeamIndex: 0, isHoly: false)

        let updatedTarget = engine.worms.first(where: { $0.id == targetWorm.id })!
        XCTAssertFalse(updatedTarget.isAlive)
        XCTAssertEqual(engine.aliveTeamIndices(), [0])
    }

    func testNewWeaponsDynamiteRetreatSheepAndShotgunTwoShots() {
        var config = MatchConfig()
        config.playerCount = 2
        config.wormsPerTeam = 2
        config.seed = 2026
        let engine = GameEngine(config: config)

        // Dismiss turn banner
        var dismiss = InputSnapshot()
        dismiss.moveX = 0.5
        engine.update(dt: 1.0 / 60.0, input: &dismiss)

        // Equip Shotgun via weapon cycling (bazooka -> grenade -> cluster -> shotgun)
        for _ in 0..<3 {
            var next = InputSnapshot(); next.nextWeaponPressed = true
            engine.update(dt: 1.0 / 60.0, input: &next)
        }
        XCTAssertEqual(engine.selectedWeapon, .shotgun)

        // Fire Shotgun shot #1 -> should stay in playerControl with 1 shot remaining!
        var shot1 = InputSnapshot(); shot1.firePressed = true
        engine.update(dt: 1.0 / 60.0, input: &shot1)
        XCTAssertEqual(engine.shotgunShotsRemaining, 1)
        XCTAssertEqual(engine.phase, .playerControl)

        // Fire Shotgun shot #2 -> should enter retreat phase (so player can run for cover!)
        var shot2 = InputSnapshot(); shot2.firePressed = true
        engine.update(dt: 1.0 / 60.0, input: &shot2)
        XCTAssertEqual(engine.shotgunShotsRemaining, 0)
        if case .retreat = engine.phase {} else {
            XCTFail("Expected retreat after 2nd shotgun shot, got \(engine.phase)")
        }

        // Equip Dynamite via weapon cycling (skips 0-ammo crate super weapons)
        let dynEngine = GameEngine(config: config)
        XCTAssertEqual(dynEngine.crates.count, 1, "A golden weapon crate should drop from the sky at match start")
        XCTAssertEqual(dynEngine.currentTeam.ammoCount(for: .bananaBomb), 0, "Super weapons start at 0 until found in crates")
        var d0 = InputSnapshot(); d0.moveX = 0.5
        dynEngine.update(dt: 1.0 / 60.0, input: &d0)
        for _ in 0..<WeaponKind.allCases.count where dynEngine.selectedWeapon != .dynamite {
            var nxt = InputSnapshot(); nxt.nextWeaponPressed = true
            dynEngine.update(dt: 1.0 / 60.0, input: &nxt)
        }
        XCTAssertEqual(dynEngine.selectedWeapon, .dynamite)
        var drop = InputSnapshot(); drop.firePressed = true
        dynEngine.update(dt: 1.0 / 60.0, input: &drop)
        if case .retreat = dynEngine.phase {} else {
            XCTFail("Expected retreat phase after placing Dynamite, got \(dynEngine.phase)")
        }

        // Verify world is 50% larger (2880 x 1500)
        XCTAssertEqual(engine.terrain.worldWidth, 2880)
        XCTAssertEqual(engine.terrain.worldHeight, 1500)
    }

    func testJumpLiftsWormAndJetpackTeleportWork() {
        var config = MatchConfig()
        config.playerCount = 2
        config.wormsPerTeam = 2
        config.mapStyle = .archipelago
        config.seed = 9001
        let engine = GameEngine(config: config)

        // Dismiss banner
        var d = InputSnapshot(); d.moveX = 0.5
        engine.update(dt: 1.0 / 60.0, input: &d)

        let startY = engine.activeWorm!.position.y
        var jump = InputSnapshot(); jump.jumpPressed = true
        engine.update(dt: 1.0 / 60.0, input: &jump)
        XCTAssertFalse(engine.activeWorm!.isGrounded, "Worm must leave ground on jump frame 1")

        var maxY = startY
        for _ in 0..<45 {
            var idle = InputSnapshot()
            engine.update(dt: 1.0 / 60.0, input: &idle)
            maxY = max(maxY, engine.activeWorm!.position.y)
        }
        XCTAssertGreaterThan(maxY - startY, 80, "Forward jump should gain significant height (> 80pt), got \(maxY - startY)")

        // Test Jetpack flies up & returns to playerControl without ending turn
        for _ in 0..<WeaponKind.allCases.count where engine.selectedWeapon != .jetpack {
            var nxt = InputSnapshot(); nxt.nextWeaponPressed = true
            engine.update(dt: 1.0 / 60.0, input: &nxt)
        }
        XCTAssertEqual(engine.selectedWeapon, .jetpack)
        let teamBefore = engine.currentTeamIndex
        var ignite = InputSnapshot(); ignite.firePressed = true
        engine.update(dt: 1.0 / 60.0, input: &ignite)
        if case .jetpackFlying = engine.phase {} else {
            XCTFail("Expected jetpackFlying, got \(engine.phase)")
        }
        for _ in 0..<20 {
            var up = InputSnapshot(); up.aimY = 1.0
            engine.update(dt: 1.0 / 60.0, input: &up)
        }
        var land = InputSnapshot(); land.firePressed = true
        engine.update(dt: 1.0 / 60.0, input: &land)
        XCTAssertEqual(engine.phase, .playerControl)
        XCTAssertEqual(engine.currentTeamIndex, teamBefore, "Jetpack should not end the player's turn")

        // Verify Teleport rejects open ocean (edge x=60) and accepts open air above a solid island
        XCTAssertFalse(engine.isValidTeleportTarget(CGPoint(x: 60, y: 800)), "Teleport must block open water")
        let islandX = WorldConstants.width * 0.38
        let islandTop = engine.terrain.surfaceY(atWorldX: islandX)!
        XCTAssertTrue(engine.isValidTeleportTarget(CGPoint(x: islandX, y: islandTop + 80)), "Teleport should allow open air above solid land")
    }
}
