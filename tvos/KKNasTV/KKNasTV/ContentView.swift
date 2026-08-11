import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Group {
            switch appModel.phase {
            case .restoring:
                ProgressView("正在载入 KKNas…")
            case .signedOut:
                ConnectionView()
            case .signedIn:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appModel.phase)
        .task {
            await appModel.restoreSessionIfNeeded()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel(preview: true))
}
