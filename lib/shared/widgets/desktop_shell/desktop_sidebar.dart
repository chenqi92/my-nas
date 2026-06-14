import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/shared/providers/desktop_space_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

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
                options: const [
                  AppSegmentedOption(
                    value: DesktopSpace.media,
                    label: '媒体',
                    icon: Icons.play_circle_outline_rounded,
                  ),
                  AppSegmentedOption(
                    value: DesktopSpace.ops,
                    label: '控制台',
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
                    icon: Icons.play_circle_outline_rounded,
                    selected: space == DesktopSpace.media,
                    onTap: () => onSpaceChanged(DesktopSpace.media),
                  ),
                  const SizedBox(height: 3),
                  _CollapsedSpaceBtn(
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
                            letterSpacing: 0.2,
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
              entry: const NavEntry(
                id: 'settings',
                route: '/mine',
                label: '设置',
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.accentBright, t.accentDeep],
        ),
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: t.accent.withValues(alpha: 0.5),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        Icons.dns_rounded,
        color: t.accentContrast,
        size: 16,
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(collapsed ? 0 : 16, 12, collapsed ? 0 : 16, 12),
      child: Row(
        mainAxisAlignment:
            collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          mark,
          if (!collapsed) ...[
            const SizedBox(width: 9),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: 'My',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: t.text0,
                    letterSpacing: -0.1,
                  ),
                ),
                TextSpan(
                  text: 'NAS',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: t.accentBright,
                    letterSpacing: -0.1,
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _CollapsedSpaceBtn extends StatelessWidget {
  const _CollapsedSpaceBtn({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: selected ? t.segOnBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Icon(
              icon,
              size: 15,
              color: selected ? t.accent : t.text2,
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
    final bg = active
        ? t.accent
        : null;
    final fg = active ? t.accentContrast : t.text1;
    final iconColor = active ? t.accentContrast : t.text2;

    final body = collapsed
        ? Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(entry.icon, size: 18, color: iconColor),
                if (entry.live)
                  const Positioned(
                    right: -8,
                    top: -4,
                    child: LiveDot(size: 7),
                  ),
              ],
            ),
          )
        : Row(
            children: [
              Icon(entry.icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w500,
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
                    color: active
                        ? t.accentContrast.withValues(alpha: 0.85)
                        : t.text2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: active ? null : t.chipBg,
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          child: Container(
            padding: collapsed
                ? const EdgeInsets.symmetric(horizontal: 0, vertical: 9)
                : const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}
