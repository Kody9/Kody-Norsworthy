import SwiftUI
import UIKit

/// Renders EntryShareCardView to an image, then wraps that single image as
/// a one-page PDF — simpler and more reliable than hand-building PDF text
/// layout, while still producing a real, printable document.
enum EntryShareExporter {
    @MainActor
    static func makePDF(for entry: PlateEntry) -> URL? {
        let renderer = ImageRenderer(content: EntryShareCardView(entry: entry))
        renderer.scale = 3 // high-res so text/photo stay crisp when zoomed or printed

        guard let uiImage = renderer.uiImage else { return nil }

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: uiImage.size))
        let data = pdfRenderer.pdfData { context in
            context.beginPage()
            uiImage.draw(in: CGRect(origin: .zero, size: uiImage.size))
        }

        let safePlate = entry.plateNumber.trimmingCharacters(in: .whitespaces)
        let fileName = (safePlate.isEmpty ? "Entry" : safePlate) + " - SAL Record.pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
