import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/providers/desktop_space_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 根据实际绘制后的背景选取稳定可见的前景色。桌面主题允许用户切换
/// 浅色/深色与强调色，不能假设 accent 在 selected 背景上始终有对比度。
@visibleForTesting
Color desktopReadableForeground(Color background) =>
    background.computeLuminance() > 0.45
    ? const Color(0xDE000000)
    : Colors.white;

/// sidebar 一级入口的描述符。`count`/`live` 由外部注入（订阅各 ListNotifier
/// / sources / live 服务），sidebar 自身不订阅 provider —— 让外壳 / page 处
/// 决定何时刷新。
class NavEntry {
  const NavEntry({
    required this.id,
    required this.route,
    required this.label,
    required this.icon,
    this.count,
    this.live = false,
  });

  /// 内部 id，与设计稿 shell.jsx 的 NAV item id 对齐（home/films/music/...）。
  final String id;
  final String route;
  final String label;
  final IconData icon;

  /// 右侧 count badge（影视库 248、音乐 1.2k 等）。
  final String? count;

  /// 直播红点。
  final bool live;
}

class NavGroup {
  const NavGroup({this.label, required this.items});
  final String? label;
  final List<NavEntry> items;
}

class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    required this.space,
    required this.collapsed,
    required this.currentRoute,
    required this.mediaGroups,
    required this.opsGroups,
    required this.onSpaceChanged,
    required this.onNavigate,
    required this.onOpenSettings,
    super.key,
  });

  final DesktopSpace space;
  final bool collapsed;
  final String currentRoute;
  final List<NavGroup> mediaGroups;
  final List<NavGroup> opsGroups;
  final ValueChanged<DesktopSpace> onSpaceChanged;
  final ValueChanged<String> onNavigate;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final groups = space == DesktopSpace.media ? mediaGroups : opsGroups;
    final width = collapsed ? DesignTokens.railW : DesignTokens.navW;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: DesignTokens.ease,
      width: width,
      decoration: BoxDecoration(
        color: t.sidebarBg,
        border: Border(right: BorderSide(color: t.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Brand(collapsed: collapsed),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: AppSegmented<DesktopSpace>(
                value: space,
                onChanged: onSpaceChanged,
                expand: true,
                options: [
                  AppSegmentedOption(
                    value: DesktopSpace.media,
                    label: l.shellSidebarSpaceMedia,
                    icon: Icons.play_circle_outline_rounded,
                  ),
                  AppSegmentedOption(
                    value: DesktopSpace.ops,
                    label: l.shellSidebarSpaceOps,
                    icon: Icons.terminal_rounded,
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Column(
                children: [
                  _CollapsedSpaceBtn(
                    label: l.shellSidebarSpaceMedia,
                    icon: Icons.play_circle_outline_rounded,
                    selected: space == DesktopSpace.media,
                    onTap: () => onSpaceChanged(DesktopSpace.media),
                  ),
                  const SizedBox(height: 3),
                  _CollapsedSpaceBtn(
                    label: l.shellSidebarSpaceOps,
                    icon: Icons.terminal_rounded,
                    selected: space == DesktopSpace.ops,
                    onTap: () => onSpaceChanged(DesktopSpace.ops),
                  ),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final g in groups) ...[
                    if (!collapsed && g.label != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                        child: Text(
                          g.label!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: t.text3,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 8),
                    for (final item in g.items)
                      _NavItem(
                        entry: item,
                        collapsed: collapsed,
                        active: currentRoute.startsWith(item.route),
                        onTap: () => onNavigate(item.route),
                      ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.hairline)),
            ),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
            child: _NavItem(
              entry: NavEntry(
                id: 'settings',
                route: '/mine',
                label: l.shellSidebarSettings,
                icon: Icons.settings_outlined,
              ),
              collapsed: collapsed,
              active: currentRoute == '/mine',
              onTap: onOpenSettings,
            ),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final mark = Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: t.accent.withValues(alpha: 0.5),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/logo.png',
        width: 26,
        height: 26,
        fit: BoxFit.cover,
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        collapsed ? 0 : 8,
        12,
        collapsed ? 0 : 8,
        12,
      ),
      child: Row(
        mainAxisAlignment: collapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          mark,
          if (!collapsed) ...[
            const SizedBox(width: 9),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'My',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: t.text0,
                    ),
                  ),
                  TextSpan(
                    text: 'NAS',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: t.accentBright,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CollapsedSpaceBtn extends StatelessWidget {
  const _CollapsedSpaceBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final selectedBg = Color.alphaBlend(t.segOnBg, t.sidebarBg);
    final selectedFg = desktopReadableForeground(selectedBg);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            canRequestFocus: true,
            focusColor: t.accent.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: selected ? selectedBg : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 15,
                  color: selected ? selectedFg : t.text2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.entry,
    required this.collapsed,
    required this.active,
    required this.onTap,
  });

  final NavEntry entry;
  final bool collapsed;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final activeBg = Color.alphaBlend(t.chipBgActive, t.sidebarBg);
    final bg = active ? activeBg : Colors.transparent;
    final activeFg = desktopReadableForeground(activeBg);
    final fg = active ? activeFg : t.text1;
    final iconColor = active ? activeFg : t.text2;

    final body = collapsed
        ? Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(entry.icon, size: 18, color: iconColor),
                if (entry.live)
                  const Positioned(right: -8, top: -4, child: LiveDot(size: 7)),
              ],
            ),
          )
        : Row(
            children: [
              if (active)
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: activeFg,
                    borderRadius: BorderRadius.circular(3),
                  ),
                )
              else
                const SizedBox(width: 3),
              const SizedBox(width: 8),
              Icon(entry.icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (entry.live) const LiveDot(size: 7),
              if (entry.count != null) ...[
                const SizedBox(width: 6),
                Text(
                  entry.count!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: active ? activeFg : t.text2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          );

    final control = Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          canRequestFocus: true,
          focusColor: t.accent.withValues(alpha: 0.24),
          hoverColor: active ? activeBg : t.chipBg,
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          child: Container(
            padding: collapsed
                ? const EdgeInsets.symmetric(horizontal: 0, vertical: 9)
                : const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            ),
            child: body,
          ),
        ),
      ),
    );
    final semanticControl = Semantics(
      button: true,
      selected: active,
      label: entry.count == null
          ? entry.label
          : '${entry.label}, ${entry.count}',
      excludeSemantics: true,
      child: control,
    );
    return collapsed
        ? Tooltip(
            message: entry.label,
            excludeFromSemantics: true,
            child: semanticControl,
          )
        : semanticControl;
  }
}
