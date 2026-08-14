import SwiftUI
import UIKit

/// Full-screen pinch-to-zoom viewer for an already-captured photo. Exists for
/// the case where a frame is clear but was shot too wide for OCR to resolve
/// the plate — zooming in visually lets the user read it themselves and type
/// it in manually.
struct PhotoZoomView: View {
    let image: UIImage
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

            ZoomableImageView(image: image)
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

    func makeUIView(context: Context) -> ZoomingScrollView {
        let view = ZoomingScrollView()
        view.configure(image: image)
        return view
    }

    func updateUIView(_ uiView: ZoomingScrollView, context: Context) {
        uiView.configure(image: image)
    }
}

final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var currentImage: UIImage?

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
        minimumZoomScale = 1.0
        maximumZoomScale = 8.0
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
        imageView.image = image
        zoomScale = 1.0
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = currentImage, image.size.width > 0, image.size.height > 0 else { return }

        let imageAspect = image.size.width / image.size.height
        let boundsAspect = bounds.width / bounds.height
        let fitSize: CGSize
        if imageAspect > boundsAspect {
            fitSize = CGSize(width: bounds.width, height: bounds.width / imageAspect)
        } else {
            fitSize = CGSize(width: bounds.height * imageAspect, height: bounds.height)
        }
        imageView.frame = CGRect(origin: .zero, size: fitSize)
        contentSize = fitSize
        centerImage()
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
