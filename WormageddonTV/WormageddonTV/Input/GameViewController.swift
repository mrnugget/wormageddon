import UIKit
import SpriteKit
import GameController

final class GameViewController: GCEventViewController {
    private var skView: SKView!
    private(set) var scene: GameScene?
    weak var gameDelegate: GameSceneDelegate?

    // Held UIPress state (Siri Remote clickpad + Simulator keyboard)
    private var heldPressTypes: Set<UIPress.PressType> = []
    private var heldKeyCodes: Set<UIKeyboardHIDUsage> = []

    // Double-tap detection for Siri Remote jump / backflip
    private var lastUpPressTime: TimeInterval = 0
    private var lastDownPressTime: TimeInterval = 0

    // Pending edge-triggered input pulses
    private var pendingInput = InputSnapshot()

    // Extended gamepad previous-frame button states for clean edge detection
    private var prevGamepadFire = false
    private var prevGamepadA = false
    private var prevGamepadB = false
    private var prevGamepadY = false
    private var prevGamepadL1 = false
    private var prevGamepadR1 = false
    private var prevGamepadMenu = false

    private var activeMatchConfig: MatchConfig?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let spriteView = SKView(frame: view.bounds)
        spriteView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        spriteView.ignoresSiblingOrder = true
        spriteView.preferredFramesPerSecond = 60
        view.addSubview(spriteView)
        self.skView = spriteView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllersChanged),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllersChanged),
            name: .GCControllerDidDisconnect,
            object: nil
        )
        configureConnectedControllers()

        if let config = activeMatchConfig {
            presentNewMatch(config: config)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func startMatch(config: MatchConfig) {
        activeMatchConfig = config
        if isViewLoaded {
            presentNewMatch(config: config)
        }
    }

    func setGameplayPaused(_ paused: Bool) {
        scene?.isGameplayPaused = paused
        controllerUserInteractionEnabled = paused
        if paused {
            heldPressTypes.removeAll()
            heldKeyCodes.removeAll()
            pendingInput = InputSnapshot()
        }
    }

    private func presentNewMatch(config: MatchConfig) {
        heldPressTypes.removeAll()
        heldKeyCodes.removeAll()
        pendingInput = InputSnapshot()

        let gameScene = GameScene(config: config)
        gameScene.gameDelegate = gameDelegate
        gameScene.inputProvider = { [weak self] in
            self?.sampleInputSnapshot() ?? InputSnapshot()
        }
        gameScene.isGameControllerConnected = false
        self.scene = gameScene

        controllerUserInteractionEnabled = false
        skView.presentScene(gameScene)
    }

    // MARK: - GameController Setup

    @objc private func controllersChanged() {
        configureConnectedControllers()
        if !hasExtendedGamepad() {
            scene?.isGameControllerConnected = false
        }
    }

    private func configureConnectedControllers() {
        for controller in GCController.controllers() {
            if let micro = controller.microGamepad {
                micro.reportsAbsoluteDpadValues = true
                micro.allowsRotation = false
            }
        }
    }

    private func hasExtendedGamepad() -> Bool {
        GCController.controllers().contains { controller in
            guard controller.extendedGamepad != nil else { return false }
            let category = controller.productCategory.lowercased()
            return !category.contains("siri") && !category.contains("remote")
        }
    }

    // MARK: - Unified Input Sampling (called once per SpriteKit frame)

    private func sampleInputSnapshot() -> InputSnapshot {
        var snap = pendingInput
        pendingInput.consumePulses()

        var moveX: CGFloat = 0
        var aimY: CGFloat = 0
        var directAimX: CGFloat = 0
        var directAimY: CGFloat = 0
        var fireHeld = heldPressTypes.contains(.select) || heldKeyCodes.contains(.keyboardReturnOrEnter)

        // 1. UIPress held arrows (Siri Remote directional ring + Simulator arrows)
        if heldPressTypes.contains(.leftArrow) || heldKeyCodes.contains(.keyboardA) { moveX -= 1 }
        if heldPressTypes.contains(.rightArrow) || heldKeyCodes.contains(.keyboardD) { moveX += 1 }
        if heldPressTypes.contains(.upArrow) || heldKeyCodes.contains(.keyboardW) { aimY += 1 }
        if heldPressTypes.contains(.downArrow) || heldKeyCodes.contains(.keyboardS) { aimY -= 1 }

        // 2. Extended Gamepads (PlayStation / Xbox / MFi controllers)
        var anyGamepadFire = false
        var anyA = false
        var anyB = false
        var anyY = false
        var anyL1 = false
        var anyR1 = false
        var anyMenu = false

        for controller in GCController.controllers() {
            if let pad = controller.extendedGamepad {
                let lx = CGFloat(pad.leftThumbstick.xAxis.value)
                let ly = CGFloat(pad.leftThumbstick.yAxis.value)
                let dx = CGFloat(pad.dpad.xAxis.value)
                let dy = CGFloat(pad.dpad.yAxis.value)

                if abs(lx) > 0.22 { moveX = lx; scene?.isGameControllerConnected = true } else if abs(dx) > 0.22 { moveX = dx; scene?.isGameControllerConnected = true }
                if abs(ly) > 0.22 { aimY = ly; scene?.isGameControllerConnected = true } else if abs(dy) > 0.22 { aimY = dy; scene?.isGameControllerConnected = true }

                let rx = CGFloat(pad.rightThumbstick.xAxis.value)
                let ry = CGFloat(pad.rightThumbstick.yAxis.value)
                if hypot(rx, ry) > 0.35 {
                    directAimX = rx
                    directAimY = ry
                    scene?.isGameControllerConnected = true
                }

                if pad.rightTrigger.value > 0.35 || pad.buttonX.isPressed { anyGamepadFire = true }
                if pad.buttonA.isPressed { anyA = true }
                if pad.buttonB.isPressed { anyB = true }
                if pad.buttonY.isPressed { anyY = true }
                if pad.leftShoulder.isPressed { anyL1 = true }
                if pad.rightShoulder.isPressed { anyR1 = true }
                if pad.buttonMenu.isPressed { anyMenu = true }
            } else if let micro = controller.microGamepad {
                // Siri Remote touchpad fallback when no discrete press arrow is held
                if moveX == 0 && aimY == 0 {
                    let tx = CGFloat(micro.dpad.xAxis.value)
                    let ty = CGFloat(micro.dpad.yAxis.value)
                    if abs(tx) > 0.42 && abs(tx) >= abs(ty) {
                        moveX = tx > 0 ? 1 : -1
                    } else if abs(ty) > 0.42 {
                        aimY = ty > 0 ? 1 : -1
                    }
                }
            }
        }

        if anyGamepadFire || anyA || anyB || anyY || anyL1 || anyR1 || anyMenu {
            scene?.isGameControllerConnected = true
        }

        if anyGamepadFire && !prevGamepadFire { snap.firePressed = true }
        if !anyGamepadFire && prevGamepadFire { snap.fireReleased = true }
        if anyGamepadFire { fireHeld = true }
        prevGamepadFire = anyGamepadFire

        if anyA && !prevGamepadA { snap.jumpPressed = true }
        prevGamepadA = anyA

        if anyB && !prevGamepadB { snap.backflipPressed = true }
        prevGamepadB = anyB

        if anyY && !prevGamepadY { snap.toggleWeaponBarPressed = true }
        prevGamepadY = anyY

        if anyL1 && !prevGamepadL1 { snap.prevWeaponPressed = true }
        prevGamepadL1 = anyL1

        if anyR1 && !prevGamepadR1 { snap.nextWeaponPressed = true }
        prevGamepadR1 = anyR1

        if anyMenu && !prevGamepadMenu { snap.pausePressed = true }
        prevGamepadMenu = anyMenu

        snap.moveX = max(-1, min(1, moveX))
        snap.aimY = max(-1, min(1, aimY))
        snap.directAimX = directAimX
        snap.directAimY = directAimY
        snap.fireHeld = fireHeld
        return snap
    }

    // MARK: - UIPress Handling (Siri Remote & tvOS Simulator Keyboard)

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard scene?.isGameplayPaused == false else {
            super.pressesBegan(presses, with: event)
            return
        }

        var handled = false
        let now = CACurrentMediaTime()

        for press in presses {
            if let keyCode = press.key?.keyCode {
                heldKeyCodes.insert(keyCode)
                switch keyCode {
                case .keyboardSpacebar:
                    pendingInput.jumpPressed = true
                    handled = true
                case .keyboardB:
                    pendingInput.backflipPressed = true
                    handled = true
                case .keyboardTab:
                    pendingInput.toggleWeaponBarPressed = true
                    handled = true
                case .keyboardQ:
                    pendingInput.prevWeaponPressed = true
                    handled = true
                case .keyboardE:
                    pendingInput.nextWeaponPressed = true
                    handled = true
                case .keyboardReturnOrEnter:
                    pendingInput.firePressed = true
                    handled = true
                case .keyboardEscape:
                    pendingInput.pausePressed = true
                    handled = true
                case .keyboardA, .keyboardD, .keyboardW, .keyboardS:
                    handled = true
                default:
                    break
                }
            }

            switch press.type {
            case .leftArrow, .rightArrow:
                heldPressTypes.insert(press.type)
                handled = true

            case .upArrow:
                heldPressTypes.insert(.upArrow)
                if now - lastUpPressTime < 0.28 {
                    pendingInput.jumpPressed = true
                    lastUpPressTime = 0
                } else {
                    lastUpPressTime = now
                }
                handled = true

            case .downArrow:
                heldPressTypes.insert(.downArrow)
                if now - lastDownPressTime < 0.28 {
                    pendingInput.backflipPressed = true
                    lastDownPressTime = 0
                } else {
                    lastDownPressTime = now
                }
                handled = true

            case .select:
                heldPressTypes.insert(.select)
                pendingInput.firePressed = true
                handled = true

            case .playPause:
                pendingInput.toggleWeaponBarPressed = true
                handled = true

            case .menu:
                pendingInput.pausePressed = true
                handled = true

            default:
                break
            }
        }

        if !handled {
            super.pressesBegan(presses, with: event)
        } else {
            scene?.isGameControllerConnected = false
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let keyCode = press.key?.keyCode {
                heldKeyCodes.remove(keyCode)
                if keyCode == .keyboardReturnOrEnter {
                    pendingInput.fireReleased = true
                }
            }
            if press.type == .select {
                pendingInput.fireReleased = true
            }
            heldPressTypes.remove(press.type)
        }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        pressesEnded(presses, with: event)
    }
}
