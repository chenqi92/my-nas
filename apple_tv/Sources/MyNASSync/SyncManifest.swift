import Foundation

/// `/<rootPath>/manifest.json`
///
/// 形状：`{ "<module-key>": { "updatedAt": <epoch 毫秒 Int> }, ... }`
///
/// 注意时间格式在这个协议里是**两种**：manifest 用 epoch 毫秒整数，
/// 模块文件（video_progress.json）里的时间戳是 ISO8601 字符串。别搞混。
public struct SyncManifest: Equatable {
    /// 原始 JSON。未知的 key 和未知的字段都留在这里，写回时不丢。
    public private(set) var raw: [String: JSONValue]

    public init(raw: [String: JSONValue] = [:]) {
        self.raw = raw
    }

    /// 某模块的远端时间。缺失 / 类型不对 / 不是整数都返回 nil（等价于「远端没有」）。
    public func updatedAt(forModule key: String) -> Date? {
        guard let millis = raw[key]?.objectValue?["updatedAt"]?.intValue else { return nil }
        return Date(timeIntervalSince1970: Double(millis) / 1000)
    }

    /// 只改目标模块的 updatedAt，其它 key 原样保留。
    ///
    /// 毫秒截断和 Dart 的 `millisecondsSinceEpoch` 一致（都是向零取整）。
    /// 由此产生的副作用两端相同：本地时间戳带微秒时，写回的 manifest 值比
    /// 真实的 localAt 略早，下一轮比较会再判一次「本地更新」并重推一次。
    /// 幂等、无数据损坏，不在这里「修」—— 修了就和 Flutter 端行为不一致。
    public mutating func setUpdatedAt(_ date: Date, forModule key: String) {
        let millis = Int((date.timeIntervalSince1970 * 1000).rounded(.towardZero))
        raw[key] = .object(["updatedAt": .int(millis)])
    }
}

extension SyncManifest: Codable {
    public init(from decoder: Decoder) throws {
        raw = try [String: JSONValue](from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try raw.encode(to: encoder)
    }
}
