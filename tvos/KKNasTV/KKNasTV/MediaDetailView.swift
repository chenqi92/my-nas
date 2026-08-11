import SwiftUI

struct MediaDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let item: MediaItem
    @State private var detail: MediaItem
    @State private var seasons: [MediaItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playerItem: MediaItem?

    init(item: MediaItem) {
        self.item = item
        _detail = State(initialValue: item)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                hero

                if detail.isSeries {
                    seriesContent
                }
            }
            .padding(.bottom, 80)
        }
        .navigationTitle(detail.name)
        .task(id: item.id) { await loadDetail() }
        .fullScreenCover(item: $playerItem) { selected in
            PlayerScreen(item: selected, appModel: appModel)
        }
        .alert("载入失败", isPresented: errorPresented) {
            Button("重试") { Task { await loadDetail() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: appModel.imageURL(for: detail, type: "Backdrop", maxWidth: 1900)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [.blue.opacity(0.32), .black], startPoint: .topTrailing, endPoint: .bottomLeading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 610, maxHeight: 610)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.97)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: 48) {
                AsyncImage(url: appModel.imageURL(for: detail, maxWidth: 700)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.gray.opacity(0.22)
                            Image(systemName: detail.isSeries ? "rectangle.stack.fill" : "film.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 260, height: 390)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(radius: 28)

                VStack(alignment: .leading, spacing: 20) {
                    if let seriesName = detail.seriesName, detail.type == "Episode" {
                        Text(seriesName)
                            .font(.title3)
                            .foregroundStyle(.cyan)
                    }
                    Text(detail.name)
                        .font(.system(size: 58, weight: .bold))
                        .lineLimit(2)
                    Text(metadataText)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    if let overview = detail.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .frame(maxWidth: 980, alignment: .leading)
                    }
                    HStack(spacing: 20) {
                        if detail.isPlayable {
                            Button {
                                playerItem = detail
                            } label: {
                                Label(playButtonTitle, systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        if isLoading { ProgressView() }
                    }
                }
            }
            .padding(70)
        }
    }

    private var seriesContent: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("季与剧集")
                .font(.title.bold())
                .padding(.horizontal, 70)

            if seasons.isEmpty && !isLoading {
                Text("没有找到剧集信息")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 70)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 30) {
                        ForEach(seasons) { season in
                            NavigationLink {
                                SeasonView(series: detail, season: season)
                            } label: {
                                MediaPosterView(item: season, width: 240)
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

    private var metadataText: String {
        var values = [detail.subtitle]
        if let duration = detail.durationText { values.append(duration) }
        if let rating = detail.communityRating { values.append(String(format: "★ %.1f", rating)) }
        if let official = detail.officialRating { values.append(official) }
        return values.joined(separator: " · ")
    }

    private var playButtonTitle: String {
        guard let progress = detail.progress, progress > 0, progress < 0.95 else { return "播放" }
        return "继续播放"
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await appModel.detail(for: item.id)
            if detail.isSeries {
                seasons = try await appModel.seasons(for: item.id)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SeasonView: View {
    @EnvironmentObject private var appModel: AppModel
    let series: MediaItem
    let season: MediaItem
    @State private var episodes: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            if !isLoading && episodes.isEmpty {
                EmptyStateView(icon: "play.rectangle", title: "没有剧集", message: "这一季暂时没有可播放内容。")
                    .frame(minHeight: 600)
            } else {
                LazyVStack(spacing: 26) {
                    ForEach(episodes) { episode in
                        NavigationLink(value: episode) {
                            EpisodeRow(episode: episode)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 70)
                .padding(.vertical, 50)
            }
        }
        .overlay { if isLoading { LoadingOverlay(text: "正在载入剧集…") } }
        .navigationTitle(season.name)
        .task(id: season.id) { await loadEpisodes() }
        .alert("载入失败", isPresented: errorPresented) {
            Button("重试") { Task { await loadEpisodes() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func loadEpisodes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            episodes = try await appModel.episodes(for: series.id, seasonID: season.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EpisodeRow: View {
    @EnvironmentObject private var appModel: AppModel
    let episode: MediaItem

    var body: some View {
        HStack(spacing: 28) {
            AsyncImage(url: appModel.imageURL(for: episode, maxWidth: 620)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.gray.opacity(0.2)
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 330, height: 185)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 12) {
                Text(episode.subtitle)
                    .font(.headline)
                    .foregroundStyle(.cyan)
                Text(episode.name)
                    .font(.title2.bold())
                    .lineLimit(1)
                if let overview = episode.overview {
                    Text(overview)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let progress = episode.progress, progress > 0, progress < 0.99 {
                    ProgressView(value: progress)
                        .tint(.cyan)
                        .frame(maxWidth: 500)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
