import XCTest
@testable import MyNASSync

/// 对应 Dart 契约测试的 `importData 合并规则` 组。
final class VideoProgressMergeTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_772_359_200)
    private let t1 = Date(timeIntervalSince1970: 1_772_359_200 + 3600)
    private let t2 = Date(timeIntervalSince1970: 1_772_359_200 + 7200)

    // MARK: - 进度

    func testNewerRemoteProgressWins() {
        var state = VideoProgressState()
        state.progress["/a"] = .init(positionMs: 100, durationMs: 1000, updatedAt: t0)

        state.merge(remote: payload([
            record(path: "/a", progress: .init(positionMs: 900, durationMs: 1000, updatedAt: t1)),
        ]))

        XCTAssertEqual(state.progress["/a"]?.positionMs, 900)
        XCTAssertEqual(state.progress["/a"]?.updatedAt, t1)
    }

    func testOlderRemoteProgressLoses() {
        var state = VideoProgressState()
        state.progress["/a"] = .init(positionMs: 900, durationMs: 1000, updatedAt: t2)

        state.merge(remote: payload([
            record(path: "/a", progress: .init(positionMs: 100, durationMs: 1000, updatedAt: t0)),
        ]))

        XCTAssertEqual(state.progress["/a"]?.positionMs, 900)
    }

    func testEqualTimestampKeepsLocal() {
        // Dart 用 isAfter（严格晚于），相等时不写入
        var state = VideoProgressState()
        state.progress["/a"] = .init(positionMs: 900, durationMs: 1000, updatedAt: t1)

        state.merge(remote: payload([
            record(path: "/a", progress: .init(positionMs: 100, durationMs: 1000, updatedAt: t1)),
        ]))

        XCTAssertEqual(state.progress["/a"]?.positionMs, 900)
    }

    func testRemoteOnlyProgressIsAdded() {
        var state = VideoProgressState()
        state.merge(remote: payload([
            record(path: "/new", progress: .init(positionMs: 1, durationMs: 2, updatedAt: t0)),
        ]))
        XCTAssertEqual(state.progress["/new"]?.positionMs, 1)
    }

    func testMicrosecondPrecisionDecidesWinner() throws {
        var state = VideoProgressState()
        let local = try XCTUnwrap(Iso8601.parse("2026-03-01T10:00:00.123456Z"))
        state.progress["/a"] = .init(positionMs: 100, durationMs: 1000, updatedAt: local)

        let payload = try JSONDecoder().decode(VideoProgressPayload.self, from: Data("""
        {"version":1,"items":[
          {"videoPath":"/a","positionMs":900,"durationMs":1000,
           "progressUpdatedAt":"2026-03-01T10:00:00.123457Z"}
        ]}
        """.utf8))
        state.merge(remote: payload)

        // 只差 1 微秒也要判出远端更新
        XCTAssertEqual(state.progress["/a"]?.positionMs, 900)
    }

    // MARK: - 已观看标记

    func testNewerRemoteWatchedAtWins() {
        var state = VideoProgressState()
        state.watched["/a"] = t0
        state.merge(remote: payload([record(path: "/a", watchedAt: t1)]))
        XCTAssertEqual(state.watched["/a"], t1)
    }

    func testMissingRemoteWatchedAtNeverClearsLocal() {
        // 契约核心：已看不会被「没看」覆盖。v1 没有 tombstone，
        // 远端缺字段只表示「那端没这个标记」，不表示「已取消」。
        var state = VideoProgressState()
        state.watched["/a"] = t0

        state.merge(remote: payload([
            record(path: "/a", progress: .init(positionMs: 1, durationMs: 2, updatedAt: t2)),
        ]))

        XCTAssertEqual(state.watched["/a"], t0)
    }

    // MARK: - 历史

    func testNewerRemoteHistoryWins() {
        var state = VideoProgressState()
        state.history["/a"] = .init(videoPath: "/a", videoName: "旧", videoUrl: "u1", size: 0, addedAt: t0)

        state.merge(remote: payload([
            record(path: "/a", history: .init(
                videoName: "新", videoUrl: "u2", size: 42, addedAt: t1
            )),
        ]))

        XCTAssertEqual(state.history["/a"]?.videoName, "新")
        XCTAssertEqual(state.history["/a"]?.size, 42)
    }

    func testLocalOnlyHistoryIsPreserved() {
        var state = VideoProgressState()
        state.history["/local"] = .init(
            videoPath: "/local", videoName: "本地", videoUrl: "u", size: 0, addedAt: t0
        )

        state.merge(remote: payload([
            record(path: "/remote", history: .init(videoName: "远端", videoUrl: "u", size: 0, addedAt: t1)),
        ]))

        XCTAssertEqual(state.history.count, 2)
        XCTAssertNotNil(state.history["/local"])
    }

    func testHistoryIsSortedDescendingAndCappedAt100() {
        var state = VideoProgressState()
        // 先塞 60 条本地
        for i in 0..<60 {
            let path = "/local/\(i)"
            state.history[path] = .init(
                videoPath: path, videoName: "L\(i)", videoUrl: "u", size: 0,
                addedAt: t0.addingTimeInterval(Double(i))
            )
        }
        // 再合入 60 条更新的远端
        let remote = (0..<60).map { i in
            record(path: "/remote/\(i)", history: .init(
                videoName: "R\(i)", videoUrl: "u", size: 0,
                addedAt: t1.addingTimeInterval(Double(i))
            ))
        }
        state.merge(remote: payload(remote))

        XCTAssertEqual(state.history.count, 100)
        let ordered = state.orderedHistory
        // 倒序
        XCTAssertEqual(ordered, ordered.sorted { $0.addedAt > $1.addedAt })
        // 被截掉的是最旧的那批本地条目
        XCTAssertNil(state.history["/local/0"])
        XCTAssertNotNil(state.history["/remote/59"])
    }

    // MARK: - 健壮性

    func testEmptyItemsDoesNotTruncateLocalHistory() {
        // Dart 的 historyBox.put 在方法末尾，items 为空时早退、不写。
        // 若这里改成「照常跑一遍再写」，101 条以上的本地历史会被空远端截断。
        var state = VideoProgressState()
        for i in 0..<5 {
            let path = "/\(i)"
            state.history[path] = .init(
                videoPath: path, videoName: "\(i)", videoUrl: "u", size: 0,
                addedAt: t0.addingTimeInterval(Double(i))
            )
        }
        let before = state

        state.merge(remote: VideoProgressPayload(version: 1, items: []))

        XCTAssertEqual(state, before)
    }

    func testOneMalformedRecordDoesNotKillTheBatch() throws {
        // Dart 侧真实踩过的坑：单条坏记录曾让整批导入中断。
        // videoPath 是数字、positionMs 是字符串、items 里混进标量 —— 都只能跳过该条。
        let payload = try JSONDecoder().decode(VideoProgressPayload.self, from: Data("""
        {"version":1,"items":[
          {"videoPath":123,"positionMs":1,"durationMs":2,"progressUpdatedAt":"2026-03-01T10:00:00.000Z"},
          {"videoPath":"/bad-types","positionMs":"1","durationMs":2,"progressUpdatedAt":"2026-03-01T10:00:00.000Z"},
          "我不是对象",
          {"videoPath":"/good","positionMs":7,"durationMs":8,"progressUpdatedAt":"2026-03-01T11:00:00.000Z"}
        ]}
        """.utf8))

        var state = VideoProgressState()
        state.merge(remote: payload)

        // 好的那条必须进来
        XCTAssertEqual(state.progress["/good"]?.positionMs, 7)
        // 坏的三条都不产生条目
        XCTAssertEqual(state.progress.count, 1)
        XCTAssertNil(state.progress["/bad-types"])
    }

    func testEmptyVideoPathIsSkipped() {
        var state = VideoProgressState()
        state.merge(remote: payload([
            record(path: "", progress: .init(positionMs: 1, durationMs: 2, updatedAt: t0)),
        ]))
        XCTAssertTrue(state.progress.isEmpty)
    }

    func testUnknownKeysAreIgnoredForForwardCompatibility() throws {
        // v2 加了字段时，v1 客户端不能整条丢弃
        let payload = try JSONDecoder().decode(VideoProgressPayload.self, from: Data("""
        {"version":1,"items":[
          {"videoPath":"/fwd","positionMs":1,"durationMs":2,
           "progressUpdatedAt":"2026-03-01T10:00:00.000Z",
           "somethingFromV2":{"nested":true},"anotherNew":[1,2,3]}
        ]}
        """.utf8))

        var state = VideoProgressState()
        state.merge(remote: payload)
        XCTAssertEqual(state.progress["/fwd"]?.positionMs, 1)
    }

    func testVersionIsNotValidated() throws {
        // 与 Dart 一致：目前不按 version 分支。加 v2 语义时两端一起改。
        let payload = try JSONDecoder().decode(VideoProgressPayload.self, from: Data("""
        {"version":99,"items":[
          {"videoPath":"/v","positionMs":1,"durationMs":2,
           "progressUpdatedAt":"2026-03-01T10:00:00.000Z"}
        ]}
        """.utf8))

        var state = VideoProgressState()
        state.merge(remote: payload)
        XCTAssertEqual(payload.version, 99)
        XCTAssertEqual(state.progress["/v"]?.positionMs, 1)
    }

    func testMissingVersionDefaultsToOne() throws {
        let payload = try JSONDecoder().decode(VideoProgressPayload.self, from: Data("""
        {"items":[]}
        """.utf8))
        XCTAssertEqual(payload.version, 1)
    }

    func testProgressGroupDroppedWhenTimestampMissing() throws {
        // 分组不完整 → 整组丢弃（Dart 要求 progressUpdatedAt + 两个 int 同时在）
        let payload = try JSONDecoder().decode(VideoProgressPayload.self, from: Data("""
        {"version":1,"items":[{"videoPath":"/x","positionMs":1,"durationMs":2}]}
        """.utf8))

        XCTAssertNil(payload.items.first?.progress)
        var state = VideoProgressState()
        state.merge(remote: payload)
        XCTAssertTrue(state.progress.isEmpty)
    }

    func testHistoryGroupDroppedWhenNameOrUrlMissing() throws {
        let payload = try JSONDecoder().decode(VideoProgressPayload.self, from: Data("""
        {"version":1,"items":[
          {"videoPath":"/x","size":1,"historyAddedAt":"2026-03-01T10:00:00.000Z"}
        ]}
        """.utf8))

        XCTAssertNil(payload.items.first?.history)
        var state = VideoProgressState()
        state.merge(remote: payload)
        XCTAssertTrue(state.history.isEmpty)
    }

    func testExportImportRoundTripIsIdempotent() throws {
        var original = VideoProgressState()
        let path = "/round.mkv"
        original.progress[path] = .init(positionMs: 123, durationMs: 456, updatedAt: t0)
        original.watched[path] = t1
        original.history[path] = .init(
            videoPath: path, videoName: "R", videoUrl: "u", sourceId: "s",
            thumbnailUrl: "th", size: 9, lastPositionMs: 120, durationMs: 450, addedAt: t2
        )

        let data = try JSONEncoder().encode(original.exportPayload())
        let decoded = try JSONDecoder().decode(VideoProgressPayload.self, from: data)

        var target = VideoProgressState()
        target.merge(remote: decoded)

        XCTAssertEqual(target, original)
    }

    // MARK: - 构造辅助

    private func payload(_ items: [VideoProgressRecord]) -> VideoProgressPayload {
        VideoProgressPayload(version: 1, items: items)
    }

    private func record(
        path: String,
        progress: VideoProgressRecord.Progress? = nil,
        watchedAt: Date? = nil,
        history: VideoProgressRecord.History? = nil
    ) -> VideoProgressRecord {
        VideoProgressRecord(
            videoPath: path, progress: progress, watchedAt: watchedAt, history: history
        )
    }
}
