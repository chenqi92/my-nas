import Cocoa
import FlutterMacOS

/// macOS 版 Liquid Glass 按钮组
///
/// 使用 NSGlassEffectView (macOS 26+) 提供原生水滴玻璃效果
/// 旧系统回退到 NSVisualEffectView
struct MacGlassButtonItem {
    let icon: String
    let tooltip: String?
    let isEnabled: Bool
    let badge: Bool
    /// ARGB32，仅在调用方显式指定颜色时非 nil
    let tintColor: Int?
    let showsChevron: Bool
}

extension NSColor {
    /// 从 Flutter 侧的 ARGB32 整数构造颜色（Color.toARGB32() 的结果）
    convenience init(argb: Int) {
        let alpha = CGFloat((argb >> 24) & 0xFF) / 255.0
        let red = CGFloat((argb >> 16) & 0xFF) / 255.0
        let green = CGFloat((argb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(argb & 0xFF) / 255.0
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

final class GlassButtonGroupFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withViewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> NSView {
        return GlassButtonGroupPlatformView(
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

final class GlassButtonGroupPlatformView: NSView {
    private static let badgeSize: CGFloat = 8

    private let glassView: NSView
    private let stackView: NSStackView
    private var buttons: [NSButton] = []
    private var methodChannel: FlutterMethodChannel?
    private let viewId: Int64
    private var isDark: Bool
    private var buttonItems: [MacGlassButtonItem] = []
    /// 与 Flutter 侧宽度公式共享的布局参数
    private let chevronExtraWidth: Double

    init(
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        self.viewId = viewId

        let params = args as? [String: Any] ?? [:]
        isDark = params["isDark"] as? Bool ?? false
        let buttonSize = params["buttonSize"] as? Double ?? 40.0
        // Flutter 侧已取过 max(spacing, minSpacing)，这里直接用，
        // 保证两侧算出的总宽度一致（不一致会导致按钮被挤压）。
        let spacing = params["spacing"] as? Double ?? 8.0
        let cornerRadius = params["cornerRadius"] as? Double ?? 22.0
        let horizontalInset = params["horizontalInset"] as? Double ?? 10.0
        chevronExtraWidth = params["chevronExtraWidth"] as? Double ?? 12.0

        var items: [MacGlassButtonItem] = []
        if let itemsData = params["items"] as? [[String: Any]] {
            items = itemsData.map { item in
                MacGlassButtonItem(
                    icon: item["icon"] as? String ?? "questionmark",
                    tooltip: item["tooltip"] as? String,
                    isEnabled: item["isEnabled"] as? Bool ?? true,
                    badge: item["badge"] as? Bool ?? false,
                    tintColor: item["tintColor"] as? Int,
                    showsChevron: item["showsChevron"] as? Bool ?? false
                )
            }
        }
        buttonItems = items

        // 玻璃背景。使用 NSClassFromString 运行时查找 NSGlassEffectView，避免编译期
        // 依赖 macOS 26 SDK（CI 上的 Xcode 15 等老版本仍能编译）。
        var resolvedGlass: NSView? = nil
        if #available(macOS 26.0, *),
           let cls = NSClassFromString("NSGlassEffectView") as? NSObject.Type,
           let glass = cls.init() as? NSView {
            glass.translatesAutoresizingMaskIntoConstraints = false
            glass.setValue(CGFloat(cornerRadius), forKey: "cornerRadius")
            resolvedGlass = glass
        }
        if let glass = resolvedGlass {
            glassView = glass
        } else {
            let visualEffect = NSVisualEffectView()
            visualEffect.translatesAutoresizingMaskIntoConstraints = false
            visualEffect.material = .hudWindow
            visualEffect.blendingMode = .withinWindow
            visualEffect.state = .active
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = CGFloat(cornerRadius)
            glassView = visualEffect
        }

        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = CGFloat(cornerRadius)
        glassView.layer?.masksToBounds = true

        stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = CGFloat(spacing)
        stackView.edgeInsets = NSEdgeInsets(
            top: 0,
            left: CGFloat(horizontalInset),
            bottom: 0,
            right: CGFloat(horizontalInset)
        )
        stackView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)

        self.wantsLayer = true
        self.layer?.masksToBounds = false
        self.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)

        // 创建按钮
        for (index, item) in items.enumerated() {
            let button = createButton(item: item, size: buttonSize, index: index)
            buttons.append(button)
            stackView.addArrangedSubview(button)
        }

        glassView.addSubview(stackView)
        self.addSubview(glassView)

        setupConstraints(cornerRadius: cornerRadius)

        if let messenger {
            setupMethodChannel(messenger: messenger)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func createButton(item: MacGlassButtonItem, size: Double, index: Int) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.imagePosition = .imageOnly
        button.focusRingType = .none
        button.tag = index

        if let image = NSImage(
            systemSymbolName: item.icon,
            accessibilityDescription: item.tooltip
        ) {
            image.size = NSSize(width: size * 0.55, height: size * 0.55)
            button.image = image
        }

        // 带下拉指示器的按钮更宽（与 Flutter 侧宽度公式中的 chevronExtraWidth 对应）
        let buttonWidth = item.showsChevron
            ? CGFloat(size) + CGFloat(chevronExtraWidth)
            : CGFloat(size)

        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: buttonWidth),
            button.heightAnchor.constraint(equalToConstant: CGFloat(size))
        ])

        button.target = self
        button.action = #selector(buttonTapped(_:))
        button.isEnabled = item.isEnabled
        button.contentTintColor = resolveTint(for: item)

        // 下拉指示器
        if item.showsChevron,
           let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) {
            chevron.size = NSSize(width: 8, height: 8)
            let chevronView = NSImageView(image: chevron)
            chevronView.translatesAutoresizingMaskIntoConstraints = false
            chevronView.contentTintColor = button.contentTintColor
            button.addSubview(chevronView)
            NSLayoutConstraint.activate([
                chevronView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
                chevronView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
        }

        // 角标：指示筛选等激活状态
        if item.badge {
            let badgeView = NSView()
            badgeView.translatesAutoresizingMaskIntoConstraints = false
            badgeView.wantsLayer = true
            badgeView.layer?.backgroundColor = NSColor.systemRed.cgColor
            badgeView.layer?.cornerRadius = Self.badgeSize / 2
            button.addSubview(badgeView)
            NSLayoutConstraint.activate([
                badgeView.widthAnchor.constraint(equalToConstant: Self.badgeSize),
                badgeView.heightAnchor.constraint(equalToConstant: Self.badgeSize),
                badgeView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
                badgeView.topAnchor.constraint(equalTo: button.topAnchor, constant: 6)
            ])
        }

        if #available(macOS 11.0, *), let tooltip = item.tooltip {
            button.toolTip = tooltip
        }

        return button
    }

    /// 按当前主题与启用状态解析按钮着色
    private func resolveTint(for item: MacGlassButtonItem) -> NSColor {
        if !item.isEnabled {
            return isDark
                ? NSColor.white.withAlphaComponent(0.38)
                : NSColor.black.withAlphaComponent(0.26)
        }
        if let argb = item.tintColor {
            return NSColor(argb: argb)
        }
        return isDark ? .white : NSColor(white: 0.2, alpha: 1.0)
    }

    private func setupConstraints(cornerRadius: Double) {
        glassView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: self.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            glassView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: self.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: glassView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
        ])

        self.layer?.cornerRadius = CGFloat(cornerRadius)
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
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func updateTheme(isDark: Bool) {
        self.isDark = isDark
        let newAppearance: NSAppearance? = isDark
            ? NSAppearance(named: .darkAqua)
            : NSAppearance(named: .aqua)

        self.appearance = newAppearance
        // appearance 是 NSView 上的属性，无论是 NSGlassEffectView 还是 NSVisualEffectView
        // 都可以直接设置，无需向下转型。
        glassView.appearance = newAppearance

        buttons.forEach { button in
            let index = button.tag
            guard index >= 0 && index < buttonItems.count else { return }
            let tint = resolveTint(for: buttonItems[index])
            button.contentTintColor = tint
            // chevron 是独立的 NSImageView，不继承 contentTintColor，需一起刷新
            button.subviews
                .compactMap { $0 as? NSImageView }
                .forEach { $0.contentTintColor = tint }
        }
    }

    @objc private func buttonTapped(_ sender: NSButton) {
        methodChannel?.invokeMethod("onButtonTap", arguments: sender.tag)
    }
}

final class GlassButtonGroupPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let factory = GlassButtonGroupFactory(messenger: registrar.messenger)
        registrar.register(factory, withId: "com.kkape.mynas/glass_button_group")

        NSLog("🔮 GlassButtonGroupPlugin(macOS): Registered")
    }
}
