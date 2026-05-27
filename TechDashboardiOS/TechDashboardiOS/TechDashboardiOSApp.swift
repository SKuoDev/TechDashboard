import SwiftUI

@main
struct TechDashboardiOSApp: App {
    @StateObject private var store = DashboardStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
