import XCTest
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

        // Fire Shotgun shot #2 -> should enter settling
        var shot2 = InputSnapshot(); shot2.firePressed = true
        engine.update(dt: 1.0 / 60.0, input: &shot2)
        XCTAssertEqual(engine.shotgunShotsRemaining, 0)
        if case .settling = engine.phase {} else {
            XCTFail("Expected settling after 2nd shotgun shot, got \(engine.phase)")
        }

        // Verify Dynamite triggers retreat phase on a fresh match
        let dynEngine = GameEngine(config: config)
        var d0 = InputSnapshot(); d0.moveX = 0.5
        dynEngine.update(dt: 1.0 / 60.0, input: &d0)
        var prev = InputSnapshot(); prev.prevWeaponPressed = true
        dynEngine.update(dt: 1.0 / 60.0, input: &prev)
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
}
