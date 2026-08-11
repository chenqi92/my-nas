import Flutter
import UIKit

/// 承载 FlutterViewController 的容器控制器
///
/// 存在的唯一理由：抵消 UITabBarController 给子控制器加的 bottom safe area。
///
/// 改用 UITabBarController 后，UIKit 会把 tabBar 高度算进子控制器的
/// safeAreaInsets.bottom，传到 Flutter 就是 MediaQuery.padding.bottom 多出
/// 约 49pt，每个页面底部凭空多一块空白。而旧的裸 UITabBar 架构下 FlutterView
/// 是全屏的，Flutter 侧的 extendBody / getTabBarHeight 等补偿逻辑全都按那个
/// 模型写的。这里把多出来的部分减掉，让 Flutter 看到的布局与改动前一致。
///
/// 注意不能用 additionalSafeAreaInsets = .zero —— 那个属性是「额外增加」，
/// 置零是 no-op，减不掉 UIKit 已经算进去的 tabBar 高度。
private final class FlutterHostViewController: UIViewController {

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        syncFlutterSafeArea()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        syncFlutterSafeArea()
    }

    private func syncFlutterSafeArea() {
        guard let tabBarController else { return }

        // 必须从 tabBar 自身高度推导，不能从 view.safeAreaInsets 反推：
        // safeAreaInsets 已经包含 additionalSafeAreaInsets，反推会自我参照，
        // 导致 设-49 → inset 变小 → 算出0 → 设0 → inset 变大 → 设-49 的无限振荡。
        //
        // UIKit 给子控制器加的 bottom inset 等于 tabBar 高度（该高度已含 home
        // indicator 区域）。窗口真实 bottom inset 是 home indicator 的物理高度，
        // 这部分要保留给 Flutter，所以只减掉差值。
        let windowBottom = view.window?.safeAreaInsets.bottom ?? 0
        let tabBarHeight = tabBarController.tabBar.frame.height
        let needed = tabBarController.tabBar.isHidden
            ? 0
            : max(0, tabBarHeight - windowBottom)

        let desired = UIEdgeInsets(top: 0, left: 0, bottom: -needed, right: 0)
        if additionalSafeAreaInsets != desired {
            additionalSafeAreaInsets = desired
        }
    }
}

/// 原生 Tab Bar 根控制器
///
/// 使用 UITabBarController 承载单个 FlutterViewController：
/// - iOS 26+ 的 tabBarMinimizeBehavior / bottomAccessory 都挂在
///   UITabBarController 上，裸 UITabBar 拿不到，所以必须用 controller。
/// - 五个 tab 的路由切换仍由 Flutter 侧 go_router 的 StatefulNavigationShell
///   负责，原生只有一个真实的子控制器（承载 Flutter），其余 tab 是占位。
///   因此这里拦截 shouldSelect，只把选中事件转给 Flutter，不做原生 VC 切换。
///
/// 架构：
/// ```
/// UIWindow
/// └── NativeTabBarController (UITabBarController)
///     └── viewControllers[0] (承载 FlutterViewController)
///         └── FlutterView（全屏，接收除 tabBar 命中区外的所有触摸）
/// ```
class NativeTabBarController: UITabBarController, UITabBarControllerDelegate {

    // MARK: - Properties

    /// Flutter 引擎
    private let flutterEngine: FlutterEngine

    /// Flutter 视图控制器
    private let flutterViewController: FlutterViewController

    /// 与 Flutter 通信的 Method Channel
    private var methodChannel: FlutterMethodChannel?

    /// Tab 配置
    private struct NavTabConfig {
        let icon: String           // SF Symbol name (未选中)
        let selectedIcon: String   // SF Symbol name (选中)
        let label: String
        let route: String          // Flutter 路由
    }

    /// 5 个 Tab 的配置
    private let tabConfigs: [NavTabConfig] = [
        NavTabConfig(icon: "film", selectedIcon: "film.fill", label: "影视", route: "/video"),
        NavTabConfig(icon: "music.note.list", selectedIcon: "music.note.list", label: "曲库", route: "/music"),
        NavTabConfig(icon: "photo.on.rectangle", selectedIcon: "photo.on.rectangle.fill", label: "相册", route: "/photo"),
        NavTabConfig(icon: "book", selectedIcon: "book.fill", label: "阅读", route: "/reading"),
        NavTabConfig(icon: "person.circle", selectedIcon: "person.circle.fill", label: "我的", route: "/mine"),
    ]

    /// 当前选中的 Tab 索引
    private var currentTabIndex: Int = 0

    /// Flutter 主动要求隐藏（进入播放器/阅读器等全屏页）
    private var isTabBarUserHidden = true

    /// iOS 26 滚动最小化状态
    private var isTabBarMinimized = false

    /// 是否正在处理 tab 切换（防止循环）
    private var isHandlingTabChange = false

    // MARK: - Initialization

    init(flutterEngine: FlutterEngine) {
        self.flutterEngine = flutterEngine
        self.flutterViewController = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self

        // 1. 用 FlutterViewController 作为唯一真实子控制器
        setupViewControllers()

        // 2. 配置 tab bar 外观与 iOS 26 行为
        setupTabBar()

        // 3. 设置 Method Channel
        setupMethodChannel()
    }

    // MARK: - View Controllers

    /// 只有 index 0 承载真正的 FlutterViewController，其余是空占位。
    ///
    /// Flutter 侧用的是 go_router 的 StatefulNavigationShell，五个 branch 共用
    /// 同一个 FlutterView。如果给每个 tab 都塞一个 FlutterViewController，会创建
    /// 五份渲染表面。所以这里让 UIKit 只持有一个真实控制器，tab 切换通过
    /// shouldSelect 拦截后转发给 Flutter。
    private func setupViewControllers() {
        let host = FlutterHostViewController()
        host.view.backgroundColor = .clear
        host.addChild(flutterViewController)

        let flutterView = flutterViewController.view!
        flutterView.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(flutterView)
        NSLayoutConstraint.activate([
            flutterView.topAnchor.constraint(equalTo: host.view.topAnchor),
            flutterView.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            flutterView.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            flutterView.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
        ])
        flutterViewController.didMove(toParent: host)

        var controllers: [UIViewController] = [host]
        // 其余 tab 用轻量占位控制器，只为让 tabBar 显示 5 个 item。
        // 它们永远不会真正呈现（shouldSelect 一律返回 false）。
        for _ in 1..<tabConfigs.count {
            let placeholder = UIViewController()
            placeholder.view.backgroundColor = .clear
            controllers.append(placeholder)
        }

        for (index, config) in tabConfigs.enumerated() {
            controllers[index].tabBarItem = UITabBarItem(
                title: config.label,
                image: UIImage(systemName: config.icon),
                selectedImage: UIImage(systemName: config.selectedIcon)
            )
            controllers[index].tabBarItem.tag = index
        }

        viewControllers = controllers
        selectedIndex = 0
    }

    // MARK: - Tab Bar Setup

    /// 设置 Tab Bar
    private func setupTabBar() {
        // 初始隐藏，等 Flutter 通知再显示（isTabBarUserHidden 初值即 true）
        applyTabBarHidden(true, animated: false)

        if #available(iOS 26.0, *) {
            // iOS 26+: 不设置任何 appearance，让系统自动应用 Liquid Glass。
            // 设置 UIBarAppearance 或 backgroundColor 都会破坏玻璃效果
            // （WWDC25 Session 284）。
            //
            // 滚动最小化：UIKit 需要找到一个原生 UIScrollView 才能追踪滚动，
            // 而 Flutter 的滚动全部发生在 FlutterView 内部，没有原生 scroll view。
            // 因此这里设为 .never，由 Flutter 侧监听滚动后主动调用
            // setTabBarMinimized 来驱动，行为可控且与 Android 侧逻辑一致。
            tabBarMinimizeBehavior = .never
        } else {
            // iOS < 26: 使用模糊效果作为回退
            configureAppearanceFallback()
        }
    }

    // MARK: - Appearance

    /// iOS < 26 的回退外观配置
    private func configureAppearanceFallback() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        // 使用系统模糊效果
        let isDark = traitCollection.userInterfaceStyle == .dark
        appearance.backgroundEffect = UIBlurEffect(style: isDark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight)

        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
        tabBar.isTranslucent = true

        NSLog("🔮 NativeTabBarController: Using blur effect fallback for iOS < 26")
    }

    /// 响应深色/浅色模式变化
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // iOS < 26: 更新模糊效果
        if #unavailable(iOS 26.0) {
            if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                configureAppearanceFallback()
            }
        }

        // 通知 Flutter 深色模式变化
        let isDark = traitCollection.userInterfaceStyle == .dark
        methodChannel?.invokeMethod("onThemeChanged", arguments: isDark)
    }

    // MARK: - UITabBarControllerDelegate

    /// 拦截 tab 选中：不做原生 VC 切换，只把事件转给 Flutter。
    ///
    /// 返回 false 阻止 UIKit 切换 selectedViewController —— 真正的页面切换由
    /// Flutter 侧 go_router 完成。但 tabBarItem 的选中高亮需要手动同步，
    /// 见 setSelectedTab（Flutter 切换成功后会回调过来）。
    func tabBarController(
        _ tabBarController: UITabBarController,
        shouldSelect viewController: UIViewController
    ) -> Bool {
        guard !isHandlingTabChange else { return false }
        guard let index = viewControllers?.firstIndex(of: viewController) else { return false }

        // 重复点击当前 tab 不必通知 Flutter
        guard index != currentTabIndex else { return false }

        let route = tabConfigs[index].route
        methodChannel?.invokeMethod("onTabSelected", arguments: [
            "index": index,
            "route": route,
        ])

        return false
    }

    // MARK: - Method Channel

    private func setupMethodChannel() {
        let channelName = "com.kkape.mynas/native_tab_bar"
        methodChannel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: flutterEngine.binaryMessenger
        )

        methodChannel?.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(FlutterMethodNotImplemented)
                return
            }

            switch call.method {
            case "setSelectedIndex":
                if let index = call.arguments as? Int {
                    self.setSelectedTab(index)
                }
                result(nil)

            case "getSelectedIndex":
                result(self.currentTabIndex)

            case "getTabBarHeight":
                result(self.tabBar.frame.height)

            case "getSafeAreaBottom":
                result(self.view.safeAreaInsets.bottom)

            case "isLiquidGlassSupported":
                if #available(iOS 26.0, *) {
                    result(true)
                } else {
                    result(false)
                }

            case "setTabBarVisible":
                if let visible = call.arguments as? Bool {
                    self.setTabBarVisible(visible)
                }
                result(nil)

            case "isTabBarVisible":
                result(!self.isTabBarUserHidden)

            case "setTabBarMinimized":
                // iOS 26+ 才有最小化概念；低版本忽略，保持现有行为不变。
                if let minimized = call.arguments as? Bool {
                    self.setTabBarMinimized(minimized)
                }
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    /// 从 Flutter 设置选中的 tab
    ///
    /// shouldSelect 一律返回 false，所以原生这边的选中高亮必须由 Flutter
    /// 路由切换成功后回调过来手动同步。
    private func setSelectedTab(_ index: Int) {
        guard !isHandlingTabChange else { return }
        guard index >= 0, index < (viewControllers?.count ?? 0) else { return }

        isHandlingTabChange = true
        currentTabIndex = index
        // 直接改 selectedIndex 不会触发 shouldSelect，正好用来同步高亮
        selectedIndex = index
        isHandlingTabChange = false
    }

    /// 设置 Tab Bar 是否可见
    ///
    /// UITabBarController 下不再直接改 tabBar.isHidden —— Apple 明确建议用
    /// controller 级 API，否则 iPad / visionOS 的变体 tab bar 不会跟着隐藏。
    /// setTabBarHidden 仅在 iOS 18+ 可用，这里同时做版本与运行时探测，
    /// 并为更低系统保留 alpha 回退。
    private func setTabBarVisible(_ visible: Bool) {
        isTabBarUserHidden = !visible
        // 重新显示时清掉最小化状态：最小化是「当前页面滚动位置」的产物，
        // 页面都换了就不该继承。否则从详情页返回后底栏会卡在收起状态，
        // 而 Flutter 侧的去重逻辑又不会再下发 false，直接锁死。
        if visible {
            isTabBarMinimized = false
        }
        applyTabBarHidden(!visible || isTabBarMinimized, animated: true)
    }

    /// iOS 26+ 滚动最小化
    ///
    /// UIKit 的自动最小化依赖它能找到一个原生 UIScrollView 来追踪滚动，
    /// 而 Flutter 的滚动完全发生在 FlutterView 内部，UIKit 追踪不到
    /// （tabBarMinimizeBehavior 因此设为 .never）。这里暴露一个显式开关，
    /// 由 Flutter 侧监听自己的滚动事件后调用，效果等价且跨平台行为一致。
    ///
    /// 只在 iOS 26+ 生效：低版本不存在"最小化"这一交互概念，调用即忽略，
    /// 保证老系统行为与改动前完全一致。
    private func setTabBarMinimized(_ minimized: Bool) {
        guard #available(iOS 26.0, *) else { return }
        isTabBarMinimized = minimized
        // 用户主动隐藏优先级更高，不能被最小化状态覆盖
        applyTabBarHidden(isTabBarUserHidden || minimized, animated: true)
    }

    /// 统一的隐藏落地点，避免 visible / minimized 两条路径互相打断动画
    private func applyTabBarHidden(_ hidden: Bool, animated: Bool) {
        // setTabBarHidden(_:animated:) 是 iOS 18+ 的 controller 级 API。
        // availability 保护编译期，responds(to:) 保护运行时；低版本回退。
        let selector = NSSelectorFromString("setTabBarHidden:animated:")
        if #available(iOS 18.0, *), responds(to: selector) {
            setTabBarHidden(hidden, animated: animated)
            return
        }

        UIView.animate(withDuration: animated ? 0.25 : 0) {
            self.tabBar.alpha = hidden ? 0.0 : 1.0
        } completion: { _ in
            self.tabBar.isHidden = hidden
        }
    }
}
