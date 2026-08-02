import Combine
import Foundation
import WatchConnectivity

/// Phone-side WatchConnectivity: pushes per-shot feedback to the watch the
/// instant a shot resolves, with a queued fallback when the watch app is
/// not reachable in the foreground.
final class WatchBridge: NSObject, ObservableObject {
    @Published private(set) var isReachable = false
    @Published private(set) var isWatchAppInstalled = false

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func send(feedback: ShotFeedback) {
        guard let session, session.activationState == .activated else { return }
        guard let message = WatchChannel.message(.shot, feedback) else { return }

        if session.isReachable {
            // Live path: arrives in well under a second, watch plays haptics.
            session.sendMessage(message, replyHandler: nil) { [weak session] _ in
                session?.transferUserInfo(message)
            }
        } else if session.isWatchAppInstalled {
            // Queued path: delivered when the watch app next wakes.
            session.transferUserInfo(message)
        }

        // Always keep the latest stats around for cold launches of the watch app.
        if let context = WatchChannel.message(.stats, feedback.stats) {
            try? session.updateApplicationContext(context)
        }
    }

    func sendSessionState(active: Bool) {
        guard let session, session.activationState == .activated else { return }
        let payload = SessionStatePayload(active: active, timestamp: Date())
        guard let message = WatchChannel.message(.sessionState, payload) else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else if session.isWatchAppInstalled {
            session.transferUserInfo(message)
        }
    }

    private func publishState(from session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }
}

extension WatchBridge: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        publishState(from: session)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        publishState(from: session)
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        publishState(from: session)
    }
}
