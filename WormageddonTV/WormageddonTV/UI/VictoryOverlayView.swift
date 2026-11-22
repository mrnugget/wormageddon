import SwiftUI

struct VictoryOverlayView: View {
    let winnerTeamIndex: Int?
    let teams: [TeamState]
    let onRematch: () -> Void
    let onBackToMenu: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()

            VStack(spacing: 32) {
                if let winnerIdx = winnerTeamIndex, winnerIdx < teams.count {
                    let winner = teams[winnerIdx].descriptor
                    Text("GEWONNEN!")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .tracking(4.5)
                        .foregroundStyle(Color(red: 1.0, green: 0.86, blue: 0.30))

                    Text("SPIELER \(winner.index + 1) – \(winner.name.uppercased())")
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .foregroundStyle(Color(winner.color))
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)

                    Text("Glückwunsch an \(winner.wormNames.joined(separator: ", "))!")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                } else {
                    Text("UNENTSCHIEDEN!")
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Alle Würmer sind gleichzeitig abgetaucht – was für ein Finale!")
                        .font(.system(size: 26, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.86))
                }

                // Team Stats Row
                HStack(spacing: 28) {
                    ForEach(teams.indices, id: \.self) { idx in
                        let team = teams[idx]
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(team.descriptor.color))
                                    .frame(width: 16, height: 16)
                                Text("S\(idx + 1) \(team.descriptor.name)")
                                    .font(.system(size: 21, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            Text("Schaden: \(team.totalDamageDealt)")
                                .font(.system(size: 19, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.86))
                            Text("Treffer-K.O.s: \(team.kills)")
                                .font(.system(size: 19, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.86))
                        }
                        .padding(24)
                        .frame(minWidth: 300, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(idx == winnerTeamIndex ? 0.16 : 0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(
                                            idx == winnerTeamIndex ? Color(team.descriptor.color) : Color.white.opacity(0.16),
                                            lineWidth: idx == winnerTeamIndex ? 3 : 1.5
                                        )
                                )
                        )
                    }
                }

                HStack(spacing: 28) {
                    Button("Nochmal spielen! (Neue Insel)", action: onRematch)
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.95, green: 0.34, blue: 0.26))

                    Button("Teams & Insel ändern", action: onBackToMenu)
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.24, green: 0.26, blue: 0.36))
                }
                .padding(.top, 12)
            }
            .padding(64)
        }
    }
}
