import SwiftUI

struct PauseOverlayView: View {
    @State private var isMuted = SoundEngine.shared.isMuted
    let onResume: () -> Void
    let onRestart: () -> Void
    let onQuitToMenu: () -> Void

    var body: some View {
        ZStack {
            Color(art: Art.inkDeep).opacity(0.82).ignoresSafeArea()

            HStack(spacing: 64) {
                VStack(alignment: .leading, spacing: 24) {
                    Text("PAUSE")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundStyle(Color(art: Art.cream))

                    Button("Weiterspielen", action: onResume)
                        .buttonStyle(.borderedProminent)
                        .tint(Color(art: Art.lagoon))

                    Button("Neue Insel (Neustart)", action: onRestart)
                        .buttonStyle(.borderedProminent)
                        .tint(Color(art: Art.inkSoft))

                    Button(isMuted ? "Geräusche: Aus" : "Geräusche: An") {
                        isMuted.toggle()
                        SoundEngine.shared.isMuted = isMuted
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(art: Art.inkSoft))

                    Button("Zurück zum Start", action: onQuitToMenu)
                        .buttonStyle(.borderedProminent)
                        .tint(Color(art: Art.coral))
                }
                .frame(width: 440, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    Text("STEUERUNG")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(Color(art: Art.sun))

                    Group {
                        Text("Apple TV Siri Remote (nur fest drücken)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(art: Art.cream))
                        Text("• Links / Rechts drücken: Wurm laufen lassen\n• Hoch / Runter drücken: Zielen\n• Auswahl halten & loslassen: Schießen (Schaf: nochmal drücken = Knall!)\n• 2× Hoch / 2× Runter drücken: Sprung / Rückwärtssalto\n• Play/Pause: Waffenkammer (10 Waffen) öffnen\n• Menü / Zurück: Pause")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(art: Art.cream).opacity(0.88))
                            .lineSpacing(6)
                    }

                    Divider().background(Color(art: Art.cream).opacity(0.2))

                    Group {
                        Text("Game-Controller (PlayStation / Xbox / MFi)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(art: Art.cream))
                        Text("• Linker Stick / Steuerkreuz: Laufen & Zielen\n• Rechter Stick: Direkt in jede Richtung zielen\n• R2 oder X/Quadrat halten: Schießen\n• A/Kreuz: Sprung  ·  B/Kreis: Rückwärtssalto\n• L1 / R1: Waffe wechseln  ·  Y/Dreieck: Waffen-Leiste")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(art: Art.cream).opacity(0.88))
                            .lineSpacing(6)
                    }
                }
                .padding(36)
                .frame(width: 660, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(art: Art.ink).opacity(0.95))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Color(art: Art.cream).opacity(0.2), lineWidth: 2)
                        )
                )
            }
            .padding(80)
        }
        .onExitCommand(perform: onResume)
    }
}
