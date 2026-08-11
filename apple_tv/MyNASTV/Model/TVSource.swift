import Foundation

/// tvOS v1 支持的源类型。
///
/// 只收 HTTP 系。SMB / FTP / SFTP / NFS 需要额外的协议栈，tvOS 上没有可直接用的
/// 系统实现，v1 不做（UI 里也不给入口，而不是给了之后报错）。
///
/// `rawValue` 与 Flutter 端 SourceType.id 完全一致
/// （lib/features/sources/domain/entities/source_entity.dart:14），
/// 手工在两端各填一次配置时不会因为类型名不同而对不上。
public enum TVSourceType: String, CaseIterable, Codable, Sendable {
    case webdav
    case jellyfin
    case emby
    case plex

    public var displayName: String {
        switch self {
        case .webdav: return "WebDAV"
        case .jellyfin: return "Jellyfin"
        case .emby: return "Emby"
        case .plex: return "Plex"
        }
    }

    /// 该类型用哪种凭证。决定表单显示密码框还是 token 框。
    public var usesToken: Bool {
        switch self {
        case .webdav: return false
        case .jellyfin, .emby, .plex: return true
        }
    }
}

/// 一个已配置的源。
///
/// **不含任何密钥字段** —— 密码 / token 只存 Keychain（见 KeychainCredentialStore），
/// 由 id 关联。这个结构本身可以安全地写进 UserDefaults。
public struct TVSource: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var type: TVSourceType
    /// 完整基址，含 scheme 和端口，例如 `https://nas.example:5006`。
    /// 不在代码里放任何默认地址（合规要求：不硬编码第三方 URL）。
    public var baseURL: URL
    public var username: String
    /// WebDAV 源的媒体根目录；媒体服务器类型忽略此字段
    public var rootPath: String
    /// 该源是否参与云同步的 WebDAV 后端角色（只有 WebDAV 类型可以）
    public var isSyncBackend: Bool
    public var syncRootPath: String

    public init(
        id: UUID = UUID(),
        name: String,
        type: TVSourceType,
        baseURL: URL,
        username: String = "",
        rootPath: String = "/",
        isSyncBackend: Bool = false,
        syncRootPath: String = "/my-nas-sync"
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.baseURL = baseURL
        self.username = username
        self.rootPath = rootPath
        self.isSyncBackend = isSyncBackend
        self.syncRootPath = syncRootPath
    }
}
