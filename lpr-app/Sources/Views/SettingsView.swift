import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// "Setup" tab. Not pixel-specced in the redesign handoff (no Setup screen
/// exists in the design canvas yet) — kept functional and restyled just
/// enough to sit comfortably next to the rest of the dark UI.
struct SettingsView: View {
    @Query private var entries: [PlateEntry]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncService: GroupSyncService
    @AppStorage("hasAcceptedDisclaimer") private var hasAcceptedDisclaimer = true
    @AppStorage("retentionDays") private var retentionDays = 30
    @AppStorage("autoScanFastMode") private var autoScanFastMode = true
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("groupCode") private var groupCode = ""
    @AppStorage("displayName") private var displayName = ""

    @State private var shareFile: ShareableFile?
    @State private var showClearConfirmation = false
    @State private var showLeaveConfirmation = false
    @State private var groupCodeDraft = ""
    @State private var displayNameDraft = ""
    @State private var showRoster = false
    @State private var rosterMembers: [GroupMember] = []
    @State private var isLoadingRoster = false

    private let retentionOptions = [7, 14, 30, 60, 90, 0]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Setup")
                    .plType(.screenTitle)
                    .foregroundStyle(PLColor.ink)
                    .padding(.horizontal, PLSpacing.gutter)
                    .padding(.top, 12)
                    .padding(.bottom, PLSpacing.gutter)

                sectionLabel("DATA")
                row { LabeledRow(label: "Total Entries", value: "\(entries.count)") }
                actionRow("Export as CSV") {
                    if let url = CSVExporter.export(entries, label: "All Entries") {
                        shareFile = ShareableFile(url: url)
                    }
                }
                actionRow("Clear All Data", destructive: true, showRule: false) {
                    showClearConfirmation = true
                }

                sectionLabel("RETENTION")
                row {
                    HStack {
                        Text("Auto-delete after").plType(.rowLabel).foregroundStyle(PLColor.inkSecondary)
                        Spacer()
                        Picker("", selection: $retentionDays) {
                            ForEach(retentionOptions, id: \.self) { days in
                                Text(days == 0 ? "Never" : "\(days) days").tag(days)
                            }
                        }
                        .tint(PLColor.accentOnDark)
                    }
                }
                Text("Entries older than the chosen window are deleted from this phone automatically on launch — DPPA hygiene by default, not by discipline.")
                    .plType(.body)
                    .foregroundStyle(PLColor.inkTertiary)
                    .padding(.horizontal, PLSpacing.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, PLSpacing.gutter)

                sectionLabel("AUTO-SCAN")
                row {
                    HStack {
                        Text("Mode").plType(.rowLabel).foregroundStyle(PLColor.inkSecondary)
                        Spacer()
                        Picker("", selection: $autoScanFastMode) {
                            Text("Fast").tag(true)
                            Text("Accurate").tag(false)
                        }
                        .tint(PLColor.accentOnDark)
                    }
                }
                Text(autoScanFastMode
                    ? "Trusts a single frame's read immediately — catches more cars, including fast-moving ones, at the cost of more wrong reads to correct."
                    : "Waits for the same reading twice within a few seconds before queuing it — fewer wrong reads, but a car only in frame briefly may not get caught at all.")
                    .plType(.body)
                    .foregroundStyle(PLColor.inkTertiary)
                    .padding(.horizontal, PLSpacing.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, PLSpacing.gutter)

                sectionLabel("PRIVACY")
                row {
                    HStack {
                        Text("App Lock").plType(.rowLabel).foregroundStyle(PLColor.inkSecondary)
                        Spacer()
                        Toggle("", isOn: $appLockEnabled)
                            .labelsHidden()
                            .tint(PLColor.accentOnDark)
                    }
                }
                Text("Requires Face ID, Touch ID, or your device passcode to open SAL — every time it's brought back to the foreground, not just on cold launch.")
                    .plType(.body)
                    .foregroundStyle(PLColor.inkTertiary)
                    .padding(.horizontal, PLSpacing.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, PLSpacing.gutter)

                groupSection

                sectionLabel("ABOUT")
                actionRow("View Usage Disclaimer") {
                    hasAcceptedDisclaimer = false
                }
                Text("All data is stored only on this device. Nothing is uploaded to any server.")
                    .plType(.body)
                    .foregroundStyle(PLColor.inkTertiary)
                    .padding(.horizontal, PLSpacing.gutter)
                    .padding(.top, 8)
            }
        }
        .background(PLColor.ground)
        .sheet(item: $shareFile) { file in
            ShareSheet(activityItems: [file.url])
        }
        .alert("Clear All Data?", isPresented: $showClearConfirmation) {
            Button("Delete Everything", role: .destructive, action: clearAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all captured plate entries from this device. This cannot be undone.")
        }
        .alert("Leave This Group?", isPresented: $showLeaveConfirmation) {
            Button("Leave", role: .destructive, action: leaveGroup)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop receiving new entries from the group, and it'll stop receiving yours. Entries already synced to this device stay in your History.")
        }
        .onAppear {
            groupCodeDraft = groupCode
            displayNameDraft = displayName
        }
        .sheet(isPresented: $showRoster) {
            GroupRosterView(members: rosterMembers, isLoading: isLoadingRoster, onDone: { showRoster = false })
        }
    }

    private var canJoin: Bool {
        !groupCodeDraft.trimmingCharacters(in: .whitespaces).isEmpty &&
        !displayNameDraft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder
    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("GROUP")

            if !syncService.isFirebaseConfigured {
                Text("Not set up yet — add GoogleService-Info.plist to the Xcode project to enable syncing with a group. See the README for setup steps.")
                    .plType(.body)
                    .foregroundStyle(PLColor.inkTertiary)
                    .padding(.horizontal, PLSpacing.gutter)
                    .padding(.bottom, PLSpacing.gutter)
            } else if groupCode.isEmpty {
                groupJoinForm
            } else {
                groupStatusRow
            }
        }
    }

    private var groupJoinForm: some View {
        VStack(alignment: .leading, spacing: PLSpacing.md) {
            Text("Share captures with a group of people who also have SAL — everyone sees each other's plates, photos, notes, and tags, and gets flagged if someone else already logged the same plate.")
                .plType(.body)
                .foregroundStyle(PLColor.inkTertiary)

            labeledField("YOUR NAME", text: $displayNameDraft)
            labeledField("GROUP CODE", text: $groupCodeDraft)

            Text("Anyone with this code can join and see the group's data — share it only with people you trust, the same way you'd share a Wi-Fi password.")
                .plType(PLTypeStyle(.medium, 11))
                .foregroundStyle(PLColor.inkTertiary)

            PLBlockButton("JOIN GROUP", filled: true, height: 52, action: joinGroup)
                .disabled(!canJoin)
                .opacity(canJoin ? 1 : 0.4)
        }
        .padding(.horizontal, PLSpacing.gutter)
        .padding(.bottom, PLSpacing.gutter)
    }

    private var groupStatusRow: some View {
        VStack(alignment: .leading, spacing: PLSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GROUP CODE").plType(.sectionLabel).foregroundStyle(PLColor.inkTertiary)
                    Text(groupCode).plType(PLTypeStyle(.heavy, 18)).foregroundStyle(PLColor.ink)
                }
                Spacer()
                Text(syncService.isActive ? "CONNECTED" : "CONNECTING…")
                    .plType(PLTypeStyle(.bold, 10, trackingEm: 0.08))
                    .foregroundStyle(syncService.isActive ? .white : PLColor.inkTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(syncService.isActive ? PLColor.accent : PLColor.surface)
            }
            Text("Logging in as \(displayName.isEmpty ? "—" : displayName)")
                .plType(.body)
                .foregroundStyle(PLColor.inkTertiary)
            if let lastError = syncService.lastError {
                Text(lastError)
                    .plType(PLTypeStyle(.medium, 11))
                    .foregroundStyle(PLColor.accentOnDark)
            }
            HStack(spacing: 20) {
                Button(action: openRoster) {
                    Text("VIEW ROSTER")
                        .underline()
                        .plType(PLTypeStyle(.bold, 12, trackingEm: 0.08))
                        .foregroundStyle(PLColor.ink)
                }
                .buttonStyle(.plain)
                Button {
                    showLeaveConfirmation = true
                } label: {
                    Text("LEAVE GROUP")
                        .underline()
                        .plType(PLTypeStyle(.bold, 12, trackingEm: 0.08))
                        .foregroundStyle(PLColor.accentOnDark)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, PLSpacing.gutter)
        .padding(.bottom, PLSpacing.gutter)
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).plType(.sectionLabel).foregroundStyle(PLColor.inkTertiary)
            TextField("", text: text)
                .plType(PLTypeStyle(.medium, 14))
                .foregroundStyle(PLColor.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
                .padding(13)
                .overlay(Rectangle().stroke(PLColor.fieldBorderStrong, lineWidth: PLSpacing.ruleWidth))
        }
    }

    private func joinGroup() {
        guard canJoin else { return }
        displayName = displayNameDraft.trimmingCharacters(in: .whitespaces)
        groupCode = groupCodeDraft.trimmingCharacters(in: .whitespaces)
        syncService.start(groupCode: groupCode, displayName: displayName, context: modelContext)
        // Local notifications for BOLO matches -- see GroupSyncService.
        // Requested here (not at app launch) so the prompt shows up
        // right when it's actually relevant, tied to the action that
        // makes it useful.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func leaveGroup() {
        syncService.stop()
        groupCode = ""
    }

    private func openRoster() {
        showRoster = true
        isLoadingRoster = true
        syncService.fetchMembers(groupCode: groupCode) { members in
            rosterMembers = members
            isLoadingRoster = false
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .plType(.sectionLabel)
            .foregroundStyle(PLColor.inkTertiary)
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.top, PLSpacing.lg)
            .padding(.bottom, 8)
            .overlay(alignment: .top) {
                Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
            }
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
            }
    }

    private func actionRow(_ title: String, destructive: Bool = false, showRule: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .plType(.rowLabel)
                .foregroundStyle(destructive ? PLColor.accentOnDark : PLColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, PLSpacing.gutter)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if showRule {
                Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
            }
        }
    }

    private func clearAll() {
        for entry in entries {
            modelContext.delete(entry)
        }
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).plType(.rowLabel).foregroundStyle(PLColor.inkSecondary)
            Spacer()
            Text(value).plType(PLTypeStyle(.semibold, 14)).foregroundStyle(PLColor.ink)
        }
    }
}

/// Wraps a URL so it can drive `.sheet(item:)`, which — unlike
/// `.sheet(isPresented:)` paired with a separately-tracked optional — is
/// guaranteed to have the value available when its content closure runs.
/// (isPresented + a sibling @State optional can present before that
/// optional is visible to the closure, rendering an empty sheet.)
struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Everyone who's ever joined this group -- see
/// GroupSyncService.fetchMembers. A one-shot fetch on open rather than a
/// live listener, since who's in the group isn't something that needs
/// to update while you're actively looking at the list.
private struct GroupRosterView: View {
    let members: [GroupMember]
    let isLoading: Bool
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("GROUP ROSTER")
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.06))
                    .foregroundStyle(PLColor.accentOnDark)
                Spacer()
                Button("DONE", action: onDone)
                    .buttonStyle(.plain)
                    .plType(PLTypeStyle(.bold, 12, trackingEm: 0.08))
                    .foregroundStyle(PLColor.ink)
            }
            .padding(.horizontal, PLSpacing.gutter)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PLColor.ink).frame(height: PLSpacing.ruleWidth)
            }

            if isLoading {
                Spacer()
                Text("LOADING…").plType(.body).foregroundStyle(PLColor.inkTertiary)
                Spacer()
            } else if members.isEmpty {
                Spacer()
                Text("No members found yet.").plType(.body).foregroundStyle(PLColor.inkTertiary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(members) { member in
                            memberRow(member)
                        }
                    }
                }
            }
        }
        .background(PLColor.ground)
    }

    private func memberRow(_ member: GroupMember) -> some View {
        HStack {
            Text(member.displayName.isEmpty ? "Unnamed" : member.displayName)
                .plType(PLTypeStyle(.semibold, 15))
                .foregroundStyle(PLColor.ink)
            Spacer()
            Text("JOINED \(member.joinedAt.formatted(date: .abbreviated, time: .omitted).uppercased())")
                .plType(PLTypeStyle(.bold, 10, trackingEm: 0.06))
                .foregroundStyle(PLColor.inkTertiary)
        }
        .padding(.horizontal, PLSpacing.gutter)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PLColor.ruleWeak).frame(height: PLSpacing.ruleWidth)
        }
    }
}
