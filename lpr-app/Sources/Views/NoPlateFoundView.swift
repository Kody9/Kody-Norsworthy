import SwiftUI
import UIKit

/// Edge state: OCR ran but found nothing plausible. Nothing was saved —
/// the photo and GPS are still attached either way once the user reshoots
/// or types the plate.
struct NoPlateFoundView: View {
    let image: UIImage?
    let onReshoot: () -> Void
    let onTypeIt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let image {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .grayscale(1.0)
                } else {
                    PLColor.surface
                }
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottom) {
                Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
            }

            VStack(alignment: .leading, spacing: PLSpacing.md) {
                Text("No plate\nfound")
                    .plType(.screenTitle)
                    .foregroundStyle(PLColor.ink)
                Text("The frame was too blurred to read. Nothing was saved. Reshoot, or type the plate — the photo and GPS are still attached either way.")
                    .plType(.body)
                    .foregroundStyle(PLColor.inkSecondary)
            }
            .padding(PLSpacing.gutter)

            Spacer()

            VStack(spacing: 2) {
                PLBlockButton("RESHOOT", filled: true, action: onReshoot)
                PLBlockButton("TYPE THE PLATE", filled: false, action: onTypeIt)
            }
            .padding(PLSpacing.gutter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PLColor.ground)
    }
}
