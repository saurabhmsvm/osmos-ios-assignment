import SwiftUI

@main
@MainActor
struct OsmosDemoApp: App {
    @StateObject private var session = DemoSession()

    var body: some Scene {
        WindowGroup {
            DemoRootView(session: session)
        }
    }
}