import Foundation

/// 本地状态持久化。协议化便于测试用内存实现。
public protocol VideoProgressStore: Sendable {
    func load() throws -> VideoProgressState
    func save(_ state: VideoProgressState) throws
}

/// 写到 Application Support 下的单个 JSON 文件。
///
/// Dart 端用三个 Hive box；tvOS 端数据量小（≤100 条历史 + 进度表），
/// 一个文件足够，也避免引入数据库依赖。文件格式是本端私有的，
/// **不是**跨端契约的一部分 —— 跨端契约只有 video_progress.json。
public struct FileVideoProgressStore: VideoProgressStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// 默认位置：Application Support/MyNASTV/video_progress_state.json
    public init(fileManager: FileManager = .default) throws {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("MyNASTV", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("video_progress_state.json")
    }

    public func load() throws -> VideoProgressState {
        guard let data = try? Data(contentsOf: url) else { return VideoProgressState() }
        // 本地文件损坏时从空状态开始，而不是让 App 起不来。
        // 远端还在，下一轮同步会拉回来。
        return (try? Self.decoder.decode(VideoProgressState.self, from: data))
            ?? VideoProgressState()
    }

    public func save(_ state: VideoProgressState) throws {
        let data = try Self.encoder.encode(state)
        // 原子写：崩溃或断电不会留下半个 JSON
        try data.write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Iso8601.format(date))
        }
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = Iso8601.parse(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "无法解析时间戳: \(raw)"
                )
            }
            return date
        }
        return decoder
    }()
}

/// 内存实现，测试和预览用。
public final class InMemoryVideoProgressStore: VideoProgressStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state: VideoProgressState

    public init(state: VideoProgressState = VideoProgressState()) {
        self.state = state
    }

    public func load() throws -> VideoProgressState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func save(_ state: VideoProgressState) throws {
        lock.lock()
        defer { lock.unlock() }
        self.state = state
    }
}
