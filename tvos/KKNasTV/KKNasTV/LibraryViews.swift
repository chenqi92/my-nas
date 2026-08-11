import SwiftUI

struct LibraryRootView: View {
    @EnvironmentObject private var appModel: AppModel
    private let columns = [GridItem(.adaptive(minimum: 390, maximum: 520), spacing: 36)]

    var body: some View {
        ScrollView {
            if appModel.libraries.isEmpty && !appModel.isLoadingHome {
                EmptyStateView(icon: "rectangle.stack", title: "没有媒体库", message: "请检查服务器中的媒体库权限。")
                    .frame(minHeight: 600)
            } else {
                LazyVGrid(columns: columns, spacing: 36) {
                    ForEach(appModel.libraries) { library in
                        NavigationLink(value: library) {
                            LibraryCard(library: library)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 70)
                .padding(.vertical, 50)
            }
        }
        .navigationTitle("媒体库")
        .task {
            if appModel.libraries.isEmpty { await appModel.refreshHome() }
        }
    }
}

struct LibraryItemsView: View {
    @EnvironmentObject private var appModel: AppModel
    let library: MediaLibrary
    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 235, maximum: 285), spacing: 34)]

    var body: some View {
        ScrollView {
            if !isLoading && items.isEmpty {
                EmptyStateView(icon: "film.stack", title: "媒体库为空", message: "这里暂时没有影片或剧集。")
                    .frame(minHeight: 600)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 46) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            MediaPosterView(item: item, width: 245)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 70)
                .padding(.vertical, 45)
            }
        }
        .overlay { if isLoading { LoadingOverlay(text: "正在载入 \(library.name)…") } }
        .navigationTitle(library.name)
        .task(id: library.id) { await load() }
        .alert("载入失败", isPresented: errorPresented) {
            Button("重试") { Task { await load() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await appModel.items(in: library.id, limit: 200).items
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
