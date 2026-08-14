import SwiftUI

/// Design tokens for the dark-first "3a" redesign. Colors and spacing are
/// literal per the design handoff. Typography substitutes the system font
/// (San Francisco) for Archivo — same weights and tracking, different
/// typeface — so no font files need bundling into the Xcode project.
enum PLColor {
    static let ground = Color(hex: 0x201E1D)
    static let groundNight = Color(hex: 0x141313)
    static let surface = Color(hex: 0x2D2B2B)
    static let surfaceAlt = Color(hex: 0x444141)
    static let ink = Color(hex: 0xF8F4F4)
    static let inkSecondary = Color(hex: 0xD7D3D3)
    static let inkTertiary = Color(hex: 0x9B9797)
    static let accent = Color(hex: 0xEC3013)
    static let accentPressed = Color(hex: 0xAE1800)
    static let accentHover = Color(hex: 0xDD2B0F)
    static let accentOnDark = Color(hex: 0xFF563C)

    static let ruleWeak = ink.opacity(0.28)
    static let fieldBorder = ink.opacity(0.32)
    static let fieldBorderStrong = ink.opacity(0.40)
}

enum PLSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Screen gutter.
    static let gutter: CGFloat = 16
    static let ruleWidth: CGFloat = 2
}

/// Named type styles from the design spec's typography table, mapped onto
/// the system font. `trackingEm` is letter-spacing expressed as a fraction
/// of the font size (matching the spec's `em` values); SwiftUI's
/// `.tracking()` wants points, so callers get that conversion for free via
/// `View.plType(_:)`.
struct PLTypeStyle {
    let weight: Font.Weight
    let size: CGFloat
    let trackingEm: CGFloat
    let monospace: Bool

    init(_ weight: Font.Weight, _ size: CGFloat, trackingEm: CGFloat = 0, monospace: Bool = false) {
        self.weight = weight
        self.size = size
        self.trackingEm = trackingEm
        self.monospace = monospace
    }

    static let plateDisplay = PLTypeStyle(.black, 54, trackingEm: 0.02)
    static let plateDisplayLarge = PLTypeStyle(.black, 56, trackingEm: 0.02)
    static let plateDetail = PLTypeStyle(.black, 46, trackingEm: 0.03)
    static let screenTitle = PLTypeStyle(.black, 34, trackingEm: -0.02)
    static let plateRow = PLTypeStyle(.heavy, 22, trackingEm: 0.04)
    static let candidate = PLTypeStyle(.bold, 20, trackingEm: 0.04)
    static let buttonPrimary = PLTypeStyle(.black, 24)
    static let buttonSubLabel = PLTypeStyle(.medium, 11, trackingEm: 0.06)
    static let buttonSecondary = PLTypeStyle(.bold, 13, trackingEm: 0.04)
    static let rowLabel = PLTypeStyle(.semibold, 14)
    static let sectionLabel = PLTypeStyle(.heavy, 10, trackingEm: 0.14)
    static let meta = PLTypeStyle(.bold, 11, trackingEm: 0.06)
    static let metaLarge = PLTypeStyle(.bold, 12, trackingEm: 0.08)
    static let body = PLTypeStyle(.regular, 13)
    static let technicalCaption = PLTypeStyle(.medium, 10, trackingEm: 0.08, monospace: true)
    static let linkRow = PLTypeStyle(.bold, 15)
}

extension View {
    func plType(_ style: PLTypeStyle) -> some View {
        self
            .font(.system(size: style.size, weight: style.weight, design: style.monospace ? .monospaced : .default))
            .tracking(style.size * style.trackingEm)
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/// A flush-left, full-width primary action: 88pt tall (56pt on a landscape
/// iPhone, where full height would eat a huge share of the much shorter
/// screen), filled accent, optional sub-label. Used for READ PLATE / LOG
/// PLATE throughout.
struct PLPrimaryButton: View {
    let title: String
    let subLabel: String?
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(_ title: String, subLabel: String? = nil, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.subLabel = subLabel
        self.isDisabled = isDisabled
        self.action = action
    }

    private var isCompact: Bool { verticalSizeClass == .compact }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).plType(.buttonPrimary)
                if let subLabel, !isCompact {
                    Text(subLabel).plType(.buttonSubLabel).opacity(0.85)
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: isCompact ? 56 : 88, alignment: .leading)
            .foregroundStyle(.white)
            .background(PLColor.accent)
        }
        .buttonStyle(PLPressStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}

/// A fixed-width, bordered secondary action next to a primary button.
struct PLSecondaryButton: View {
    let lines: [String]
    let width: CGFloat
    let action: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(_ lines: [String], width: CGFloat = 96, action: @escaping () -> Void) {
        self.lines = lines
        self.width = width
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines, id: \.self) { line in
                    Text(line).plType(.buttonSecondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(width: width)
            .frame(minHeight: verticalSizeClass == .compact ? 56 : 88, alignment: .leading)
            .foregroundStyle(PLColor.ink)
            .overlay(Rectangle().stroke(PLColor.ink, lineWidth: PLSpacing.ruleWidth))
        }
        .buttonStyle(PLPressStyle())
    }
}

/// A full-width, stacked action (used on the edge-state screens where two
/// buttons stack vertically rather than sitting side by side).
struct PLBlockButton: View {
    let title: String
    let filled: Bool
    let height: CGFloat
    let action: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(_ title: String, filled: Bool, height: CGFloat = 80, action: @escaping () -> Void) {
        self.title = title
        self.filled = filled
        self.height = height
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .plType(PLTypeStyle(.black, 18, trackingEm: 0.02))
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: verticalSizeClass == .compact ? 52 : height, alignment: .leading)
                .foregroundStyle(filled ? .white : PLColor.ink)
                .background(filled ? PLColor.accent : Color.clear)
                .overlay(Rectangle().stroke(filled ? Color.clear : PLColor.ink, lineWidth: PLSpacing.ruleWidth))
        }
        .buttonStyle(PLPressStyle())
    }
}

private struct PLPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.08 : 0)
    }
}
