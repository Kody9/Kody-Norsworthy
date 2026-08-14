import SwiftUI

/// Full-screen state picker — used from the Read screen when auto-detection
/// couldn't read the state off the plate (too far away, bad angle, worn
/// text). Same visual language as the rest of the app: flush rows, search
/// field, no native picker/menu chrome.
struct StatePickerView: View {
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""

    private var filteredStates: [String] {
        guard !searchText.isEmpty else { return USStates.all }
        return USStates.all.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("CANCEL", action: onCancel)
                    .buttonStyle(.plain)
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.06))
                    .foregroundStyle(PLColor.inkTertiary)
                Spacer()
                Text("STATE")
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.06))
                    .foregroundStyle(PLColor.accentOnDark)
            }
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.vertical, 12)

            TextField("", text: $searchText, prompt: Text("Search states").foregroundStyle(PLColor.inkTertiary))
                .plType(PLTypeStyle(.medium, 14))
                .foregroundStyle(PLColor.ink)
                .padding(13)
                .overlay(Rectangle().stroke(PLColor.fieldBorderStrong, lineWidth: PLSpacing.ruleWidth))
                .padding(.horizontal, PLSpacing.gutter)
                .padding(.bottom, PLSpacing.md)

            ScrollView {
                VStack(spacing: 0) {
                    Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
                    ForEach(filteredStates, id: \.self) { state in
                        Button {
                            onSelect(state)
                        } label: {
                            Text(state.uppercased())
                                .plType(PLTypeStyle(.semibold, 16))
                                .foregroundStyle(PLColor.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, PLSpacing.gutter)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
                        }
                    }
                    if filteredStates.isEmpty {
                        Text("No match")
                            .plType(.body)
                            .foregroundStyle(PLColor.inkTertiary)
                            .padding(PLSpacing.gutter)
                    }
                }
            }
        }
        .background(PLColor.ground)
    }
}
