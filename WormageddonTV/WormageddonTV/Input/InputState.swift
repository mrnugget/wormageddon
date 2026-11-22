import Foundation
import CoreGraphics

struct InputSnapshot {
    /// Horizontal movement axis (-1 left ... +1 right)
    var moveX: CGFloat = 0
    /// Vertical aim axis (-1 down ... +1 up)
    var aimY: CGFloat = 0
    /// Optional direct aim vector from a game controller's right thumbstick
    var directAimX: CGFloat = 0
    var directAimY: CGFloat = 0
    /// True while fire/select is currently held down
    var fireHeld: Bool = false
    /// Edge-triggered pulses consumed once per simulation step
    var firePressed: Bool = false
    var fireReleased: Bool = false
    var jumpPressed: Bool = false
    var backflipPressed: Bool = false
    var toggleWeaponBarPressed: Bool = false
    var prevWeaponPressed: Bool = false
    var nextWeaponPressed: Bool = false
    var pausePressed: Bool = false

    mutating func consumePulses() {
        firePressed = false
        fireReleased = false
        jumpPressed = false
        backflipPressed = false
        toggleWeaponBarPressed = false
        prevWeaponPressed = false
        nextWeaponPressed = false
        pausePressed = false
    }

    var hasAnyAction: Bool {
        abs(moveX) > 0.2 || abs(aimY) > 0.2 || firePressed || jumpPressed || backflipPressed || toggleWeaponBarPressed
    }
}
