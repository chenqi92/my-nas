import Foundation

/// tvOS 端的本地状态，对应 Dart 的三个 Hive box。
///
/// 纯值类型、无 IO，合并规则可以直接单测（见 MyNASSyncTests）。
/// 持久化交给 VideoProgressStore。
public struct VideoProgressState: Equatable, Codable {
    /// 与 Dart `_historyCap` 一致；两端都按 100 截断
    public static let historyCap = 100

    public struct ProgressEntry: Equatable, Codable {
        public var positionMs: Int
        public var durationMs: Int
        public var updatedAt: Date

        public init(positionMs: Int, durationMs: Int, updatedAt: Date) {
            self.positionMs = positionMs
            self.durationMs = durationMs
            self.updatedAt = updatedAt
        }
    }

    public struct HistoryEntry: Equatable, Codable {
        public var videoPath: String
        public var videoName: String
        public var videoUrl: String
        public var sourceId: String?
        public var thumbnailUrl: String?
        public var size: Int
        public var lastPositionMs: Int?
        public var durationMs: Int?
        public var addedAt: Date

        public init(
            videoPath: String,
            videoName: String,
            videoUrl: String,
            sourceId: String? = nil,
            thumbnailUrl: String? = nil,
            size: Int = 0,
            lastPositionMs: Int? = nil,
            durationMs: Int? = nil,
            addedAt: Date
        ) {
            self.videoPath = videoPath
            self.videoName = videoName
            self.videoUrl = videoUrl
            self.sourceId = sourceId
            self.thumbnailUrl = thumbnailUrl
            self.size = size
            self.lastPositionMs = lastPositionMs
            self.durationMs = durationMs
            self.addedAt = addedAt
        }
    }

    public var progress: [String: ProgressEntry]
    public var watched: [String: Date]
    public var history: [String: HistoryEntry]

    public init(
        progress: [String: ProgressEntry] = [:],
        watched: [String: Date] = [:],
        history: [String: HistoryEntry] = [:]
    ) {
        self.progress = progress
        self.watched = watched
        self.history = history
    }

    /// 三处时间的最大值。全空返回 nil —— 与 Dart getLocalUpdatedAt 一致，
    /// 调用方据此决定 skip。
    public var localUpdatedAt: Date? {
        var newest: Date?
        func bump(_ date: Date?) {
            guard let date else { return }
            if newest == nil || date > newest! { newest = date }
        }
        for entry in progress.values { bump(entry.updatedAt) }
        for date in watched.values { bump(date) }
        for entry in history.values { bump(entry.addedAt) }
        return newest
    }

    /// 历史按时间倒序并截断到 100 条（与 Dart 合并后的写入形态一致）
    public var orderedHistory: [HistoryEntry] {
        Array(
            history.values
                .sorted { $0.addedAt > $1.addedAt }
                .prefix(Self.historyCap)
        )
    }
}
