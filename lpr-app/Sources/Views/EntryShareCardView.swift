import SwiftUI
import UIKit

/// A standalone "field record" card for a single entry — meant to leave the
/// device (AirDrop, Messages, email, print), so it intentionally does NOT
/// use the app's dark in-app theme: plain white background, black text,
/// full-color photo, easy to read printed or on any screen.
struct EntryShareCardView: View {
    let entry: PlateEntry

    private let cardWidth: CGFloat = 900

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.black).frame(height: 3)

            VStack(alignment: .leading, spacing: 24) {
                plateSection

                if let photoImage {
                    Image(uiImage: photoImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 480)
                        .overlay(Rectangle().stroke(Color.black.opacity(0.15), lineWidth: 1))
                }

                if !entry.driverName.isEmpty {
                    detailRow(label: "DRIVER", value: entry.driverName)
                }
                if let vin = entry.vin, !vin.isEmpty {
                    detailRow(label: "VIN", value: vin)
                }
                if let latitude = entry.latitude, let longitude = entry.longitude {
                    detailRow(label: "LOCATION", value: String(format: "%.5f, %.5f", latitude, longitude))
                }

                if !entry.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Color.black.opacity(0.5))
                        Text(entry.notes)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.black)
                    }
                }
            }
            .padding(40)

            footer
        }
        .frame(width: cardWidth)
        .background(Color.white)
    }

    private var photoImage: UIImage? {
        entry.photoData.flatMap { UIImage(data: $0) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PLATE LOG")
                    .font(.system(size: 14, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(.black)
                Text("FIELD RECORD")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
            Spacer()
            Text("Printed \(Date.now.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.55))
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
    }

    private var plateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.plateNumber)
                .font(.system(size: 56, weight: .black))
                .tracking(1)
                .foregroundStyle(.black)
            Text("\(entry.state.uppercased()) · \(entry.capturedAt.formatted(date: .abbreviated, time: .shortened)) · \(entry.tag.uppercased())")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.65))
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.black.opacity(0.5))
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.black)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Color.black.opacity(0.15)).frame(height: 1)
            Text("Captured on-device with SAL. Not sourced from any government, DMV, or law enforcement database.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.55))
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 28)
    }
}
