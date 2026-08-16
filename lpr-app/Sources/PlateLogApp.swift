import FirebaseCore
import SwiftData
import SwiftUI

@main
struct PlateLogApp: App {
    @AppStorage("hasAcceptedDisclaimer") private var hasAcceptedDisclaimer = false
    private let container = PlateLogApp.makeContainer()

    init() {
        // FirebaseApp.configure() itself crashes if GoogleService-Info.plist
        // isn't in the bundle, so group sync (an optional, opt-in feature --
        // see Setup's GROUP section) is only turned on when that file has
        // actually been added to the Xcode project. Everything else about
        // the app works identically without it.
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            if hasAcceptedDisclaimer {
                ContentView()
            } else {
                DisclaimerView(onAccept: { hasAcceptedDisclaimer = true })
            }
        }
        .modelContainer(container)
    }

    /// `.modelContainer(for:)`'s default behavior on a schema mismatch
    /// (e.g. a stored property was added since the on-disk store was
    /// created, and this device never got a clean reinstall to clear it)
    /// is to crash at launch -- which looks to a user like "the app just
    /// stopped saving," not an obvious crash report. Falls back to
    /// deleting and recreating the store so a future field addition can
    /// never brick saving again; this is a personal single-device log
    /// with no backend to reconcile against, so losing entries in that
    /// one-time recovery is an acceptable tradeoff against the app not
    /// working at all.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([PlateEntry.self])
        let configuration = ModelConfiguration(schema: schema)

        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }

        let storeURL = configuration.url
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }

        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            fatalError("Could not create ModelContainer even after resetting the store.")
        }
        return container
    }
}
