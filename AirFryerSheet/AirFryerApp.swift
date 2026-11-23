import SwiftUI

@main
@MainActor
struct AirFryerApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notifications

    var body: some Scene {
        WindowGroup { MainView() }
    }
}
