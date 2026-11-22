import SwiftUI

struct GameContainerView: UIViewControllerRepresentable {
    let config: MatchConfig
    let matchToken: UUID
    let cameraViewRequestToken: UUID
    let isPaused: Bool
    let onPauseRequested: () -> Void
    let onMatchFinished: (Int?, [TeamState]) -> Void

    final class Coordinator: NSObject, GameSceneDelegate {
        var parent: GameContainerView
        var lastToken: UUID?
        var lastCameraToken: UUID?

        init(parent: GameContainerView) {
            self.parent = parent
        }

        func gameSceneDidRequestPause() {
            DispatchQueue.main.async {
                self.parent.onPauseRequested()
            }
        }

        func gameSceneDidFinishMatch(winnerTeamIndex: Int?, teams: [TeamState]) {
            DispatchQueue.main.async {
                self.parent.onMatchFinished(winnerTeamIndex, teams)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> GameViewController {
        let vc = GameViewController()
        vc.gameDelegate = context.coordinator
        context.coordinator.lastToken = matchToken
        context.coordinator.lastCameraToken = cameraViewRequestToken
        vc.startMatch(config: config)
        return vc
    }

    func updateUIViewController(_ uiViewController: GameViewController, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastToken != matchToken {
            context.coordinator.lastToken = matchToken
            uiViewController.startMatch(config: config)
        }
        if context.coordinator.lastCameraToken != cameraViewRequestToken {
            context.coordinator.lastCameraToken = cameraViewRequestToken
            uiViewController.enterCameraViewMode()
        }
        uiViewController.setGameplayPaused(isPaused)
    }
}
