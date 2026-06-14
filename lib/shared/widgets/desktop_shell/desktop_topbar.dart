import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/atoms/app_kbd.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';

/// 设计稿 `.topbar` 桌面顶栏（高 56）。
///
/// 中央搜索框是 trigger（点击=唤起 [CommandPalette]），不实际承载输入。
class DesktopTopbar extends StatelessWidget {
  const DesktopTopbar({
    required this.crumb,
    required this.onToggleSidebar,
    required this.onOpenSearch,
    required this.onOpenActivity,
    required this.onOpenAppearance,
    required this.activityBadge,
    super.key,
  });

  /// 面包屑（如 `["媒体", "影视"]` → `媒体 › 影视`）。
  final List<String> crumb;
  final VoidCallback onToggleSidebar;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenActivity;
  final VoidCallback onOpenAppearance;

  /// 活动中心右上角圆点（有正在跑的任务时显示）。
  final bool activityBadge;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      height: DesignTokens.topbarH,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        // 与侧栏同色，统一外壳 chrome；避免经典浅色下纯白顶栏过于突兀。
        color: t.sidebarBg,
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          _TbIcon(
            icon: Icons.menu_rounded,
            onTap: onToggleSidebar,
            tooltip: l.shellTopbarToggleSidebar,
          ),
          const SizedBox(width: 6),
          if (crumb.isNotEmpty)
            _Crumb(crumb: crumb),
          const Spacer(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: _SearchTrigger(onTap: onOpenSearch),
          ),
          const Spacer(),
          _TbIcon(
            icon: Icons.notifications_none_rounded,
            onTap: onOpenActivity,
            tooltip: l.shellTopbarActivity,
            badge: activityBadge,
          ),
          _TbIcon(
            icon: Icons.palette_outlined,
            onTap: onOpenAppearance,
            tooltip: l.shellTopbarAppearance,
          ),
        ],
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.crumb});
  final List<String> crumb;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final children = <InlineSpan>[];
    for (var i = 0; i < crumb.length; i++) {
      final isLast = i == crumb.length - 1;
      children.add(TextSpan(
        text: crumb[i],
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
          color: isLast ? t.text0 : t.text2,
        ),
      ));
      if (!isLast) {
        children.add(WidgetSpan(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 14,
              color: t.text2,
            ),
          ),
        ));
      }
    }
    return Text.rich(TextSpan(children: children));
  }
}

class _SearchTrigger extends StatelessWidget {
  const _SearchTrigger({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: t.insetBg,
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            border: Border.all(color: t.hairline, width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 16, color: t.text2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.shellTopbarSearchPlaceholder,
                  style: TextStyle(fontSize: 12.5, color: t.text2),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const AppKbd('⌘K'),
            ],
          ),
        ),
      ),
    );
  }
}

class _TbIcon extends StatelessWidget {
  const _TbIcon({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        hoverColor: t.chipBg,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(child: Icon(icon, size: 18, color: t.text2)),
              if (badge)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: t.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final tip = tooltip;
    return tip == null
        ? btn
        : Tooltip(
            message: tip,
            child: btn,
          );
  }
}

/// 桌面顶栏 + 任意悬浮 overlay 的通用容器（topbar 自身已是 panel；这里仅
/// 供 appearance popover 等需要"贴齐 topbar 右下"的场景复用）。
class TopbarAnchoredPopover extends StatelessWidget {
  const TopbarAnchoredPopover({
    required this.alignment,
    required this.child,
    super.key,
  });

  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(
        top: DesignTokens.topbarH + 8,
        right: 20,
        child: GlassPanel(
          strong: true,
          padding: const EdgeInsets.all(14),
          child: child,
        ),
      );
}
