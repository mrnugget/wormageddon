import SwiftUI

enum AppScreenState {
    case setup
    case playing
    case paused
    case victory(winnerTeamIndex: Int?, teams: [TeamState])
}

struct RootView: View {
    @State private var config = MatchConfig()
    @State private var screen: AppScreenState = .setup
    @State private var matchToken = UUID()
    @State private var cameraViewRequestToken = UUID()

    var body: some View {
        ZStack {
            switch screen {
            case .setup:
                SetupMenuView(config: $config) {
                    startNewMatch()
                }
            case .playing, .paused, .victory:
                GameContainerView(
                    config: config,
                    matchToken: matchToken,
                    cameraViewRequestToken: cameraViewRequestToken,
                    isPaused: isOverlayVisible,
                    onPauseRequested: {
                        if case .playing = screen {
                            screen = .paused
                        }
                    },
                    onMatchFinished: { winnerIdx, teams in
                        screen = .victory(winnerTeamIndex: winnerIdx, teams: teams)
                    }
                )
                .ignoresSafeArea()

                if case .paused = screen {
                    PauseOverlayView(
                        onResume: { screen = .playing },
                        onInspectMap: {
                            cameraViewRequestToken = UUID()
                            screen = .playing
                        },
                        onRestart: { startNewMatch() },
                        onQuitToMenu: { screen = .setup }
                    )
                } else if case .victory(let winnerIdx, let teams) = screen {
                    VictoryOverlayView(
                        winnerTeamIndex: winnerIdx,
                        teams: teams,
                        onRematch: { startNewMatch() },
                        onBackToMenu: { screen = .setup }
                    )
                }
            }
        }
    }

    private var isOverlayVisible: Bool {
        if case .playing = screen { return false }
        return true
    }

    private func startNewMatch() {
        config.seed = UInt64.random(in: 1...UInt64.max)
        matchToken = UUID()
        screen = .playing
    }
}
