import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("retentionDays") private var retentionDays = 30
    @State private var selectedTab: PLTab = .capture

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PlateLogTabBar(selection: $selectedTab)
        }
        .background(PLColor.ground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            RetentionService.purgeExpiredEntries(context: modelContext, retentionDays: retentionDays)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .capture:
            CaptureView()
        case .history:
            HistoryListView()
        case .setup:
            SettingsView()
        }
    }
}
