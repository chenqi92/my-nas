import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case restoring
        case signedOut
        case signedIn
    }

    @Published private(set) var phase: Phase = .restoring
    @Published private(set) var session: ServerSession?
    @Published private(set) var libraries: [MediaLibrary] = []
    @Published private(set) var latestItems: [MediaItem] = []
    @Published private(set) var resumeItems: [MediaItem] = []
    @Published private(set) var isLoadingHome = false
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?
    @Published private(set) var quickConnectCode: String?
    @Published private(set) var quickConnectStatus: String?
    @Published var preferDirectPlay: Bool {
        didSet { defaults.set(preferDirectPlay, forKey: Self.preferDirectPlayKey) }
    }
    @Published var maxStreamingBitrate: Int {
        didSet { defaults.set(maxStreamingBitrate, forKey: Self.maxBitrateKey) }
    }

    private static let preferDirectPlayKey = "tvos.playback.preferDirectPlay"
    private static let maxBitrateKey = "tvos.playback.maxBitrate"

    private let defaults: UserDefaults
    private let accountStore: ServerAccountStore
    private var client: MediaServerClient?
    private var didRestore = false
    private var quickConnectTask: Task<Void, Never>?
    private var quickConnectGeneration = 0

    init(defaults: UserDefaults = .standard, tokenStore: TokenStoring = KeychainTokenStore()) {
        self.defaults = defaults
        self.accountStore = ServerAccountStore(defaults: defaults, tokenStore: tokenStore)
        self.preferDirectPlay = defaults.object(forKey: Self.preferDirectPlayKey) as? Bool ?? true
        self.maxStreamingBitrate = defaults.object(forKey: Self.maxBitrateKey) as? Int ?? 80_000_000
    }

    convenience init(preview: Bool) {
        let suite = UserDefaults(suiteName: "KKNasTVPreview") ?? .standard
        self.init(defaults: suite, tokenStore: PreviewTokenStore())
        if preview { phase = .signedOut }
    }

    func restoreSessionIfNeeded() async {
        guard !didRestore else { return }
        didRestore = true
        do {
            guard let restored = try accountStore.load() else {
                phase = .signedOut
                return
            }
            activate(restored)
            await refreshHome()
        } catch {
            errorMessage = error.localizedDescription
            phase = .signedOut
        }
    }

    func login(kind: MediaServerKind, address: String, username: String, password: String) async {
        cancelQuickConnect()
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }
        do {
            let baseURL = try MediaServerClient.normalizedBaseURL(address)
            let temporary = makeTemporaryClient(kind: kind, baseURL: baseURL)
            async let infoRequest = temporary.publicServerInfo()
            async let authRequest = temporary.authenticate(username: username, password: password)
            let (info, auth) = try await (infoRequest, authRequest)
            try finishAuthentication(kind: kind, baseURL: baseURL, info: info, auth: auth)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startQuickConnect(address: String) {
        cancelQuickConnect()
        errorMessage = nil
        let generation = quickConnectGeneration
        quickConnectTask = Task { [weak self] in
            await self?.runQuickConnect(address: address, generation: generation)
        }
    }

    func cancelQuickConnect() {
        quickConnectGeneration &+= 1
        quickConnectTask?.cancel()
        quickConnectTask = nil
        quickConnectCode = nil
        quickConnectStatus = nil
        isAuthenticating = false
    }

    func refreshHome() async {
        guard let client else { return }
        isLoadingHome = true
        errorMessage = nil
        defer { isLoadingHome = false }
        do {
            async let librariesRequest = client.libraries()
            async let latestRequest = client.latest()
            async let resumeRequest = client.resume()
            let (libraries, latest, resume) = try await (librariesRequest, latestRequest, resumeRequest)
            self.libraries = libraries
            self.latestItems = latest
            self.resumeItems = resume
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func items(in libraryID: String?, startIndex: Int = 0, limit: Int = 100) async throws -> ItemsResponse {
        guard let client else { throw MediaServerError.missingSession }
        return try await client.items(parentID: libraryID, limit: limit, startIndex: startIndex)
    }

    func search(_ query: String) async throws -> [MediaItem] {
        guard let client else { throw MediaServerError.missingSession }
        let response = try await client.items(searchTerm: query, limit: 60)
        return response.items
    }

    func detail(for itemID: String) async throws -> MediaItem {
        guard let client else { throw MediaServerError.missingSession }
        return try await client.detail(itemID: itemID)
    }

    func seasons(for seriesID: String) async throws -> [MediaItem] {
        guard let client else { throw MediaServerError.missingSession }
        return try await client.seasons(seriesID: seriesID)
    }

    func episodes(for seriesID: String, seasonID: String?) async throws -> [MediaItem] {
        guard let client else { throw MediaServerError.missingSession }
        return try await client.episodes(seriesID: seriesID, seasonID: seasonID)
    }

    func imageURL(for item: MediaItem, type: String = "Primary", maxWidth: Int = 640) -> URL? {
        let tag: String?
        if type == "Backdrop" { tag = item.backdropImageTags?.first }
        else { tag = item.imageTags?[type] }
        return client?.imageURL(itemID: item.id, type: type, maxWidth: maxWidth, tag: tag)
    }

    func imageURL(for library: MediaLibrary, maxWidth: Int = 640) -> URL? {
        guard let imageID = library.primaryImageItemID ?? Optional(library.id) else { return nil }
        return client?.imageURL(itemID: imageID, maxWidth: maxWidth)
    }

    func playbackPlan(for item: MediaItem) async throws -> PlaybackPlan {
        guard let client else { throw MediaServerError.missingSession }
        return try await client.playbackPlan(
            item: item,
            preferDirectPlay: preferDirectPlay,
            maxBitrate: maxStreamingBitrate
        )
    }

    func reportPlaybackStart(itemID: String, plan: PlaybackPlan, positionTicks: Int64) async {
        try? await client?.reportPlaybackStart(itemID: itemID, plan: plan, positionTicks: positionTicks)
    }

    func reportPlaybackProgress(itemID: String, plan: PlaybackPlan, positionTicks: Int64, isPaused: Bool) async {
        try? await client?.reportPlaybackProgress(itemID: itemID, plan: plan, positionTicks: positionTicks, isPaused: isPaused)
    }

    func reportPlaybackStopped(itemID: String, plan: PlaybackPlan, positionTicks: Int64) async {
        try? await client?.reportPlaybackStopped(itemID: itemID, plan: plan, positionTicks: positionTicks)
        await refreshHome()
    }

    func signOut() async {
        cancelQuickConnect()
        await client?.logout()
        do { try accountStore.clear() } catch { errorMessage = error.localizedDescription }
        client = nil
        session = nil
        libraries = []
        latestItems = []
        resumeItems = []
        phase = .signedOut
    }

    private func runQuickConnect(address: String, generation: Int) async {
        isAuthenticating = true
        defer {
            if generation == quickConnectGeneration {
                isAuthenticating = false
                quickConnectTask = nil
            }
        }
        do {
            let baseURL = try MediaServerClient.normalizedBaseURL(address)
            let temporary = makeTemporaryClient(kind: .jellyfin, baseURL: baseURL)
            let info = try await temporary.publicServerInfo()
            guard generation == quickConnectGeneration else { return }
            let initial = try await temporary.initiateQuickConnect()
            guard generation == quickConnectGeneration else { return }
            guard !initial.code.isEmpty, !initial.secret.isEmpty else {
                throw MediaServerError.invalidResponse
            }
            quickConnectCode = initial.code
            quickConnectStatus = "请在 Jellyfin 的快速连接页面输入此代码"

            for _ in 0..<60 {
                try Task.checkCancellation()
                try await Task.sleep(for: .seconds(3))
                let state = try await temporary.quickConnectState(secret: initial.secret)
                guard generation == quickConnectGeneration else { return }
                guard state.authenticated else { continue }
                quickConnectStatus = "已授权，正在登录…"
                let auth = try await temporary.authenticateWithQuickConnect(secret: initial.secret)
                guard generation == quickConnectGeneration else { return }
                try finishAuthentication(kind: .jellyfin, baseURL: baseURL, info: info, auth: auth)
                return
            }
            throw MediaServerError.httpStatus(408, "快速连接已超时，请重新尝试。")
        } catch is CancellationError {
            return
        } catch {
            guard generation == quickConnectGeneration else { return }
            errorMessage = error.localizedDescription
            quickConnectStatus = nil
        }
    }

    private func makeTemporaryClient(kind: MediaServerKind, baseURL: URL) -> MediaServerClient {
        let session = MediaServerClient.temporarySession(kind: kind, baseURL: baseURL, deviceID: accountStore.deviceID())
        return MediaServerClient(session: session)
    }

    private func finishAuthentication(
        kind: MediaServerKind,
        baseURL: URL,
        info: ServerInfo,
        auth: AuthenticationResponse
    ) throws {
        guard !auth.user.id.isEmpty, !auth.accessToken.isEmpty else {
            throw MediaServerError.invalidResponse
        }
        let authenticated = ServerSession(
            kind: kind,
            baseURL: baseURL,
            userID: auth.user.id,
            username: auth.user.name,
            serverName: auth.serverName ?? info.serverName,
            serverVersion: info.version,
            deviceID: accountStore.deviceID(),
            accessToken: auth.accessToken
        )
        try accountStore.save(authenticated)
        activate(authenticated)
        Task { await refreshHome() }
    }

    private func activate(_ session: ServerSession) {
        self.session = session
        client = MediaServerClient(session: session)
        phase = .signedIn
        quickConnectCode = nil
        quickConnectStatus = nil
    }
}

private struct PreviewTokenStore: TokenStoring {
    func read() throws -> String? { nil }
    func write(_ value: String) throws {}
    func delete() throws {}
}
