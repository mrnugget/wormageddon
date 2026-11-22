import Foundation
import CoreGraphics
import SpriteKit

enum MapStyle: String, CaseIterable, Identifiable {
    case archipelago = "Archipel"
    case twinPeaks = "Gipfel"
    case canyon = "Schlucht"
    case fortress = "Festung"
    // Hand-painted battlefields copied from Hedgewars (GFDL 1.2, see README)
    case cheese = "Käse-Insel"
    case cake = "Riesentorte"
    case mushrooms = "Pilzwald"
    case castle = "Märchenburg"
    case pirateFlag = "Piratenflagge"
    case hammock = "Hängematte"
    case hedgelove = "Igel-Liebe"
    case octorama = "Krakenmeer"

    var id: String { rawValue }

    /// Asset catalog image (1440×750, binary alpha = solid terrain) for Hedgewars bitmap maps.
    var hedgewarsAssetName: String? {
        switch self {
        case .archipelago, .twinPeaks, .canyon, .fortress: return nil
        case .cheese: return "map_hw_cheese"
        case .cake: return "map_hw_cake"
        case .mushrooms: return "map_hw_mushrooms"
        case .castle: return "map_hw_castle"
        case .pirateFlag: return "map_hw_pirateflag"
        case .hammock: return "map_hw_hammock"
        case .hedgelove: return "map_hw_hedgelove"
        case .octorama: return "map_hw_octorama"
        }
    }

    var isHedgewarsArt: Bool { hedgewarsAssetName != nil }

    var subtitle: String {
        switch self {
        case .archipelago: return "Vier grüne Inseln im glitzernden Meer"
        case .twinPeaks: return "Hohe Bergketten mit weiten Tälern"
        case .canyon: return "Steile Klippen und eine mutige Brücke"
        case .fortress: return "Treppen-Inseln und geheime Verstecke"
        case .cheese: return "Löchriger Käse, eine Gabel und eine fliegende Maus"
        case .cake: return "Drei Etagen Sahnetorte und ein Tortenmesser-Steg"
        case .mushrooms: return "Hüpf von Fliegenpilz zu Fliegenpilz"
        case .castle: return "Ritterburg auf dem Hügel und eine Wolken-Insel"
        case .pirateFlag: return "Säbel-Brücken über dem Meer – sprengen!"
        case .hammock: return "Baumkronen und eine wackelige Hängematte"
        case .hedgelove: return "Zwei verliebte Igel und ein schwebendes Herz"
        case .octorama: return "Krake Olga und schwebende Blasen-Inseln"
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
    case bananaBomb = 6
    case sheep = 7
    case firePunch = 8
    case dynamite = 9

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .bazooka: return "Bazooka"
        case .grenade: return "Granate"
        case .clusterBomb: return "Streubombe"
        case .shotgun: return "Schrotflinte"
        case .airstrike: return "Luftangriff"
        case .holyGrenade: return "Heilige Granate"
        case .bananaBomb: return "Bananenbombe"
        case .sheep: return "Super-Schaf"
        case .firePunch: return "Feuerfaust"
        case .dynamite: return "Dynamit"
        }
    }

    var iconName: String {
        switch self {
        case .bazooka: return "weapon_bazooka"
        case .grenade: return "weapon_grenade"
        case .clusterBomb: return "weapon_cluster"
        case .shotgun: return "weapon_shotgun"
        case .airstrike: return "weapon_airstrike"
        case .holyGrenade: return "weapon_holy_grenade"
        case .bananaBomb: return "weapon_banana"
        case .sheep: return "weapon_sheep"
        case .firePunch: return "weapon_firepunch"
        case .dynamite: return "weapon_dynamite"
        }
    }

    var tagBadge: String {
        switch self {
        case .bazooka: return "WIND"
        case .grenade: return "3s ZÜNDER"
        case .clusterBomb: return "5× SPLITTER"
        case .shotgun: return "2 SCHÜSSE"
        case .airstrike: return "5 RAKETEN"
        case .holyGrenade: return "HALLELUJA!"
        case .bananaBomb: return "6× BANANEN"
        case .sheep: return "HÜPFT!"
        case .firePunch: return "NAHKAMPF"
        case .dynamite: return "WEGRENNEN!"
        }
    }

    var hint: String {
        switch self {
        case .bazooka: return "Fliegt mit dem Wind · Auswahl gedrückt halten für Kraft"
        case .grenade: return "Hüpft 3s bis zum Knall · Ohne Wind"
        case .clusterBomb: return "Zerplatzt nach 3s in 5 Mini-Knaller"
        case .shotgun: return "Sofort-Treffer ohne Wind · Du darfst 2× pro Zug schießen!"
        case .airstrike: return "Ziel mit ← / → wählen · Auswahl ruft 5 Raketen von oben"
        case .holyGrenade: return "Riesen-Knall nach 3,5s · Halleluja!"
        case .bananaBomb: return "Hüpft wild & zerplatzt in 6 chaotische Mini-Bananen!"
        case .sheep: return "Hoppelt los! Auswahl drücken für Sofort-Knall (oder nach 5,5s)"
        case .firePunch: return "Feuriger Kinnhaken! Schleudert nahe Gegner weit weg"
        case .dynamite: return "Vor dir ablegen (4s Zünder) – dann 3,5s schnell wegrennen!"
        }
    }

    var startingAmmo: Int? {
        switch self {
        case .bazooka, .grenade, .shotgun, .firePunch: return nil // Unendlich
        case .clusterBomb: return 3
        case .airstrike: return 2
        case .sheep: return 2
        case .dynamite: return 2
        case .holyGrenade: return 1
        case .bananaBomb: return 1
        }
    }

    var shotsPerTurn: Int {
        switch self {
        case .shotgun: return 2
        default: return 1
        }
    }

    var usesChargePower: Bool {
        switch self {
        case .bazooka, .grenade, .clusterBomb, .holyGrenade, .bananaBomb: return true
        case .shotgun, .airstrike, .sheep, .firePunch, .dynamite: return false
        }
    }

    var affectedByWind: Bool {
        switch self {
        case .bazooka, .airstrike: return true
        default: return false
        }
    }

    var explosionRadius: CGFloat {
        switch self {
        case .bazooka: return 74
        case .grenade: return 68
        case .clusterBomb: return 54
        case .shotgun: return 26
        case .airstrike: return 60
        case .holyGrenade: return 128
        case .bananaBomb: return 76
        case .sheep: return 94
        case .firePunch: return 36
        case .dynamite: return 104
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
        case .bananaBomb: return 46
        case .sheep: return 62
        case .firePunch: return 35
        case .dynamite: return 68
        }
    }

    var knockbackSpeed: CGFloat {
        switch self {
        case .bazooka: return 460
        case .grenade: return 430
        case .clusterBomb: return 370
        case .shotgun: return 290
        case .airstrike: return 400
        case .holyGrenade: return 640
        case .bananaBomb: return 480
        case .sheep: return 540
        case .firePunch: return 620
        case .dynamite: return 580
        }
    }

    var accentColor: SKColor {
        switch self {
        case .bazooka: return SKColor(red: 0.98, green: 0.48, blue: 0.24, alpha: 1)
        case .grenade: return SKColor(red: 0.34, green: 0.84, blue: 0.42, alpha: 1)
        case .clusterBomb: return SKColor(red: 0.96, green: 0.34, blue: 0.52, alpha: 1)
        case .shotgun: return SKColor(red: 0.74, green: 0.80, blue: 0.92, alpha: 1)
        case .airstrike: return SKColor(red: 0.30, green: 0.78, blue: 0.98, alpha: 1)
        case .holyGrenade: return SKColor(red: 1.00, green: 0.85, blue: 0.26, alpha: 1)
        case .bananaBomb: return SKColor(red: 1.00, green: 0.88, blue: 0.18, alpha: 1)
        case .sheep: return SKColor(red: 0.98, green: 0.56, blue: 0.72, alpha: 1)
        case .firePunch: return SKColor(red: 1.00, green: 0.42, blue: 0.16, alpha: 1)
        case .dynamite: return SKColor(red: 0.96, green: 0.24, blue: 0.26, alpha: 1)
        }
    }
}

enum WorldConstants {
    /// 1080p tvOS viewport size
    static let viewportWidth: CGFloat = 1920
    static let viewportHeight: CGFloat = 1080
    /// 50% larger destructible world with smooth camera panning & zooming
    static let width: CGFloat = 2880
    static let height: CGFloat = 1500
    static let initialWaterY: CGFloat = 104
    static let gravity: CGFloat = -680
    static let maxWindAccel: CGFloat = 310
    static let wormRadius: CGFloat = 16
    static let wormWalkSpeed: CGFloat = 122
    static let wormMaxStepUp: CGFloat = 15
    static let retreatDuration: TimeInterval = 3.5
    static let suddenDeathStartTurn: Int = 16
    static let suddenDeathWaterStep: CGFloat = 32
}
