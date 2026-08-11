import Foundation

// video_progress v1 的读写实现，逐条对应 Dart
// lib/features/video/data/services/sync/video_progress_sync_module.dart。
// 改动任一侧都要同步改另一侧，并跑两边的契约测试。
public extension VideoProgressState {

    /// 对应 Dart exportData()：按 videoPath 聚合三个 box 的字段成扁平记录。
    ///
    /// items 顺序不属于契约（记录以 videoPath 为主键），这里按 path 排序只为
    /// 输出稳定、便于 diff；Dart 侧是 Set 的插入序。
    func exportPayload() -> VideoProgressPayload {
        var paths = Set(progress.keys)
        paths.formUnion(history.keys)
        paths.formUnion(watched.keys)

        let items = paths.sorted().map { path -> VideoProgressRecord in
            VideoProgressRecord(
                videoPath: path,
                progress: progress[path].map {
                    .init(
                        positionMs: $0.positionMs,
                        durationMs: $0.durationMs,
                        updatedAt: $0.updatedAt
                    )
                },
                watchedAt: watched[path],
                history: history[path].map {
                    .init(
                        videoName: $0.videoName,
                        videoUrl: $0.videoUrl,
                        sourceId: $0.sourceId,
                        thumbnailUrl: $0.thumbnailUrl,
                        size: $0.size,
                        addedAt: $0.addedAt,
                        lastPositionMs: $0.lastPositionMs,
                        durationMs: $0.durationMs
                    )
                }
            )
        }

        return VideoProgressPayload(version: VideoProgressPayload.currentVersion, items: items)
    }

    /// 对应 Dart importData()：三组字段各自按自己的时间戳 last-wins。
    ///
    /// 三处细节和 Dart 完全一致，都不是随意选的：
    /// 1. `items` 为空直接返回，**不重写 history**。Dart 的 historyBox.put 在方法末尾，
    ///    空 items 早退时不会执行，所以空远端不会截断本地历史。
    /// 2. 比较用严格「晚于」：时间戳相等时保留本地，不写入。
    /// 3. 远端 watchedAt 缺失时不清除本地标记（已看不会被没看覆盖）。
    mutating func merge(remote: VideoProgressPayload) {
        guard !remote.items.isEmpty else { return }

        for record in remote.items where !record.videoPath.isEmpty {
            let path = record.videoPath

            // 1. 进度
            if let incoming = record.progress {
                let localAt = progress[path]?.updatedAt
                if localAt == nil || incoming.updatedAt > localAt! {
                    progress[path] = .init(
                        positionMs: incoming.positionMs,
                        durationMs: incoming.durationMs,
                        updatedAt: incoming.updatedAt
                    )
                }
            }

            // 2. 已观看标记
            if let incoming = record.watchedAt {
                let localAt = watched[path]
                if localAt == nil || incoming > localAt! {
                    watched[path] = incoming
                }
            }

            // 3. 历史元数据
            if let incoming = record.history {
                let localAt = history[path]?.addedAt
                if localAt == nil || incoming.addedAt > localAt! {
                    history[path] = .init(
                        videoPath: path,
                        videoName: incoming.videoName,
                        videoUrl: incoming.videoUrl,
                        sourceId: incoming.sourceId,
                        thumbnailUrl: incoming.thumbnailUrl,
                        size: incoming.size,
                        lastPositionMs: incoming.lastPositionMs,
                        durationMs: incoming.durationMs,
                        addedAt: incoming.addedAt
                    )
                }
            }
        }

        // 合并后按时间倒序截断到 100 条：本地独有的条目保留，参与排序和截断。
        let kept = orderedHistory
        history = Dictionary(uniqueKeysWithValues: kept.map { ($0.videoPath, $0) })
    }
}
