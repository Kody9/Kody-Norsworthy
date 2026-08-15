import UIKit

/// Thin wrapper over UIFeedbackGenerator so call sites read as intent
/// ("a plate was logged") rather than "medium impact, notification success."
enum Haptics {
    static func capture() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func logged() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func queued() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}
