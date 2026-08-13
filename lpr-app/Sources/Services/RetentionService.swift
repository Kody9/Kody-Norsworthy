import Foundation
import SwiftData

/// Auto-purge: deletes entries older than the user's chosen retention
/// window. Runs once per launch. `retentionDays <= 0` means "never" (no
/// purge) — Setup's picker should never store 0 for anything but that.
enum RetentionService {
    static func purgeExpiredEntries(context: ModelContext, retentionDays: Int) {
        guard retentionDays > 0 else { return }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now) else { return }

        let predicate = #Predicate<PlateEntry> { $0.capturedAt < cutoff }
        guard let expired = try? context.fetch(FetchDescriptor(predicate: predicate)) else { return }
        for entry in expired {
            context.delete(entry)
        }
    }
}
