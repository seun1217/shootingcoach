import SwiftUI

@main
struct ShootingCoachWatchApp: App {
    @StateObject private var connector = PhoneConnector()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(connector)
        }
    }
}
