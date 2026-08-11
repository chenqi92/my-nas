import Foundation

enum MediaServerError: LocalizedError, Equatable {
    case invalidAddress
    case missingSession
    case invalidResponse
    case httpStatus(Int, String)
    case noPlayableSource

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "服务器地址无效，请输入完整的 HTTP 或 HTTPS 地址。"
        case .missingSession:
            return "登录状态已失效，请重新连接服务器。"
        case .invalidResponse:
            return "服务器返回了无法识别的数据。"
        case .httpStatus(let status, let message):
            return message.isEmpty ? "服务器请求失败（HTTP \(status)）" : message
        case .noPlayableSource:
            return "服务器没有返回 Apple TV 可播放或可转码的媒体源。"
        }
    }
}

final class MediaServerClient {
    static let appVersion = "1.2.3"

    private(set) var session: ServerSession
    private let urlSession: URLSession
    private let decoder = JSONDecoder()

    init(session: ServerSession, urlSession: URLSession = .shared) {
        self.session = session
        self.urlSession = urlSession
    }

    static func normalizedBaseURL(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MediaServerError.invalidAddress }
        let candidate = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            throw MediaServerError.invalidAddress
        }
        components.path = components.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard let url = components.url else { throw MediaServerError.invalidAddress }
        return url
    }

    static func temporarySession(kind: MediaServerKind, baseURL: URL, deviceID: String) -> ServerSession {
        ServerSession(
            kind: kind,
            baseURL: baseURL,
            userID: "",
            username: "",
            serverName: kind.title,
            serverVersion: "",
            deviceID: deviceID,
            accessToken: ""
        )
    }

    static func authorizationHeader(kind: MediaServerKind, deviceID: String, token: String?) -> (name: String, value: String) {
        var parts = [
            "Client=\"KKNas\"",
            "Device=\"Apple TV\"",
            "DeviceId=\"\(deviceID)\"",
            "Version=\"\(appVersion)\"",
        ]
        if let token, !token.isEmpty {
            parts.append("Token=\"\(token)\"")
        }
        let name = kind == .emby ? "X-Emby-Authorization" : "Authorization"
        return (name, "MediaBrowser \(parts.joined(separator: ", "))")
    }

    func publicServerInfo() async throws -> ServerInfo {
        try await request(path: "/System/Info/Public", authenticated: false)
    }

    func authenticate(username: String, password: String) async throws -> AuthenticationResponse {
        try await request(
            path: "/Users/AuthenticateByName",
            method: "POST",
            body: ["Username": username, "Pw": password],
            authenticated: false
        )
    }

    func initiateQuickConnect() async throws -> QuickConnectState {
        try await request(path: "/QuickConnect/Initiate", method: "POST", authenticated: false)
    }

    func quickConnectState(secret: String) async throws -> QuickConnectState {
        try await request(
            path: "/QuickConnect/Connect",
            query: [URLQueryItem(name: "Secret", value: secret)],
            authenticated: false
        )
    }

    func authenticateWithQuickConnect(secret: String) async throws -> AuthenticationResponse {
        try await request(
            path: "/Users/AuthenticateWithQuickConnect",
            method: "POST",
            body: ["Secret": secret],
            authenticated: false
        )
    }

    func libraries() async throws -> [MediaLibrary] {
        try requireSignedIn()
        let response: LibrariesResponse = try await request(path: "/Users/\(session.userID)/Views")
        return response.items
    }

    func items(
        parentID: String? = nil,
        searchTerm: String? = nil,
        includeTypes: [String] = ["Movie", "Series", "Episode", "Video"],
        limit: Int = 100,
        startIndex: Int = 0,
        sortBy: String = "SortName",
        sortOrder: String = "Ascending"
    ) async throws -> ItemsResponse {
        try requireSignedIn()
        var query = commonItemQuery(limit: limit)
        query.append(URLQueryItem(name: "StartIndex", value: String(startIndex)))
        query.append(URLQueryItem(name: "Recursive", value: "true"))
        query.append(URLQueryItem(name: "IncludeItemTypes", value: includeTypes.joined(separator: ",")))
        query.append(URLQueryItem(name: "SortBy", value: sortBy))
        query.append(URLQueryItem(name: "SortOrder", value: sortOrder))
        if let parentID { query.append(URLQueryItem(name: "ParentId", value: parentID)) }
        if let searchTerm, !searchTerm.isEmpty {
            query.append(URLQueryItem(name: "SearchTerm", value: searchTerm))
        }
        return try await request(path: "/Users/\(session.userID)/Items", query: query)
    }

    func latest(limit: Int = 30) async throws -> [MediaItem] {
        try requireSignedIn()
        var query = commonItemQuery(limit: limit)
        query.append(URLQueryItem(name: "IncludeItemTypes", value: "Movie,Series,Episode,Video"))
        let data = try await dataRequest(path: "/Users/\(session.userID)/Items/Latest", query: query)
        return try decoder.decode([MediaItem].self, from: data)
    }

    func resume(limit: Int = 24) async throws -> [MediaItem] {
        try requireSignedIn()
        var query = commonItemQuery(limit: limit)
        query.append(URLQueryItem(name: "MediaTypes", value: "Video"))
        let response: ItemsResponse = try await request(path: "/Users/\(session.userID)/Items/Resume", query: query)
        return response.items
    }

    func detail(itemID: String) async throws -> MediaItem {
        try requireSignedIn()
        return try await request(
            path: "/Users/\(session.userID)/Items/\(itemID)",
            query: [URLQueryItem(name: "Fields", value: requestedFields)]
        )
    }

    func seasons(seriesID: String) async throws -> [MediaItem] {
        try requireSignedIn()
        let response: ItemsResponse = try await request(
            path: "/Shows/\(seriesID)/Seasons",
            query: [
                URLQueryItem(name: "UserId", value: session.userID),
                URLQueryItem(name: "Fields", value: requestedFields),
            ]
        )
        return response.items
    }

    func episodes(seriesID: String, seasonID: String?) async throws -> [MediaItem] {
        try requireSignedIn()
        var query = [
            URLQueryItem(name: "UserId", value: session.userID),
            URLQueryItem(name: "Fields", value: requestedFields),
        ]
        if let seasonID { query.append(URLQueryItem(name: "SeasonId", value: seasonID)) }
        let response: ItemsResponse = try await request(path: "/Shows/\(seriesID)/Episodes", query: query)
        return response.items
    }

    func imageURL(itemID: String, type: String = "Primary", maxWidth: Int = 640, tag: String? = nil) -> URL? {
        var query = [
            URLQueryItem(name: "maxWidth", value: String(maxWidth)),
            URLQueryItem(name: "quality", value: "90"),
        ]
        if let tag { query.append(URLQueryItem(name: "tag", value: tag)) }
        if !session.accessToken.isEmpty {
            query.append(URLQueryItem(name: "api_key", value: session.accessToken))
        }
        return try? buildURL(path: "/Items/\(itemID)/Images/\(type)", query: query)
    }

    func playbackPlan(item: MediaItem, preferDirectPlay: Bool, maxBitrate: Int) async throws -> PlaybackPlan {
        try requireSignedIn()
        let info: PlaybackInfo = try await request(
            path: "/Items/\(item.id)/PlaybackInfo",
            method: "POST",
            query: [URLQueryItem(name: "UserId", value: session.userID)],
            body: ["DeviceProfile": TVDeviceProfile.payload(maxBitrate: maxBitrate)]
        )
        guard let source = info.mediaSources.first else { throw MediaServerError.noPlayableSource }
        let playSessionID = info.playSessionID ?? UUID().uuidString

        if item.type == "Audio", source.supportsDirectPlay,
           let url = directStreamURL(itemID: item.id, sourceID: source.id, isAudio: true) {
            return PlaybackPlan(url: url, method: .directPlay, playSessionID: playSessionID, mediaSourceID: source.id)
        }

        if preferDirectPlay,
           source.supportsDirectPlay,
           TVDeviceProfile.supportsDirectPlay(container: source.container),
           let url = directStreamURL(itemID: item.id, sourceID: source.id, isAudio: false) {
            return PlaybackPlan(url: url, method: .directPlay, playSessionID: playSessionID, mediaSourceID: source.id)
        }

        if source.supportsDirectStream,
           let value = source.directStreamURL,
           let url = authenticatedMediaURL(value) {
            return PlaybackPlan(url: url, method: .directStream, playSessionID: playSessionID, mediaSourceID: source.id)
        }

        if source.supportsTranscoding,
           let value = source.transcodingURL,
           let url = authenticatedMediaURL(value) {
            return PlaybackPlan(url: url, method: .transcode, playSessionID: playSessionID, mediaSourceID: source.id)
        }

        if source.supportsTranscoding,
           let url = fallbackHLSURL(itemID: item.id, sourceID: source.id, playSessionID: playSessionID, maxBitrate: maxBitrate) {
            return PlaybackPlan(url: url, method: .transcode, playSessionID: playSessionID, mediaSourceID: source.id)
        }

        throw MediaServerError.noPlayableSource
    }

    func reportPlaybackStart(itemID: String, plan: PlaybackPlan, positionTicks: Int64) async throws {
        try await sendPlaybackReport(
            path: "/Sessions/Playing",
            itemID: itemID,
            plan: plan,
            positionTicks: positionTicks,
            isPaused: false
        )
    }

    func reportPlaybackProgress(itemID: String, plan: PlaybackPlan, positionTicks: Int64, isPaused: Bool) async throws {
        try await sendPlaybackReport(
            path: "/Sessions/Playing/Progress",
            itemID: itemID,
            plan: plan,
            positionTicks: positionTicks,
            isPaused: isPaused
        )
    }

    func reportPlaybackStopped(itemID: String, plan: PlaybackPlan, positionTicks: Int64) async throws {
        try await sendPlaybackReport(
            path: "/Sessions/Playing/Stopped",
            itemID: itemID,
            plan: plan,
            positionTicks: positionTicks,
            isPaused: true
        )
    }

    func logout() async {
        try? await send(path: "/Sessions/Logout", method: "POST")
    }

    private var requestedFields: String {
        "Overview,Genres,MediaStreams,MediaSources,ProviderIds,PrimaryImageAspectRatio,DateCreated"
    }

    private func commonItemQuery(limit: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: requestedFields),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "ImageTypeLimit", value: "1"),
        ]
    }

    private func sendPlaybackReport(
        path: String,
        itemID: String,
        plan: PlaybackPlan,
        positionTicks: Int64,
        isPaused: Bool
    ) async throws {
        try await send(
            path: path,
            method: "POST",
            body: [
                "ItemId": itemID,
                "MediaSourceId": plan.mediaSourceID,
                "PlaySessionId": plan.playSessionID,
                "PlayMethod": plan.method.rawValue,
                "PositionTicks": positionTicks,
                "CanSeek": true,
                "IsPaused": isPaused,
                "IsMuted": false,
            ]
        )
    }

    private func directStreamURL(itemID: String, sourceID: String, isAudio: Bool) -> URL? {
        let mediaPath = isAudio ? "Audio" : "Videos"
        return try? buildURL(
            path: "/\(mediaPath)/\(itemID)/stream",
            query: [
                URLQueryItem(name: "static", value: "true"),
                URLQueryItem(name: "MediaSourceId", value: sourceID),
                URLQueryItem(name: "api_key", value: session.accessToken),
            ]
        )
    }

    private func fallbackHLSURL(itemID: String, sourceID: String, playSessionID: String, maxBitrate: Int) -> URL? {
        try? buildURL(
            path: "/Videos/\(itemID)/master.m3u8",
            query: [
                URLQueryItem(name: "MediaSourceId", value: sourceID),
                URLQueryItem(name: "PlaySessionId", value: playSessionID),
                URLQueryItem(name: "DeviceId", value: session.deviceID),
                URLQueryItem(name: "api_key", value: session.accessToken),
                URLQueryItem(name: "VideoCodec", value: "h264"),
                URLQueryItem(name: "AudioCodec", value: "aac"),
                URLQueryItem(name: "MaxStreamingBitrate", value: String(maxBitrate)),
                URLQueryItem(name: "SegmentContainer", value: "ts"),
                URLQueryItem(name: "MinSegments", value: "2"),
                URLQueryItem(name: "BreakOnNonKeyFrames", value: "true"),
            ]
        )
    }

    private func authenticatedMediaURL(_ value: String) -> URL? {
        let rawURL: URL
        if let absolute = URL(string: value), absolute.scheme != nil {
            rawURL = absolute
        } else {
            guard let relative = URLComponents(string: value),
                  let resolved = try? buildURL(path: relative.path, query: relative.queryItems ?? []) else {
                return nil
            }
            rawURL = resolved
        }
        guard var components = URLComponents(url: rawURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let base = URLComponents(url: session.baseURL, resolvingAgainstBaseURL: false)
        let isSameOrigin = components.scheme?.lowercased() == base?.scheme?.lowercased()
            && components.host?.lowercased() == base?.host?.lowercased()
            && components.port == base?.port
        guard isSameOrigin else { return rawURL }

        var query = components.queryItems ?? []
        if !query.contains(where: { ["api_key", "access_token"].contains($0.name.lowercased()) }) {
            query.append(URLQueryItem(name: "api_key", value: session.accessToken))
        }
        components.queryItems = query
        return components.url
    }

    private func requireSignedIn() throws {
        guard !session.userID.isEmpty, !session.accessToken.isEmpty else {
            throw MediaServerError.missingSession
        }
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        let data = try await dataRequest(
            path: path,
            method: method,
            query: query,
            body: body,
            authenticated: authenticated
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MediaServerError.invalidResponse
        }
    }

    private func send(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil
    ) async throws {
        _ = try await dataRequest(path: path, method: method, query: query, body: body)
    }

    private func dataRequest(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        authenticated: Bool = true
    ) async throws -> Data {
        var request = URLRequest(url: try buildURL(path: path, query: query))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = authenticated ? session.accessToken : nil
        let auth = Self.authorizationHeader(kind: session.kind, deviceID: session.deviceID, token: token)
        request.setValue(auth.value, forHTTPHeaderField: auth.name)
        if authenticated, !session.accessToken.isEmpty {
            request.setValue(session.accessToken, forHTTPHeaderField: "X-Emby-Token")
        }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaServerError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MediaServerError.httpStatus(httpResponse.statusCode, serverMessage(from: data))
        }
        return data
    }

    private func buildURL(path: String, query: [URLQueryItem]) throws -> URL {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(url: session.baseURL, resolvingAgainstBaseURL: false) else {
            throw MediaServerError.invalidAddress
        }
        let basePath = components.percentEncodedPath
        let allowedPathSegment = CharacterSet.urlPathAllowed.subtracting(
            CharacterSet(charactersIn: "/?#")
        )
        let encodedPath = cleanPath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                String(segment).addingPercentEncoding(withAllowedCharacters: allowedPathSegment)
                    ?? String(segment)
            }
            .joined(separator: "/")
        components.percentEncodedPath = basePath == "/" || basePath.isEmpty
            ? "/\(encodedPath)"
            : "\(basePath)/\(encodedPath)"
        components.queryItems = query.isEmpty ? nil : query
        guard let result = components.url else { throw MediaServerError.invalidAddress }
        return result
    }

    private func serverMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        return (object["Message"] as? String) ?? (object["message"] as? String) ?? ""
    }
}
