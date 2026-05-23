import Flutter
import UIKit

/// CarPlay 桥接通道
///
/// Swift 端的 `CarPlaySceneDelegate` 通过此 channel 调用 Dart 的
/// `MusicBrowserService`，拉取浏览树（艺术家 / 专辑 / 歌单 / 收藏）
/// 并触发播放。
///
/// channel name: `com.kkape.mynas/carplay`
///
/// Dart 端约定的方法：
/// - `getChildren(parentMediaId)` -> `[CarPlayItemDict]`
/// - `getMediaItem(mediaId)`      -> `CarPlayItemDict?`
/// - `playFromMediaId(mediaId)`   -> `void`
/// - `getNowPlaying()`            -> `CarPlayItemDict?`
///
/// 其中 `CarPlayItemDict` 是 JSON 兼容的 Map：
/// ```
/// {
///   "id": String,
///   "title": String,
///   "subtitle": String?,   // 通常是 artist 或 trackCount
///   "album": String?,
///   "isPlayable": Bool,
///   "isBrowsable": Bool,
///   "artUri": String?
/// }
/// ```
class CarPlayChannel: NSObject, FlutterPlugin {

    /// 进程内单例，供 CarPlaySceneDelegate 调用
    static let shared = CarPlayChannel()

    /// 给 CarPlay 侧广播 Now Playing 变化的回调
    /// Dart 端在 mediaItem 变化时通过 `nowPlayingChanged` 反向调进来
    var onNowPlayingChanged: ((CarPlayMediaItem?) -> Void)?

    private var channel: FlutterMethodChannel?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.kkape.mynas/carplay",
            binaryMessenger: registrar.messenger()
        )
        shared.channel = channel
        registrar.addMethodCallDelegate(shared, channel: channel)
        NSLog("🚗 CarPlayChannel: registered")
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "nowPlayingChanged":
            let dict = call.arguments as? [String: Any]
            let item = dict.flatMap { CarPlayMediaItem(dict: $0) }
            DispatchQueue.main.async { [weak self] in
                self?.onNowPlayingChanged?(item)
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Swift → Dart

    /// 拉取浏览树某个节点的子项
    func getChildren(parentMediaId: String, completion: @escaping ([CarPlayMediaItem]) -> Void) {
        guard let channel = channel else {
            NSLog("🚗 CarPlayChannel: getChildren called but channel not registered yet")
            completion([])
            return
        }
        channel.invokeMethod(
            "getChildren",
            arguments: ["parentMediaId": parentMediaId]
        ) { result in
            let items = CarPlayChannel.parseItems(result)
            DispatchQueue.main.async {
                completion(items)
            }
        }
    }

    /// 触发指定 mediaId 的播放（曲目或集合）
    func playFromMediaId(_ mediaId: String) {
        guard let channel = channel else {
            NSLog("🚗 CarPlayChannel: playFromMediaId called but channel not registered yet")
            return
        }
        channel.invokeMethod(
            "playFromMediaId",
            arguments: ["mediaId": mediaId]
        ) { _ in }
    }

    /// 拉取当前正在播放的曲目（用于 CarPlay 启动时回填 Now Playing）
    func getNowPlaying(completion: @escaping (CarPlayMediaItem?) -> Void) {
        guard let channel = channel else {
            completion(nil)
            return
        }
        channel.invokeMethod("getNowPlaying", arguments: nil) { result in
            let item = (result as? [String: Any]).flatMap { CarPlayMediaItem(dict: $0) }
            DispatchQueue.main.async {
                completion(item)
            }
        }
    }

    // MARK: - Private

    private static func parseItems(_ raw: Any?) -> [CarPlayMediaItem] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.compactMap { CarPlayMediaItem(dict: $0) }
    }
}

/// CarPlay 用的轻量 MediaItem 视图
struct CarPlayMediaItem {
    let id: String
    let title: String
    let subtitle: String?
    let album: String?
    let isPlayable: Bool
    let isBrowsable: Bool
    let artUri: String?

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let title = dict["title"] as? String else {
            return nil
        }
        self.id = id
        self.title = title
        self.subtitle = dict["subtitle"] as? String
        self.album = dict["album"] as? String
        self.isPlayable = (dict["isPlayable"] as? Bool) ?? false
        self.isBrowsable = (dict["isBrowsable"] as? Bool) ?? false
        self.artUri = dict["artUri"] as? String
    }
}
