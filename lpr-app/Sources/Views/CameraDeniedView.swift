import CoreLocation
import SwiftUI

/// Edge state replacing the old permission `.alert`. Camera access is a
/// hard requirement for the primary flow; location is optional (entries
/// still save without it).
struct CameraDeniedView: View {
    let locationStatus: CLAuthorizationStatus
    let onOpenSettings: () -> Void
    let onTypeInstead: () -> Void

    private var locationText: (label: String, color: Color) {
        switch locationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return ("WHILE IN USE", PLColor.inkTertiary)
        case .denied, .restricted:
            return ("DENIED", PLColor.accentOnDark)
        default:
            return ("NOT SET", PLColor.inkTertiary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Scrollable so the status rows never get pushed off-screen by
            // the buttons below on a short landscape screen.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: PLSpacing.sm) {
                        Text("PERMISSION REQUIRED")
                            .plType(.sectionLabel)
                            .foregroundStyle(PLColor.accentOnDark)
                        Text("Camera access\nis off")
                            .plType(.screenTitle)
                            .foregroundStyle(PLColor.ink)
                        Text("This app can't quick-capture plates without camera access. Location is optional — entries still save without it.")
                            .plType(.body)
                            .foregroundStyle(PLColor.inkSecondary)
                    }
                    .padding(PLSpacing.gutter)

                    VStack(spacing: 0) {
                        statusRow(label: "Camera", value: "DENIED", color: PLColor.accentOnDark)
                        statusRow(label: "Location", value: locationText.label, color: locationText.color)
                    }
                    .overlay(alignment: .top) {
                        Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
                    }
                }
            }

            VStack(spacing: 2) {
                PLBlockButton("OPEN IOS SETTINGS", filled: true, action: onOpenSettings)
                PLBlockButton("TYPE PLATES INSTEAD", filled: false, action: onTypeInstead)
            }
            .padding(PLSpacing.gutter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PLColor.ground)
    }

    private func statusRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .plType(.rowLabel)
                .foregroundStyle(PLColor.inkSecondary)
            Spacer()
            Text(value)
                .plType(PLTypeStyle(.bold, 14))
                .foregroundStyle(color)
        }
        .padding(.horizontal, PLSpacing.gutter)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
        }
    }
}
