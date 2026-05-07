import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var widgetDataChannel: WidgetDataChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 注册小组件数据通道
    widgetDataChannel = WidgetDataChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  // 窗口尺寸 / 位置 / 标题栏样式由 Dart 侧 DesktopWindowService 统一管理
  // （含上次几何恢复、最小尺寸、macOS title bar inset），不再在原生层硬编码。
}
