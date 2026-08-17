import Foundation

/// 对应 Dart CloudSyncBackend（lib/core/sync/cloud_sync_backend.dart）。
///
/// 协议化是为了测试能塞内存实现，不需要真的 WebDAV 服务器。
public struct CloudSyncDocument: Equatable, Sendable {
    public let data: Data
    public let revision: String?

    public init(data: Data, revision: String?) {
        self.data = data
        self.revision = revision
    }
}

public protocol CloudSyncBackend: Sendable {
    /// 可读返回 true。false = 凭证错或网络不通。
    func healthCheck() async -> Bool

    /// 读 manifest.json 及同一 GET 响应里的 ETag。不存在返回 nil。
    func readManifestDocument() async throws -> CloudSyncDocument?

    /// ETag 未变化时才写入；412/409 冲突返回 false，绝不覆盖新版本。
    func writeManifestIfUnchanged(
        _ manifest: SyncManifest,
        expected: CloudSyncDocument?
    ) async throws -> Bool

    /// 读模块数据及同一 GET 响应里的 ETag。不存在返回 nil。
    func readModuleDocument(_ key: String) async throws -> CloudSyncDocument?

    /// ETag 未变化时才写入；412/409 冲突返回 false，绝不覆盖新版本。
    func writeModuleIfUnchanged(
        _ key: String,
        data: Data,
        expected: CloudSyncDocument?
    ) async throws -> Bool
}

public extension CloudSyncBackend {
    func readManifest() async throws -> SyncManifest {
        guard let document = try await readManifestDocument() else {
            return SyncManifest()
        }
        return try JSONDecoder().decode(SyncManifest.self, from: document.data)
    }

    func readModule(_ key: String) async throws -> Data? {
        (try await readModuleDocument(key))?.data
    }
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

    public func readManifestDocument() async throws -> CloudSyncDocument? {
        try await read(name: "manifest.json")
    }

    public func writeManifestIfUnchanged(
        _ manifest: SyncManifest,
        expected: CloudSyncDocument?
    ) async throws -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try await write(
            name: "manifest.json",
            data: try encoder.encode(manifest),
            expected: expected
        )
    }

    public func readModuleDocument(_ key: String) async throws -> CloudSyncDocument? {
        try await read(name: "\(key).json")
    }

    public func writeModuleIfUnchanged(
        _ key: String,
        data: Data,
        expected: CloudSyncDocument?
    ) async throws -> Bool {
        try await write(name: "\(key).json", data: data, expected: expected)
    }

    // MARK: - HTTP

    private func read(name: String) async throws -> CloudSyncDocument? {
        let request = try makeRequest(path: path(for: name), method: "GET")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CloudSyncError.invalidResponse(path: name)
        }
        let code = response.statusCode
        if code == 404 || code == 410 { return nil }
        guard (200..<300).contains(code) else {
            throw CloudSyncError.httpStatus(code: code, path: name)
        }
        return CloudSyncDocument(
            data: data,
            revision: response.value(forHTTPHeaderField: "ETag")
        )
    }

    private func write(
        name: String,
        data: Data,
        expected: CloudSyncDocument?
    ) async throws -> Bool {
        // 目录可能还不存在。先建；已存在的 301 / 405 在 makeCollection 内处理。
        try await makeCollection()

        var request = try makeRequest(path: path(for: name), method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let expected {
            guard let revision = expected.revision, !revision.isEmpty else {
                throw CloudSyncError.missingEntityTag(path: name)
            }
            request.setValue(revision, forHTTPHeaderField: "If-Match")
        } else {
            request.setValue("*", forHTTPHeaderField: "If-None-Match")
        }
        let (_, response) = try await session.upload(for: request, from: data)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 409 || code == 412 { return false }
        guard (200..<300).contains(code) else {
            throw CloudSyncError.httpStatus(code: code, path: name)
        }
        return true
    }

    private func makeCollection() async throws {
        let request = try makeRequest(path: rootPath, method: "MKCOL")
        let (_, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) || code == 301 || code == 405 else {
            throw CloudSyncError.httpStatus(code: code, path: rootPath)
        }
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
    case invalidResponse(path: String)
    case missingEntityTag(path: String)
    case httpStatus(code: Int, path: String)
    case remoteModuleMissing(key: String)
    case concurrentRemoteChange(key: String)
}
