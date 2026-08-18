import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("retentionDays") private var retentionDays = 30
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("groupCode") private var groupCode = ""
    @AppStorage("displayName") private var displayName = ""
    @StateObject private var lockService = AppLockService()
    @StateObject private var syncService = GroupSyncService()
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
        .environmentObject(syncService)
        .background(PLColor.ground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            RetentionService.purgeExpiredEntries(context: modelContext, retentionDays: retentionDays)
            // Resumes an already-joined group on every launch -- joining
            // itself happens from Setup's GROUP section.
            if !groupCode.isEmpty {
                syncService.start(groupCode: groupCode, displayName: displayName, context: modelContext)
            }
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
