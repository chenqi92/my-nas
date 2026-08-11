import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 52) {
                if let featured = appModel.latestItems.first {
                    featuredView(featured)
                }

                if !appModel.resumeItems.isEmpty {
                    MediaShelf(title: "继续观看", items: appModel.resumeItems)
                }

                if !appModel.latestItems.isEmpty {
                    MediaShelf(title: "最近添加", items: appModel.latestItems)
                }

                if !appModel.libraries.isEmpty {
                    libraryShelf
                }

                if !appModel.isLoadingHome,
                   appModel.latestItems.isEmpty,
                   appModel.libraries.isEmpty {
                    EmptyStateView(
                        icon: "rectangle.stack.badge.questionmark",
                        title: "没有可显示的媒体",
                        message: "请确认当前账号有媒体库访问权限。"
                    )
                    .frame(maxWidth: .infinity, minHeight: 520)
                }
            }
            .padding(.bottom, 90)
        }
        .overlay {
            if appModel.isLoadingHome && appModel.latestItems.isEmpty {
                LoadingOverlay(text: "正在同步媒体库…")
            }
        }
        .navigationTitle(appModel.session?.serverName ?? "KKNas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await appModel.refreshHome() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(appModel.isLoadingHome)
            }
        }
    }

    private func featuredView(_ item: MediaItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: appModel.imageURL(for: item, type: "Backdrop", maxWidth: 1800)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [.cyan.opacity(0.28), .black], startPoint: .topTrailing, endPoint: .bottomLeading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 510, maxHeight: 510)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 18) {
                Text("精选推荐")
                    .font(.headline)
                    .foregroundStyle(.cyan)
                Text(item.name)
                    .font(.system(size: 58, weight: .bold))
                    .lineLimit(2)
                Text([item.subtitle, item.durationText].compactMap { $0 }.joined(separator: " · "))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                NavigationLink(value: item) {
                    Label(item.isPlayable ? "播放与详情" : "查看详情", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(70)
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .padding(.horizontal, 70)
        .padding(.top, 24)
    }

    private var libraryShelf: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("媒体库")
                .font(.title.bold())
                .padding(.horizontal, 70)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 32) {
                    ForEach(appModel.libraries) { library in
                        NavigationLink(value: library) {
                            LibraryCard(library: library)
                                .frame(width: 430)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 70)
                .padding(.vertical, 24)
            }
        }
    }
}
