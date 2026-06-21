import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/shared/utils/form_l10n.dart';

/// 键盘快捷键处理器组件
///
/// 包装子组件并处理键盘事件，支持各种媒体播放页面的快捷键操作。
/// 使用 [KeyboardListener] 监听键盘事件，避免与其他焦点组件冲突。
class KeyboardShortcuts extends StatelessWidget {
  const KeyboardShortcuts({
    required this.child,
    required this.shortcuts,
    this.autofocus = true,
    super.key,
  });

  /// 子组件
  final Widget child;

  /// 快捷键映射
  final Map<ShortcutKey, VoidCallback> shortcuts;

  /// 是否自动获取焦点
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: autofocus,
        onKeyEvent: (node, event) {
          // 只处理按下事件
          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          final key = ShortcutKey.fromKeyEvent(event);
          if (key != null && shortcuts.containsKey(key)) {
            shortcuts[key]!();
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: child,
      );
}

/// 快捷键定义
class ShortcutKey {
  const ShortcutKey(
    this.key, {
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  final LogicalKeyboardKey key;
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;

  /// 从键盘事件创建快捷键
  static ShortcutKey? fromKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    // 忽略单独的修饰键
    if (_isModifierKey(key)) return null;

    return ShortcutKey(
      key,
      ctrl: HardwareKeyboard.instance.isControlPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
      meta: HardwareKeyboard.instance.isMetaPressed,
    );
  }

  static bool _isModifierKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShortcutKey &&
          key == other.key &&
          ctrl == other.ctrl &&
          shift == other.shift &&
          alt == other.alt &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash(key, ctrl, shift, alt, meta);

  @override
  String toString() {
    final parts = <String>[];
    if (ctrl) parts.add('Ctrl');
    if (shift) parts.add('Shift');
    if (alt) parts.add('Alt');
    if (meta) parts.add('Meta');
    parts.add(key.keyLabel);
    return parts.join('+');
  }
}

/// 常用快捷键定义
class CommonShortcuts {
  CommonShortcuts._();

  // === 播放控制 ===
  /// 播放/暂停 (Space)
  static const playPause = ShortcutKey(LogicalKeyboardKey.space);

  /// 播放/暂停 (K - YouTube风格)
  static const playPauseK = ShortcutKey(LogicalKeyboardKey.keyK);

  // === 导航 ===
  /// 上一个 (左箭头)
  static const previous = ShortcutKey(LogicalKeyboardKey.arrowLeft);

  /// 下一个 (右箭头)
  static const next = ShortcutKey(LogicalKeyboardKey.arrowRight);

  /// 上一个 (Page Up)
  static const previousPage = ShortcutKey(LogicalKeyboardKey.pageUp);

  /// 下一个 (Page Down)
  static const nextPage = ShortcutKey(LogicalKeyboardKey.pageDown);

  /// 第一个/首页 (Home)
  static const first = ShortcutKey(LogicalKeyboardKey.home);

  /// 最后一个/尾页 (End)
  static const last = ShortcutKey(LogicalKeyboardKey.end);

  // === 视频快进快退 ===
  /// 快退5秒 (J - YouTube风格)
  static const seekBackward = ShortcutKey(LogicalKeyboardKey.keyJ);

  /// 快进5秒 (L - YouTube风格)
  static const seekForward = ShortcutKey(LogicalKeyboardKey.keyL);

  /// 快退10秒 (Shift+左箭头)
  static const seekBackwardLong =
      ShortcutKey(LogicalKeyboardKey.arrowLeft, shift: true);

  /// 快进10秒 (Shift+右箭头)
  static const seekForwardLong =
      ShortcutKey(LogicalKeyboardKey.arrowRight, shift: true);

  // === 音量 ===
  /// 增加音量 (上箭头)
  static const volumeUp = ShortcutKey(LogicalKeyboardKey.arrowUp);

  /// 减少音量 (下箭头)
  static const volumeDown = ShortcutKey(LogicalKeyboardKey.arrowDown);

  /// 静音切换 (M)
  static const mute = ShortcutKey(LogicalKeyboardKey.keyM);

  // === 全屏 ===
  /// 全屏切换 (F)
  static const fullscreen = ShortcutKey(LogicalKeyboardKey.keyF);

  /// 全屏切换 (F11 - Windows风格)
  static const fullscreenF11 = ShortcutKey(LogicalKeyboardKey.f11);

  // === 缩放 ===
  /// 放大 (=或+)
  static const zoomIn = ShortcutKey(LogicalKeyboardKey.equal);

  /// 放大 (Ctrl+=)
  static const zoomInCtrl = ShortcutKey(LogicalKeyboardKey.equal, ctrl: true);

  /// 缩小 (-)
  static const zoomOut = ShortcutKey(LogicalKeyboardKey.minus);

  /// 缩小 (Ctrl+-)
  static const zoomOutCtrl = ShortcutKey(LogicalKeyboardKey.minus, ctrl: true);

  /// 重置缩放 (0)
  static const zoomReset = ShortcutKey(LogicalKeyboardKey.digit0);

  /// 重置缩放 (Ctrl+0)
  static const zoomResetCtrl = ShortcutKey(LogicalKeyboardKey.digit0, ctrl: true);

  // === 退出 ===
  /// 退出/返回 (Escape)
  static const escape = ShortcutKey(LogicalKeyboardKey.escape);

  /// 返回 (Backspace)
  static const back = ShortcutKey(LogicalKeyboardKey.backspace);

  // === 其他 ===
  /// 显示/隐藏控制栏 (C)
  static const toggleControls = ShortcutKey(LogicalKeyboardKey.keyC);

  /// 帮助 (?)
  static const help = ShortcutKey(LogicalKeyboardKey.slash, shift: true);

  /// 循环模式 (R)
  static const repeatMode = ShortcutKey(LogicalKeyboardKey.keyR);

  /// 随机播放 (S)
  static const shuffle = ShortcutKey(LogicalKeyboardKey.keyS);

  /// 收藏 (F或L)
  static const favorite = ShortcutKey(LogicalKeyboardKey.keyL);

  /// 信息 (I)
  static const info = ShortcutKey(LogicalKeyboardKey.keyI);

  /// 设置 (,)
  static const settings = ShortcutKey(LogicalKeyboardKey.comma);

  /// 字幕切换 (C) - 用于视频
  static const subtitles = ShortcutKey(LogicalKeyboardKey.keyC);

  // === 滚动 ===
  /// 向上滚动 (上箭头)
  static const scrollUp = ShortcutKey(LogicalKeyboardKey.arrowUp);

  /// 向下滚动 (下箭头)
  static const scrollDown = ShortcutKey(LogicalKeyboardKey.arrowDown);

  // === 播放速度 ===
  /// 减慢速度 ([)
  static const speedDown = ShortcutKey(LogicalKeyboardKey.bracketLeft);

  /// 加快速度 (])
  static const speedUp = ShortcutKey(LogicalKeyboardKey.bracketRight);

  /// 正常速度 (Backslash \)
  static const speedNormal = ShortcutKey(LogicalKeyboardKey.backslash);

  // === 数字键跳转 ===
  /// 跳转到 0% (0)
  static const jumpTo0 = ShortcutKey(LogicalKeyboardKey.digit0);

  /// 跳转到 10% (1)
  static const jumpTo10 = ShortcutKey(LogicalKeyboardKey.digit1);

  /// 跳转到 20% (2)
  static const jumpTo20 = ShortcutKey(LogicalKeyboardKey.digit2);

  /// 跳转到 30% (3)
  static const jumpTo30 = ShortcutKey(LogicalKeyboardKey.digit3);

  /// 跳转到 40% (4)
  static const jumpTo40 = ShortcutKey(LogicalKeyboardKey.digit4);

  /// 跳转到 50% (5)
  static const jumpTo50 = ShortcutKey(LogicalKeyboardKey.digit5);

  /// 跳转到 60% (6)
  static const jumpTo60 = ShortcutKey(LogicalKeyboardKey.digit6);

  /// 跳转到 70% (7)
  static const jumpTo70 = ShortcutKey(LogicalKeyboardKey.digit7);

  /// 跳转到 80% (8)
  static const jumpTo80 = ShortcutKey(LogicalKeyboardKey.digit8);

  /// 跳转到 90% (9)
  static const jumpTo90 = ShortcutKey(LogicalKeyboardKey.digit9);
}

/// 快捷键帮助分组
class ShortcutGroup {
  const ShortcutGroup({
    required this.title,
    required this.shortcuts,
  });

  final String title;
  final List<({String key, String description})> shortcuts;
}

/// 快捷键帮助对话框
class KeyboardShortcutsHelpDialog extends StatelessWidget {
  const KeyboardShortcutsHelpDialog({
    required this.title,
    required this.shortcuts,
    this.groups,
    super.key,
  });

  final String title;
  final List<({String key, String description})> shortcuts;
  final List<ShortcutGroup>? groups;

  /// 显示帮助对话框（平铺列表）
  static void show(
    BuildContext context, {
    required String title,
    required List<({String key, String description})> shortcuts,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => KeyboardShortcutsHelpDialog(
        title: title,
        shortcuts: shortcuts,
      ),
    );
  }

  /// 显示帮助对话框（分组列表）
  static void showGrouped(
    BuildContext context, {
    required String title,
    required List<ShortcutGroup> groups,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => KeyboardShortcutsHelpDialog(
        title: title,
        shortcuts: const [],
        groups: groups,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.keyboard_rounded,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      localizeFormText(context, title),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                    tooltip: localizeFormText(context, '关闭'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 内容
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: groups != null
                    ? _buildGroupedContent(context, isDark)
                    : _buildFlatContent(context, isDark),
              ),
            ),
            // 底部提示
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const _KeyCap(label: '?'),
                  const SizedBox(width: 8),
                  Text(
                    localizeFormText(context, '按此键显示/隐藏帮助'),
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(localizeFormText(context, '关闭')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlatContent(BuildContext context, bool isDark) => Column(
        mainAxisSize: MainAxisSize.min,
        children: shortcuts
            .map((s) => _ShortcutRow(keyLabel: s.key, description: localizeFormText(context, s.description)))
            .toList(),
      );

  Widget _buildGroupedContent(BuildContext context, bool isDark) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < groups!.length; i++) ...[
            if (i > 0) const SizedBox(height: 20),
            _ShortcutGroupSection(group: groups![i]),
          ],
        ],
      );
}

/// 快捷键分组区域
class _ShortcutGroupSection extends StatelessWidget {
  const _ShortcutGroupSection({required this.group});

  final ShortcutGroup group;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            localizeFormText(context, group.title),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...group.shortcuts.map(
          (s) => _ShortcutRow(keyLabel: s.key, description: localizeFormText(context, s.description)),
        ),
      ],
    );
  }
}

/// 单个快捷键行
class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.keyLabel,
    required this.description,
  });

  final String keyLabel;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _buildKeyLabels(context),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );

  Widget _buildKeyLabels(BuildContext context) {
    // 解析组合键（如 "Ctrl+S"）
    final parts = keyLabel.split('+');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < parts.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '+',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          _KeyCap(label: parts[i].trim()),
        ],
      ],
    );
  }
}

/// 键帽组件
class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      constraints: const BoxConstraints(minWidth: 28),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.2)
              : colorScheme.outline.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
            offset: const Offset(0, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: isDark ? Colors.white : colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// 快捷键帮助覆盖层
///
/// 用于在页面上快速显示快捷键帮助，按 `?` 键显示
class KeyboardShortcutsOverlay extends StatefulWidget {
  const KeyboardShortcutsOverlay({
    super.key,
    required this.child,
    required this.title,
    this.shortcuts = const [],
    this.groups,
    this.enabled = true,
  });

  final Widget child;
  final String title;
  final List<({String key, String description})> shortcuts;
  final List<ShortcutGroup>? groups;
  final bool enabled;

  @override
  State<KeyboardShortcutsOverlay> createState() => _KeyboardShortcutsOverlayState();
}

class _KeyboardShortcutsOverlayState extends State<KeyboardShortcutsOverlay> {
  void _showHelp() {
    if (widget.groups != null) {
      KeyboardShortcutsHelpDialog.showGrouped(
        context,
        title: widget.title,
        groups: widget.groups!,
      );
    } else {
      KeyboardShortcutsHelpDialog.show(
        context,
        title: widget.title,
        shortcuts: widget.shortcuts,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        // 检测 ? 键（Shift + /）
        if (event.logicalKey == LogicalKeyboardKey.slash &&
            HardwareKeyboard.instance.isShiftPressed) {
          _showHelp();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }
}

/// 常用的快捷键帮助分组
class CommonShortcutGroups {
  CommonShortcutGroups._();

  /// 视频播放快捷键
  static List<ShortcutGroup> get videoPlayer => [
        const ShortcutGroup(
          title: '播放控制',
          shortcuts: [
            (key: 'Space', description: '播放 / 暂停'),
            (key: 'K', description: '播放 / 暂停'),
            (key: 'J', description: '快退 10 秒'),
            (key: 'L', description: '快进 10 秒'),
            (key: '←', description: '快退 5 秒'),
            (key: '→', description: '快进 5 秒'),
            (key: '0-9', description: '跳转到 0%-90%'),
          ],
        ),
        const ShortcutGroup(
          title: '音量',
          shortcuts: [
            (key: '↑', description: '增加音量'),
            (key: '↓', description: '减少音量'),
            (key: 'M', description: '静音 / 取消静音'),
          ],
        ),
        const ShortcutGroup(
          title: '显示',
          shortcuts: [
            (key: 'F', description: '全屏 / 退出全屏'),
            (key: 'F11', description: '全屏 / 退出全屏'),
            (key: 'C', description: '显示 / 隐藏字幕'),
            (key: 'I', description: '显示视频信息'),
          ],
        ),
        const ShortcutGroup(
          title: '播放速度',
          shortcuts: [
            (key: '[', description: '减慢播放速度'),
            (key: ']', description: '加快播放速度'),
            (key: r'\', description: '恢复正常速度'),
          ],
        ),
        const ShortcutGroup(
          title: '其他',
          shortcuts: [
            (key: 'Esc', description: '退出全屏 / 返回'),
            (key: '?', description: '显示帮助'),
          ],
        ),
      ];

  /// 音乐播放快捷键
  static List<ShortcutGroup> get musicPlayer => [
        const ShortcutGroup(
          title: '播放控制',
          shortcuts: [
            (key: 'Space', description: '播放 / 暂停'),
            (key: '←', description: '上一曲'),
            (key: '→', description: '下一曲'),
          ],
        ),
        const ShortcutGroup(
          title: '音量',
          shortcuts: [
            (key: '↑', description: '增加音量'),
            (key: '↓', description: '减少音量'),
            (key: 'M', description: '静音 / 取消静音'),
          ],
        ),
        const ShortcutGroup(
          title: '播放模式',
          shortcuts: [
            (key: 'R', description: '切换循环模式'),
            (key: 'S', description: '随机播放'),
            (key: 'L', description: '喜欢 / 取消喜欢'),
          ],
        ),
        const ShortcutGroup(
          title: '其他',
          shortcuts: [
            (key: 'Esc', description: '返回'),
            (key: '?', description: '显示帮助'),
          ],
        ),
      ];

  /// 图片浏览快捷键
  static List<ShortcutGroup> get photoViewer => [
        const ShortcutGroup(
          title: '导航',
          shortcuts: [
            (key: '←', description: '上一张'),
            (key: '→', description: '下一张'),
            (key: 'Home', description: '第一张'),
            (key: 'End', description: '最后一张'),
          ],
        ),
        const ShortcutGroup(
          title: '缩放',
          shortcuts: [
            (key: '+', description: '放大'),
            (key: '-', description: '缩小'),
            (key: '0', description: '重置缩放'),
            (key: 'F', description: '适合屏幕'),
          ],
        ),
        const ShortcutGroup(
          title: '其他',
          shortcuts: [
            (key: 'I', description: '显示图片信息'),
            (key: 'L', description: '喜欢 / 取消喜欢'),
            (key: 'Esc', description: '退出'),
            (key: '?', description: '显示帮助'),
          ],
        ),
      ];

  /// 文件管理快捷键
  static List<ShortcutGroup> get fileManager => [
        const ShortcutGroup(
          title: '导航',
          shortcuts: [
            (key: '↑', description: '向上移动'),
            (key: '↓', description: '向下移动'),
            (key: 'Enter', description: '打开文件/文件夹'),
            (key: 'Backspace', description: '返回上级目录'),
          ],
        ),
        const ShortcutGroup(
          title: '选择',
          shortcuts: [
            (key: 'Ctrl+A', description: '全选'),
            (key: 'Shift+↑/↓', description: '扩展选择'),
            (key: 'Ctrl+Click', description: '多选'),
          ],
        ),
        const ShortcutGroup(
          title: '操作',
          shortcuts: [
            (key: 'Ctrl+C', description: '复制'),
            (key: 'Ctrl+X', description: '剪切'),
            (key: 'Ctrl+V', description: '粘贴'),
            (key: 'Delete', description: '删除'),
            (key: 'F2', description: '重命名'),
          ],
        ),
        const ShortcutGroup(
          title: '其他',
          shortcuts: [
            (key: 'Ctrl+F', description: '搜索'),
            (key: 'F5', description: '刷新'),
            (key: '?', description: '显示帮助'),
          ],
        ),
      ];
}
