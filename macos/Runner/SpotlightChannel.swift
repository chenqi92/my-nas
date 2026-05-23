import Cocoa
import CoreSpotlight
import FlutterMacOS

/// macOS Core Spotlight 索引通道
///
/// Dart 侧通过 `com.kkape.mynas/spotlight` 调用：
/// - `upsertItems(List<Map>)`：批量索引（title/subtitle/kind/thumbPath?）
/// - `deleteItems(List<String>)`：按 id 删除
/// - `deleteAll()`：清空本 App 的全部索引
/// - `consumePendingDeepLink()`：读取 cold-start 时 NSUserActivity 缓存的 id
///
/// 反向：原生收到 CSSearchableItemActionType 后通过 `onSpotlightOpen` 主动回调。
final class SpotlightChannel {
    static let channelName = "com.kkape.mynas/spotlight"

    /// 单例，AppDelegate 处理 userActivity 时使用。
    static var shared: SpotlightChannel?

    private let channel: FlutterMethodChannel
    private var pendingDeepLink: String?

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: SpotlightChannel.channelName,
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        SpotlightChannel.shared = self
    }

    /// domain identifier = Bundle ID + ".spotlight"。
    /// Debug/Release Bundle ID 可能不同，从 Info.plist 派生而非硬编码。
    private var domainIdentifier: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.kkape.mynas"
        return "\(bundleID).spotlight"
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "upsertItems":
            upsertItems(call.arguments, result: result)
        case "deleteItems":
            deleteItems(call.arguments, result: result)
        case "deleteAll":
            deleteAll(result: result)
        case "consumePendingDeepLink":
            let pending = pendingDeepLink
            pendingDeepLink = nil
            result(pending)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func upsertItems(_ args: Any?, result: @escaping FlutterResult) {
        guard let items = args as? [[String: Any]] else {
            result(FlutterError(code: "INVALID_ARGS", message: "items must be List<Map>", details: nil))
            return
        }

        let domain = domainIdentifier
        let searchable: [CSSearchableItem] = items.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let title = dict["title"] as? String,
                  let kind = dict["kind"] as? String else {
                return nil
            }
            let subtitle = dict["subtitle"] as? String
            let thumbPath = dict["thumbPath"] as? String

            let attrs = CSSearchableItemAttributeSet(itemContentType: Self.contentType(forKind: kind))
            attrs.title = title
            attrs.displayName = title
            if let subtitle = subtitle, !subtitle.isEmpty {
                attrs.contentDescription = subtitle
            }
            attrs.identifier = id
            attrs.keywords = ["MyNAS", kind]

            if let path = thumbPath, !path.isEmpty,
               FileManager.default.fileExists(atPath: path) {
                attrs.thumbnailURL = URL(fileURLWithPath: path)
            }

            return CSSearchableItem(
                uniqueIdentifier: id,
                domainIdentifier: domain,
                attributeSet: attrs
            )
        }

        guard !searchable.isEmpty else {
            result(0)
            return
        }

        CSSearchableIndex.default().indexSearchableItems(searchable) { error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(
                        code: "INDEX_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    ))
                } else {
                    result(searchable.count)
                }
            }
        }
    }

    private func deleteItems(_ args: Any?, result: @escaping FlutterResult) {
        guard let ids = args as? [String], !ids.isEmpty else {
            result(nil)
            return
        }
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids) { error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(
                        code: "DELETE_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    ))
                } else {
                    result(nil)
                }
            }
        }
    }

    private func deleteAll(result: @escaping FlutterResult) {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domainIdentifier]
        ) { error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(
                        code: "DELETE_ALL_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    ))
                } else {
                    result(nil)
                }
            }
        }
    }

    /// 处理 Spotlight 点击事件：把 unique id 透传到 Dart。
    /// 若 Dart 尚未注册回调（cold-start 太早），暂存以便后续 consume。
    @discardableResult
    func handleSpotlightActivity(_ userActivity: NSUserActivity) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let id = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            return false
        }
        pendingDeepLink = id
        channel.invokeMethod("onSpotlightOpen", arguments: id)
        return true
    }

    private static func contentType(forKind kind: String) -> String {
        switch kind {
        case "video":
            return "public.movie"
        case "music":
            return "public.audio"
        case "book", "note":
            return "public.text"
        case "comic":
            return "public.image"
        default:
            return "public.item"
        }
    }
}
