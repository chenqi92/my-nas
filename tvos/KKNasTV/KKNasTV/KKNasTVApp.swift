import SwiftUI

@main
struct KKNasTVApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .tint(.cyan)
        }
    }
}
