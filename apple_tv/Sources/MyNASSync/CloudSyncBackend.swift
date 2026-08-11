import Foundation

/// 对应 Dart CloudSyncBackend（lib/core/sync/cloud_sync_backend.dart）。
///
/// 协议化是为了测试能塞内存实现，不需要真的 WebDAV 服务器。
public protocol CloudSyncBackend: Sendable {
    /// 可读返回 true。false = 凭证错或网络不通。
    func healthCheck() async -> Bool

    /// 读 manifest.json。不存在 / 读不到视为首次同步，返回空 manifest。
    func readManifest() async throws -> SyncManifest

    /// 覆盖 manifest.json
    func writeManifest(_ manifest: SyncManifest) async throws

    /// 读模块数据。不存在返回 nil。
    func readModule(_ key: String) async throws -> Data?

    /// 覆盖模块数据
    func writeModule(_ key: String, data: Data) async throws
}

/// WebDAV 实现。文件结构与 Flutter 端完全一致：
/// ```
/// /<rootPath>/manifest.json
/// /<rootPath>/<module-key>.json
/// ```
public actor WebDavCloudSyncBackend: CloudSyncBackend {
    public static let defaultRootPath = "/my-nas-sync"

    private let endpoint: URL
    private let rootPath: String
    private let authorization: String
    private let session: URLSession

    /// - Parameters:
    ///   - endpoint: WebDAV 根地址
    ///   - rootPath: 同步目录，默认 `/my-nas-sync`（与 Flutter 端默认值一致，
    ///               两端必须填同一个值才会同步到同一份文件）
    public init(
        endpoint: URL,
        username: String,
        password: String,
        rootPath: String = WebDavCloudSyncBackend.defaultRootPath,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.rootPath = rootPath
        self.session = session

        let token = Data("\(username):\(password)".utf8).base64EncodedString()
        authorization = "Basic \(token)"
    }

    public func healthCheck() async -> Bool {
        do {
            var request = try makeRequest(path: rootPath, method: "PROPFIND")
            request.setValue("0", forHTTPHeaderField: "Depth")
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 {
                // 目录还不存在：能建出来也算连通（首次同步）
                try await makeCollection()
                return true
            }
            return (200..<300).contains(code)
        } catch {
            return false
        }
    }

    public func readManifest() async throws -> SyncManifest {
        guard let data = try await read(name: "manifest.json") else { return SyncManifest() }
        // 坏 manifest 视为空：等价于首次同步，会重新推一次，不会丢本地数据。
        // 直接抛的话整轮同步停在这里，反而更糟。
        return (try? JSONDecoder().decode(SyncManifest.self, from: data)) ?? SyncManifest()
    }

    public func writeManifest(_ manifest: SyncManifest) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try await write(name: "manifest.json", data: try encoder.encode(manifest))
    }

    public func readModule(_ key: String) async throws -> Data? {
        try await read(name: "\(key).json")
    }

    public func writeModule(_ key: String, data: Data) async throws {
        try await write(name: "\(key).json", data: data)
    }

    // MARK: - HTTP

    private func read(name: String) async throws -> Data? {
        let request = try makeRequest(path: path(for: name), method: "GET")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 || code == 410 { return nil }
        guard (200..<300).contains(code) else {
            throw CloudSyncError.httpStatus(code: code, path: name)
        }
        return data.isEmpty ? nil : data
    }

    private func write(name: String, data: Data) async throws {
        // 目录可能还不存在。先建（已存在会返回 405，忽略），再 PUT。
        try? await makeCollection()

        var request = try makeRequest(path: path(for: name), method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: request, from: data)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw CloudSyncError.httpStatus(code: code, path: name)
        }
    }

    private func makeCollection() async throws {
        let request = try makeRequest(path: rootPath, method: "MKCOL")
        _ = try await session.data(for: request)
    }

    private func path(for name: String) -> String {
        let base = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        return "\(base)/\(name)"
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true) else {
            throw CloudSyncError.invalidEndpoint
        }
        // endpoint 自带的路径要保留（很多 NAS 的 WebDAV 挂在子路径上，如 /dav）
        let prefix = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = prefix + (path.hasPrefix("/") ? path : "/\(path)")

        guard let url = components.url else { throw CloudSyncError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        // 同步文件必须读到最新版本，不能吃缓存
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }
}

public enum CloudSyncError: Error, Equatable {
    case invalidEndpoint
    case httpStatus(code: Int, path: String)
}
