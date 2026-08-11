import SwiftUI
import MyNASSync

@main
struct MyNASTVApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            SourceListView()
                .environmentObject(appState)
        }
    }
}

/// 全应用共享的状态。
@MainActor
final class AppState: ObservableObject {
    @Published var sources: [TVSource] = []
    @Published var activeSource: TVSource?

    /// 每个源一套 sync coordinator。退出源时不 stop，让它继续后台跑，直到 app 挂起。
    private var coordinators: [String: CloudSyncCoordinator] = [:]

    private let keychain = KeychainCredentialStore()
    private let progressStore = FileVideoProgressStore()

    init() {
        loadSources()
    }

    func loadSources() {
        // 简单持久化：UserDefaults 存源列表 JSON，Keychain 存凭证
        guard let data = UserDefaults.standard.data(forKey: "tv_sources"),
              let loaded = try? JSONDecoder().decode([TVSource].self, from: data)
        else {
            sources = []
            return
        }
        sources = loaded
    }

    func saveSources() {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        UserDefaults.standard.set(data, forKey: "tv_sources")
    }

    func addSource(_ source: TVSource, password: String?, token: String?) {
        sources.append(source)
        saveSources()
        if let password {
            keychain.store(.password, for: source.id, value: password)
        }
        if let token {
            keychain.store(.token, for: source.id, value: token)
        }
    }

    func updateSource(_ source: TVSource, password: String?, token: String?) {
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            sources[index] = source
            saveSources()
        }
        if let password {
            keychain.store(.password, for: source.id, value: password)
        }
        if let token {
            keychain.store(.token, for: source.id, value: token)
        }
    }

    func deleteSource(at offsets: IndexSet) {
        for i in offsets {
            let sourceID = sources[i].id
            keychain.deleteAll(for: sourceID)
            coordinators.removeValue(forKey: sourceID)
        }
        sources.remove(atOffsets: offsets)
        saveSources()
    }

    func selectSource(_ source: TVSource) {
        activeSource = source
        // 首次选中时创建 coordinator 并启动同步
        if coordinators[source.id] == nil, source.type == .webdav {
            startSync(for: source)
        }
    }

    private func startSync(for source: TVSource) {
        // v1 只有 WebDAV sync。Jellyfin/Emby/Plex 媒体服务器不同步，
        // 因为它们跨客户端的进度用服务端 API 管（Dart 里也是）。
        guard let password = keychain.read(.password, for: source.id),
              let url = URL(string: source.endpoint)
        else { return }

        let backend = WebDavCloudSyncBackend(endpoint: url, username: source.username, password: password)
        let coordinator = CloudSyncCoordinator(store: progressStore, backend: backend)
        coordinators[source.id] = coordinator

        Task { try? await coordinator.syncOnce() }
    }

    func progressService(for source: TVSource) -> VideoProgressService {
        // 打开某个源的播放器时拿 service。所有源共用同一 store；key 是 videoPath（不带源前缀）。
        VideoProgressService(store: progressStore)
    }
}
