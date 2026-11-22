import SwiftUI

struct SetupMenuView: View {
    @Binding var config: MatchConfig
    let onStart: () -> Void

    private var themeColors: [Color] {
        switch config.mapTheme {
        case .alpineSunset:
            return [
                Color(red: 0.11, green: 0.13, blue: 0.32),
                Color(red: 0.42, green: 0.22, blue: 0.40),
                Color(red: 0.78, green: 0.39, blue: 0.30)
            ]
        case .emeraldIsles:
            return [
                Color(red: 0.08, green: 0.32, blue: 0.64),
                Color(red: 0.16, green: 0.50, blue: 0.72),
                Color(red: 0.22, green: 0.62, blue: 0.68)
            ]
        case .volcanicDusk:
            return [
                Color(red: 0.07, green: 0.08, blue: 0.22),
                Color(red: 0.24, green: 0.13, blue: 0.38),
                Color(red: 0.58, green: 0.25, blue: 0.40)
            ]
        }
    }

    var body: some View {
        ZStack {
            // Live scenic sky reacting to chosen theme
            LinearGradient(
                colors: themeColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.45), value: config.mapTheme)

            // Decorative glowing sun/moon + distant island horizon
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.93, blue: 0.75).opacity(0.14))
                        .frame(width: 420, height: 420)
                        .position(x: geo.size.width * 0.84, y: geo.size.height * 0.18)

                    Circle()
                        .fill(Color(red: 1.0, green: 0.95, blue: 0.82).opacity(0.28))
                        .frame(width: 210, height: 210)
                        .position(x: geo.size.width * 0.84, y: geo.size.height * 0.18)

                    // Subtle rolling island silhouettes along bottom edge
                    Ellipse()
                        .fill(Color.black.opacity(0.20))
                        .frame(width: 900, height: 300)
                        .position(x: geo.size.width * 0.22, y: geo.size.height * 1.02)

                    Ellipse()
                        .fill(Color.black.opacity(0.24))
                        .frame(width: 1050, height: 340)
                        .position(x: geo.size.width * 0.78, y: geo.size.height * 1.04)
                }
            }
            .ignoresSafeArea()

            HStack(alignment: .center, spacing: 60) {
                // Left column: Title + Match Configuration
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DAS GROSSE INSEL-SPEKTAKEL")
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .tracking(3.2)
                            .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.42))

                        Text("WURMAGEDDON")
                            .font(.system(size: 76, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, Color(red: 1.0, green: 0.90, blue: 0.70)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .black.opacity(0.45), radius: 16, y: 6)

                        Text("Rundenbasierte Wurm-Duelle für 2–3 Spieler auf Apple TV.")
                            .font(.system(size: 25, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
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

                        optionRow(title: "INSEL-WELT") {
                            ForEach(MapStyle.allCases) { style in
                                selectPill(label: style.rawValue, selected: config.mapStyle == style) {
                                    config.mapStyle = style
                                }
                            }
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
                        .foregroundStyle(.white)
                        .padding(.horizontal, 46)
                        .padding(.vertical, 20)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.95, green: 0.34, blue: 0.26))
                    .padding(.top, 8)
                }
                .frame(maxWidth: 960, alignment: .leading)

                // Right column: Teams & Controls summary card
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("TEAMS AM START")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .tracking(2.4)
                            .foregroundStyle(Color(red: 1.0, green: 0.86, blue: 0.48))

                        ForEach(0..<config.playerCount, id: \.self) { idx in
                            let team = TeamDescriptor.all[idx]
                            HStack(spacing: 16) {
                                teamBadgeIcon(for: team)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Spieler \(idx + 1) · \(team.name)")
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text(team.wormNames.prefix(config.wormsPerTeam).joined(separator: " · "))
                                        .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.76))
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }

                    Divider().background(.white.opacity(0.22))

                    VStack(alignment: .leading, spacing: 11) {
                        Text("SIRI REMOTE & CONTROLLER")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .tracking(2.4)
                            .foregroundStyle(Color(red: 1.0, green: 0.86, blue: 0.48))

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
                        .fill(Color(red: 0.06, green: 0.08, blue: 0.15).opacity(0.62))
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .strokeBorder(.white.opacity(0.22), lineWidth: 2)
                        )
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
                .frame(width: 42, height: 42)
                .shadow(color: Color(team.color).opacity(0.45), radius: 8)
            switch team.accessory {
            case .ladybugDots:
                HStack(spacing: 4) {
                    Circle().fill(.black.opacity(0.85)).frame(width: 6, height: 6)
                    VStack(spacing: 5) {
                        Circle().fill(.black.opacity(0.85)).frame(width: 6, height: 6)
                        Circle().fill(.black.opacity(0.85)).frame(width: 6, height: 6)
                    }
                    Circle().fill(.black.opacity(0.85)).frame(width: 6, height: 6)
                }
            case .wizardStar:
                Image(systemName: "star.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.88, blue: 0.30))
            case .kittyEars:
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func optionRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(.white.opacity(0.72))
            HStack(spacing: 14) {
                content()
            }
        }
    }

    private func selectPill(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        SelectableTVPill(label: label, selected: selected, action: action)
    }

    private func controlLine(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.34))
                .frame(width: 26)
            Text(text)
                .font(.system(size: 19.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}

private struct SelectableTVPill: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 21, weight: (selected || isFocused) ? .heavy : .semibold, design: .rounded))
                .foregroundStyle(isFocused ? Color(red: 0.08, green: 0.10, blue: 0.18) : .white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
        }
        .focused($isFocused)
        .buttonStyle(.borderedProminent)
        .tint(selected ? Color(red: 0.16, green: 0.56, blue: 0.98) : Color(red: 0.18, green: 0.20, blue: 0.32).opacity(0.90))
    }
}
