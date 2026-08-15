import Foundation
import LocalAuthentication

/// Face ID / Touch ID / passcode gate for the whole app. Nothing about this
/// touches the data itself — it's a UI-level lock, not encryption — but for
/// an app that logs where you were and what car you saw there, that's the
/// right amount of friction for a lost, shared, or borrowed phone.
@MainActor
final class AppLockService: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var lastError: String?

    /// Prompts Face ID/Touch ID, falling back to the device passcode if
    /// biometrics fail or aren't set up. If the device has no passcode at
    /// all, there's nothing to lock behind, so this unlocks immediately
    /// rather than stranding the user outside their own app.
    func authenticate() {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isUnlocked = true
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Watchtower") { [weak self] success, evaluationError in
            Task { @MainActor in
                self?.isUnlocked = success
                self?.lastError = success ? nil : evaluationError?.localizedDescription
            }
        }
    }

    func lock() {
        isUnlocked = false
    }
}
