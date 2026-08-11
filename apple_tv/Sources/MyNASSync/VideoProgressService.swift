import Foundation

/// 本端读写入口。播放器只跟这个类打交道，不直接碰 store / state。
///
/// 阈值和时机全部对齐 Dart VideoPlayerNotifier
/// （lib/features/video/presentation/providers/video_player_provider.dart）：
/// - 每 10 秒存一次（`saveInterval`）
/// - 位置 < 5 秒不存（`minPositionSeconds`）
/// - 时长 < 10 秒不存（`minDurationSeconds`）
/// - 播放完成 → **清除**进度条目，且**不**自动标记已观看
///
/// 最后一条容易想反：Dart 的播放器完成时只调 clearProgress，markAsWatched 只来自
/// 用户手动切换和媒体服务器状态同步。tvOS 端如果自动标记，两端「已观看」列表会不一致。
public actor VideoProgressService {
    /// 进度保存间隔
    public static let saveInterval: TimeInterval = 10
    /// 低于此位置不保存
    public static let minPositionSeconds: Double = 5
    /// 低于此时长不保存
    public static let minDurationSeconds: Double = 10

    private let store: VideoProgressStore
    private var state: VideoProgressState
    private let now: () -> Date

    /// - Parameter now: 注入时间源，测试里可固定
    public init(store: VideoProgressStore, now: @escaping () -> Date = Date.init) throws {
        self.store = store
        self.now = now
        state = try store.load()
    }

    public var currentState: VideoProgressState { state }

    /// 重新读盘。同步协调器写完之后调，让内存状态跟上。
    public func reload() throws {
        state = try store.load()
    }

    public func progress(for videoPath: String) -> VideoProgressState.ProgressEntry? {
        state.progress[videoPath]
    }

    public func isWatched(_ videoPath: String) -> Bool {
        state.watched[videoPath] != nil
    }

    public var history: [VideoProgressState.HistoryEntry] {
        state.orderedHistory
    }

    /// 未看完的条目，用于「继续观看」。
    /// 5% ~ 95% 区间与 Dart getContinueWatching 一致。
    public var continueWatching: [VideoProgressState.HistoryEntry] {
        state.orderedHistory.filter { item in
            guard let entry = state.progress[item.videoPath], entry.durationMs > 0 else {
                return false
            }
            let percent = Double(entry.positionMs) / Double(entry.durationMs)
            return percent > 0.05 && percent < 0.95
        }
    }

    /// 保存播放进度。不满足阈值时什么都不做并返回 false。
    @discardableResult
    public func saveProgress(
        videoPath: String,
        position: TimeInterval,
        duration: TimeInterval
    ) throws -> Bool {
        guard position >= Self.minPositionSeconds,
              duration >= Self.minDurationSeconds else { return false }

        state.progress[videoPath] = .init(
            positionMs: Int(position * 1000),
            durationMs: Int(duration * 1000),
            updatedAt: now()
        )
        try store.save(state)
        return true
    }

    /// 播放完成：清除进度条目。
    ///
    /// v1 没有 tombstone，**这个删除不会同步到其它端**（契约文档里的已知限制）。
    /// 别在这里自造删除标记 —— 那会变成 Flutter 端读不懂的字段。
    public func clearProgress(videoPath: String) throws {
        state.progress.removeValue(forKey: videoPath)
        try store.save(state)
    }

    public func markWatched(_ videoPath: String) throws {
        state.watched[videoPath] = now()
        try store.save(state)
    }

    /// 取消已观看标记。同上，删除不会同步出去。
    public func markUnwatched(_ videoPath: String) throws {
        state.watched.removeValue(forKey: videoPath)
        try store.save(state)
    }

    @discardableResult
    public func toggleWatched(_ videoPath: String) throws -> Bool {
        if isWatched(videoPath) {
            try markUnwatched(videoPath)
            return false
        }
        try markWatched(videoPath)
        return true
    }

    /// 加入播放历史。已存在的同 path 条目被替换，时间戳刷新到现在
    /// （Dart addToHistory 是 removeWhere + insert(0)，效果相同）。
    public func addToHistory(
        videoPath: String,
        videoName: String,
        videoUrl: String,
        sourceId: String? = nil,
        thumbnailUrl: String? = nil,
        size: Int = 0,
        lastPositionMs: Int? = nil,
        durationMs: Int? = nil
    ) throws {
        state.history[videoPath] = .init(
            videoPath: videoPath,
            videoName: videoName,
            videoUrl: videoUrl,
            sourceId: sourceId,
            thumbnailUrl: thumbnailUrl,
            size: size,
            lastPositionMs: lastPositionMs,
            durationMs: durationMs,
            addedAt: now()
        )
        // 截断到 100 条，与 Dart 一致
        let kept = state.orderedHistory
        state.history = Dictionary(uniqueKeysWithValues: kept.map { ($0.videoPath, $0) })
        try store.save(state)
    }
}
