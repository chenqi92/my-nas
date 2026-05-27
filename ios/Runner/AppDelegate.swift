import CarPlay
import Flutter
import UIKit

@main
@objc class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    /// Flutter 引擎（需要手动管理生命周期）
    lazy var flutterEngine: FlutterEngine = {
        let engine = FlutterEngine(name: "main engine")
        return engine
    }()

    /// 原生 Tab Bar 控制器（iOS 平台）
    private var nativeTabBarController: NativeTabBarController?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 1. 启动 Flutter 引擎
        flutterEngine.run()
        NSLog("🔮 AppDelegate: Flutter engine started")

        // 2. 注册 Flutter 插件
        // 注意：使用 flutterEngine.registrar() 而非 FlutterAppDelegate 的 self.registrar()
        GeneratedPluginRegistrant.register(with: flutterEngine)
        registerCustomPlugins()

        // 3. 启用远程控制事件接收
        // 这是 iOS Now Playing / 灵动岛显示的关键
        application.beginReceivingRemoteControlEvents()

        // 4. window 由 SceneDelegate 在 scene(_:willConnectTo:options:) 中创建
        //    iOS 13+ scene-based lifecycle 下，AppDelegate 不能直接管理 window：
        //    必须用 UIWindow(windowScene:) 关联到具体的 UIWindowScene 才能显示。
        return true
    }

    /// 注册自定义插件
    private func registerCustomPlugins() {
        // 注册自定义的 Music Live Activity Channel
        // 用于支持个人开发者账号（不需要 Push Notification 能力）
        if let registrar = flutterEngine.registrar(forPlugin: "MusicLiveActivityChannel") {
            MusicLiveActivityChannel.register(with: registrar)
        }

        // 注册原生日志桥接通道
        // 用于将 Swift 端日志（包括 Widget Extension）上传到 RabbitMQ
        if let registrar = flutterEngine.registrar(forPlugin: "NativeLogBridge") {
            NativeLogBridge.register(with: registrar)
        }

        // 注册 Chromaprint 音频指纹通道
        if let registrar = flutterEngine.registrar(forPlugin: "ChromaprintChannel") {
            ChromaprintChannel.register(with: registrar)
        }

        // 注册 Widget 数据通道
        // 用于将 Flutter 数据同步到 Home Screen Widgets
        if let registrar = flutterEngine.registrar(forPlugin: "WidgetDataChannel") {
            WidgetDataChannel.register(with: registrar)
        }

        // 注册显示能力检测通道 (HDR)
        if let registrar = flutterEngine.registrar(forPlugin: "DisplayCapabilityChannel") {
            DisplayCapabilityChannel.register(with: registrar)
        }

        // 注册音频能力检测通道 (直通)
        if let registrar = flutterEngine.registrar(forPlugin: "AudioCapabilityChannel") {
            AudioCapabilityChannel.register(with: registrar)
        }

        // 注册原生模糊视图 Platform View
        // 用于实现真正的 iOS 系统级毛玻璃效果
        if let registrar = flutterEngine.registrar(forPlugin: "NativeBlurViewPlugin") {
            NativeBlurViewPlugin.register(with: registrar)
        }

        // 注册 Liquid Glass 视图和通道
        // 注意：这些现在主要用于子页面，底部导航栏由 NativeTabBarController 处理
        if let registrar = flutterEngine.registrar(forPlugin: "LiquidGlassPlugin") {
            LiquidGlassPlugin.register(with: registrar)
        }
        if let registrar = flutterEngine.registrar(forPlugin: "LiquidGlassChannel") {
            LiquidGlassChannel.register(with: registrar)
        }

        // 注册原生 AVPlayer 通道
        // 用于播放 Dolby Vision 等需要原生支持的视频格式
        if let registrar = flutterEngine.registrar(forPlugin: "NativeAVPlayerChannel") {
            NativeAVPlayerChannel.register(with: registrar)
        }

        // 注册玻璃按钮组 Platform View
        // 用于实现 iOS 26 Liquid Glass 风格的顶栏按钮
        if let registrar = flutterEngine.registrar(forPlugin: "GlassButtonGroupPlugin") {
            GlassButtonGroupPlugin.register(with: registrar)
        }

        // 注册玻璃搜索栏 Platform View
        // 用于实现 iOS 26 Liquid Glass 风格的搜索框
        if let registrar = flutterEngine.registrar(forPlugin: "GlassSearchBarPlugin") {
            GlassSearchBarPlugin.register(with: registrar)
        }

        // 注册玻璃弹出菜单
        // 用于实现 iOS 26 Liquid Glass 风格的上下文菜单
        if let registrar = flutterEngine.registrar(forPlugin: "GlassPopupMenuPlugin") {
            GlassPopupMenuPlugin.register(with: registrar)
        }

        // 注册玻璃底部弹框
        // 用于实现 iOS 26 Liquid Glass 风格的底部弹框
        if let registrar = flutterEngine.registrar(forPlugin: "GlassBottomSheetPlugin") {
            GlassBottomSheetPlugin.register(with: registrar)
        }

        // 注册 CarPlay 桥接通道
        // Swift 侧的 CarPlaySceneDelegate 通过此 channel 调 Dart MusicBrowserService
        // 拉浏览树和触发播放
        if let registrar = flutterEngine.registrar(forPlugin: "CarPlayChannel") {
            CarPlayChannel.register(with: registrar)
        }

        NSLog("🔮 AppDelegate: Custom plugins registered")
    }

    // MARK: - UIScene Lifecycle

    /// 按 scene role 路由：
    /// - 普通 iPhone / iPad window → SceneDelegate（在那里创建 UIWindow + 挂 NativeTabBarController）
    /// - CarPlay role → CarPlaySceneDelegate
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if #available(iOS 14.0, *) {
            if connectingSceneSession.role == UISceneSession.Role.carTemplateApplication {
                let config = UISceneConfiguration(
                    name: "CarPlay",
                    sessionRole: connectingSceneSession.role
                )
                config.delegateClass = CarPlaySceneDelegate.self
                NSLog("🚗 AppDelegate: CarPlay scene configuration provided")
                return config
            }
        }
        let config = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = SceneDelegate.self
        return config
    }

    /// App 即将终止时清理 Live Activity
    func applicationWillTerminate(_ application: UIApplication) {
        // 结束所有 Live Activities
        if #available(iOS 16.1, *) {
            print("AppDelegate: App terminating, ending all Live Activities")
            MusicLiveActivityManager.shared.endAllActivities()
        }
    }

    /// App 进入后台时的处理
    /// 注意：不在这里结束 Live Activity，因为用户可能希望在后台继续显示
    /// 只有在 app 完全终止时才清理
    func applicationDidEnterBackground(_ application: UIApplication) {
        print("AppDelegate: App entered background")

        // 重要：重新启用远程控制事件接收
        // 当 app 从前台返回后台时，需要重新"声明"我们是活跃的音频播放器
        // 这有助于 iOS 在灵动岛中正确显示 Now Playing 信息
        application.beginReceivingRemoteControlEvents()
        print("AppDelegate: Re-enabled remote control events")
    }

    /// App 即将返回前台
    func applicationWillEnterForeground(_ application: UIApplication) {
        print("AppDelegate: App will enter foreground")
    }

    /// App 已激活（返回前台）
    func applicationDidBecomeActive(_ application: UIApplication) {
        print("AppDelegate: App did become active")

        // 确保远程控制事件仍然激活
        application.beginReceivingRemoteControlEvents()
    }
}

// MARK: - SceneDelegate

/// 普通 iPhone / iPad window 的 scene delegate。
/// iOS 13+ scene-based lifecycle 下，window 必须通过 UIWindow(windowScene:) 创建并
/// 关联到具体的 UIWindowScene；老式 UIWindow(frame:) + makeKeyAndVisible() 在 iOS 18
/// 上不再生效（导致 application.windows 为空、屏幕全黑）。
@objc class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var nativeTabBarController: NativeTabBarController?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            NSLog("🔮 SceneDelegate: AppDelegate not available, abort")
            return
        }

        let window = UIWindow(windowScene: windowScene)
        let tabBar = NativeTabBarController(flutterEngine: appDelegate.flutterEngine)
        window.rootViewController = tabBar
        window.makeKeyAndVisible()

        self.window = window
        self.nativeTabBarController = tabBar
        // 兼容部分插件仍读 AppDelegate.window
        appDelegate.window = window
        NSLog("🔮 SceneDelegate: window created (NativeTabBarController as root)")
    }
}
