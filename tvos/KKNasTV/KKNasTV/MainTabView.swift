import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
                    .mediaDestinations()
            }
            .tabItem { Label("首页", systemImage: "house.fill") }

            NavigationStack {
                LibraryRootView()
                    .mediaDestinations()
            }
            .tabItem { Label("媒体库", systemImage: "rectangle.stack.fill") }

            NavigationStack {
                MediaSearchView()
                    .mediaDestinations()
            }
            .tabItem { Label("搜索", systemImage: "magnifyingglass") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
    }
}

private extension View {
    func mediaDestinations() -> some View {
        navigationDestination(for: MediaItem.self) { item in
            MediaDetailView(item: item)
        }
        .navigationDestination(for: MediaLibrary.self) { library in
            LibraryItemsView(library: library)
        }
    }
}
