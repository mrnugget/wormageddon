# Wurmageddon (Apple TV)

A native tvOS turn-based artillery game inspired by *Worms Armageddon*, built in Swift with SpriteKit and SwiftUI for 2–3 local players on Apple TV — localized in German with Miraculous, Harry Potter, Gabby's Dollhouse, and Bluey-inspired teams.

## Teams
- **Miraculous-Würmer**: Wurmbug, Cat Wurm, Tikki-Turbo, Plagg-Käse
- **Hogwarts-Knaller**: Harry Wurm, Hermine Bumm, Dumblewurm, Hedwig-Zack
- **Pfoten-Power**: Bluey-Bumm, Bingo-Blitz, Kuchi-Knall, Pandy-Pfote

## Features
- **2–3 Player Local Multiplayer**: Hotseat turn banners, 45s turn timer, team health bars, and victory summary.
- **Pixel-Level Destructible Terrain**: 4 procedural layouts (*Archipel*, *Gipfel*, *Schlucht*, *Festung*) plus 8 hand-painted Hedgewars maps (*Käse-Insel*, *Riesentorte*, *Pilzwald*, *Märchenburg*, *Piratenflagge*, *Hängematte*, *Igel-Liebe*, *Krakenmeer*) and 3 themes (*Goldener Abend*, *Smaragd-Inseln*, *Zauber-Nacht*) with charred craters, destructible wildflowers & trees, fall damage, supply crates, and Sudden Death rising water.
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

## Map Credits

The hand-painted battlefields are copied from [Hedgewars](https://github.com/hedgewars/hw) (`share/hedgewars/Data/Maps/*/map.png`), whose images are licensed under the GNU Free Documentation License 1.2. They were scaled to 1440×750 and their alpha masks cleaned (binary alpha, specks and thin hairs removed) for Wurmageddon's destructible terrain.

| Wurmageddon | Hedgewars map | Author |
|---|---|---|
| Käse-Insel | Cheese | CopherNeue |
| Riesentorte | Cake | Josh |
| Pilzwald | Mushrooms | John Dum |
| Märchenburg | Castle | Stanko Tadić |
| Piratenflagge | PirateFlag | Stanko Tadić |
| Hängematte | Hammock | John Dum |
| Igel-Liebe | Hedgelove | John Dum |
| Krakenmeer | Octorama | jessor (octopus art: iconicon.net, CC) |
