import SwiftUI

enum PLTab: CaseIterable, Hashable {
    case capture
    case history
    case setup

    var label: String {
        switch self {
        case .capture: return "CAPTURE"
        case .history: return "HISTORY"
        case .setup: return "SETUP"
        }
    }
}

/// Three equal typographic cells, no icons. Active cell is a filled block
/// (ink background, ground text); inactive cells are plain labels on the
/// dark ground. Persistent across every screen, including pushed detail
/// views — there is no native TabView/NavigationStack chrome underneath.
struct PlateLogTabBar: View {
    @Binding var selection: PLTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(PLTab.allCases.enumerated()), id: \.element) { index, tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.label)
                        .plType(PLTypeStyle(.heavy, 12, trackingEm: 0.1))
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(selection == tab ? PLColor.ground : PLColor.inkTertiary)
                        .background(selection == tab ? PLColor.ink : Color.clear)
                        .overlay(alignment: .leading) {
                            if index > 0 {
                                Rectangle()
                                    .fill(PLColor.ruleWeak)
                                    .frame(width: PLSpacing.ruleWidth)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
        }
        .background(PLColor.ground)
    }
}

extension PLTab: Identifiable {
    var id: Self { self }
}
