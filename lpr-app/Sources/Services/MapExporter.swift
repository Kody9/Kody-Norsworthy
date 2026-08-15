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

    /// A cluster of nearby captures, mirroring HistoryListView's
    /// `HeatCell` -- `maxCount` (the busiest cluster in the whole set) is
    /// carried along so opacity can be computed per-cell without the
    /// exporter needing the full cluster list.
    struct HeatCell {
        let coordinate: CLLocationCoordinate2D
        let count: Int
        let maxCount: Int
    }

    enum Overlay {
        case pins([Pin])
        case heatmap([HeatCell])
    }

    /// Calls `completion` on the main queue (matching
    /// `MKMapSnapshotter.start`'s own default), with `nil` if the snapshot
    /// or file write failed.
    static func exportSnapshot(region: MKCoordinateRegion, overlay: Overlay, completion: @escaping (URL?) -> Void) {
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
                switch overlay {
                case .pins(let pins):
                    for pin in pins {
                        drawPin(at: snapshot.point(for: pin.coordinate), in: context.cgContext)
                    }
                case .heatmap(let cells):
                    for cell in cells {
                        drawHeatCell(cell, snapshot: snapshot, in: context.cgContext)
                    }
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

    /// Same radius/opacity formula as HistoryListView's on-screen
    /// `MapCircle` rendering, so the shared image matches what was on
    /// screen. `MKMapSnapshot.point(for:)` only gives a center point, not
    /// a scale factor, so the real-world radius (meters) is converted to
    /// on-image pixels by measuring the on-image distance to a coordinate
    /// offset by that many meters of longitude.
    private static func drawHeatCell(_ cell: HeatCell, snapshot: MKMapSnapshotter.Snapshot, in context: CGContext) {
        let radiusMeters = 90 * (1 + min(Double(cell.count), 12) * 0.35)
        let opacity = 0.16 + 0.5 * (Double(cell.count) / Double(max(cell.maxCount, 1)))

        let lonDelta = radiusMeters / (111_320 * cos(cell.coordinate.latitude * .pi / 180))
        let edgeCoordinate = CLLocationCoordinate2D(latitude: cell.coordinate.latitude, longitude: cell.coordinate.longitude + lonDelta)
        let centerPoint = snapshot.point(for: cell.coordinate)
        let edgePoint = snapshot.point(for: edgeCoordinate)
        let pixelRadius = abs(edgePoint.x - centerPoint.x)

        let rect = CGRect(x: centerPoint.x - pixelRadius, y: centerPoint.y - pixelRadius, width: pixelRadius * 2, height: pixelRadius * 2)
        context.setFillColor(UIColor(red: 0xFF / 255, green: 0x56 / 255, blue: 0x3C / 255, alpha: opacity).cgColor)
        context.fillEllipse(in: rect)
    }

    private static func fileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy h.mm a"
        let raw = "SAL Map - \(formatter.string(from: .now))"
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return raw.components(separatedBy: invalid).joined(separator: "-") + ".png"
    }
}
