import SwiftData
import SwiftUI

@main
struct PlateLogApp: App {
    @AppStorage("hasAcceptedDisclaimer") private var hasAcceptedDisclaimer = false

    var body: some Scene {
        WindowGroup {
            if hasAcceptedDisclaimer {
                ContentView()
            } else {
                DisclaimerView(onAccept: { hasAcceptedDisclaimer = true })
            }
        }
        .modelContainer(for: PlateEntry.self)
    }
}
