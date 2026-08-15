import SwiftUI
import UIKit

/// Multi-page PDF version of the single-entry share card -- a whole
/// day (or filtered range/selection) as one printable report instead
/// of a bare CSV. Each page is rendered as its own image via
/// ImageRenderer, then drawn into its own PDF page -- the same
/// one-image-per-page trick EntryShareExporter uses for a single
/// entry, just repeated across however many pages the entry count
/// needs.
enum DayReportExporter {
    private static let rowsPerPage = 5

    @MainActor
    static func makePDF(entries: [PlateEntry], label: String) -> URL? {
        guard !entries.isEmpty else { return nil }
        let pages = stride(from: 0, to: entries.count, by: rowsPerPage).map {
            Array(entries[$0..<min($0 + rowsPerPage, entries.count)])
        }

        let pageSize = DayReportPageView.pageSize
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let data = pdfRenderer.pdfData { context in
            for (index, pageEntries) in pages.enumerated() {
                context.beginPage()
                let pageView = DayReportPageView(
                    reportLabel: label,
                    totalCount: entries.count,
                    pageEntries: pageEntries,
                    pageNumber: index + 1,
                    totalPages: pages.count
                )
                let renderer = ImageRenderer(content: pageView)
                renderer.scale = 3
                if let uiImage = renderer.uiImage {
                    uiImage.draw(in: CGRect(origin: .zero, size: pageSize))
                }
            }
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(label: label))
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func fileName(label: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy h.mm a"
        let stamp = formatter.string(from: .now)
        let raw = "SAL - \(label) Report - \(stamp)"
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return raw.components(separatedBy: invalid).joined(separator: "-") + ".pdf"
    }
}
