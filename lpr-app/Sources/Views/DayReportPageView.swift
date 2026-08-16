import SwiftUI
import UIKit

/// One printable page of a multi-entry PDF report -- same plain
/// white/black "field record" aesthetic as EntryShareCardView, but a
/// condensed row-per-entry layout so several captures fit on one page.
/// DayReportExporter renders one of these per page and stitches them
/// into a single PDF.
struct DayReportPageView: View {
    let reportLabel: String
    let totalCount: Int
    let pageEntries: [PlateEntry]
    let pageNumber: Int
    let totalPages: Int

    static let pageSize = CGSize(width: 900, height: 1166)
    private let rowHeight: CGFloat = 172

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.black).frame(height: 3)

            VStack(spacing: 0) {
                ForEach(pageEntries) { entry in
                    row(for: entry)
                }
            }

            Spacer(minLength: 0)
            footer
        }
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .top)
        .background(Color.white)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SAL — REPORT")
                    .font(.system(size: 14, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(.black)
                Text("\(reportLabel.uppercased()) · \(totalCount) ENTR\(totalCount == 1 ? "Y" : "IES")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Printed \(Date.now.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.55))
                if totalPages > 1 {
                    Text("PAGE \(pageNumber) OF \(totalPages)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
    }

    private func stateTimeLine(for entry: PlateEntry) -> String {
        let base = "\(entry.state.isEmpty ? "UNKNOWN" : entry.state.uppercased()) · \(entry.capturedAt.formatted(date: .abbreviated, time: .shortened))"
        guard !entry.loggedByName.isEmpty else { return base }
        return "\(base) · LOGGED BY \(entry.loggedByName.uppercased())"
    }

    private func row(for entry: PlateEntry) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Group {
                if let data = entry.photoData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black.opacity(0.06)
                }
            }
            .frame(width: 100, height: 100)
            .clipped()
            .overlay(Rectangle().stroke(Color.black.opacity(0.15), lineWidth: 1))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.plateNumber)
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(.black)
                    if !entry.tag.isEmpty {
                        Text(entry.tag == "Parking Complaint" ? "PARKING" : entry.tag.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(entry.tag == "BOLO" ? Color(red: 0xEC / 255, green: 0x30 / 255, blue: 0x13 / 255) : Color.black.opacity(0.5))
                    }
                }
                Text(stateTimeLine(for: entry))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.6))
                if !entry.driverName.isEmpty {
                    Text("DRIVER: \(entry.driverName)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.7))
                }
                if let latitude = entry.latitude, let longitude = entry.longitude {
                    Text(String(format: "%.5f, %.5f", latitude, longitude))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.5))
                }
                if !entry.notes.isEmpty {
                    Text(entry.notes)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.black)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .padding(.top, 18)
        .frame(height: rowHeight, alignment: .top)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.12)).frame(height: 1).padding(.horizontal, 40)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Color.black.opacity(0.15)).frame(height: 1)
            Text("Generated on-device with SAL. Not sourced from any government, DMV, or law enforcement database.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.55))
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 28)
    }
}
