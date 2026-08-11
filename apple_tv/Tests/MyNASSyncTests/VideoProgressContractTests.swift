import XCTest
@testable import MyNASSync

/// 与 Dart 侧
/// test/features/video/data/services/sync/video_progress_sync_contract_test.dart
/// 一一对应。两边任一侧改了字段或合并规则，对应的那条会红。
final class VideoProgressContractTests: XCTestCase {

    private let moduleKey = "video_progress"

    // MARK: - 固定时间点

    private let t0 = Date(timeIntervalSince1970: 1_772_359_200)          // 2026-03-01T10:00:00Z
    private let t1 = Date(timeIntervalSince1970: 1_772_359_200 + 3600)   // +1h
    private let t2 = Date(timeIntervalSince1970: 1_772_359_200 + 7200)   // +2h

    // MARK: - 模块标识

    func testModuleKeyIsStable() {
        // 这个字符串同时是 manifest 的 key 和远端文件名 video_progress.json。
        // 改了它等于换了一个新模块，旧数据全部读不到。
        XCTAssertEqual(CloudSyncCoordinator.moduleKey, moduleKey)
    }

    func testHistoryCapMatchesDart() {
        XCTAssertEqual(VideoProgressState.historyCap, 100)
    }

    // MARK: - exportPayload 顶层结构

    func testExportTopLevelShape() throws {
        var state = VideoProgressState()
        state.progress["/a.mkv"] = .init(positionMs: 1000, durationMs: 2000, updatedAt: t0)

        let json = try encodeToObject(state.exportPayload())

        XCTAssertEqual(Set(json.keys), ["version", "items"])
        XCTAssertEqual(json["version"]?.intValue, 1)
        guard case let .array(items) = try XCTUnwrap(json["items"]) else {
            return XCTFail("items 必须是数组")
        }
        XCTAssertEqual(items.count, 1)
    }

    func testExportEmptyStateStillWritesEmptyItemsArray() throws {
        let json = try encodeToObject(VideoProgressState().exportPayload())
        XCTAssertEqual(json["items"], .array([]))
    }

    // MARK: - exportPayload 记录字段集（v1）

    func testFullRecordHasExactlyThirteenKeys() throws {
        var state = VideoProgressState()
        let path = "/movies/full.mkv"
        state.progress[path] = .init(positionMs: 12_345, durationMs: 98_765, updatedAt: t1)
        state.watched[path] = t2
        state.history[path] = .init(
            videoPath: path,
            videoName: "Full",
            videoUrl: "https://example.invalid/full.mkv",
            sourceId: "src-1",
            thumbnailUrl: "https://example.invalid/full.jpg",
            size: 4096,
            lastPositionMs: 11_000,
            durationMs: 98_000,
            addedAt: t0
        )

        let record = try firstItem(of: state)

        // 全字段齐全时正好这 13 个键。加字段必须同时改 Dart 契约测试和文档。
        XCTAssertEqual(Set(record.keys), [
            "videoPath",
            "positionMs", "durationMs", "progressUpdatedAt",
            "watchedAt",
            "videoName", "videoUrl", "sourceId", "thumbnailUrl", "size",
            "historyAddedAt", "historyLastPositionMs", "historyDurationMs",
        ])
    }

    func testDurationMsAndHistoryDurationMsAreIndependentSources() throws {
        // 同名易混：durationMs 来自 progress，historyDurationMs 来自 history。
        // 两者可以不相等，不能互相回填。
        var state = VideoProgressState()
        let path = "/movies/dual.mkv"
        state.progress[path] = .init(positionMs: 1, durationMs: 111, updatedAt: t0)
        state.history[path] = .init(
            videoPath: path,
            videoName: "Dual",
            videoUrl: "u",
            size: 0,
            durationMs: 222,
            addedAt: t0
        )

        let record = try firstItem(of: state)
        XCTAssertEqual(record["durationMs"]?.intValue, 111)
        XCTAssertEqual(record["historyDurationMs"]?.intValue, 222)
    }

    func testWatchedAtIsNotHistoryTime() throws {
        // watchedAt 是「已观看」标记时间，historyAddedAt 是历史条目时间。
        // 两者不同源，不能拿一个当另一个用。
        var state = VideoProgressState()
        let path = "/movies/marks.mkv"
        state.watched[path] = t2
        state.history[path] = .init(
            videoPath: path, videoName: "Marks", videoUrl: "u", size: 0, addedAt: t0
        )

        let record = try firstItem(of: state)
        XCTAssertEqual(record["watchedAt"], .string(Iso8601.format(t2)))
        XCTAssertEqual(record["historyAddedAt"], .string(Iso8601.format(t0)))
        XCTAssertNotEqual(record["watchedAt"], record["historyAddedAt"])
    }

    func testProgressOnlyRecordOmitsHistoryAndWatchedKeys() throws {
        var state = VideoProgressState()
        state.progress["/p.mkv"] = .init(positionMs: 5, durationMs: 10, updatedAt: t0)

        let record = try firstItem(of: state)
        XCTAssertEqual(Set(record.keys), ["videoPath", "positionMs", "durationMs", "progressUpdatedAt"])
    }

    func testWatchedOnlyRecordHasJustPathAndWatchedAt() throws {
        var state = VideoProgressState()
        state.watched["/w.mkv"] = t0

        let record = try firstItem(of: state)
        XCTAssertEqual(Set(record.keys), ["videoPath", "watchedAt"])
    }

    func testOptionalHistoryFieldsAreOmittedNotNull() throws {
        var state = VideoProgressState()
        state.history["/h.mkv"] = .init(
            videoPath: "/h.mkv", videoName: "H", videoUrl: "u", size: 0, addedAt: t0
        )

        let record = try firstItem(of: state)
        // 省略键，而不是写 null —— Dart 侧是 `if (x != null) record[...] = x`
        XCTAssertFalse(record.keys.contains("sourceId"))
        XCTAssertFalse(record.keys.contains("thumbnailUrl"))
        XCTAssertFalse(record.keys.contains("historyLastPositionMs"))
        XCTAssertFalse(record.keys.contains("historyDurationMs"))
    }

    func testSizeIsAlwaysWrittenEvenWhenZero() throws {
        var state = VideoProgressState()
        state.history["/h.mkv"] = .init(
            videoPath: "/h.mkv", videoName: "H", videoUrl: "u", size: 0, addedAt: t0
        )

        let record = try firstItem(of: state)
        // size 无值时写 0，不省略
        XCTAssertEqual(record["size"]?.intValue, 0)
    }

    // MARK: - 线格式

    func testTimestampsAreIso8601StringsAndDurationsAreMilliInts() throws {
        var state = VideoProgressState()
        let path = "/wire.mkv"
        state.progress[path] = .init(positionMs: 90_000, durationMs: 7_200_000, updatedAt: t0)

        let record = try firstItem(of: state)
        // 时间是字符串，时长是毫秒整数 —— 别写成秒或 Duration 对象
        XCTAssertEqual(record["progressUpdatedAt"], .string("2026-03-01T10:00:00.000Z"))
        XCTAssertEqual(record["positionMs"]?.intValue, 90_000)
        XCTAssertEqual(record["durationMs"]?.intValue, 7_200_000)
    }

    func testAcceptsSixDigitFractionFromDart() throws {
        // Dart 端真实写出的形态（DateTime.now() 带微秒 + 非 UTC 无 Z）
        let payload = try decodePayload("""
        {"version":1,"items":[
          {"videoPath":"/micro.mkv","positionMs":1,"durationMs":2,
           "progressUpdatedAt":"2026-03-01T10:00:00.123456Z"}
        ]}
        """)

        let progress = try XCTUnwrap(payload.items.first?.progress)
        XCTAssertEqual(
            progress.updatedAt.timeIntervalSince1970,
            1_772_359_200.123456,
            accuracy: 0.000001
        )
    }

    // MARK: - localUpdatedAt

    func testLocalUpdatedAtIsNilWhenEmpty() {
        // nil → 协调器判 skipped
        XCTAssertNil(VideoProgressState().localUpdatedAt)
    }

    func testLocalUpdatedAtTakesMaxAcrossAllThreeSources() {
        var state = VideoProgressState()
        state.progress["/a"] = .init(positionMs: 1, durationMs: 2, updatedAt: t0)
        state.watched["/b"] = t2
        state.history["/c"] = .init(videoPath: "/c", videoName: "C", videoUrl: "u", size: 0, addedAt: t1)

        XCTAssertEqual(state.localUpdatedAt, t2)
    }

    func testLocalUpdatedAtSeesHistoryOnly() {
        var state = VideoProgressState()
        state.history["/c"] = .init(videoPath: "/c", videoName: "C", videoUrl: "u", size: 0, addedAt: t1)
        XCTAssertEqual(state.localUpdatedAt, t1)
    }
}

// MARK: - 测试辅助

extension VideoProgressContractTests {

    func encodeToObject(_ payload: VideoProgressPayload) throws -> [String: JSONValue] {
        let data = try JSONEncoder().encode(payload)
        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    }

    /// 取导出的第一条记录，解成裸 JSON 对象，用于断言「键的集合」。
    func firstItem(of state: VideoProgressState) throws -> [String: JSONValue] {
        let json = try encodeToObject(state.exportPayload())
        guard case let .array(items) = try XCTUnwrap(json["items"]),
              let first = items.first,
              case let .object(record) = first
        else {
            throw XCTSkip("items 为空或形状不对")
        }
        return record
    }

    func decodePayload(_ raw: String) throws -> VideoProgressPayload {
        try JSONDecoder().decode(VideoProgressPayload.self, from: Data(raw.utf8))
    }
}
