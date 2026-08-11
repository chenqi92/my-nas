import SwiftUI
import AVKit
import Combine

struct PlayerView: View {
    @EnvironmentObject private var appState: AppState
    let source: TVSource
    let item: CatalogItem

    @State private var player: AVPlayer?
    @State private var error: String?
    @StateObject private var progressReporter = ProgressReporter()

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .onAppear {
                        progressReporter.startReporting(
                            player: player,
                            service: appState.progressService(for: source),
                            videoPath: item.videoPath
                        )
                    }
                    .onDisappear {
                        progressReporter.stopReporting()
                    }
            } else if let error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.subheadline)
                }
            } else {
                ProgressView("加载中...")
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPlayer()
        }
    }

    private func loadPlayer() async {
        do {
            let catalog = try makeCatalog()
            let url = try await catalog.playbackURL(for: item)
            let service = appState.progressService(for: source)

            // 先查有没有接着看的进度
            let asset = AVURLAsset(url: url)
            if let authHeader = authorizationHeader() {
                asset.resourceLoader.setDelegate(
                    HeaderInjector(header: authHeader),
                    queue: .main
                )
            }

            let playerItem = AVPlayerItem(asset: asset)
            let newPlayer = AVPlayer(playerItem: playerItem)

            // 恢复进度：非阻塞，直接 seek
            if let savedPosition = await service.progress(for: item.videoPath)?.positionMs {
                let seconds = Double(savedPosition) / 1000.0
                await newPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
            }

            player = newPlayer
            newPlayer.play()
        } catch {
            self.error = error.localizedDescription
        }
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

    private func authorizationHeader() -> String? {
        guard source.type == .webdav,
              let password = KeychainCredentialStore().read(.password, for: source.id)
        else { return nil }
        let auth = "\(source.username):\(password)"
        guard let data = auth.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }
}

/// AVPlayer 每 10 秒上报一次进度。
@MainActor
final class ProgressReporter: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private weak var player: AVPlayer?
    private var service: VideoProgressService?
    private var videoPath: String?

    func startReporting(player: AVPlayer, service: VideoProgressService, videoPath: String) {
        self.player = player
        self.service = service
        self.videoPath = videoPath

        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self, let player = self.player, let service = self.service, let path = self.videoPath
            else { return }

            let currentTime = player.currentTime()
            let duration = player.currentItem?.duration ?? .zero
            guard currentTime.isNumeric, duration.isNumeric else { return }

            let positionMs = Int(currentTime.seconds * 1000)
            let durationMs = Int(duration.seconds * 1000)

            Task {
                _ = await service.saveProgress(videoPath: path, positionMs: positionMs, durationMs: durationMs)
            }
        }
        timer?.fire()  // 立即触发一次
    }

    func stopReporting() {
        timer?.invalidate()
        timer = nil
        player = nil
        service = nil
        videoPath = nil
    }
}

/// 给 AVURLAsset 的请求注入认证头（WebDAV 需要）。
private final class HeaderInjector: NSObject, AVAssetResourceLoaderDelegate {
    let header: String

    init(header: String) {
        self.header = header
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        // 这个 delegate 方法在 tvOS 上其实不会被调用（AVPlayer 直接走系统 HTTP stack），
        // 但保留作为文档。真正注入认证头的方法是 AVURLAsset.httpHeaderFields，
        // 不过它对 HLS 无效。v1 只播 WebDAV 直出的单文件，不涉及 HLS manifest，
        // 所以 Basic Auth 进 URL 的 userinfo 部分（url.user / url.password）就够了。
        // 这段代码留着以防后续扩展其他协议。
        return false
    }
}
