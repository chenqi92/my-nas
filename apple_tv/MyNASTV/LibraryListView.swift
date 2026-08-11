import SwiftUI

struct LibraryListView: View {
    @EnvironmentObject private var appState: AppState
    let source: TVSource

    @State private var items: [CatalogItem] = []
    @State private var path: [String] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack {
            if loading {
                ProgressView()
            } else if let error {
                errorView(error)
            } else if items.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 20)], spacing: 20) {
                        ForEach(items) { item in
                            if item.isDirectory {
                                Button {
                                    navigate(to: item)
                                } label: {
                                    folderCard(item)
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink {
                                    PlayerView(source: source, item: item)
                                        .environmentObject(appState)
                                } label: {
                                    videoCard(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(path.isEmpty ? source.name : path.last ?? "")
        .task {
            appState.selectSource(source)
            await load()
        }
    }

    private func navigate(to item: CatalogItem) {
        path.append(item.videoPath)
        Task { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            let catalog = try makeCatalog()
            let loaded = try await catalog.list(path: path.last ?? "")
            items = loaded
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func makeCatalog() throws -> any VideoCatalog {
        let keychain = KeychainCredentialStore()
        switch source.type {
        case .webdav:
            guard let password = keychain.read(.password, for: source.id),
                  let url = URL(string: source.endpoint)
            else { throw CatalogError.missingCredentials }
            return WebDavCatalog(baseURL: url, username: source.username, password: password)

        case .jellyfin:
            guard let token = keychain.read(.token, for: source.id),
                  let url = URL(string: source.endpoint)
            else { throw CatalogError.missingCredentials }
            return JellyfinCatalog(baseURL: url, userID: source.username, token: token, flavor: .jellyfin)

        case .emby:
            guard let token = keychain.read(.token, for: source.id),
                  let url = URL(string: source.endpoint)
            else { throw CatalogError.missingCredentials }
            return JellyfinCatalog(baseURL: url, userID: source.username, token: token, flavor: .emby)

        case .plex:
            guard let token = keychain.read(.token, for: source.id),
                  let url = URL(string: source.endpoint)
            else { throw CatalogError.missingCredentials }
            return PlexCatalog(baseURL: url, token: token)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
            Button("重试", action: { Task { await load() } })
                .buttonStyle(.borderedProminent)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("这里还没有内容")
                .font(.subheadline)
        }
    }

    private func folderCard(_ item: CatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.tertiary)
                    .frame(height: 140)
                Image(systemName: "folder.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }
            Text(item.name)
                .font(.headline)
                .lineLimit(2)
        }
        .frame(width: 250)
    }

    private func videoCard(_ item: CatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let thumbnailURL = item.thumbnailURL {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            placeholderThumbnail
                        @unknown default:
                            placeholderThumbnail
                        }
                    }
                } else {
                    placeholderThumbnail
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(item.name)
                .font(.headline)
                .lineLimit(2)
        }
        .frame(width: 250)
    }

    private var placeholderThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.tertiary)
            Image(systemName: "film")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        }
    }
}
