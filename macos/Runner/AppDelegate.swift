import Cocoa
import CoreSpotlight
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var spotlightChannel: SpotlightChannel?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Spotlight 搜索结果被点击 → CSSearchableItemActionType
  /// 把 unique id（mynas://kind/id 形式）转给 Dart 由 GoRouter 接管。
  override func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                            restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
    if userActivity.activityType == CSSearchableItemActionType,
       let channel = spotlightChannel,
       channel.handleSpotlightActivity(userActivity) {
      return true
    }
    return false
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // 注册自定义 MethodChannel 插件
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }

    // 注册 Widget 数据通道
    _ = WidgetDataChannel(messenger: controller.engine.binaryMessenger)

    // 注册 Core Spotlight 索引通道
    spotlightChannel = SpotlightChannel(messenger: controller.engine.binaryMessenger)

    // 注册显示能力检测通道 (HDR)
    DisplayCapabilityChannel.register(
      with: controller.engine.registrar(forPlugin: "DisplayCapabilityChannel")
    )

    // 注册音频能力检测通道 (直通)
    AudioCapabilityChannel.register(
      with: controller.engine.registrar(forPlugin: "AudioCapabilityChannel")
    )

    // 注册原生模糊视图 Platform View
    // 用于实现真正的 macOS 系统级毛玻璃效果
    NativeBlurViewPlugin.register(
      with: controller.engine.registrar(forPlugin: "NativeBlurViewPlugin")
    )

    // 注册原生 AVPlayer 通道
    // 用于播放 Dolby Vision 等需要原生支持的视频格式
    NativeAVPlayerChannel.register(
      with: controller.engine.registrar(forPlugin: "NativeAVPlayerChannel")
    )

    // 注册玻璃按钮组 / 弹出菜单 (macOS Liquid Glass)
    GlassButtonGroupPlugin.register(
      with: controller.engine.registrar(forPlugin: "GlassButtonGroupPlugin")
    )
    GlassPopupMenuPlugin.register(
      with: controller.engine.registrar(forPlugin: "GlassPopupMenuPlugin")
    )

    // 注册桌面歌词通道
    // 用于在独立窗口显示歌词
    DesktopLyricChannel.register(
      with: controller.engine.registrar(forPlugin: "DesktopLyricChannel")
    )

    // 注册状态栏播放器通道
    // 用于在菜单栏显示迷你播放器
    StatusBarChannel.register(
      with: controller.engine.registrar(forPlugin: "StatusBarChannel")
    )
  }
}
