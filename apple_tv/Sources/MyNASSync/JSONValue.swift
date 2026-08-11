import Foundation

/// 最小 JSON 值模型。
///
/// 存在的唯一理由是 manifest 必须**原样保留**其它模块的条目。Dart 侧一轮同步
/// （cloud_sync_service.dart）会把整个 manifest 拷进 newManifest，只替换自己
/// 模块的 key 再整体写回。tvOS 端只同步 video_progress，如果写 manifest 时
/// 只放这一个 key，就会抹掉另外 7 个模块的 updatedAt —— 那些模块在 Flutter 端
/// 会被判成「远端没有记录」，于是每轮都重新整表推送。
///
/// 所以这里不建模成 `[String: Int]`，而是保留任意 JSON 结构，
/// 只定点改写目标 key 的 updatedAt。
public enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

public extension JSONValue {
    /// 整数取值。JSON 里 `1` 和 `1.0` 都可能出现（不同语言的编码器行为不同），
    /// 小数部分为 0 的 double 也按整数返回。
    var intValue: Int? {
        switch self {
        case let .int(value):
            return value
        case let .double(value):
            guard value.rounded() == value, value.magnitude < Double(Int.max) else { return nil }
            return Int(value)
        default:
            return nil
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "不是合法的 JSON 值"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}
