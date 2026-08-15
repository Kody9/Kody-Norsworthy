import SwiftUI

/// Covers the whole app until Face ID/Touch ID/passcode succeeds. Deliberately
/// plain — the eye mark and an UNLOCK button — since its only job is to sit in
/// front of everything else until `AppLockService.isUnlocked` flips true.
struct LockScreenView: View {
    let lastError: String?
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: PLSpacing.xl) {
            Spacer()

            Text("WATCHTOWER")
                .plType(PLTypeStyle(.heavy, 16, trackingEm: 0.14))
                .foregroundStyle(PLColor.inkTertiary)

            Text("LOCKED")
                .plType(.screenTitle)
                .foregroundStyle(PLColor.ink)

            if let lastError {
                Text(lastError)
                    .plType(.body)
                    .foregroundStyle(PLColor.accentOnDark)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, PLSpacing.xxl)
            }

            Spacer()

            PLPrimaryButton("UNLOCK", action: onUnlock)
                .padding(.horizontal, PLSpacing.gutter)
                .padding(.bottom, PLSpacing.gutter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PLColor.ground.ignoresSafeArea())
        .onAppear(perform: onUnlock)
    }
}
