import SwiftUI

struct SetupMenuView: View {
    @Binding var config: MatchConfig
    let onStart: () -> Void

    /// Mood wash laid over the painted hero so the menu previews the chosen sky.
    private var moodWash: Color {
        switch config.mapTheme {
        case .alpineSunset: return Color(red: 0.36, green: 0.18, blue: 0.30)
        case .emeraldIsles: return Color(red: 0.08, green: 0.38, blue: 0.56)
        case .volcanicDusk: return Color(red: 0.10, green: 0.08, blue: 0.28)
        }
    }

    var body: some View {
        ZStack {
            // Painted island hero (same Painter style as every in-game asset)
            Image("menu_hero")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            Rectangle()
                .fill(moodWash)
                .blendMode(.multiply)
                .opacity(config.mapTheme == .emeraldIsles ? 0.35 : 0.55)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.45), value: config.mapTheme)

            // Darken the left side so the cream title and options read clearly
            LinearGradient(
                colors: [Color(art: Art.inkDeep).opacity(0.78), Color(art: Art.inkDeep).opacity(0.35), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()

            HStack(alignment: .center, spacing: 60) {
                // Left column: Title + Match Configuration
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DAS GROSSE INSEL-SPEKTAKEL")
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .tracking(3.2)
                            .foregroundStyle(Color(art: Art.sun))

                        Text("WURMAGEDDON")
                            .font(.system(size: 82, weight: .black, design: .rounded))
                            .foregroundStyle(Color(art: Art.cream))
                            // Plum ink outline + offset shadow, like the painted assets
                            .shadow(color: Color(art: Art.ink), radius: 0, x: 3, y: 3)
                            .shadow(color: Color(art: Art.ink), radius: 0, x: -3, y: 3)
                            .shadow(color: Color(art: Art.ink), radius: 0, x: 3, y: -3)
                            .shadow(color: Color(art: Art.ink), radius: 0, x: -3, y: -3)
                            .shadow(color: Color(art: Art.ink).opacity(0.7), radius: 0, x: 0, y: 9)

                        Text("Rundenbasierte Wurm-Duelle für 2–3 Spieler auf Apple TV.")
                            .font(.system(size: 25, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(art: Art.cream).opacity(0.92))
                            .shadow(color: Color(art: Art.ink), radius: 4)
                    }

                    // Match Options
                    VStack(alignment: .leading, spacing: 20) {
                        optionRow(title: "SPIELER") {
                            ForEach([2, 3], id: \.self) { count in
                                selectPill(label: "\(count) Spieler", selected: config.playerCount == count) {
                                    config.playerCount = count
                                }
                            }
                        }

                        optionRow(title: "WÜRMER PRO TEAM") {
                            ForEach([2, 3, 4], id: \.self) { count in
                                selectPill(label: "\(count) Würmer", selected: config.wormsPerTeam == count) {
                                    config.wormsPerTeam = count
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            optionTitle("INSEL-WELT")
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), alignment: .leading, spacing: 14) {
                                ForEach(MapStyle.allCases) { style in
                                    SelectableTVPill(label: style.rawValue, selected: config.mapStyle == style, fillsWidth: true) {
                                        config.mapStyle = style
                                    }
                                }
                            }
                            Text(config.mapStyle.subtitle)
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(art: Art.cream).opacity(0.82))
                                .lineLimit(1)
                        }

                        optionRow(title: "STIMMUNG") {
                            ForEach(MapTheme.allCases) { theme in
                                selectPill(label: theme.rawValue, selected: config.mapTheme == theme) {
                                    config.mapTheme = theme
                                }
                            }
                        }
                    }

                    Button(action: onStart) {
                        HStack(spacing: 16) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 28, weight: .bold))
                            Text("LOS GEHT'S!")
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .tracking(1.5)
                        }
                            .foregroundStyle(Color(art: Art.cream))
                        .padding(.horizontal, 46)
                        .padding(.vertical, 20)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(art: Art.coral))
                    .padding(.top, 8)
                }
                .frame(maxWidth: 960, alignment: .leading)

                // Right column: Teams & Controls summary card
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("TEAMS AM START")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .tracking(2.4)
                            .foregroundStyle(Color(art: Art.sun))

                        ForEach(0..<config.playerCount, id: \.self) { idx in
                            let team = TeamDescriptor.all[idx]
                            HStack(spacing: 16) {
                                teamBadgeIcon(for: team)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Spieler \(idx + 1) · \(team.name)")
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color(art: Art.cream))
                                    Text(team.wormNames.prefix(config.wormsPerTeam).joined(separator: " · "))
                                        .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color(art: Art.cream).opacity(0.76))
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }

                    Divider().background(Color(art: Art.cream).opacity(0.22))

                    VStack(alignment: .leading, spacing: 11) {
                        Text("SIRI REMOTE & CONTROLLER")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .tracking(2.4)
                            .foregroundStyle(Color(art: Art.sun))

                        controlLine(icon: "arrow.left.and.right", text: "Links / Rechts drücken: Wurm laufen")
                        controlLine(icon: "arrow.up.and.down", text: "Hoch / Runter drücken: Zielen")
                        controlLine(icon: "flame.fill", text: "Auswahl halten & loslassen: Schießen")
                        controlLine(icon: "arrow.up.forward", text: "2× Hoch drücken (oder A): Sprung")
                        controlLine(icon: "tray.full.fill", text: "Play/Pause (oder Y): 10 Waffen wählen")
                        controlLine(icon: "wind", text: "Schrotflinte hat 2 Schüsse · Wind beachten!")
                    }
                }
                .padding(36)
                .frame(width: 600, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color(art: Art.inkDeep).opacity(0.86))
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .strokeBorder(Color(art: Art.cream).opacity(0.22), lineWidth: 2)
                        )
                        .shadow(color: Color(art: Art.ink).opacity(0.6), radius: 0, y: 8)
                )
            }
            .padding(.horizontal, 86)
            .padding(.vertical, 58)
        }
    }

    private func teamBadgeIcon(for team: TeamDescriptor) -> some View {
        ZStack {
            Circle()
                .fill(Color(team.color))
                .frame(width: 46, height: 46)
                .overlay(Circle().strokeBorder(Color(art: Art.ink), lineWidth: 3))
            switch team.accessory {
            case .ladybugDots:
                HStack(spacing: 4) {
                    Circle().fill(Color(art: Art.ink)).frame(width: 6, height: 6)
                    VStack(spacing: 5) {
                        Circle().fill(Color(art: Art.ink)).frame(width: 6, height: 6)
                        Circle().fill(Color(art: Art.ink)).frame(width: 6, height: 6)
                    }
                    Circle().fill(Color(art: Art.ink)).frame(width: 6, height: 6)
                }
            case .wizardStar:
                Image(systemName: "star.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color(art: Art.sun))
            case .kittyEars:
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(art: Art.cream))
            }
        }
    }

    private func optionRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            optionTitle(title)
            HStack(spacing: 14) {
                content()
            }
        }
    }

    private func optionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .tracking(2.2)
            .foregroundStyle(Color(art: Art.cream).opacity(0.80))
    }

    private func selectPill(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        SelectableTVPill(label: label, selected: selected, action: action)
    }

    private func controlLine(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color(art: Art.sun))
                .frame(width: 26)
            Text(text)
                .font(.system(size: 19.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color(art: Art.cream).opacity(0.92))
        }
    }
}

private struct SelectableTVPill: View {
    let label: String
    let selected: Bool
    var fillsWidth: Bool = false
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 21, weight: (selected || isFocused) ? .heavy : .semibold, design: .rounded))
                .foregroundStyle(isFocused ? Color(art: Art.ink) : Color(art: Art.cream))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, fillsWidth ? 12 : 22)
                .padding(.vertical, 12)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .focused($isFocused)
        .buttonStyle(.borderedProminent)
        .tint(selected ? Color(art: Art.lagoon) : Color(art: Art.inkSoft).opacity(0.92))
    }
}
