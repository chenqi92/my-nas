import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/presentation/providers/home_layout_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 显示首页布局设置弹框
void showHomeLayoutSheet(BuildContext context) {
  showAdaptiveModalSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const HomeLayoutSheet(),
  );
}

/// 首页布局设置底部弹框
class HomeLayoutSheet extends ConsumerStatefulWidget {
  const HomeLayoutSheet({super.key});

  @override
  ConsumerState<HomeLayoutSheet> createState() => _HomeLayoutSheetState();
}

class _HomeLayoutSheetState extends ConsumerState<HomeLayoutSheet> {
  late List<HomeSectionConfig> _sections;

  @override
  void initState() {
    super.initState();
    _sections = List.from(ref.read(homeLayoutProvider).sections);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (context, scrollController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.grey[900]!.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
            ),
            child: Column(
              children: [
                // 拖拽指示器
                const SheetDragHandle(bottomPadding: 0),
                // 标题栏
                _buildHeader(context, isDark),
                // 分隔线
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(
                    height: 1,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                // 提示文字
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.musicHomeLayoutHint,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
                // 可排序列表
                Expanded(
                  child: ReorderableListView.builder(
                    scrollController: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: _sections.length,
                    proxyDecorator: (child, index, animation) =>
                        _buildProxyDecorator(child, animation, isDark),
                    onReorder: _onReorder,
                    itemBuilder: (context, index) {
                      final config = _sections[index];
                      return _SectionTile(
                        key: ValueKey(config.section),
                        config: config,
                        isDark: isDark,
                        onVisibilityChanged: () => _toggleVisibility(index),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        child: Row(
          children: [
            // 图标
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary,
                    AppColors.secondary,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.dashboard_customize_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            // 标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.musicHomeLayoutTitle,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.musicHomeLayoutSubtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            // 重置按钮
            TextButton.icon(
              onPressed: _reset,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(context.l10n.musicHomeLayoutReset),
            ),
          ],
        ),
      );

  Widget _buildProxyDecorator(
    Widget child,
    Animation<double> animation,
    bool isDark,
  ) =>
      AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final animValue = Curves.easeInOut.transform(animation.value);
          final elevation = lerpDouble(0, 8, animValue)!;
          final scale = lerpDouble(1, 1.02, animValue)!;
          return Transform.scale(
            scale: scale,
            child: Material(
              elevation: elevation,
              color: Colors.transparent,
              shadowColor: AppColors.primary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              child: child,
            ),
          );
        },
        child: child,
      );

  void _onReorder(int oldIndex, int newIndex) {
    var adjustedNewIndex = newIndex;
    if (adjustedNewIndex > oldIndex) {
      adjustedNewIndex -= 1;
    }
    setState(() {
      final item = _sections.removeAt(oldIndex);
      _sections.insert(adjustedNewIndex, item);
    });
    // 保存到 provider
    ref.read(homeLayoutProvider.notifier).reorderSections(oldIndex, adjustedNewIndex);
  }

  void _toggleVisibility(int index) {
    final section = _sections[index].section;
    ref.read(homeLayoutProvider.notifier).toggleSectionVisibility(section);
    setState(() {
      _sections[index] = _sections[index].copyWith(
        visible: !_sections[index].visible,
      );
    });
  }

  void _reset() {
    ref.read(homeLayoutProvider.notifier).reset();
    setState(() {
      _sections = List.from(ref.read(homeLayoutProvider).sections);
    });
  }
}

/// 区块项组件
class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required super.key,
    required this.config,
    required this.isDark,
    required this.onVisibilityChanged,
  });

  final HomeSectionConfig config;
  final bool isDark;
  final VoidCallback onVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    final isVisible = config.visible;
    final icon = getHomeSectionIcon(config.section);
    final name = getHomeSectionName(config.section);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: isVisible ? 0.08 : 0.03)
            : Colors.black.withValues(alpha: isVisible ? 0.04 : 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: isVisible ? 0.1 : 0.05)
              : Colors.black.withValues(alpha: isVisible ? 0.08 : 0.03),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isVisible
                ? AppColors.primary.withValues(alpha: 0.15)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: isVisible
                ? AppColors.primary
                : (isDark ? Colors.white38 : Colors.black26),
            size: 22,
          ),
        ),
        title: Text(
          name,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isVisible
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? Colors.white38 : Colors.black38),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 可见性开关
            GestureDetector(
              onTap: onVisibilityChanged,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isVisible
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  color: isVisible
                      ? AppColors.primary
                      : (isDark ? Colors.white38 : Colors.black26),
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 拖动手柄
            Icon(
              Icons.drag_handle_rounded,
              color: isDark ? Colors.white38 : Colors.black26,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
