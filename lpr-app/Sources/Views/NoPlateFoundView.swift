import SwiftUI
import UIKit

/// Edge state: OCR ran but found nothing plausible. Nothing was saved —
/// the photo and GPS are still attached either way once the user reshoots
/// or types the plate.
struct NoPlateFoundView: View {
    let image: UIImage?
    @ObservedObject var photoZoomState: PhotoZoomState
    let onReshoot: () -> Void
    let onTypeIt: () -> Void

    @State private var showZoomedPhoto = false

    /// Once zoomed in on this photo, keep showing that same crop here too.
    private var previewImage: UIImage? {
        guard let image else { return nil }
        guard let rect = photoZoomState.normalizedVisibleRect else { return image }
        return image.cropped(toNormalizedRect: rect) ?? image
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Scrollable — the photo + title + body alone can exceed a
            // landscape iPhone's available height, which would otherwise
            // clip the buttons below.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        if image != nil { showZoomedPhoto = true }
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            if let previewImage {
                                Color.black
                                Image(uiImage: previewImage)
                                    .resizable()
                                    .scaledToFill()
                                    .grayscale(1.0)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                Text("TAP TO ZOOM")
                                    .plType(PLTypeStyle(.bold, 10, trackingEm: 0.08))
                                    .foregroundStyle(PLColor.ink)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.black.opacity(0.6))
                                    .padding(10)
                            } else {
                                PLColor.surface
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(image == nil)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
                    }

                    VStack(alignment: .leading, spacing: PLSpacing.md) {
                        Text("No plate\nfound")
                            .plType(.screenTitle)
                            .foregroundStyle(PLColor.ink)
                        Text("The frame was too blurred to read. Nothing was saved. Zoom into the photo to read it yourself, reshoot, or type the plate — the photo and GPS are still attached either way.")
                            .plType(.body)
                            .foregroundStyle(PLColor.inkSecondary)
                    }
                    .padding(PLSpacing.gutter)
                }
            }

            VStack(spacing: 2) {
                PLBlockButton("RESHOOT", filled: true, action: onReshoot)
                PLBlockButton("TYPE THE PLATE", filled: false, action: onTypeIt)
            }
            .padding(PLSpacing.gutter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PLColor.ground)
        .fullScreenCover(isPresented: $showZoomedPhoto) {
            if let image {
                PhotoZoomView(image: image, zoomState: photoZoomState, onDone: { showZoomedPhoto = false })
            }
        }
    }
}
