import Foundation
import CoreGraphics
import SpriteKit

enum MapStyle: String, CaseIterable, Identifiable {
    case archipelago = "Archipel"
    case twinPeaks = "Gipfel"
    case canyon = "Schlucht"
    case fortress = "Festung"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .archipelago: return "Drei grüne Inseln im glitzernden Meer"
        case .twinPeaks: return "Zwei hohe Gipfel mit einem grünen Tal"
        case .canyon: return "Steile Klippen und eine mutige Brücke"
        case .fortress: return "Treppen-Inseln und geheime Verstecke"
        }
    }
}

enum MapTheme: String, CaseIterable, Identifiable {
    case alpineSunset = "Goldener Abend"
    case emeraldIsles = "Smaragd-Inseln"
    case volcanicDusk = "Zauber-Nacht"

    var id: String { rawValue }

    var skyTop: SKColor {
        switch self {
        case .alpineSunset: return SKColor(red: 0.13, green: 0.15, blue: 0.36, alpha: 1)
        case .emeraldIsles: return SKColor(red: 0.12, green: 0.48, blue: 0.88, alpha: 1)
        case .volcanicDusk: return SKColor(red: 0.08, green: 0.09, blue: 0.24, alpha: 1)
        }
    }

    var skyMid: SKColor {
        switch self {
        case .alpineSunset: return SKColor(red: 0.56, green: 0.31, blue: 0.48, alpha: 1)
        case .emeraldIsles: return SKColor(red: 0.36, green: 0.74, blue: 0.96, alpha: 1)
        case .volcanicDusk: return SKColor(red: 0.30, green: 0.16, blue: 0.44, alpha: 1)
        }
    }

    var skyBottom: SKColor {
        switch self {
        case .alpineSunset: return SKColor(red: 0.98, green: 0.64, blue: 0.42, alpha: 1)
        case .emeraldIsles: return SKColor(red: 0.80, green: 0.95, blue: 0.98, alpha: 1)
        case .volcanicDusk: return SKColor(red: 0.82, green: 0.42, blue: 0.52, alpha: 1)
        }
    }

    var showsStars: Bool {
        switch self {
        case .alpineSunset, .volcanicDusk: return true
        case .emeraldIsles: return false
        }
    }

    var sunColor: SKColor {
        switch self {
        case .alpineSunset: return SKColor(red: 1.0, green: 0.94, blue: 0.76, alpha: 0.96)
        case .emeraldIsles: return SKColor(red: 1.0, green: 0.97, blue: 0.82, alpha: 0.98)
        case .volcanicDusk: return SKColor(red: 0.95, green: 0.93, blue: 1.0, alpha: 0.95)
        }
    }

    var grassColor: (r: UInt8, g: UInt8, b: UInt8) {
        switch self {
        case .alpineSunset: return (74, 188, 92)
        case .emeraldIsles: return (58, 204, 96)
        case .volcanicDusk: return (62, 168, 138)
        }
    }

    var grassHighlight: (r: UInt8, g: UInt8, b: UInt8) {
        switch self {
        case .alpineSunset: return (142, 232, 114)
        case .emeraldIsles: return (136, 242, 126)
        case .volcanicDusk: return (122, 224, 188)
        }
    }

    var soilColor: (r: UInt8, g: UInt8, b: UInt8) {
        switch self {
        case .alpineSunset: return (148, 96, 66)
        case .emeraldIsles: return (166, 114, 72)
        case .volcanicDusk: return (92, 68, 98)
        }
    }

    var rockColor: (r: UInt8, g: UInt8, b: UInt8) {
        switch self {
        case .alpineSunset: return (92, 68, 78)
        case .emeraldIsles: return (112, 92, 82)
        case .volcanicDusk: return (58, 46, 76)
        }
    }

    var waterColor: SKColor {
        switch self {
        case .alpineSunset: return SKColor(red: 0.10, green: 0.44, blue: 0.68, alpha: 0.88)
        case .emeraldIsles: return SKColor(red: 0.06, green: 0.58, blue: 0.82, alpha: 0.86)
        case .volcanicDusk: return SKColor(red: 0.14, green: 0.24, blue: 0.50, alpha: 0.90)
        }
    }

    var farHillColor: SKColor {
        switch self {
        case .alpineSunset: return SKColor(red: 0.34, green: 0.24, blue: 0.44, alpha: 0.52)
        case .emeraldIsles: return SKColor(red: 0.36, green: 0.66, blue: 0.84, alpha: 0.42)
        case .volcanicDusk: return SKColor(red: 0.24, green: 0.16, blue: 0.38, alpha: 0.58)
        }
    }

    var hillColor: SKColor {
        switch self {
        case .alpineSunset: return SKColor(red: 0.24, green: 0.19, blue: 0.36, alpha: 0.72)
        case .emeraldIsles: return SKColor(red: 0.22, green: 0.52, blue: 0.70, alpha: 0.55)
        case .volcanicDusk: return SKColor(red: 0.16, green: 0.12, blue: 0.28, alpha: 0.76)
        }
    }

    var flowerPalette: [SKColor] {
        switch self {
        case .alpineSunset:
            return [
                SKColor(red: 1.0, green: 0.86, blue: 0.32, alpha: 1),
                SKColor(red: 1.0, green: 0.48, blue: 0.58, alpha: 1),
                SKColor(red: 0.96, green: 0.96, blue: 1.0, alpha: 1)
            ]
        case .emeraldIsles:
            return [
                SKColor(red: 1.0, green: 0.84, blue: 0.24, alpha: 1),
                SKColor(red: 1.0, green: 0.52, blue: 0.72, alpha: 1),
                SKColor(red: 0.46, green: 0.86, blue: 1.0, alpha: 1)
            ]
        case .volcanicDusk:
            return [
                SKColor(red: 0.68, green: 0.96, blue: 1.0, alpha: 1),
                SKColor(red: 1.0, green: 0.72, blue: 0.92, alpha: 1),
                SKColor(red: 1.0, green: 0.90, blue: 0.46, alpha: 1)
            ]
        }
    }
}

struct MatchConfig: Equatable {
    var playerCount: Int = 3
    var wormsPerTeam: Int = 3
    var mapStyle: MapStyle = .archipelago
    var mapTheme: MapTheme = .alpineSunset
    var turnDuration: TimeInterval = 45.0
    var seed: UInt64 = UInt64.random(in: 1...UInt64.max)
}

enum TeamAccessoryStyle {
    case ladybugDots   // Miraculous-Würmer
    case wizardStar    // Hogwarts-Knaller
    case kittyEars     // Pfoten-Power (Bluey & Gabby)
}

struct TeamDescriptor {
    let index: Int
    let name: String
    let tagline: String
    let color: SKColor
    let accessory: TeamAccessoryStyle
    let accentHex: UInt32
    let wormNames: [String]

    static let all: [TeamDescriptor] = [
        TeamDescriptor(
            index: 0,
            name: "Miraculous-Würmer",
            tagline: "Glücksbringer mit Wumms",
            color: SKColor(red: 0.96, green: 0.25, blue: 0.32, alpha: 1),
            accessory: .ladybugDots,
            accentHex: 0xF54052,
            wormNames: ["Wurmbug", "Cat Wurm", "Tikki-Turbo", "Plagg-Käse"]
        ),
        TeamDescriptor(
            index: 1,
            name: "Hogwarts-Knaller",
            tagline: "Magische Wurm-Zauberei",
            color: SKColor(red: 0.24, green: 0.60, blue: 1.00, alpha: 1),
            accessory: .wizardStar,
            accentHex: 0x3D99FF,
            wormNames: ["Harry Wurm", "Hermine Bumm", "Dumblewurm", "Hedwig-Zack"]
        ),
        TeamDescriptor(
            index: 2,
            name: "Pfoten-Power",
            tagline: "Kicher-Chaos aus dem Puppenhaus",
            color: SKColor(red: 0.18, green: 0.84, blue: 0.56, alpha: 1),
            accessory: .kittyEars,
            accentHex: 0x2ED68F,
            wormNames: ["Bluey-Bumm", "Bingo-Blitz", "Kuchi-Knall", "Pandy-Pfote"]
        )
    ]
}

enum WeaponKind: Int, CaseIterable, Identifiable {
    case bazooka = 0
    case grenade = 1
    case clusterBomb = 2
    case shotgun = 3
    case airstrike = 4
    case holyGrenade = 5

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .bazooka: return "Bazooka"
        case .grenade: return "Granate"
        case .clusterBomb: return "Streubombe"
        case .shotgun: return "Schrotflinte"
        case .airstrike: return "Luftangriff"
        case .holyGrenade: return "Heilige Granate"
        }
    }

    var shortLabel: String {
        switch self {
        case .bazooka: return "BAZ"
        case .grenade: return "GRN"
        case .clusterBomb: return "STR"
        case .shotgun: return "SCH"
        case .airstrike: return "LUF"
        case .holyGrenade: return "HLG"
        }
    }

    var hint: String {
        switch self {
        case .bazooka: return "Fliegt mit dem Wind · Auswahl halten für mehr Kraft"
        case .grenade: return "Hüpft 3s bis zum Knall · Ohne Wind"
        case .clusterBomb: return "Zerplatzt nach 3s in 5 Mini-Knaller"
        case .shotgun: return "Sofort-Treffer · 2 Schüsse pro Zug"
        case .airstrike: return "Ziel mit ← / → wählen · Auswahl ruft 5 Raketen"
        case .holyGrenade: return "Riesen-Knall nach 3,5s · Halleluja!"
        }
    }

    var startingAmmo: Int? {
        switch self {
        case .bazooka, .grenade, .shotgun: return nil // Unendlich
        case .clusterBomb: return 3
        case .airstrike: return 1
        case .holyGrenade: return 1
        }
    }

    var usesChargePower: Bool {
        switch self {
        case .bazooka, .grenade, .clusterBomb, .holyGrenade: return true
        case .shotgun, .airstrike: return false
        }
    }

    var affectedByWind: Bool {
        switch self {
        case .bazooka, .airstrike: return true
        case .grenade, .clusterBomb, .shotgun, .holyGrenade: return false
        }
    }

    var explosionRadius: CGFloat {
        switch self {
        case .bazooka: return 68
        case .grenade: return 62
        case .clusterBomb: return 50
        case .shotgun: return 22
        case .airstrike: return 54
        case .holyGrenade: return 118
        }
    }

    var maxDamage: Int {
        switch self {
        case .bazooka: return 45
        case .grenade: return 42
        case .clusterBomb: return 30
        case .shotgun: return 25
        case .airstrike: return 32
        case .holyGrenade: return 75
        }
    }

    var knockbackSpeed: CGFloat {
        switch self {
        case .bazooka: return 440
        case .grenade: return 410
        case .clusterBomb: return 360
        case .shotgun: return 270
        case .airstrike: return 380
        case .holyGrenade: return 620
        }
    }

    var accentColor: SKColor {
        switch self {
        case .bazooka: return SKColor(red: 0.98, green: 0.48, blue: 0.24, alpha: 1)
        case .grenade: return SKColor(red: 0.34, green: 0.82, blue: 0.42, alpha: 1)
        case .clusterBomb: return SKColor(red: 0.96, green: 0.34, blue: 0.52, alpha: 1)
        case .shotgun: return SKColor(red: 0.72, green: 0.78, blue: 0.88, alpha: 1)
        case .airstrike: return SKColor(red: 0.30, green: 0.78, blue: 0.98, alpha: 1)
        case .holyGrenade: return SKColor(red: 1.00, green: 0.85, blue: 0.26, alpha: 1)
        }
    }
}

enum WorldConstants {
    static let width: CGFloat = 1920
    static let height: CGFloat = 1080
    static let initialWaterY: CGFloat = 88
    static let gravity: CGFloat = -680
    static let maxWindAccel: CGFloat = 290
    static let wormRadius: CGFloat = 15
    static let wormWalkSpeed: CGFloat = 108
    static let wormMaxStepUp: CGFloat = 14
    static let retreatDuration: TimeInterval = 3.0
    static let suddenDeathStartTurn: Int = 14
    static let suddenDeathWaterStep: CGFloat = 26
}
