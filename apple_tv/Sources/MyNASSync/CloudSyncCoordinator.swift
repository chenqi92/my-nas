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

/// 一轮 video_progress 双向记录合并。
///
/// 不能只比较两份快照的最大时间戳：两台设备各自新增不同记录时，其中一份快照
/// 虽然“更晚”，却并不包含另一台的记录。本协调器始终读取远端内容，以
/// videoPath 和各字段时间戳合并后，把并集写回。
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
        let manifestDocument = try await backend.readManifestDocument()
        let manifest = try manifestDocument.map {
            try JSONDecoder().decode(SyncManifest.self, from: $0.data)
        } ?? SyncManifest()
        let remoteAt = manifest.updatedAt(forModule: Self.moduleKey)
        var state = try store.load()
        let localBefore = state
        let localAt = state.localUpdatedAt

        let remoteDocument = try await backend.readModuleDocument(Self.moduleKey)
        let remoteData = remoteDocument?.data
        if remoteAt != nil, remoteDocument == nil {
            throw CloudSyncError.remoteModuleMissing(key: Self.moduleKey)
        }

        var normalizedRemote: VideoProgressPayload?
        if let remoteData {
            let payload = try JSONDecoder().decode(VideoProgressPayload.self, from: remoteData)
            var remoteState = VideoProgressState()
            remoteState.merge(remote: payload)
            normalizedRemote = remoteState.exportPayload()
            state.merge(remote: payload)
        }

        let localChanged = state != localBefore
        if localChanged { try store.save(state) }

        let merged = state.exportPayload()
        let shouldUpload = remoteData == nil ? localAt != nil : merged != normalizedRemote

        if shouldUpload {
            let data = try Self.encode(merged)
            let written = try await backend.writeModuleIfUnchanged(
                Self.moduleKey,
                data: data,
                expected: remoteDocument
            )
            guard written else {
                throw CloudSyncError.concurrentRemoteChange(key: Self.moduleKey)
            }

            let updatedAt = Self.nextUpdatedAt(
                localAt: localAt,
                remoteAt: remoteAt,
                mergedAt: state.localUpdatedAt
            )
            try await updateManifest(updatedAt: updatedAt)
            return CloudSyncReport(moduleKey: Self.moduleKey, outcome: .pushed)
        }

        // 模块文件写成功、manifest 条件写冲突后，下轮即使快照已一致也要
        // 修复落后的索引时间，否则其它设备仍会按旧时间判断方向。
        if remoteData != nil,
           let mergedAt = state.localUpdatedAt,
           remoteAt == nil || remoteAt! < mergedAt
        {
            try await updateManifest(updatedAt: mergedAt)
        }
        return CloudSyncReport(
            moduleKey: Self.moduleKey,
            outcome: localChanged ? .pulled : .skipped
        )
    }

    private func updateManifest(updatedAt: Date) async throws {
        // 模块写完后重新读 manifest，只改自己的 key，并用 ETag 条件写保存，
        // 不能让 tvOS 覆盖同期由 Flutter 写入的其它模块索引。
        let document = try await backend.readManifestDocument()
        var latest = try document.map {
            try JSONDecoder().decode(SyncManifest.self, from: $0.data)
        } ?? SyncManifest()
        if let existing = latest.updatedAt(forModule: Self.moduleKey), existing > updatedAt {
            return
        }
        latest.setUpdatedAt(updatedAt, forModule: Self.moduleKey)
        let written = try await backend.writeManifestIfUnchanged(
            latest,
            expected: document
        )
        guard written else {
            throw CloudSyncError.concurrentRemoteChange(key: "manifest")
        }
    }

    private static func encode(_ payload: VideoProgressPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    private static func nextUpdatedAt(
        localAt: Date?,
        remoteAt: Date?,
        mergedAt: Date?
    ) -> Date {
        var next = [localAt, remoteAt, mergedAt].compactMap { $0 }.max() ?? Date()
        if let remoteAt, next <= remoteAt {
            next = remoteAt.addingTimeInterval(0.001)
        }
        return next
    }
}
