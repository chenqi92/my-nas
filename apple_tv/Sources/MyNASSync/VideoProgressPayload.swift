import Foundation

/// `video_progress.json` 的顶层结构：`{ "version": 1, "items": [...] }`
///
/// items 逐条宽松解码：**单条坏记录只跳过该条，不能让整批失败**。
/// Dart 端曾因为 `on Exception` 漏掉 `TypeError` 而在这里整批中断，
/// Swift 侧如果直接 `decode([VideoProgressRecord].self)` 会犯同样的错。
public struct VideoProgressPayload: Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var items: [VideoProgressRecord]

    public init(version: Int = currentVersion, items: [VideoProgressRecord]) {
        self.version = version
        self.items = items
    }
}

extension VideoProgressPayload: Codable {
    private enum Key: String, CodingKey {
        case version, items
    }

    /// 逐元素吞掉解码失败的包装。数组元素照常被消费，索引不会卡住。
    private struct Lenient: Decodable {
        let record: VideoProgressRecord?

        init(from decoder: Decoder) throws {
            record = try? VideoProgressRecord(from: decoder)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)

        // version 目前不参与分支（与 Dart 一致）。加 v2 时两端一起加。
        version =
            (try? c.decodeIfPresent(Int.self, forKey: .version))
            .flatMap { $0 } ?? Self.currentVersion

        let raw =
            (try? c.decodeIfPresent([Lenient].self, forKey: .items))
            .flatMap { $0 } ?? []
        items = raw.compactMap(\.record)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(version, forKey: .version)
        // 空也要写成 []，不省略、不写 null
        try c.encode(items, forKey: .items)
    }
}
