import Foundation

/// Plex 目录。
///
/// ⚠️ videoPath 规则和 Jellyfin/Emby **不一样**，这不是笔误。
/// Flutter 端 plex_virtual_fs.dart 每一层都是 `'/${item.title}'`（:225 / :237 / :251），
/// 也就是**扁平**命名：一集的 path 是 `/凛冬将至`，不带剧名和季。
/// Jellyfin 那边才是 `/<库>/<剧>/<季>/S01E01 <标题>` 的层级路径。
///
/// 这里照抄扁平规则。它有个已知后果：不同剧里同名的集会共用同一条进度
/// （已记在 README 的已知问题里）。tvOS 端不能自作主张改成层级 ——
/// 改了就和 Flutter 端的键失配，两端进度各存一份、永远同步不上。
public struct PlexCatalog: VideoCatalog {
    private let baseURL: URL
    private let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    public func list(path: String) async throws -> [CatalogItem] {
        let segments = path.split(separator: "/").map(String.init)
        if segments.isEmpty { return try await listLibraries() }

        guard let key = try await resolveKey(segments: segments) else { return [] }
        if let libraryKey = key.libraryKey {
            return try await items(at: "/library/sections/\(libraryKey)/all")
        }
        return try await items(at: "/library/metadata/\(key.ratingKey ?? "")/children")
    }

    public func playbackURL(for item: CatalogItem) async throws -> URL {
        guard !item.isDirectory, let ratingKey = item.serverItemID else {
            throw CatalogError.notPlayable
        }
        // 取 part.key 后直出原文件。Plex 的 transcode 协商 v1 不做。
        let metadata = try await fetch(path: "/library/metadata/\(ratingKey)")
        guard let partKey = metadata.items.first?.partKey else {
            throw CatalogError.notPlayable
        }
        // Plex 只认 query 里的 token，没有等价的请求头，这一处只能放进 URL
        return try makeURL(path: partKey, query: [("X-Plex-Token", token)])
    }

    // MARK: - 层级

    private func listLibraries() async throws -> [CatalogItem] {
        let response = try await fetch(path: "/library/sections")
        return response.items
            // 只要视频类库，photo / artist 不显示
            .filter { $0.type == "movie" || $0.type == "show" }
            .map { library in
                CatalogItem(
                    videoPath: CatalogPath.library(library.title),
                    name: library.title,
                    isDirectory: true
                )
            }
    }

    private func items(at path: String) async throws -> [CatalogItem] {
        let response = try await fetch(path: path)
        return response.items.map { item in
            let isPlayable = item.type == "movie" || item.type == "episode"
            return CatalogItem(
                // 扁平：直接 /<title>，不拼父路径。见类型注释。
                videoPath: "/\(item.title)",
                name: item.title,
                isDirectory: !isPlayable,
                thumbnailURL: item.thumb.flatMap { thumb in
                    try? makeURL(path: thumb, query: [("X-Plex-Token", token)])
                },
                serverItemID: item.ratingKey
            )
        }
    }

    private struct ResolvedKey {
        var libraryKey: String?
        var ratingKey: String?
    }

    /// 路径 → library key 或 ratingKey。
    ///
    /// 因为路径是扁平的，只能按「第一段是库名，其后逐段在当前层找同名条目」解析。
    private func resolveKey(segments: [String]) async throws -> ResolvedKey? {
        let libraries = try await fetch(path: "/library/sections")
        guard let library = libraries.items.first(where: { $0.title == segments[0] }),
              let libraryKey = library.key
        else { return nil }

        if segments.count == 1 { return ResolvedKey(libraryKey: libraryKey) }

        var current = try await fetch(path: "/library/sections/\(libraryKey)/all")
        var ratingKey: String?
        for segment in segments.dropFirst() {
            guard let match = current.items.first(where: { $0.title == segment }),
                  let key = match.ratingKey
            else { return nil }
            ratingKey = key
            current = try await fetch(path: "/library/metadata/\(key)/children")
        }
        return ResolvedKey(ratingKey: ratingKey)
    }

    // MARK: - HTTP

    private func fetch(path: String) async throws -> PlexResponse {
        var request = URLRequest(url: try makeURL(path: path, query: []))
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        // 不加这个头 Plex 返回 XML
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw CatalogError.badResponse(status: status)
        }
        return try JSONDecoder().decode(PlexResponse.self, from: data)
    }

    private func makeURL(path: String, query: [(String, String)]) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            throw CatalogError.malformedResponse
        }
        let prefix = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = prefix + (path.hasPrefix("/") ? path : "/\(path)")
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else { throw CatalogError.malformedResponse }
        return url
    }

    // MARK: - 响应模型

    private struct PlexResponse: Decodable {
        let items: [Item]

        private enum Root: String, CodingKey { case mediaContainer = "MediaContainer" }
        private enum Container: String, CodingKey {
            case metadata = "Metadata"
            case directory = "Directory"
        }

        init(from decoder: Decoder) throws {
            let root = try decoder.container(keyedBy: Root.self)
            let container = try root.nestedContainer(keyedBy: Container.self, forKey: .mediaContainer)
            // 库列表在 Directory，媒体条目在 Metadata。两个都收。
            let metadata = (try? container.decodeIfPresent([Item].self, forKey: .metadata))
                .flatMap { $0 } ?? []
            let directory = (try? container.decodeIfPresent([Item].self, forKey: .directory))
                .flatMap { $0 } ?? []
            items = metadata + directory
        }
    }

    private struct Item: Decodable {
        let title: String
        let type: String
        let ratingKey: String?
        /// 库列表里是 section key
        let key: String?
        let thumb: String?
        /// Media[0].Part[0].key，播放地址
        let partKey: String?

        private enum Key: String, CodingKey {
            case title, type, ratingKey, key, thumb
            case media = "Media"
        }

        private struct Media: Decodable {
            let parts: [Part]?
            private enum Key: String, CodingKey { case parts = "Part" }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: Key.self)
                parts = try? container.decodeIfPresent([Part].self, forKey: .parts)
            }
        }

        private struct Part: Decodable {
            let key: String?
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            title = (try? container.decodeIfPresent(String.self, forKey: .title))
                .flatMap { $0 } ?? ""
            type = (try? container.decodeIfPresent(String.self, forKey: .type))
                .flatMap { $0 } ?? ""
            // ratingKey 有时是数字有时是字符串，两种都收
            if let value = try? container.decodeIfPresent(String.self, forKey: .ratingKey) {
                ratingKey = value
            } else if let value = try? container.decodeIfPresent(Int.self, forKey: .ratingKey) {
                ratingKey = String(value)
            } else {
                ratingKey = nil
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: .key) {
                key = value
            } else if let value = try? container.decodeIfPresent(Int.self, forKey: .key) {
                key = String(value)
            } else {
                key = nil
            }
            thumb = try? container.decodeIfPresent(String.self, forKey: .thumb)
            let media = (try? container.decodeIfPresent([Media].self, forKey: .media)).flatMap { $0 }
            partKey = media?.first?.parts?.first?.key
        }
    }
}
