import SwiftUI

/// Full-bleed accent confirmation. Auto-dismisses back to the camera after
/// 1500ms (handled by the caller) — this is the whole post-save feedback,
/// no toast, no navigation.
struct SavedConfirmationView: View {
    let plateText: String

    var body: some View {
        VStack(alignment: .leading, spacing: PLSpacing.md) {
            Spacer()
            Text("SAVED ON THIS DEVICE")
                .plType(PLTypeStyle(.heavy, 11, trackingEm: 0.14))
                .foregroundStyle(.white.opacity(0.85))
            Text(plateText)
                .plType(.plateDisplayLarge)
                .foregroundStyle(.white)
            Text("Returning to camera")
                .plType(PLTypeStyle(.semibold, 13))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
        }
        .padding(PLSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(PLColor.accent)
    }
}
