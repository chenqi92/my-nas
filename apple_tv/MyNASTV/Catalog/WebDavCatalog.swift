import Foundation

/// WebDAV 目录：PROPFIND Depth:1 列目录，视频直接用带认证的 URL 播放。
public struct WebDavCatalog: VideoCatalog {
    private let baseURL: URL
    private let rootPath: String
    private let username: String
    private let password: String
    private let session: URLSession

    public init(
        baseURL: URL,
        rootPath: String,
        username: String,
        password: String,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.rootPath = rootPath
        self.username = username
        self.password = password
        self.session = session
    }

    public func list(path: String) async throws -> [CatalogItem] {
        let target = resolve(path)
        var request = URLRequest(url: try url(for: target))
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        // 只要这几个属性，少传一点 XML
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:resourcetype/><d:getcontentlength/><d:displayname/>
          </d:prop>
        </d:propfind>
        """.utf8)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw CatalogError.badResponse(status: status)
        }

        let entries = try WebDavPropfindParser.parse(data)
        return entries
            // PROPFIND Depth:1 的第一条是目录自身，按 href 去掉
            .filter { normalize($0.href) != normalize(target) }
            .filter { $0.isDirectory || VideoExtensions.isVideo($0.name) }
            .map { entry in
                CatalogItem(
                    videoPath: joined(path, entry.name),
                    name: entry.name,
                    isDirectory: entry.isDirectory,
                    size: entry.size
                )
            }
            .sorted { lhs, rhs in
                // 目录在前，其余按名称
                lhs.isDirectory == rhs.isDirectory
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : lhs.isDirectory
            }
    }

    public func playbackURL(for item: CatalogItem) async throws -> URL {
        guard !item.isDirectory else { throw CatalogError.notPlayable }
        // 凭证不放进 URL（会进日志、进 AVPlayer 的错误信息）。
        // 认证走 URLSession 的 challenge —— 见 PlaybackAuth。
        return try url(for: resolve(item.videoPath))
    }

    /// AVPlayer 需要的 Basic 认证头。播放器侧用 AVURLAsset 的
    /// `AVURLAssetHTTPHeaderFieldsKey` 或 resource loader 带上。
    public var authorizationHeader: String {
        let token = Data("\(username):\(password)".utf8).base64EncodedString()
        return "Basic \(token)"
    }

    // MARK: - 路径

    /// 目录里的相对路径 → 服务器上的绝对路径
    private func resolve(_ path: String) -> String {
        let base = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        if path == "/" || path.isEmpty { return base.isEmpty ? "/" : base }
        return base + (path.hasPrefix("/") ? path : "/\(path)")
    }

    private func joined(_ parent: String, _ name: String) -> String {
        parent == "/" ? "/\(name)" : "\(parent)/\(name)"
    }

    private func normalize(_ path: String) -> String {
        var value = path
        if let decoded = value.removingPercentEncoding { value = decoded }
        while value.count > 1, value.hasSuffix("/") { value = String(value.dropLast()) }
        return value
    }

    private func url(for absolutePath: String) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            throw CatalogError.malformedResponse
        }
        let prefix = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        // 用 path 赋值而非手工百分号编码：URLComponents 会正确处理中文和空格
        components.path = prefix + (absolutePath.hasPrefix("/") ? absolutePath : "/\(absolutePath)")
        guard let url = components.url else { throw CatalogError.malformedResponse }
        return url
    }
}

/// PROPFIND 响应解析。
///
/// 用 XMLParser 而不是正则：命名空间前缀各家不同（d: / D: / lp1: 都见过），
/// 正则匹配 `<d:response>` 在一半服务器上会漏。
struct WebDavPropfindParser: NSObject, XMLParserDelegate {
    struct Entry {
        var href: String = ""
        var name: String = ""
        var isDirectory: Bool = false
        var size: Int = 0
    }

    static func parse(_ data: Data) throws -> [Entry] {
        let delegate = WebDavPropfindParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        guard parser.parse() else { throw CatalogError.malformedResponse }
        return delegate.entries
    }

    private var entries: [Entry] = []
    private var current: Entry?
    private var text = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        text = ""
        switch elementName {
        case "response":
            current = Entry()
        case "collection":
            current?.isDirectory = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "href":
            current?.href = value
        case "displayname":
            if !value.isEmpty { current?.name = value }
        case "getcontentlength":
            current?.size = Int(value) ?? 0
        case "response":
            if var entry = current {
                // displayname 缺失时从 href 末段取，并解百分号编码
                if entry.name.isEmpty {
                    let trimmed = entry.href.hasSuffix("/")
                        ? String(entry.href.dropLast())
                        : entry.href
                    let last = trimmed.split(separator: "/").last.map(String.init) ?? ""
                    entry.name = last.removingPercentEncoding ?? last
                }
                if !entry.name.isEmpty { entries.append(entry) }
            }
            current = nil
        default:
            break
        }
        text = ""
    }
}
