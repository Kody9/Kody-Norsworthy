import UIKit

extension UIImage {
    /// Bakes `imageOrientation` into the actual pixel data (returns an
    /// equivalent image tagged `.up`), so rect-based cropping doesn't have
    /// to separately account for EXIF rotation.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Crops to the region that maps onto `fractionalRect` (0...1, origin
    /// top-left) of a preview of `previewSize` shown with `.resizeAspectFill`
    /// — i.e. "the part of this photo that was actually visible behind the
    /// framing box on screen." Falls back to the original image if the
    /// math doesn't work out (e.g. preview size never got recorded).
    func croppedToPreviewRegion(previewSize: CGSize, fractionalRect: CGRect) -> UIImage {
        guard previewSize.width > 0, previewSize.height > 0 else { return self }
        let normalized = normalizedOrientation()
        guard let cgImage = normalized.cgImage, normalized.size.width > 0, normalized.size.height > 0 else { return self }

        let imageSize = normalized.size
        // .resizeAspectFill scales the image up until it fully covers the
        // preview, using the larger of the two scale factors, then crops
        // whatever exceeds the preview bounds — the same math in reverse.
        let scale = max(previewSize.width / imageSize.width, previewSize.height / imageSize.height)
        let visibleSize = CGSize(width: previewSize.width / scale, height: previewSize.height / scale)
        let visibleOrigin = CGPoint(x: (imageSize.width - visibleSize.width) / 2, y: (imageSize.height - visibleSize.height) / 2)

        let cropRectInPoints = CGRect(
            x: visibleOrigin.x + fractionalRect.minX * visibleSize.width,
            y: visibleOrigin.y + fractionalRect.minY * visibleSize.height,
            width: fractionalRect.width * visibleSize.width,
            height: fractionalRect.height * visibleSize.height
        )

        // CGImage.cropping(to:) works in pixels; `.size` is in points.
        let pixelScale = CGFloat(cgImage.width) / imageSize.width
        let cropRectInPixels = CGRect(
            x: cropRectInPoints.minX * pixelScale,
            y: cropRectInPoints.minY * pixelScale,
            width: cropRectInPoints.width * pixelScale,
            height: cropRectInPoints.height * pixelScale
        ).integral.intersection(CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))

        guard !cropRectInPixels.isEmpty, let cropped = cgImage.cropping(to: cropRectInPixels) else { return normalized }
        return UIImage(cgImage: cropped, scale: normalized.scale, orientation: .up)
    }
}
