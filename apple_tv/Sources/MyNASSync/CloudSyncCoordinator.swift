import Foundation

public enum CloudSyncOutcome: String, Equatable, Sendable {
    case pulled
    case pushed
    case skipped
    case failed
}

public struct CloudSyncReport: Equatable, Sendable {
    public let moduleKey: String
    public let outcome: CloudSyncOutcome
    public let error: String?

    public init(moduleKey: String, outcome: CloudSyncOutcome, error: String? = nil) {
        self.moduleKey = moduleKey
        self.outcome = outcome
        self.error = error
    }
}

/// 一轮 video_progress 同步。
///
/// 决策逻辑逐条对应 Dart `_syncModuleOnce`（lib/core/sync/cloud_sync_service.dart:334）：
/// 1. 两端都没有 → skipped
/// 2. 远端严格更新 → 拉取 + 合并；拿不到文件时**继续往下**判推送（Dart 是 fall-through）
/// 3. 本地严格更新 → 推送
/// 4. 否则 → skipped，manifest 保留远端时间
///
/// 时间相等时两个分支都不成立，落到 skipped —— 与 Dart 的 `isAfter` 语义一致。
public actor CloudSyncCoordinator {
    public static let moduleKey = "video_progress"

    private static let maxRetries = 3

    private let backend: CloudSyncBackend
    private let store: VideoProgressStore

    public init(backend: CloudSyncBackend, store: VideoProgressStore) {
        self.backend = backend
        self.store = store
    }

    /// 跑一轮同步。抛错只发生在无法开始的情况（连不上），
    /// 模块级失败通过 report.outcome == .failed 返回。
    public func sync() async -> CloudSyncReport {
        guard await backend.healthCheck() else {
            return CloudSyncReport(
                moduleKey: Self.moduleKey,
                outcome: .failed,
                error: "无法连接 WebDAV"
            )
        }

        var lastError: Error?
        for attempt in 1...Self.maxRetries {
            do {
                return try await syncOnce()
            } catch {
                lastError = error
                if attempt < Self.maxRetries {
                    // 与 Dart 一致的线性退避：200ms * attempt
                    try? await Task.sleep(nanoseconds: UInt64(200_000_000 * attempt))
                }
            }
        }

        return CloudSyncReport(
            moduleKey: Self.moduleKey,
            outcome: .failed,
            error: lastError.map(String.init(describing:))
        )
    }

    private func syncOnce() async throws -> CloudSyncReport {
        let manifest = try await backend.readManifest()
        // 拷贝后只改自己的 key，其它模块条目原样写回（见 SyncManifest 注释）
        var newManifest = manifest

        let remoteAt = manifest.updatedAt(forModule: Self.moduleKey)
        var state = try store.load()
        let localAt = state.localUpdatedAt

        if localAt == nil, remoteAt == nil {
            return CloudSyncReport(moduleKey: Self.moduleKey, outcome: .skipped)
        }

        // 远端更新 → 拉取
        if let remoteAt, localAt == nil || remoteAt > localAt! {
            if let data = try await backend.readModule(Self.moduleKey) {
                let payload = try JSONDecoder().decode(VideoProgressPayload.self, from: data)
                state.merge(remote: payload)
                try store.save(state)
                newManifest.setUpdatedAt(remoteAt, forModule: Self.moduleKey)
                try await backend.writeManifest(newManifest)
                return CloudSyncReport(moduleKey: Self.moduleKey, outcome: .pulled)
            }
            // manifest 说有、文件却读不到（被删了 / 半个写入）：不 return，
            // 往下走推送分支。Dart 在这里也是 fall-through。
        }

        // 本地更新 → 推送
        if let localAt, remoteAt == nil || localAt > remoteAt! {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state.exportPayload())
            try await backend.writeModule(Self.moduleKey, data: data)
            newManifest.setUpdatedAt(localAt, forModule: Self.moduleKey)
            try await backend.writeManifest(newManifest)
            return CloudSyncReport(moduleKey: Self.moduleKey, outcome: .pushed)
        }

        // 一致 → 保留 manifest 里的远端时间
        if let remoteAt {
            newManifest.setUpdatedAt(remoteAt, forModule: Self.moduleKey)
            try await backend.writeManifest(newManifest)
        }
        return CloudSyncReport(moduleKey: Self.moduleKey, outcome: .skipped)
    }
}
