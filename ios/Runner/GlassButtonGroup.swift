import Flutter
import UIKit

/// iOS 26 Liquid Glass 按钮组
///
/// 使用原生 UIGlassEffect 实现真正的 iOS 26 玻璃效果
/// 多个按钮组合在同一个胶囊形玻璃背景中
///
/// iOS 26+: 使用 UIGlassEffect
/// iOS 15.5-25: 使用 UIVisualEffectView + UIBlurEffect 回退
///
/// 弹出菜单按钮使用原生 UIButton.menu + showsMenuAsPrimaryAction，点击即弹出。
/// 最低部署版本为 15.5，因此不再保留 iOS 13/14 的 UIContextMenuInteraction 回退。

// MARK: - Button Data

struct GlassButtonItem {
    let icon: String       // SF Symbol name
    let tooltip: String?
    let isMenuButton: Bool
    let menuItems: [GlassMenuItem]
    let isEnabled: Bool
    let badge: Bool
    /// ARGB32，由 Flutter 侧按主题解析后下发
    let tintColor: Int?
    let showsChevron: Bool
}

struct GlassMenuItem {
    let title: String
    let icon: String?
    let value: String
    let isDestructive: Bool
}

// MARK: - Color Bridging

extension UIColor {
    /// 从 Flutter 侧的 ARGB32 整数构造颜色（Color.toARGB32() 的结果）
    convenience init(argb: Int) {
        let alpha = CGFloat((argb >> 24) & 0xFF) / 255.0
        let red = CGFloat((argb >> 16) & 0xFF) / 255.0
        let green = CGFloat((argb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(argb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Custom Glass Container View

/// 自定义玻璃容器视图，确保圆角始终正确应用
/// 解决菜单弹出/关闭时圆角闪烁的问题
class GlassContainerView: UIView {
    private let glassView: UIVisualEffectView
    private let cornerRadius: CGFloat
    
    init(cornerRadius: CGFloat, isDark: Bool) {
        self.cornerRadius = cornerRadius
        
        // 创建玻璃效果视图
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect()
            glassEffect.isInteractive = true
            glassView = UIVisualEffectView(effect: glassEffect)
        } else {
            // iOS 26 以下没有 UIGlassEffect。thinMaterial 比 Liquid Glass 明显更"厚"，
            // 观感差距大；ultraThin 更接近，配合下面的高光描边进一步缩小差距。
            let blurStyle: UIBlurEffect.Style = isDark
                ? .systemUltraThinMaterialDark
                : .systemUltraThinMaterialLight
            glassView = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
        }

        super.init(frame: .zero)

        // 设置视图属性
        backgroundColor = .clear
        clipsToBounds = true
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous

        // iOS 26 的 Liquid Glass 自带边缘高光；低版本用一圈极细描边模拟，
        // 否则 ultraThin 在浅色背景上几乎看不出边界。
        if #unavailable(iOS 26.0) {
            layer.borderWidth = 0.5
            layer.borderColor = (isDark
                ? UIColor.white.withAlphaComponent(0.18)
                : UIColor.white.withAlphaComponent(0.55)).cgColor
        }
        
        // 设置玻璃视图
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.clipsToBounds = true
        glassView.layer.cornerRadius = cornerRadius
        glassView.layer.cornerCurve = .continuous
        glassView.overrideUserInterfaceStyle = isDark ? .dark : .light
        
        addSubview(glassView)
        
        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var contentView: UIView {
        return glassView.contentView
    }
    
    func updateTheme(isDark: Bool) {
        glassView.overrideUserInterfaceStyle = isDark ? .dark : .light

        // 只在非 iOS 26 时更新 blur effect（iOS 26 使用 UIGlassEffect 自动响应主题）
        if #unavailable(iOS 26.0) {
            let blurStyle: UIBlurEffect.Style = isDark
                ? .systemUltraThinMaterialDark
                : .systemUltraThinMaterialLight
            glassView.effect = UIBlurEffect(style: blurStyle)
            layer.borderColor = (isDark
                ? UIColor.white.withAlphaComponent(0.18)
                : UIColor.white.withAlphaComponent(0.55)).cgColor
        }
    }
    
    /// 强制在 layout 时重新应用圆角，防止系统重置
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // 确保圆角始终正确应用
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        glassView.layer.cornerRadius = cornerRadius
        glassView.layer.cornerCurve = .continuous
    }
}

// MARK: - Platform View Factory

class GlassButtonGroupFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return GlassButtonGroupPlatformView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: - Platform View

class GlassButtonGroupPlatformView: NSObject, FlutterPlatformView {
    private static let badgeSize: CGFloat = 8

    private let containerView: UIView
    private let glassContainer: GlassContainerView
    private let stackView: UIStackView
    private var buttons: [UIButton] = []
    private var methodChannel: FlutterMethodChannel?
    private let viewId: Int64
    private var isDark: Bool
    private var buttonItems: [GlassButtonItem] = []
    /// 与 Flutter 侧宽度公式共享的布局参数
    private let chevronExtraWidth: Double
    private let horizontalInset: Double
    /// 按压触觉反馈。复用同一个实例，避免每次按下都新建。
    private let selectionFeedback = UISelectionFeedbackGenerator()

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        self.viewId = viewId

        // 解析参数
        let params = args as? [String: Any] ?? [:]
        isDark = params["isDark"] as? Bool ?? false
        let buttonSize = params["buttonSize"] as? Double ?? 40.0
        // Flutter 侧已经取过 max(spacing, minSpacing)，这里直接用，
        // 保证两侧算出的总宽度一致（不一致会导致按钮被挤压）。
        let spacing = params["spacing"] as? Double ?? 8.0
        let cornerRadius = params["cornerRadius"] as? Double ?? 22.0
        let horizontalInset = params["horizontalInset"] as? Double ?? 10.0
        chevronExtraWidth = params["chevronExtraWidth"] as? Double ?? 12.0
        self.horizontalInset = horizontalInset

        // 解析按钮数据
        if let itemsData = params["items"] as? [[String: Any]] {
            buttonItems = itemsData.map { item in
                var menuItems: [GlassMenuItem] = []
                if let menuData = item["menuItems"] as? [[String: Any]] {
                    menuItems = menuData.map { menuItem in
                        GlassMenuItem(
                            title: menuItem["title"] as? String ?? "",
                            icon: menuItem["icon"] as? String,
                            value: menuItem["value"] as? String ?? "",
                            isDestructive: menuItem["isDestructive"] as? Bool ?? false
                        )
                    }
                }
                return GlassButtonItem(
                    icon: item["icon"] as? String ?? "questionmark",
                    tooltip: item["tooltip"] as? String,
                    isMenuButton: item["isMenuButton"] as? Bool ?? false,
                    menuItems: menuItems,
                    isEnabled: item["isEnabled"] as? Bool ?? true,
                    badge: item["badge"] as? Bool ?? false,
                    tintColor: item["tintColor"] as? Int,
                    showsChevron: item["showsChevron"] as? Bool ?? false
                )
            }
        }

        // 创建容器
        containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.overrideUserInterfaceStyle = isDark ? .dark : .light

        // 创建自定义玻璃容器（确保圆角始终正确）
        glassContainer = GlassContainerView(cornerRadius: CGFloat(cornerRadius), isDark: isDark)
        glassContainer.translatesAutoresizingMaskIntoConstraints = false
        glassContainer.overrideUserInterfaceStyle = isDark ? .dark : .light

        // 创建按钮堆叠视图
        stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = CGFloat(spacing)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        super.init()

        // 创建按钮
        for (index, item) in buttonItems.enumerated() {
            let button = createButton(item: item, size: buttonSize, index: index)
            buttons.append(button)
            stackView.addArrangedSubview(button)
        }

        // 设置视图层级
        glassContainer.contentView.addSubview(stackView)
        containerView.addSubview(glassContainer)

        // 设置布局约束
        setupConstraints()

        // 设置 Method Channel
        if let messenger = messenger {
            setupMethodChannel(messenger: messenger)
        }
    }

    private func createButton(item: GlassButtonItem, size: Double, index: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = index

        // 配置图标
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let image = UIImage(systemName: item.icon, withConfiguration: config)
        button.setImage(image, for: .normal)

        // 启用状态与配色：Flutter 侧只在调用方显式指定颜色时下发 tintColor，
        // 其余情况由这里按当前主题推导，这样主题切换只需一次 updateTheme。
        button.isEnabled = item.isEnabled
        button.tintColor = resolveTint(for: item)

        // 带下拉指示器的按钮更宽（与 Flutter 侧宽度公式中的 chevronExtraWidth 对应）
        let buttonWidth = item.showsChevron
            ? CGFloat(size) + CGFloat(chevronExtraWidth)
            : CGFloat(size)

        // 设置大小 - 使用较低优先级避免约束冲突
        button.translatesAutoresizingMaskIntoConstraints = false
        let widthConstraint = button.widthAnchor.constraint(equalToConstant: buttonWidth)
        let heightConstraint = button.heightAnchor.constraint(equalToConstant: CGFloat(size))
        widthConstraint.priority = .defaultHigh
        heightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([widthConstraint, heightConstraint])

        // 下拉指示器：单独一层 image view，避免改动主图标的居中布局。
        // 不设 tintColor —— UIKit 的 tintColor 会沿视图层级向下继承，
        // 所以 updateTheme 改 button.tintColor 时 chevron 自动跟随。
        if item.showsChevron {
            let chevronConfig = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            let chevron = UIImageView(
                image: UIImage(systemName: "chevron.down", withConfiguration: chevronConfig)
            )
            chevron.translatesAutoresizingMaskIntoConstraints = false
            chevron.isUserInteractionEnabled = false
            chevron.contentMode = .scaleAspectFit
            button.addSubview(chevron)
            NSLayoutConstraint.activate([
                chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
                chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
        }

        // 角标：指示筛选等激活状态。此前该状态没有过桥，iOS 上完全不显示。
        if item.badge {
            let badgeView = UIView()
            badgeView.translatesAutoresizingMaskIntoConstraints = false
            badgeView.backgroundColor = .systemRed
            badgeView.layer.cornerRadius = Self.badgeSize / 2
            badgeView.isUserInteractionEnabled = false
            button.addSubview(badgeView)
            NSLayoutConstraint.activate([
                badgeView.widthAnchor.constraint(equalToConstant: Self.badgeSize),
                badgeView.heightAnchor.constraint(equalToConstant: Self.badgeSize),
                // 贴着图标右上角，但留出边距避免被玻璃容器圆角裁掉
                badgeView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
                badgeView.topAnchor.constraint(equalTo: button.topAnchor, constant: 6)
            ])
        }

        // 如果是菜单按钮，配置原生 UIMenu
        if item.isMenuButton && !item.menuItems.isEmpty {
            configureNativeMenu(for: button, items: item.menuItems, index: index)
        } else {
            // 普通按钮 - 添加点击事件
            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        }

        // 按压反馈：UIGlassEffect 的 isInteractive 只负责玻璃本身的形变，
        // 按钮内容不会跟着响应，需要自己加缩放 + 触觉。
        button.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        button.addTarget(
            self,
            action: #selector(buttonTouchUp(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )

        // 设置 tooltip（iOS 15+，指针设备上才可见）
        if #available(iOS 15.0, *), let tooltip = item.tooltip {
            button.toolTip = tooltip
        }
        // 触摸设备没有 tooltip，用无障碍标签承载同一份文案
        button.accessibilityLabel = item.tooltip

        return button
    }

    /// 按当前主题与启用状态解析按钮着色
    private func resolveTint(for item: GlassButtonItem) -> UIColor {
        if !item.isEnabled {
            return isDark
                ? UIColor.white.withAlphaComponent(0.38)
                : UIColor.black.withAlphaComponent(0.26)
        }
        if let argb = item.tintColor {
            return UIColor(argb: argb)
        }
        return isDark ? .white : UIColor(white: 0.2, alpha: 1.0)
    }

    /// 配置原生 UIMenu - 系统会自动应用 iOS 26 Liquid Glass 样式
    private func configureNativeMenu(for button: UIButton, items: [GlassMenuItem], index: Int) {
        let actions = items.map { item -> UIAction in
            var image: UIImage?
            if let iconName = item.icon {
                let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                image = UIImage(systemName: iconName, withConfiguration: config)
            }

            return UIAction(
                title: item.title,
                image: image,
                attributes: item.isDestructive ? .destructive : [],
                handler: { [weak self] _ in
                    self?.methodChannel?.invokeMethod("onMenuItemSelected", arguments: [
                        "buttonIndex": index,
                        "value": item.value
                    ])
                }
            )
        }

        button.menu = UIMenu(title: "", children: actions)
        button.showsMenuAsPrimaryAction = true  // 点击即显示菜单，无需长按
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Glass container 填充容器
            glassContainer.topAnchor.constraint(equalTo: containerView.topAnchor),
            glassContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            glassContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            glassContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            // Stack view 在 glass container 内部居中
            stackView.centerYAnchor.constraint(equalTo: glassContainer.contentView.centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: glassContainer.contentView.leadingAnchor, constant: CGFloat(horizontalInset)),
            stackView.trailingAnchor.constraint(equalTo: glassContainer.contentView.trailingAnchor, constant: -CGFloat(horizontalInset))
        ])
    }

    private func setupMethodChannel(messenger: FlutterBinaryMessenger) {
        let channelName = "com.kkape.mynas/glass_button_group_\(viewId)"
        methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)

        methodChannel?.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "updateTheme":
                if let isDark = call.arguments as? Bool {
                    self?.updateTheme(isDark: isDark)
                }
                result(nil)
            case "updateMenuItems":
                if let args = call.arguments as? [String: Any],
                   let buttonIndex = args["buttonIndex"] as? Int,
                   let menuData = args["items"] as? [[String: Any]] {
                    self?.updateMenuItems(at: buttonIndex, items: menuData)
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func updateMenuItems(at buttonIndex: Int, items: [[String: Any]]) {
        guard buttonIndex >= 0 && buttonIndex < buttons.count else { return }

        let menuItems = items.map { item in
            GlassMenuItem(
                title: item["title"] as? String ?? "",
                icon: item["icon"] as? String,
                value: item["value"] as? String ?? "",
                isDestructive: item["isDestructive"] as? Bool ?? false
            )
        }

        let button = buttons[buttonIndex]
        let actions = menuItems.map { item -> UIAction in
            var image: UIImage?
            if let iconName = item.icon {
                let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                image = UIImage(systemName: iconName, withConfiguration: config)
            }

            return UIAction(
                title: item.title,
                image: image,
                attributes: item.isDestructive ? .destructive : [],
                handler: { [weak self] _ in
                    self?.methodChannel?.invokeMethod("onMenuItemSelected", arguments: [
                        "buttonIndex": buttonIndex,
                        "value": item.value
                    ])
                }
            )
        }
        button.menu = UIMenu(title: "", children: actions)

        // 同时更新本地存储的菜单项（保留其余字段，避免丢掉 badge/tint 等状态）
        if buttonIndex < buttonItems.count {
            let existing = buttonItems[buttonIndex]
            buttonItems[buttonIndex] = GlassButtonItem(
                icon: existing.icon,
                tooltip: existing.tooltip,
                isMenuButton: true,
                menuItems: menuItems,
                isEnabled: existing.isEnabled,
                badge: existing.badge,
                tintColor: existing.tintColor,
                showsChevron: existing.showsChevron
            )
        }
    }

    private func updateTheme(isDark: Bool) {
        self.isDark = isDark
        containerView.overrideUserInterfaceStyle = isDark ? .dark : .light
        glassContainer.overrideUserInterfaceStyle = isDark ? .dark : .light
        glassContainer.updateTheme(isDark: isDark)

        // 按每个按钮各自的 item 重新解析着色：自定义色要保留，
        // 禁用态要保持变淡，不能一律刷成主题前景色。
        for button in buttons {
            let index = button.tag
            guard index >= 0 && index < buttonItems.count else { continue }
            button.tintColor = resolveTint(for: buttonItems[index])
        }
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        methodChannel?.invokeMethod("onButtonTap", arguments: sender.tag)
    }

    /// 按下：轻微缩放 + 轻触反馈
    @objc private func buttonTouchDown(_ sender: UIButton) {
        selectionFeedback.selectionChanged()
        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            sender.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }
    }

    /// 抬起：弹回。用 spring 贴近 iOS 26 玻璃控件的回弹手感。
    @objc private func buttonTouchUp(_ sender: UIButton) {
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.55,
            initialSpringVelocity: 0.4,
            options: [.beginFromCurrentState]
        ) {
            sender.transform = .identity
        }
    }

    func view() -> UIView {
        return containerView
    }
}

// MARK: - Plugin Registration

class GlassButtonGroupPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let factory = GlassButtonGroupFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "com.kkape.mynas/glass_button_group")

        NSLog("🔮 GlassButtonGroupPlugin: Registered")

        if #available(iOS 26.0, *) {
            NSLog("🔮 GlassButtonGroupPlugin: iOS 26+ - Using UIGlassEffect")
        } else {
            NSLog("🔮 GlassButtonGroupPlugin: iOS < 26 - Using UIBlurEffect fallback")
        }
    }
}
