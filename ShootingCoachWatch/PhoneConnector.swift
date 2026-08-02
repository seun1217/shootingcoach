import Combine
import Foundation
import WatchConnectivity
import WatchKit

/// Watch-side WatchConnectivity: receives per-shot feedback from the phone,
/// plays the matching haptic, and publishes state for the UI.
final class PhoneConnector: NSObject, ObservableObject {
    @Published var lastFeedback: ShotFeedback?
    @Published var stats = SessionStats.empty
    @Published var sessionActive = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    fileprivate func route(_ payload: [String: Any]) {
        guard let kind = WatchChannel.kind(of: payload) else { return }
        DispatchQueue.main.async {
            switch kind {
            case .shot:
                guard let feedback = WatchChannel.decode(ShotFeedback.self, from: payload) else { return }
                self.lastFeedback = feedback
                self.stats = feedback.stats
                self.sessionActive = true
                WKInterfaceDevice.current().play(feedback.outcome == .made ? .success : .failure)

            case .stats:
                guard let stats = WatchChannel.decode(SessionStats.self, from: payload) else { return }
                self.stats = stats

            case .sessionState:
                guard let state = WatchChannel.decode(SessionStatePayload.self, from: payload) else { return }
                self.sessionActive = state.active
                if state.active {
                    // Fresh session: clear the previous run.
                    self.lastFeedback = nil
                    self.stats = .empty
                    WKInterfaceDevice.current().play(.start)
                } else {
                    WKInterfaceDevice.current().play(.stop)
                }
            }
        }
    }
}

extension PhoneConnector: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        route(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        route(userInfo)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        route(applicationContext)
    }
}
