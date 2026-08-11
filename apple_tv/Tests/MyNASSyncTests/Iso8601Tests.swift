import XCTest
@testable import MyNASSync

/// Dart 的 DateTime.toIso8601String() 小数位是 0 / 3 / 6 位三种，
/// 且非 UTC 值不带 Z。ISO8601DateFormatter 配 .withFractionalSeconds 只接受 3 位，
/// 所以这里必须用自己的解析器，且必须把三种精度都测到。
final class Iso8601Tests: XCTestCase {

    func testParsesSixFractionalDigits() throws {
        // DateTime.now() 微秒非 0 时输出这种形态，是实际最常见的形式
        let date = try XCTUnwrap(Iso8601.parse("2026-03-01T10:00:00.123456Z"))
        let expected = Date(timeIntervalSince1970: 1_772_359_200 + 0.123456)
        XCTAssertEqual(date.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.000001)
    }

    func testParsesThreeFractionalDigits() throws {
        let date = try XCTUnwrap(Iso8601.parse("2026-03-01T10:00:00.000Z"))
        XCTAssertEqual(date.timeIntervalSince1970, 1_772_359_200, accuracy: 0.0005)
    }

    func testParsesNoFractionalDigits() throws {
        let date = try XCTUnwrap(Iso8601.parse("2026-03-01T10:00:00Z"))
        XCTAssertEqual(date.timeIntervalSince1970, 1_772_359_200, accuracy: 0.0005)
    }

    func testNoSuffixIsLocalTime() throws {
        // Dart 的 DateTime.parse 把无后缀字符串当本地时间。
        // 若这里按 UTC 解析，跨端比较会整体偏移一个时区，last-wins 会判错。
        let parsed = try XCTUnwrap(Iso8601.parse("2026-03-01T10:00:00.000"))

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1
        components.hour = 10
        components.minute = 0
        components.second = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let expected = try XCTUnwrap(calendar.date(from: components))

        XCTAssertEqual(parsed.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.0005)
    }

    func testParsesNumericOffsets() throws {
        let colon = try XCTUnwrap(Iso8601.parse("2026-03-01T18:00:00.000+08:00"))
        let bare = try XCTUnwrap(Iso8601.parse("2026-03-01T18:00:00.000+0800"))
        let utc = try XCTUnwrap(Iso8601.parse("2026-03-01T10:00:00.000Z"))

        XCTAssertEqual(colon.timeIntervalSince1970, utc.timeIntervalSince1970, accuracy: 0.0005)
        XCTAssertEqual(bare.timeIntervalSince1970, utc.timeIntervalSince1970, accuracy: 0.0005)
    }

    func testMicrosecondDifferenceSurvivesParsing() throws {
        // 同一秒内仅微秒不同要能分出先后，否则 last-wins 在高频写入下失效
        let earlier = try XCTUnwrap(Iso8601.parse("2026-03-01T10:00:00.123456Z"))
        let later = try XCTUnwrap(Iso8601.parse("2026-03-01T10:00:00.123457Z"))
        XCTAssertLessThan(earlier, later)
    }

    func testReturnsNilForMalformedInput() {
        // 契约：解析不出来等价于「该字段不存在」，不抛错
        for raw in ["", "not-a-date", "2026-03-01", "2026-13-01T10:00:00Z", "2026-03-01T10:00"] {
            XCTAssertNil(Iso8601.parse(raw), "应当解析失败: \(raw)")
        }
    }

    func testFormatEmitsUtcWithThreeDigits() {
        let date = Date(timeIntervalSince1970: 1_772_359_200.123)
        XCTAssertEqual(Iso8601.format(date), "2026-03-01T10:00:00.123Z")
    }

    func testFormatRoundTrips() throws {
        let original = Date(timeIntervalSince1970: 1_772_359_200.456)
        let parsed = try XCTUnwrap(Iso8601.parse(Iso8601.format(original)))
        XCTAssertEqual(parsed.timeIntervalSince1970, original.timeIntervalSince1970, accuracy: 0.0005)
    }
}
