import Foundation

/// 目录里的一项（文件夹或视频）。
public struct CatalogItem: Identifiable, Equatable, Sendable {
    public var id: String { videoPath }

    /// 同步主键。**必须**和 Flutter 端为同一个视频算出的值逐字符相同，
    /// 否则两端的进度各存一份、永远对不上。构造规则见 CatalogPath。
    public var videoPath: String
    public var name: String
    public var isDirectory: Bool
    public var size: Int
    public var thumbnailURL: URL?
    /// 媒体服务器上的 item id / ratingKey，取播放地址时用
    public var serverItemID: String?

    public init(
        videoPath: String,
        name: String,
        isDirectory: Bool,
        size: Int = 0,
        thumbnailURL: URL? = nil,
        serverItemID: String? = nil
    ) {
        self.videoPath = videoPath
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.thumbnailURL = thumbnailURL
        self.serverItemID = serverItemID
    }
}

/// videoPath 构造规则，从 Flutter 端逐条搬过来。
///
/// 对应实现：
/// - lib/media_server_adapters/jellyfin/jellyfin_virtual_fs.dart:225（媒体库层）
/// - 同文件 :253（剧集 / 电影层）、:269（季层）、:293（集层）、:428（sanitize）
///
/// 改这里等于改同步主键：旧进度会全部失配。任何调整都要两端一起改。
public enum CatalogPath {
    /// Flutter `_sanitizeName`：替换 9 个字符为下划线。
    /// 注意**不包含**空格和点，也不做 trim —— 别顺手多加，多一个就失配。
    public static func sanitize(_ name: String) -> String {
        var result = name
        for bad in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"] {
            result = result.replacingOccurrences(of: bad, with: "_")
        }
        return result
    }

    /// 媒体库层：`/<库名>`。
    /// 库名**不过** sanitize（Flutter 侧这一层就是直接拼的）。
    public static func library(_ name: String) -> String {
        "/\(name)"
    }

    /// 库下的条目（电影 / 剧集 / 季）：`<父路径>/<sanitize(名称)>`
    public static func child(of parent: String, name: String) -> String {
        "\(parent)/\(sanitize(name))"
    }

    /// 集：`<季路径>/S01E01 <标题>`。
    /// 季号 / 集号缺失时分别落到 1，两位补零，**不带扩展名**。
    public static func episode(
        of seasonPath: String,
        seasonNumber: Int?,
        episodeNumber: Int?,
        title: String
    ) -> String {
        let season = String(format: "%02d", seasonNumber ?? 1)
        let episode = String(format: "%02d", episodeNumber ?? 1)
        return "\(seasonPath)/\(sanitize("S\(season)E\(episode) \(title)"))"
    }
}

/// 只读视频目录。
///
/// v1 不含写操作：tvOS 端不上传、不删除、不改名。
/// 与 Flutter 端媒体服务器虚拟文件系统的只读约定一致。
public protocol VideoCatalog: Sendable {
    /// 列目录。`path` 为 "/" 表示根。
    func list(path: String) async throws -> [CatalogItem]

    /// 取可直接喂给 AVPlayer 的播放地址。
    func playbackURL(for item: CatalogItem) async throws -> URL
}

public enum CatalogError: Error, Equatable {
    case notPlayable
    case badResponse(status: Int)
    case malformedResponse
    case missingCredential
}

/// 视频扩展名白名单。AVPlayer 实际能播的比这个少（见 README 的容器说明），
/// 但列表阶段先按扩展名过滤，能不能解码交给播放器报错。
public enum VideoExtensions {
    public static let all: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "avi", "wmv", "flv", "webm",
        "ts", "m2ts", "mts", "mpg", "mpeg", "rmvb", "3gp", "vob", "iso",
    ]

    public static func isVideo(_ name: String) -> Bool {
        guard let ext = name.split(separator: ".").last, name.contains(".") else {
            return false
        }
        return all.contains(ext.lowercased())
    }
}
