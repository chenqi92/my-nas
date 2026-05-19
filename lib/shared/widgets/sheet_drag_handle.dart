import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

/// 底部 sheet 顶部的拖动条。
///
/// 桌面端 [showAdaptiveModalSheet] 会把内容渲染到居中 Dialog 中，
/// 拖动条在 Dialog 里显得突兀（且无法拖动）。本组件在桌面下渲染
/// `SizedBox.shrink`，移动端保持原 40×4 灰色 pill。
///
/// 用法：在 sheet 内容顶部用 `const SheetDragHandle()` 替换内联的
/// `Container(width: 40, height: 4, ...)` 拖动条。
class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({
    super.key,
    this.topPadding = 12,
    this.bottomPadding = 8,
  });

  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    if (context.isDesktopLayout) {
      return const SizedBox.shrink();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
