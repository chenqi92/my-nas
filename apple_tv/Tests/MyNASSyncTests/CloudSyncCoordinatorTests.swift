import XCTest
@testable import MyNASSync

/// 内存后端，替代真 WebDAV 服务器。
actor FakeBackend: CloudSyncBackend {
    var manifest: SyncManifest
    var modules: [String: Data]
    var healthy: Bool
    /// 记录 writeManifest 被调用时写进去的内容，用于断言其它模块条目没丢
    private(set) var writtenManifests: [SyncManifest] = []
    private(set) var writtenModules: [String: Data] = [:]
    /// 置 true 时 readModule 返回 nil，模拟「manifest 说有、文件没了」
    var moduleFileMissing = false

    init(
        manifest: SyncManifest = SyncManifest(),
        modules: [String: Data] = [:],
        healthy: Bool = true
    ) {
        self.manifest = manifest
        self.modules = modules
        self.healthy = healthy
    }

    func healthCheck() async -> Bool { healthy }

    func readManifest() async throws -> SyncManifest { manifest }

    func writeManifest(_ manifest: SyncManifest) async throws {
        self.manifest = manifest
        writtenManifests.append(manifest)
    }

    func readModule(_ key: String) async throws -> Data? {
        moduleFileMissing ? nil : modules[key]
    }

    func writeModule(_ key: String, data: Data) async throws {
        modules[key] = data
        writtenModules[key] = data
    }
}

final class CloudSyncCoordinatorTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_772_359_200)
    private let t1 = Date(timeIntervalSince1970: 1_772_359_200 + 3600)

    func testBothEmptyIsSkipped() async throws {
        let backend = FakeBackend()
        let store = InMemoryVideoProgressStore()
        let coordinator = CloudSyncCoordinator(backend: backend, store: store)

        let report = await coordinator.sync()

        XCTAssertEqual(report.outcome, .skipped)
        // 两端都空时不该产生任何写入
        let written = await backend.writtenManifests
        XCTAssertTrue(written.isEmpty)
    }

    func testLocalNewerIsPushed() async throws {
        let backend = FakeBackend()
        var state = VideoProgressState()
        state.progress["/a"] = .init(positionMs: 1, durationMs: 2, updatedAt: t1)
        let store = InMemoryVideoProgressStore(state: state)

        let report = await CloudSyncCoordinator(backend: backend, store: store).sync()

        XCTAssertEqual(report.outcome, .pushed)
        let data = try XCTUnwrap(await backend.writtenModules["video_progress"])
        let payload = try JSONDecoder().decode(VideoProgressPayload.self, from: data)
        XCTAssertEqual(payload.items.first?.videoPath, "/a")
        // manifest 时间戳按毫秒写
        let stamp = await backend.manifest.updatedAt(forModule: "video_progress")
        XCTAssertEqual(try XCTUnwrap(stamp).timeIntervalSince1970, t1.timeIntervalSince1970, accuracy: 0.001)
    }

    func testRemoteNewerIsPulledAndMerged() async throws {
        var manifest = SyncManifest()
        manifest.setUpdatedAt(t1, forModule: "video_progress")
        let remote = Data("""
        {"version":1,"items":[
          {"videoPath":"/remote","positionMs":500,"durationMs":1000,
           "progressUpdatedAt":"2026-03-01T11:00:00.000Z"}
        ]}
        """.utf8)
        let backend = FakeBackend(manifest: manifest, modules: ["video_progress": remote])

        var state = VideoProgressState()
        state.progress["/local"] = .init(positionMs: 1, durationMs: 2, updatedAt: t0)
        let store = InMemoryVideoProgressStore(state: state)

        let report = await CloudSyncCoordinator(backend: backend, store: store).sync()

        XCTAssertEqual(report.outcome, .pulled)
        let merged = try store.load()
        XCTAssertEqual(merged.progress["/remote"]?.positionMs, 500)
        // 本地条目不能被拉取覆盖掉
        XCTAssertEqual(merged.progress["/local"]?.positionMs, 1)
    }

    func testWriteManifestPreservesOtherModules() async throws {
        // 回归用：tvOS 只同步 video_progress，但 manifest 是全模块共享的。
        // 只写自己那一个 key 会抹掉另外 7 个模块的 updatedAt，
        // Flutter 端随后会把那些模块整表重推。
        var manifest = SyncManifest(raw: [
            "app_settings": .object(["updatedAt": .int(1_700_000_000_000)]),
            "favorites": .object(["updatedAt": .int(1_700_000_001_000)]),
            "book_progress": .object(["updatedAt": .int(1_700_000_002_000)]),
        ])
        manifest.setUpdatedAt(t0, forModule: "video_progress")
        let backend = FakeBackend(manifest: manifest)

        var state = VideoProgressState()
        state.progress["/a"] = .init(positionMs: 1, durationMs: 2, updatedAt: t1)
        let store = InMemoryVideoProgressStore(state: state)

        let report = await CloudSyncCoordinator(backend: backend, store: store).sync()
        XCTAssertEqual(report.outcome, .pushed)

        let after = await backend.manifest
        XCTAssertEqual(after.raw["app_settings"], .object(["updatedAt": .int(1_700_000_000_000)]))
        XCTAssertEqual(after.raw["favorites"], .object(["updatedAt": .int(1_700_000_001_000)]))
        XCTAssertEqual(after.raw["book_progress"], .object(["updatedAt": .int(1_700_000_002_000)]))
    }

    func testEqualTimestampsAreSkipped() async throws {
        var manifest = SyncManifest()
        manifest.setUpdatedAt(t1, forModule: "video_progress")
        let backend = FakeBackend(manifest: manifest, modules: ["video_progress": Data("{}".utf8)])

        var state = VideoProgressState()
        state.progress["/a"] = .init(positionMs: 1, durationMs: 2, updatedAt: t1)
        let store = InMemoryVideoProgressStore(state: state)

        let report = await CloudSyncCoordinator(backend: backend, store: store).sync()

        XCTAssertEqual(report.outcome, .skipped)
        let written = await backend.writtenModules
        XCTAssertTrue(written.isEmpty)
    }

    func testMissingRemoteFileFallsThroughToPush() async throws {
        // manifest 说远端更新，但文件读不到（被删 / 半个写入）。
        // Dart 在这里是 fall-through，不 return，继续判推送。
        var manifest = SyncManifest()
        manifest.setUpdatedAt(t1, forModule: "video_progress")
        let backend = FakeBackend(manifest: manifest)
        await backend.setModuleFileMissing(true)

        var state = VideoProgressState()
        state.progress["/a"] = .init(positionMs: 1, durationMs: 2, updatedAt: t0)
        let store = InMemoryVideoProgressStore(state: state)

        let report = await CloudSyncCoordinator(backend: backend, store: store).sync()

        // 本地时间比 manifest 旧，推送条件也不成立 → skipped，且不写模块文件
        XCTAssertEqual(report.outcome, .skipped)
        let written = await backend.writtenModules
        XCTAssertTrue(written.isEmpty)
    }

    func testUnhealthyBackendFails() async {
        let backend = FakeBackend(healthy: false)
        let report = await CloudSyncCoordinator(
            backend: backend, store: InMemoryVideoProgressStore()
        ).sync()

        XCTAssertEqual(report.outcome, .failed)
        XCTAssertNotNil(report.error)
    }

    func testManifestWithGarbageEntryTreatedAsAbsent() {
        // updatedAt 类型不对 / 缺失 → 视为远端没有记录
        let cases: [String: JSONValue] = [
            "video_progress": .object(["updatedAt": .string("2026-03-01")]),
        ]
        XCTAssertNil(SyncManifest(raw: cases).updatedAt(forModule: "video_progress"))
        XCTAssertNil(SyncManifest(raw: ["video_progress": .null]).updatedAt(forModule: "video_progress"))
        XCTAssertNil(SyncManifest().updatedAt(forModule: "video_progress"))
    }

    func testManifestAcceptsDoubleEncodedMillis() {
        // 别的客户端可能把毫秒写成 1.7e12 这种 double
        let manifest = SyncManifest(raw: [
            "video_progress": .object(["updatedAt": .double(1_772_359_200_000)]),
        ])
        let stamp = manifest.updatedAt(forModule: "video_progress")
        XCTAssertEqual(stamp?.timeIntervalSince1970 ?? 0, 1_772_359_200, accuracy: 0.001)
    }
}

extension FakeBackend {
    func setModuleFileMissing(_ value: Bool) {
        moduleFileMissing = value
    }
}
