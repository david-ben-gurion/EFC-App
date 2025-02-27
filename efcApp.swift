import SwiftUI

@main
struct efcApp: App {
    // Integrate AppDelegate into the SwiftUI app lifecycle
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
