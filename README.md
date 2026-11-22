# Wurmageddon (Apple TV)

A native tvOS turn-based artillery game inspired by *Worms Armageddon*, built in Swift with SpriteKit and SwiftUI for 2–3 local players on Apple TV — localized in German with Miraculous, Harry Potter, Gabby's Dollhouse, and Bluey-inspired teams.

## Teams
- **Miraculous-Würmer**: Wurmbug, Cat Wurm, Tikki-Turbo, Plagg-Käse
- **Hogwarts-Knaller**: Harry Wurm, Hermine Bumm, Dumblewurm, Hedwig-Zack
- **Pfoten-Power**: Bluey-Bumm, Bingo-Blitz, Kuchi-Knall, Pandy-Pfote

## Features
- **2–3 Player Local Multiplayer**: Hotseat turn banners, 45s turn timer, team health bars, and victory summary.
- **Pixel-Level Destructible Terrain**: 4 layouts (*Archipel*, *Gipfel*, *Schlucht*, *Festung*) and 3 themes (*Goldener Abend*, *Smaragd-Inseln*, *Zauber-Nacht*) with charred craters, destructible wildflowers & trees, fall damage, supply crates, and Sudden Death rising water.
- **6 Weapons**: Bazooka, Granate, Streubombe, Schrotflinte (2 shots), Luftangriff, and Heilige Granate.
- **Siri Remote & Game Controllers**: Works with just the Apple TV Siri Remote (pass around between turns) or Bluetooth PlayStation / Xbox / Switch Pro / MFi controllers.

## Controls

| Action | Siri Remote | Game Controller (PS / Xbox / MFi) |
|---|---|---|
| Walk | Left / Right | Left Stick / D-Pad Left–Right |
| Aim | Up / Down | Left Stick / D-Pad Up–Down, or Right Stick (360°) |
| Charge & Fire | Hold Select, release to fire | Hold R2/RT or X/Square |
| Jump / Backflip | Double-tap Up / Double-tap Down | A (Cross) / B (Circle) |
| Weapon Bar | Play/Pause | Y (Triangle), or L1/R1 to cycle |
| Pause | Back / Menu | Menu / Options |

## Install on Apple TV from Xcode

1. Put your Mac and Apple TV on the same Wi-Fi network.
2. On Apple TV: **Settings → Remotes and Devices → Remote App and Devices**.
3. Open `WormageddonTV/WormageddonTV.xcodeproj` in Xcode.
4. Go to **Window → Devices and Simulators**, select your Apple TV, and enter the pairing code shown on the TV.
5. Select the `WormageddonTV` target → **Signing & Capabilities** → pick your **Team** (a free Apple ID works for 7-day installs) and change the **Bundle Identifier** if needed (e.g. `com.mrnugget.wurmageddon.tv`).
6. Select your Apple TV as the run destination and press **⌘R**.
