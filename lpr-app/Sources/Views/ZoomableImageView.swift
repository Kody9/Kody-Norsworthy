import Combine
import SwiftUI
import UIKit

/// Shared across every screen showing one capture's photo (Read screen, its
/// correction editor, "no plate found," manual entry) so that once you've
/// pinch-zoomed in to make out a hard-to-read plate, that same zoomed-in
/// crop shows up everywhere else the photo appears for this capture —
/// including the small preview next to the keyboard, which the full-screen
/// viewer can't do since it covers the keyboard entirely. Reset by the
/// caller whenever a genuinely new photo starts (a new capture, or the next
/// queued auto-scan detection) — not on every navigation, since e.g. "no
/// plate found" -> "type it" reuses the same photo the zoom was set on.
final class PhotoZoomState: ObservableObject {
    /// The last-viewed region of the photo, as a fraction (0...1) of the
    /// image's own width/height. Nil until zoomed in past the default fit.
    @Published var normalizedVisibleRect: CGRect?

    func reset() {
        normalizedVisibleRect = nil
    }
}

extension UIImage {
    /// Crops to `rect`, given as a fraction (0...1) of this image's own
    /// point-space `size`. Renders through `draw(at:)` rather than cropping
    /// the raw `CGImage` so `imageOrientation` is respected automatically.
    func cropped(toNormalizedRect rect: CGRect) -> UIImage? {
        let cropRect = CGRect(
            x: rect.minX * size.width,
            y: rect.minY * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
        guard cropRect.width > 1, cropRect.height > 1 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: cropRect.size)
        return renderer.image { _ in
            draw(at: CGPoint(x: -cropRect.minX, y: -cropRect.minY))
        }
    }
}

/// Full-screen pinch-to-zoom viewer for an already-captured photo. Exists for
/// the case where a frame is clear but was shot too wide for OCR to resolve
/// the plate — zooming in visually lets the user read it themselves and type
/// it in manually.
struct PhotoZoomView: View {
    let image: UIImage
    let zoomState: PhotoZoomState
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onDone) {
                    Text("DONE")
                        .plType(PLTypeStyle(.bold, 13, trackingEm: 0.06))
                        .foregroundStyle(PLColor.ink)
                }
                .buttonStyle(.plain)
            }
            .padding(PLSpacing.gutter)

            ZoomableImageView(image: image, zoomState: zoomState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("PINCH TO ZOOM · DOUBLE-TAP TO RESET")
                .plType(PLTypeStyle(.bold, 11, trackingEm: 0.06))
                .foregroundStyle(PLColor.inkTertiary)
                .padding(PLSpacing.gutter)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

/// `UIViewRepresentable` wrapper over a frame-based `UIScrollView` zoom —
/// the classic, well-proven pattern (see Apple's old PhotoScroller sample),
/// more reliable here than an AutoLayout-constraint-based approach given
/// there's no way to test this on real hardware ahead of time.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let zoomState: PhotoZoomState

    func makeUIView(context: Context) -> ZoomingScrollView {
        let view = ZoomingScrollView()
        view.zoomState = zoomState
        view.configure(image: image)
        return view
    }

    func updateUIView(_ uiView: ZoomingScrollView, context: Context) {
        uiView.zoomState = zoomState
        uiView.configure(image: image)
    }
}

final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var currentImage: UIImage?
    private var hasRestoredZoomState = false
    var zoomState: PhotoZoomState?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        delegate = self
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = .black

        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    func configure(image: UIImage) {
        guard image !== currentImage else { return }
        currentImage = image
        hasRestoredZoomState = false
        imageView.image = image
        // Native image size, not a bounds-fitted size -- UIScrollView's
        // zoom mechanism scales this view via minimumZoomScale/zoomScale,
        // it isn't something layoutSubviews should ever recompute.
        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        setNeedsLayout()
    }

    /// Only recomputes the zoom-scale range and re-centers -- must NOT touch
    /// imageView's frame size. layoutSubviews fires continuously during an
    /// active pinch gesture (UIScrollView drives the zoom by transforming
    /// the zoomed view), so resetting the frame here on every pass would
    /// snap the image straight back to its un-zoomed size each time,
    /// which is exactly what made pinch-to-zoom look like it did nothing.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard
            let image = currentImage,
            image.size.width > 0, image.size.height > 0,
            bounds.width > 0, bounds.height > 0
        else { return }

        let widthScale = bounds.width / image.size.width
        let heightScale = bounds.height / image.size.height
        let minScale = min(widthScale, heightScale)

        if minimumZoomScale != minScale {
            let wasAtMinimum = zoomScale <= minimumZoomScale || minimumZoomScale == 0
            minimumZoomScale = minScale
            maximumZoomScale = minScale * 8
            if wasAtMinimum {
                zoomScale = minScale
            }
        }

        if !hasRestoredZoomState {
            hasRestoredZoomState = true
            restoreZoomState(image: image)
        }

        centerImage()
    }

    /// Jumps straight to the last-viewed crop for this capture, if any,
    /// instead of always reopening at the default fit-to-screen view. Uses
    /// the same `zoom(to:animated:)` API the double-tap gesture already
    /// relies on (it takes a rect in the un-scaled image-view coordinate
    /// space, which is exactly what `normalizedVisibleRect` maps to at
    /// scale 1) rather than computing zoomScale/contentOffset by hand.
    private func restoreZoomState(image: UIImage) {
        guard let rect = zoomState?.normalizedVisibleRect, rect.width > 0, rect.height > 0 else { return }
        let targetRect = CGRect(
            x: rect.minX * image.size.width,
            y: rect.minY * image.size.height,
            width: rect.width * image.size.width,
            height: rect.height * image.size.height
        )
        zoom(to: targetRect, animated: false)
    }

    private func centerImage() {
        let boundsSize = bounds.size
        var frame = imageView.frame
        frame.origin.x = frame.width < boundsSize.width ? (boundsSize.width - frame.width) / 2 : 0
        frame.origin.y = frame.height < boundsSize.height ? (boundsSize.height - frame.height) / 2 : 0
        imageView.frame = frame
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        persistVisibleRect()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        persistVisibleRect()
    }

    /// Records the currently-visible region back into the shared zoom
    /// state, in real time, so it's captured whenever the viewer closes --
    /// there's no reliable single "the user is done" callback to hook
    /// instead. Cleared back to nil once zoomed back out to the default
    /// fit, so other previews of this photo go back to showing the whole
    /// thing rather than a stale crop.
    private func persistVisibleRect() {
        guard let image = currentImage, image.size.width > 0, image.size.height > 0 else { return }
        guard zoomScale > minimumZoomScale * 1.01 else {
            zoomState?.normalizedVisibleRect = nil
            return
        }
        let visibleRect = CGRect(
            x: (contentOffset.x / zoomScale) / image.size.width,
            y: (contentOffset.y / zoomScale) / image.size.height,
            width: (bounds.width / zoomScale) / image.size.width,
            height: (bounds.height / zoomScale) / image.size.height
        )
        zoomState?.normalizedVisibleRect = visibleRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let targetScale = min(maximumZoomScale, 3.0)
            let width = bounds.width / targetScale
            let height = bounds.height / targetScale
            let rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
            zoom(to: rect, animated: true)
        }
    }
}
