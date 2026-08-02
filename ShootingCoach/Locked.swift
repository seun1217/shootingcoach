import Foundation

/// Minimal lock-protected box for values that cross the camera/vision queues
/// and the main thread (rim rect, rotation angle, busy flags).
final class Locked<Value>: @unchecked Sendable {
    private var stored: Value
    private let lock = NSLock()

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

extension Locked where Value == Bool {
    /// Atomically flips false -> true. Returns false when already true.
    func trySetTrue() -> Bool {
        lock.withLock {
            if stored { return false }
            stored = true
            return true
        }
    }
}
