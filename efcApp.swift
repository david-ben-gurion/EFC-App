import SwiftUI

@main
struct efcApp: App {
    // Integrate AppDelegate into the SwiftUI app lifecycle
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Optional: Remove onAppear if you rely on AppDelegate for scheduling
                .onAppear {
                    // Automatically schedule the background upload task when the app starts
                    appDelegate.scheduleDailyUpload()
                }
        }
    }
}
