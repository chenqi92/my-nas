import SwiftUI

struct MediaSearchView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var query = ""
    @State private var results: [MediaItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 235, maximum: 285), spacing: 34)]

    var body: some View {
        ScrollView {
            if query.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "搜索媒体", message: "输入片名、剧名或集名。")
                    .frame(minHeight: 600)
            } else if !isSearching && results.isEmpty {
                EmptyStateView(icon: "film", title: "没有结果", message: "没有找到与“\(query)”匹配的媒体。")
                    .frame(minHeight: 600)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 46) {
                    ForEach(results) { item in
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
        .overlay { if isSearching { LoadingOverlay(text: "正在搜索…") } }
        .navigationTitle("搜索")
        .searchable(text: $query, placement: .automatic, prompt: "搜索电影和剧集")
        .task(id: query) {
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                results = []
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(450))
                try Task.checkCancellation()
                isSearching = true
                results = try await appModel.search(query)
                errorMessage = nil
                isSearching = false
            } catch is CancellationError {
                return
            } catch {
                isSearching = false
                errorMessage = error.localizedDescription
            }
        }
        .alert("搜索失败", isPresented: errorPresented) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
