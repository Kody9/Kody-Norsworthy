import CoreGraphics

/// Single source of truth for the framing box's size/position, shared
/// between the on-screen brackets (CaptureView) and the OCR crop (which
/// needs to know the same box in fractional terms to map it onto the
/// captured photo's very different pixel dimensions).
enum PlateFrameGeometry {
    /// The framing box's rect within a preview of `size`, in points.
    static func boxRect(in size: CGSize) -> CGRect {
        let shortSide = min(size.width, size.height)
        let width = max(min(size.width - 96, shortSide * 1.4), 0)
        let height = max(min(width * 0.5, size.height - 120), 0)
        return CGRect(
            x: size.width / 2 - width / 2,
            y: size.height / 2 - height / 2,
            width: width,
            height: height
        )
    }

    /// The box expressed as fractions (0...1) of the preview size, padded
    /// a bit for aim tolerance — used to crop the captured photo before
    /// OCR so text outside the marks (signs, other plates) isn't read.
    static func fractionalBoxRect(in size: CGSize, paddingFraction: CGFloat = 0.15) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let rect = boxRect(in: size)
        let padded = rect.insetBy(dx: -rect.width * paddingFraction, dy: -rect.height * paddingFraction)
        let clamped = padded.intersection(CGRect(origin: .zero, size: size))
        return CGRect(
            x: clamped.minX / size.width,
            y: clamped.minY / size.height,
            width: clamped.width / size.width,
            height: clamped.height / size.height
        )
    }
}
