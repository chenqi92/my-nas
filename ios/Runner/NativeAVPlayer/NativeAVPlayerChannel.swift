import Flutter
import UIKit
import AVFoundation
import AVKit

/**
 原生 AVPlayer 播放器 Flutter 插件

 用于在 iOS 上播放 Dolby Vision 等需要原生支持的视频格式
 */
class NativeAVPlayerChannel: NSObject, FlutterPlugin {

    static let channelName = "com.kkape.mynas/native_av_player"
    static let eventChannelName = "com.kkape.mynas/native_av_player/events"

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    /// 播放器实例管理
    private var players: [Int64: NativeAVPlayerController] = [:]
    private var nextPlayerId: Int64 = 1

    /// 注册插件
    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = NativeAVPlayerChannel()

        // Method Channel
        let methodChannel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        instance.methodChannel = methodChannel
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        // Event Channel
        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: registrar.messenger()
        )
        instance.eventChannel = eventChannel
        eventChannel.setStreamHandler(instance)

        // 注册 Platform View
        let factory = NativeAVPlayerViewFactory(channel: instance)
        registrar.register(factory, withId: "native_av_player_view")
    }

    /// 获取播放器实例
    func getPlayer(_ playerId: Int64) -> NativeAVPlayerController? {
        return players[playerId]
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {
        case "create":
            handleCreate(result: result)

        case "open":
            guard let playerId = args?["playerId"] as? Int64,
                  let url = args?["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId or url", details: nil))
                return
            }
            let headers = args?["headers"] as? [String: String]
            handleOpen(playerId: playerId, url: url, headers: headers, result: result)

        case "play":
            guard let playerId = args?["playerId"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId", details: nil))
                return
            }
            handlePlay(playerId: playerId, result: result)

        case "pause":
            guard let playerId = args?["playerId"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId", details: nil))
                return
            }
            handlePause(playerId: playerId, result: result)

        case "seek":
            guard let playerId = args?["playerId"] as? Int64,
                  let positionMs = args?["position"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId or position", details: nil))
                return
            }
            handleSeek(playerId: playerId, positionMs: positionMs, result: result)

        case "setSpeed":
            guard let playerId = args?["playerId"] as? Int64,
                  let speed = args?["speed"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId or speed", details: nil))
                return
            }
            handleSetSpeed(playerId: playerId, speed: Float(speed), result: result)

        case "setVolume":
            guard let playerId = args?["playerId"] as? Int64,
                  let volume = args?["volume"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId or volume", details: nil))
                return
            }
            handleSetVolume(playerId: playerId, volume: Float(volume), result: result)

        case "getAudioTracks":
            guard let playerId = args?["playerId"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId", details: nil))
                return
            }
            handleGetAudioTracks(playerId: playerId, result: result)

        case "setAudioTrack":
            guard let playerId = args?["playerId"] as? Int64,
                  let index = args?["index"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId or index", details: nil))
                return
            }
            handleSetAudioTrack(playerId: playerId, index: index, result: result)

        case "getSubtitleTracks":
            guard let playerId = args?["playerId"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId", details: nil))
                return
            }
            handleGetSubtitleTracks(playerId: playerId, result: result)

        case "setSubtitleTrack":
            guard let playerId = args?["playerId"] as? Int64,
                  let index = args?["index"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId or index", details: nil))
                return
            }
            handleSetSubtitleTrack(playerId: playerId, index: index, result: result)

        case "disableSubtitle":
            guard let playerId = args?["playerId"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId", details: nil))
                return
            }
            handleDisableSubtitle(playerId: playerId, result: result)

        case "loadExternalSubtitle":
            guard let playerId = args?["playerId"] as? Int64,
                  let url = args?["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId or url", details: nil))
                return
            }
            handleLoadExternalSubtitle(
                playerId: playerId,
                url: url,
                title: args?["title"] as? String,
                language: args?["language"] as? String,
                result: result
            )

        case "getState":
            guard let playerId = args?["playerId"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId", details: nil))
                return
            }
            handleGetState(playerId: playerId, result: result)

        case "screenshot":
            guard let playerId = args?["playerId"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId", details: nil))
                return
            }
            handleScreenshot(playerId: playerId, result: result)

        case "enterPiP":
            guard let playerId = args?["playerId"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId", details: nil))
                return
            }
            handleEnterPiP(playerId: playerId, result: result)

        case "exitPiP":
            guard let playerId = args?["playerId"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId", details: nil))
                return
            }
            handleExitPiP(playerId: playerId, result: result)

        case "dispose":
            guard let playerId = args?["playerId"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId", details: nil))
                return
            }
            handleDispose(playerId: playerId, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Handler Methods

    private func handleCreate(result: @escaping FlutterResult) {
        let playerId = nextPlayerId
        nextPlayerId += 1

        let controller = NativeAVPlayerController(playerId: playerId) { [weak self] event in
            self?.sendEvent(event)
        }
        players[playerId] = controller

        result(playerId)
    }

    private func handleOpen(playerId: Int64, url: String, headers: [String: String]?, result: @escaping FlutterResult) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }

        controller.open(url: url, headers: headers) { error in
            if let error = error {
                result(FlutterError(code: "OPEN_FAILED", message: error.localizedDescription, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func handlePlay(playerId: Int64, result: @escaping FlutterResult) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }
        controller.play()
        result(nil)
    }

    private func handlePause(playerId: Int64, result: @escaping FlutterResult) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }
        controller.pause()
        result(nil)
    }

    private func handleSeek(playerId: Int64, positionMs: Int64, result: @escaping FlutterResult) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }
        controller.seek(to: positionMs)
        result(nil)
    }

    private func handleSetSpeed(playerId: Int64, speed: Float, result: @escaping FlutterResult) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }
        controller.setSpeed(speed)
        result(nil)
    }

    private func handleSetVolume(playerId: Int64, volume: Float, result: @escaping FlutterResult) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }
        controller.setVolume(volume)
        result(nil)
    }

    private func handleGetAudioTracks(playerId: Int64, result: @escaping FlutterResult) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }
        result(controller.getAudioTracks())
    }

    private func handleSetAudioTrack(playerId: Int64, index: Int, result: @escaping FlutterResult) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }
        controller.setAudioTrack(index: index)
        result(nil)
    }

    private func handleGetSubtitleTracks(playerId: Int64, result: @escaping FlutterResult) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }
        result(controller.getSubtitleTracks())
    }

    private func handleSetSubtitleTrack(playerId: Int64, index: Int, result: @escaping FlutterResult) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }
        controller.setSubtitleTrack(index: index)
        result(nil)
    }

    private func handleDisableSubtitle(playerId: Int64, result: @escaping FlutterResult) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }
        controller.disableSubtitle()
        result(nil)
    }

    private func handleLoadExternalSubtitle(
        playerId: Int64,
        url: String,
        title: String?,
        language: String?,
        result: @escaping FlutterResult
    ) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }
        controller.loadExternalSubtitle(urlString: url, title: title, language: language) { index in
            result(index >= 0 ? index : nil)
        }
    }

    private func handleGetState(playerId: Int64, result: @escaping FlutterResult) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }
        result(controller.getState())
    }

    private func handleScreenshot(playerId: Int64, result: @escaping FlutterResult) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }
        controller.screenshot { imageData in
            result(imageData)
        }
    }

    private func handleEnterPiP(playerId: Int64, result: @escaping FlutterResult) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }
        let success = controller.enterPictureInPicture()
        result(success)
    }

    private func handleExitPiP(playerId: Int64, result: @escaping FlutterResult) {
        guard let controller = players[playerId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Player not found", details: nil))
            return
        }
        let success = controller.exitPictureInPicture()
        result(success)
    }

    private func handleDispose(playerId: Int64, result: @escaping FlutterResult) {
        if let controller = players.removeValue(forKey: playerId) {
            controller.dispose()
        }
        result(nil)
    }

    // MARK: - Event Sending

    private func sendEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(event)
        }
    }
}

// MARK: - FlutterStreamHandler

extension NativeAVPlayerChannel: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
