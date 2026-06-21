import Flutter
import UIKit
import AVFoundation

/**
 原生 AVPlayer 视图工厂

 用于在 Flutter 中嵌入原生 AVPlayerLayer
 */
class NativeAVPlayerViewFactory: NSObject, FlutterPlatformViewFactory {

    private weak var channel: NativeAVPlayerChannel?

    init(channel: NativeAVPlayerChannel) {
        self.channel = channel
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return NativeAVPlayerPlatformView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            channel: channel
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

/**
 原生 AVPlayer Platform View

 在 Flutter widget 树中显示 AVPlayerLayer
 */
class NativeAVPlayerPlatformView: NSObject, FlutterPlatformView {

    private let containerView: UIView
    private let playerLayer: AVPlayerLayer
    private weak var controller: NativeAVPlayerController?

    /// 外部字幕 overlay（AVPlayer 无法直接挂载独立字幕文件，用此 label 绘制）
    private let subtitleLabel = UILabel()

    /// 视频填充模式
    private var videoGravity: AVLayerVideoGravity = .resizeAspect

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        channel: NativeAVPlayerChannel?
    ) {
        // 创建容器视图
        containerView = UIView(frame: frame)
        containerView.backgroundColor = .black
        containerView.clipsToBounds = true

        // 创建播放器图层
        playerLayer = AVPlayerLayer()
        playerLayer.frame = containerView.bounds
        playerLayer.videoGravity = videoGravity
        playerLayer.backgroundColor = UIColor.black.cgColor

        super.init()

        // 解析参数
        if let argsDict = args as? [String: Any] {
            // 获取播放器 ID
            if let playerId = argsDict["playerId"] as? Int64,
               let playerController = channel?.getPlayer(playerId) {
                self.controller = playerController
                playerLayer.player = playerController.player

                // 注册 playerLayer 到控制器（用于画中画）
                playerController.setupPlayerLayer(playerLayer)
            }

            // 设置填充模式
            if let fitMode = argsDict["fit"] as? String {
                switch fitMode {
                case "contain":
                    videoGravity = .resizeAspect
                case "cover":
                    videoGravity = .resizeAspectFill
                case "fill":
                    videoGravity = .resize
                default:
                    videoGravity = .resizeAspect
                }
                playerLayer.videoGravity = videoGravity
            }
        }

        // 添加图层
        containerView.layer.addSublayer(playerLayer)

        // 外部字幕 overlay
        configureSubtitleLabel()
        containerView.addSubview(subtitleLabel)
        containerView.bringSubviewToFront(subtitleLabel)
        controller?.setSubtitleOverlayLabel(subtitleLabel)
        layoutSubtitleLabel()

        // 监听布局变化
        containerView.addObserver(self, forKeyPath: "bounds", options: [.new], context: nil)
    }

    private func configureSubtitleLabel() {
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        subtitleLabel.textColor = .white
        subtitleLabel.font = .systemFont(ofSize: 18, weight: .medium)
        subtitleLabel.shadowColor = .black
        subtitleLabel.shadowOffset = CGSize(width: 1, height: 1)
        subtitleLabel.isHidden = true
        subtitleLabel.isUserInteractionEnabled = false
    }

    private func layoutSubtitleLabel() {
        let bounds = containerView.bounds
        let width = bounds.width * 0.9
        let height: CGFloat = 80
        subtitleLabel.frame = CGRect(
            x: (bounds.width - width) / 2,
            y: bounds.height - height - 24,
            width: width,
            height: height
        )
    }

    deinit {
        containerView.removeObserver(self, forKeyPath: "bounds")
    }

    func view() -> UIView {
        return containerView
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "bounds" {
            // 更新播放器图层大小
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = containerView.bounds
            CATransaction.commit()
            layoutSubtitleLabel()
        }
    }
}

// MARK: - 扩展：支持安全区域

extension NativeAVPlayerPlatformView {
    /// 更新视频填充模式
    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        videoGravity = gravity
        playerLayer.videoGravity = gravity
    }
}
