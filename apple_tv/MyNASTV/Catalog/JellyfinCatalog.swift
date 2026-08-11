import Foundation

/// Jellyfin / Emby 目录。
///
/// 两家的 REST 接口在这个子集上是同构的，只有认证头名字不同，
/// 所以共用一个实现，靠 `flavor` 切头。与 Flutter 端把两者分成两个 adapter
/// 的做法不同 —— 那边还要处理各自独有的能力，这里只用到公共子集。
///
/// 层级和 videoPath 都跟着 Flutter 的虚拟文件系统走：
/// `/<库名>/<剧集>/<季>/S01E01 <标题>`
public struct JellyfinCatalog: VideoCatalog {
    public enum Flavor: Sendable {
        case jellyfin
        case emby

        var tokenHeader: String {
            switch self {
            // Jellyfin 也认 X-Emby-Token，但按各自官方的头更稳
            case .jellyfin: return "X-MediaBrowser-Token"
            case .emby: return "X-Emby-Token"
            }
        }
    }

    private let baseURL: URL
    private let token: String
    private let userID: String
    private let flavor: Flavor
    private let session: URLSession

    public init(
        baseURL: URL,
        token: String,
        userID: String,
        flavor: Flavor,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.token = token
        self.userID = userID
        self.flavor = flavor
        self.session = session
    }

    public func list(path: String) async throws -> [CatalogItem] {
        let segments = path.split(separator: "/").map(String.init)
        if segments.isEmpty { return try await listLibraries() }
        return try await listChildren(path: path, segments: segments)
    }

    public func playbackURL(for item: CatalogItem) async throws -> URL {
        guard !item.isDirectory, let id = item.serverItemID else {
            throw CatalogError.notPlayable
        }
        // static=true 请求直出原文件，不转码。tvOS 解不了的容器会在播放器侧报错，
        // v1 不做服务端转码协商（Flutter 端有，tvOS 版留到后续）。
        return try makeURL(
            path: "/Videos/\(id)/stream",
            query: [("static", "true"), ("api_key", token)]
        )
    }

    // MARK: - 层级

    private func listLibraries() async throws -> [CatalogItem] {
        let url = try makeURL(path: "/Users/\(userID)/Views", query: [])
        let result: ItemsResponse = try await get(url)
        return result.items.map { item in
            CatalogItem(
                // 库层不 sanitize，与 Flutter 一致
                videoPath: CatalogPath.library(item.name),
                name: item.name,
                isDirectory: true,
                thumbnailURL: imageURL(for: item.id)
            )
        }
    }

    private func listChildren(path: String, segments: [String]) async throws -> [CatalogItem] {
        guard let parentID = try await resolveID(segments: segments) else { return [] }

        let url = try makeURL(
            path: "/Users/\(userID)/Items",
            query: [
                ("ParentId", parentID),
                ("SortBy", "SortName"),
                ("SortOrder", "Ascending"),
                ("Fields", "MediaSources,ParentIndexNumber,IndexNumber"),
            ]
        )
        let result: ItemsResponse = try await get(url)

        return result.items.compactMap { item in
            switch item.type {
            case "Episode":
                return CatalogItem(
                    videoPath: CatalogPath.episode(
                        of: path,
                        seasonNumber: item.parentIndexNumber,
                        episodeNumber: item.indexNumber,
                        title: item.name
                    ),
                    name: item.name,
                    isDirectory: false,
                    thumbnailURL: imageURL(for: item.id),
                    serverItemID: item.id
                )
            case "Movie", "Video":
                return CatalogItem(
                    videoPath: CatalogPath.child(of: path, name: item.name),
                    name: item.name,
                    isDirectory: false,
                    thumbnailURL: imageURL(for: item.id),
                    serverItemID: item.id
                )
            case "Series", "Season", "Folder", "CollectionFolder", "BoxSet":
                return CatalogItem(
                    videoPath: CatalogPath.child(of: path, name: item.name),
                    name: item.name,
                    isDirectory: true,
                    thumbnailURL: imageURL(for: item.id)
                )
            default:
                // 音乐 / 图片等非视频类型直接不显示
                return nil
            }
        }
    }

    /// 路径 → itemId。逐段列目录比对名称。
    ///
    /// Flutter 端有 _pathToIdCache，这里每次重新解析：tvOS 上层级浅、
    /// 请求次数可接受，省掉一份需要失效管理的缓存。
    private func resolveID(segments: [String]) async throws -> String? {
        let libraries = try await libraryIndex()
        guard var currentID = libraries[segments[0]] else { return nil }
        guard segments.count > 1 else { return currentID }

        for segment in segments.dropFirst() {
            let url = try makeURL(
                path: "/Users/\(userID)/Items",
                query: [("ParentId", currentID), ("Fields", "ParentIndexNumber,IndexNumber")]
            )
            let result: ItemsResponse = try await get(url)
            let match = result.items.first { item in
                if item.type == "Episode" {
                    let season = String(format: "%02d", item.parentIndexNumber ?? 1)
                    let episode = String(format: "%02d", item.indexNumber ?? 1)
                    return CatalogPath.sanitize("S\(season)E\(episode) \(item.name)") == segment
                }
                return CatalogPath.sanitize(item.name) == segment
            }
            guard let match else { return nil }
            currentID = match.id
        }
        return currentID
    }

    private func libraryIndex() async throws -> [String: String] {
        let url = try makeURL(path: "/Users/\(userID)/Views", query: [])
        let result: ItemsResponse = try await get(url)
        return Dictionary(result.items.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
    }

    private func imageURL(for itemID: String) -> URL? {
        try? makeURL(
            path: "/Items/\(itemID)/Images/Primary",
            query: [("maxWidth", "480"), ("api_key", token)]
        )
    }

    // MARK: - HTTP

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: flavor.tokenHeader)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw CatalogError.badResponse(status: status)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func makeURL(path: String, query: [(String, String)]) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            throw CatalogError.malformedResponse
        }
        let prefix = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = prefix + path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else { throw CatalogError.malformedResponse }
        return url
    }

    // MARK: - 响应模型

    private struct ItemsResponse: Decodable {
        let items: [Item]

        private enum Key: String, CodingKey { case items = "Items" }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            items = (try? container.decodeIfPresent([Item].self, forKey: .items))
                .flatMap { $0 } ?? []
        }
    }

    private struct Item: Decodable {
        let id: String
        let name: String
        let type: String
        let indexNumber: Int?
        let parentIndexNumber: Int?

        private enum Key: String, CodingKey {
            case id = "Id"
            case name = "Name"
            case type = "Type"
            case indexNumber = "IndexNumber"
            case parentIndexNumber = "ParentIndexNumber"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            id = try container.decode(String.self, forKey: .id)
            // 极少数条目没有 Name，给空串而不是整条失败
            name = (try? container.decodeIfPresent(String.self, forKey: .name)).flatMap { $0 } ?? ""
            type = (try? container.decodeIfPresent(String.self, forKey: .type)).flatMap { $0 } ?? ""
            indexNumber = try? container.decodeIfPresent(Int.self, forKey: .indexNumber)
            parentIndexNumber = try? container.decodeIfPresent(Int.self, forKey: .parentIndexNumber)
        }
    }
}
