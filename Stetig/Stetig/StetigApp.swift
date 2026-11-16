import SwiftUI
import SwiftData

@main
struct StetigApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Stetig")
        }
        .modelContainer(Store.shared)
    }
}
