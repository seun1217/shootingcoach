import SwiftUI

@main
struct ShootingCoachApp: App {
    @StateObject private var viewModel = SessionViewModel()

    var body: some Scene {
        WindowGroup {
            CoachSessionView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
