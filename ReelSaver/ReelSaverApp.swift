import SwiftUI
import SwiftData

@main
struct ReelSaverApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([SavedReel.self])

        // Point at an explicit path rather than using `groupContainer:`, which
        // traps if the entitlement is missing and assumes directories that the
        // group container doesn't ship with. Falling back to the default store
        // keeps the app usable without the App Group — it just won't see
        // anything the share extension hands over.
        let configuration = AppGroup.storeURL.map {
            ModelConfiguration(schema: schema, url: $0)
        } ?? ModelConfiguration(schema: schema)

        do {
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // A corrupt store shouldn't brick launch; start over in memory.
            container = try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(container)
    }
}
