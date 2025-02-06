import SwiftUI

@main
struct EclipseTVApp: App {
    init() {
        // Prevent Apple TV from going to sleep
        UIApplication.shared.isIdleTimerDisabled = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
