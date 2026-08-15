import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("retentionDays") private var retentionDays = 30
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @StateObject private var lockService = AppLockService()
    @State private var selectedTab: PLTab = .capture

    var body: some View {
        Group {
            if appLockEnabled && !lockService.isUnlocked {
                LockScreenView(lastError: lockService.lastError, onUnlock: lockService.authenticate)
            } else {
                VStack(spacing: 0) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    PlateLogTabBar(selection: $selectedTab)
                }
            }
        }
        .background(PLColor.ground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            RetentionService.purgeExpiredEntries(context: modelContext, retentionDays: retentionDays)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background, appLockEnabled {
                lockService.lock()
            }
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
