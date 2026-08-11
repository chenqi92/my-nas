import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/video/presentation/pages/tv_home_page.dart';
import 'package:my_nas/l10n/app_localizations.dart';

/// TV 专用脚手架：左侧固定导航 Rail + 主内容区 + 顶部安全区（overscan）。
///
/// - **导航 Rail**：固定宽度 88px，5 个主 Tab（影视/音乐/相册/阅读/我的）+
///   设置按钮，聚焦时放大 + 白边框。
/// - **安全区（Overscan）**：上下左右各 48px padding，避免内容被电视边缘裁切。
/// - **主题**：深色背景 #0A0D12，卡片背景 #161D2B，焦点白边 2px。
/// - **字体**：放大 1.1 倍（已在 app.dart 处理，此处不再重复）。
///
/// 布局结构：
/// ```
/// SafeArea(48px overscan)
///   Row
///     ├─ _TvNavigationRail(88px)
///     └─ Expanded(child: navigationShell)
/// ```
class TvScaffold extends ConsumerWidget {
  const TvScaffold({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const _overscanPadding = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final branchIndex = navigationShell.currentIndex;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0D12) : AppColors.lightBackground,
      body: SafeArea(
        minimum: const EdgeInsets.all(_overscanPadding),
        child: Row(
          children: [
            _TvNavigationRail(
              // 工具页等非 Rail branch 返回 null，此时保留首个 Tab 的高亮。
              currentIndex: tvRailIndexForBranch(branchIndex) ?? 0,
              onDestinationSelected: (index) =>
                  _onDestinationSelected(context, index),
              // 强制 initialLocation：清空该 branch 栈，直达设置主页。
              onSettingsSelected: () => navigationShell.goBranch(
                AppBranch.mine,
                initialLocation: true,
              ),
            ),
            Expanded(
              // 影视 branch 在 TV 上换成 shelves 首页；其余 branch 用各自的页面。
              child: branchIndex == AppBranch.video
                  ? const TvHomePage()
                  : navigationShell,
            ),
          ],
        ),
      ),
    );
  }

  void _onDestinationSelected(BuildContext context, int railIndex) {
    final branchIndex = tvRailBranchForIndex(railIndex);
    navigationShell.goBranch(
      branchIndex,
      initialLocation: branchIndex == navigationShell.currentIndex,
    );
  }
}

/// TV 导航 Rail：固定左侧 88px 宽度，垂直排列 5 个主 Tab + 底部设置按钮。
class _TvNavigationRail extends StatelessWidget {
  const _TvNavigationRail({
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.onSettingsSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onSettingsSelected;

  static const _destinations = [
    _TvDestination(
      icon: Icons.movie_filter_outlined,
      selectedIcon: Icons.movie_filter_rounded,
      labelKey: 'mainNavTabFilms',
    ),
    _TvDestination(
      icon: Icons.library_music_outlined,
      selectedIcon: Icons.library_music_rounded,
      labelKey: 'mainNavTabMusic',
    ),
    _TvDestination(
      icon: Icons.photo_album_outlined,
      selectedIcon: Icons.photo_album_rounded,
      labelKey: 'mainNavTabPhotos',
    ),
    _TvDestination(
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book_rounded,
      labelKey: 'mainNavTabReading',
    ),
    _TvDestination(
      icon: Icons.account_circle_outlined,
      selectedIcon: Icons.account_circle_rounded,
      labelKey: 'mainNavTabMe',
    ),
  ];

  @override
  Widget build(BuildContext context) => Container(
        width: 88,
        decoration: BoxDecoration(
          color: const Color(0xFF161D2B),
          border: Border(
            right: BorderSide(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 24),
            for (var i = 0; i < _destinations.length; i++)
              _TvRailItem(
                destination: _destinations[i],
                selected: i == currentIndex,
                onTap: () => onDestinationSelected(i),
              ),
            const Spacer(),
            // 设置入口：切到「我的」Tab（设置在该 Tab 内），与桌面 Cmd+, 一致。
            _TvRailItem(
              destination: const _TvDestination(
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings_rounded,
                labelKey: 'mineSettings',
              ),
              selected: false,
              onTap: onSettingsSelected,
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
}

/// 单个 Rail 项目：图标 + 标签，选中时高亮。
class _TvRailItem extends StatefulWidget {
  const _TvRailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _TvDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TvRailItem> createState() => _TvRailItemState();
}

class _TvRailItemState extends State<_TvRailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = _getLabel(l, widget.destination.labelKey);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (focused) => setState(() => _focused = focused),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: widget.selected
                ? Colors.white.withValues(alpha: 0.15)
                : _focused
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.transparent,
            border: _focused ? Border.all(color: Colors.white, width: 2) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.selected
                    ? widget.destination.selectedIcon
                    : widget.destination.icon,
                size: 28,
                color: widget.selected || _focused
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: widget.selected || _focused
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getLabel(AppLocalizations l, String key) => switch (key) {
        'mainNavTabFilms' => l.mainNavTabFilms,
        'mainNavTabMusic' => l.mainNavTabMusic,
        'mainNavTabPhotos' => l.mainNavTabPhotos,
        'mainNavTabReading' => l.mainNavTabReading,
        'mainNavTabMe' => l.mainNavTabMe,
        'mineSettings' => l.setShellTitle,
        _ => '',
      };
}

class _TvDestination {
  const _TvDestination({
    required this.icon,
    required this.selectedIcon,
    required this.labelKey,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
}
