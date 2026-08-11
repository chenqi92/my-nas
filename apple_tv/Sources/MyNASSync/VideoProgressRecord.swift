import Foundation

/// video_progress v1 的一条记录。
///
/// 契约见 docs/sync-contract-video-progress.md。这里把 13 个平铺字段建模成
/// 三个可选分组，让「有 progressUpdatedAt 就一定有 positionMs + durationMs」
/// 这类分组约束由类型系统保证，而不是靠调用方自觉。JSON 编解码时再拍平。
public struct VideoProgressRecord: Equatable {
    /// 来自 video_progress box
    public struct Progress: Equatable {
        public var positionMs: Int
        public var durationMs: Int
        public var updatedAt: Date

        public init(positionMs: Int, durationMs: Int, updatedAt: Date) {
            self.positionMs = positionMs
            self.durationMs = durationMs
            self.updatedAt = updatedAt
        }
    }

    /// 来自 video_history box
    public struct History: Equatable {
        public var videoName: String
        public var videoUrl: String
        public var sourceId: String?
        public var thumbnailUrl: String?
        /// 无值时写 0，不省略（契约规定）
        public var size: Int
        public var addedAt: Date
        public var lastPositionMs: Int?
        public var durationMs: Int?

        public init(
            videoName: String,
            videoUrl: String,
            sourceId: String? = nil,
            thumbnailUrl: String? = nil,
            size: Int = 0,
            addedAt: Date,
            lastPositionMs: Int? = nil,
            durationMs: Int? = nil
        ) {
            self.videoName = videoName
            self.videoUrl = videoUrl
            self.sourceId = sourceId
            self.thumbnailUrl = thumbnailUrl
            self.size = size
            self.addedAt = addedAt
            self.lastPositionMs = lastPositionMs
            self.durationMs = durationMs
        }
    }

    public var videoPath: String
    public var progress: Progress?
    /// 「已观看」标记时间，来自 video_watched box。**不是** history 时间。
    public var watchedAt: Date?
    public var history: History?

    public init(
        videoPath: String,
        progress: Progress? = nil,
        watchedAt: Date? = nil,
        history: History? = nil
    ) {
        self.videoPath = videoPath
        self.progress = progress
        self.watchedAt = watchedAt
        self.history = history
    }
}

extension VideoProgressRecord: Codable {
    private enum Key: String, CodingKey {
        case videoPath
        case positionMs, durationMs, progressUpdatedAt
        case watchedAt
        case videoName, videoUrl, sourceId, thumbnailUrl, size
        case historyAddedAt, historyLastPositionMs, historyDurationMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        videoPath = try c.decode(String.self, forKey: .videoPath)
        guard !videoPath.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .videoPath, in: c, debugDescription: "empty videoPath"
            )
        }

        // 分组判定与 Dart importData 一致：缺时间戳或字段类型不对 => 整组丢弃。
        if let stamp = Self.date(c, .progressUpdatedAt),
           let position = Self.int(c, .positionMs),
           let duration = Self.int(c, .durationMs) {
            progress = Progress(
                positionMs: position, durationMs: duration, updatedAt: stamp
            )
        } else {
            progress = nil
        }

        watchedAt = Self.date(c, .watchedAt)

        if let addedAt = Self.date(c, .historyAddedAt),
           let name = try? c.decodeIfPresent(String.self, forKey: .videoName),
           let url = try? c.decodeIfPresent(String.self, forKey: .videoUrl) {
            history = History(
                videoName: name,
                videoUrl: url,
                sourceId: try? c.decodeIfPresent(String.self, forKey: .sourceId),
                thumbnailUrl: try? c.decodeIfPresent(
                    String.self, forKey: .thumbnailUrl
                ),
                size: Self.int(c, .size) ?? 0,
                addedAt: addedAt,
                lastPositionMs: Self.int(c, .historyLastPositionMs),
                durationMs: Self.int(c, .historyDurationMs)
            )
        } else {
            history = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(videoPath, forKey: .videoPath)

        if let progress {
            try c.encode(progress.positionMs, forKey: .positionMs)
            try c.encode(progress.durationMs, forKey: .durationMs)
            try c.encode(
                Iso8601.format(progress.updatedAt), forKey: .progressUpdatedAt
            )
        }

        if let watchedAt {
            try c.encode(Iso8601.format(watchedAt), forKey: .watchedAt)
        }

        if let history {
            try c.encode(history.videoName, forKey: .videoName)
            try c.encode(history.videoUrl, forKey: .videoUrl)
            // nil 时省略整个键，不写 null（契约规定）
            try c.encodeIfPresent(history.sourceId, forKey: .sourceId)
            try c.encodeIfPresent(history.thumbnailUrl, forKey: .thumbnailUrl)
            try c.encode(history.size, forKey: .size)
            try c.encode(Iso8601.format(history.addedAt), forKey: .historyAddedAt)
            try c.encodeIfPresent(
                history.lastPositionMs, forKey: .historyLastPositionMs
            )
            try c.encodeIfPresent(history.durationMs, forKey: .historyDurationMs)
        }
    }

    /// 宽松读整数：接受 Int，也接受对端写成 Double 的情况。
    private static func int(
        _ c: KeyedDecodingContainer<Key>, _ key: Key
    ) -> Int? {
        if let value = try? c.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? c.decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    private static func date(
        _ c: KeyedDecodingContainer<Key>, _ key: Key
    ) -> Date? {
        guard let raw = try? c.decodeIfPresent(String.self, forKey: key),
              let raw
        else { return nil }
        return Iso8601.parse(raw)
    }
}
