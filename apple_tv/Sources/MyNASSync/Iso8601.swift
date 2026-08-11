import Foundation

/// video_progress 契约的时间戳编解码。
///
/// 见 docs/sync-contract-video-progress.md「时间戳格式」。Dart 的
/// `DateTime.toIso8601String()` 有三种小数位（0 / 3 / 6）且可能不带 `Z`，
/// `ISO8601DateFormatter` 只接受 3 位，所以这里手写解析。
///
/// 关键语义：**不带 `Z` 也不带偏移的字符串按本地时区解释**，与 Dart 的
/// `DateTime.parse` 一致。否则 last-wins 的胜负会在跨时区时算错。
public enum Iso8601 {
    /// 写出去统一用 UTC + 3 位小数 + `Z`（契约推荐的形态）。
    public static func format(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        // 纳秒转毫秒时向下取整，避免出现 .1000
        let millis = min(999, (c.nanosecond ?? 0) / 1_000_000)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
            c.year ?? 0, c.month ?? 1, c.day ?? 1,
            c.hour ?? 0, c.minute ?? 0, c.second ?? 0, millis
        )
    }

    /// 容忍 0 / 3 / 6 位小数、`Z`、`+08:00` / `+0800` 偏移、无后缀（本地时区）。
    /// 无法解析时返回 nil —— 契约要求「解析不了当作没有该字段」，不抛错。
    public static func parse(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard s.count >= 19 else { return nil }

        var scanner = Cursor(s)
        guard let year = scanner.int(4), scanner.match("-"),
              let month = scanner.int(2), scanner.match("-"),
              let day = scanner.int(2),
              scanner.match("T") || scanner.match(" "),
              let hour = scanner.int(2), scanner.match(":"),
              let minute = scanner.int(2), scanner.match(":"),
              let second = scanner.int(2)
        else { return nil }

        // 小数秒：位数不定，全部读掉后归一到纳秒
        var nanos = 0
        if scanner.match(".") {
            let digits = scanner.digits()
            guard !digits.isEmpty else { return nil }
            let capped = String(digits.prefix(9))
            let padded = capped.padding(
                toLength: 9, withPad: "0", startingAt: 0
            )
            nanos = Int(padded) ?? 0
        }

        // 时区：Z / ±HH:MM / ±HHMM / 无
        let timeZone: TimeZone
        if scanner.match("Z") || scanner.match("z") {
            timeZone = TimeZone(identifier: "UTC")!
        } else if let sign = scanner.sign() {
            guard let offHour = scanner.int(2) else { return nil }
            _ = scanner.match(":")
            let offMinute = scanner.int(2) ?? 0
            let seconds = sign * (offHour * 3600 + offMinute * 60)
            guard let tz = TimeZone(secondsFromGMT: seconds) else { return nil }
            timeZone = tz
        } else if scanner.isAtEnd {
            // 无后缀 => 本地时区（与 Dart DateTime.parse 一致）
            timeZone = TimeZone.current
        } else {
            return nil
        }

        guard scanner.isAtEnd else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = nanos
        components.timeZone = timeZone

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: components)
    }

    /// 极小的字符游标，避免为了解析日期引入正则。
    private struct Cursor {
        private let chars: [Character]
        private var index: Int = 0

        init(_ s: String) { chars = Array(s) }

        var isAtEnd: Bool { index >= chars.count }

        mutating func match(_ c: Character) -> Bool {
            guard index < chars.count, chars[index] == c else { return false }
            index += 1
            return true
        }

        mutating func sign() -> Int? {
            guard index < chars.count else { return nil }
            switch chars[index] {
            case "+": index += 1; return 1
            case "-": index += 1; return -1
            default: return nil
            }
        }

        mutating func int(_ width: Int) -> Int? {
            guard index + width <= chars.count else { return nil }
            var value = 0
            for offset in 0..<width {
                guard let digit = chars[index + offset].wholeNumberValue,
                      chars[index + offset].isNumber
                else { return nil }
                value = value * 10 + digit
            }
            index += width
            return value
        }

        mutating func digits() -> String {
            var out = ""
            while index < chars.count, chars[index].isNumber {
                out.append(chars[index])
                index += 1
            }
            return out
        }
    }
}
