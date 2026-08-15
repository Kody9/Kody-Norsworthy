import MapKit
import UIKit

/// Renders History's map view (region + pins) to a shareable PNG. Uses
/// `MKMapSnapshotter` rather than snapshotting the live `Map` view directly —
/// `Map` streams map tiles in asynchronously, so an `ImageRenderer` grab of
/// it can catch tiles mid-load; the snapshotter is Apple's API specifically
/// for producing a complete, already-rendered static map image.
enum MapExporter {
    struct Pin {
        let coordinate: CLLocationCoordinate2D
    }

    /// Calls `completion` on the main queue (matching
    /// `MKMapSnapshotter.start`'s own default), with `nil` if the snapshot
    /// or file write failed.
    static func exportSnapshot(region: MKCoordinateRegion, pins: [Pin], completion: @escaping (URL?) -> Void) {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 1000, height: 1000)
        options.scale = UIScreen.main.scale
        options.mapType = .standard

        MKMapSnapshotter(options: options).start { snapshot, _ in
            guard let snapshot else {
                completion(nil)
                return
            }

            let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
            let finalImage = renderer.image { context in
                snapshot.image.draw(at: .zero)
                for pin in pins {
                    drawPin(at: snapshot.point(for: pin.coordinate), in: context.cgContext)
                }
            }

            guard let data = finalImage.pngData() else {
                completion(nil)
                return
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName())
            do {
                try data.write(to: url)
                completion(url)
            } catch {
                completion(nil)
            }
        }
    }

    private static func drawPin(at point: CGPoint, in context: CGContext) {
        let radius: CGFloat = 9
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.setFillColor(UIColor(red: 0xFF / 255, green: 0x56 / 255, blue: 0x3C / 255, alpha: 1).cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2.5)
        context.strokeEllipse(in: rect)
    }

    private static func fileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy h.mm a"
        let raw = "Watchtower Map - \(formatter.string(from: .now))"
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return raw.components(separatedBy: invalid).joined(separator: "-") + ".png"
    }
}
