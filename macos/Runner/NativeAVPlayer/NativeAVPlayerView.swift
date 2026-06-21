import Cocoa
import FlutterMacOS
import AVFoundation

/**
 原生 AVPlayer 视图工厂 (macOS)

 用于在 Flutter 中嵌入原生 AVPlayerLayer
 */
class NativeAVPlayerViewFactory: NSObject, FlutterPlatformViewFactory {

    private weak var channel: NativeAVPlayerChannel?

    init(channel: NativeAVPlayerChannel) {
        self.channel = channel
        super.init()
    }

    func create(
        withViewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> NSView {
        return NativeAVPlayerPlatformView(
            viewIdentifier: viewId,
            arguments: args,
            channel: channel
        )
    }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

/**
 原生 AVPlayer Platform View (macOS)

 在 Flutter widget 树中显示 AVPlayerLayer
 */
class NativeAVPlayerPlatformView: NSView {

    private let playerLayer: AVPlayerLayer
    private weak var controller: NativeAVPlayerController?

    /// 外部字幕 overlay（AVPlayer 无法直接挂载独立字幕文件，用此 label 绘制）
    private let subtitleLabel = NSTextField(labelWithString: "")

    /// 视频填充模式
    private var videoGravity: AVLayerVideoGravity = .resizeAspect

    init(
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        channel: NativeAVPlayerChannel?
    ) {
        // 创建播放器图层
        playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = videoGravity
        playerLayer.backgroundColor = NSColor.black.cgColor

        super.init(frame: .zero)

        // 设置视图属性
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // 添加播放器图层
        layer?.addSublayer(playerLayer)

        // 解析参数
        if let argsDict = args as? [String: Any] {
            // 获取播放器 ID
            if let playerId = argsDict["playerId"] as? Int64,
               let playerController = channel?.getPlayer(playerId) {
                self.controller = playerController
                playerLayer.player = playerController.player

                // 注册 playerLayer 到控制器
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

        // 外部字幕 overlay
        configureSubtitleLabel()
        addSubview(subtitleLabel)
        controller?.setSubtitleOverlayLabel(subtitleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureSubtitleLabel() {
        subtitleLabel.isEditable = false
        subtitleLabel.isSelectable = false
        subtitleLabel.isBordered = false
        subtitleLabel.drawsBackground = false
        subtitleLabel.textColor = .white
        subtitleLabel.alignment = .center
        subtitleLabel.font = .systemFont(ofSize: 18, weight: .medium)
        subtitleLabel.maximumNumberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.cell?.wraps = true
        subtitleLabel.isHidden = true
        subtitleLabel.wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowColor = .black
        shadow.shadowOffset = NSSize(width: 1, height: -1)
        shadow.shadowBlurRadius = 2
        subtitleLabel.shadow = shadow
    }

    override func layout() {
        super.layout()
        // 更新播放器图层大小
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
        // 字幕 overlay 置于底部居中（NSView 默认非翻转坐标，y=0 在底部）
        let width = bounds.width * 0.9
        let height: CGFloat = 80
        subtitleLabel.frame = NSRect(
            x: (bounds.width - width) / 2,
            y: 24,
            width: width,
            height: height
        )
    }

    /// 更新视频填充模式
    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        videoGravity = gravity
        playerLayer.videoGravity = gravity
    }
}
