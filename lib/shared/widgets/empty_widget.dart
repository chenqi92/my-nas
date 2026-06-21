import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';

class EmptyWidget extends StatelessWidget {
  const EmptyWidget({
    super.key,
    this.icon,
    this.title,
    this.message,
    this.action,
  });

  final IconData? icon;
  final String? title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 空状态图标容器
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    if (isDark) AppColors.darkSurfaceVariant else AppColors.lightSurfaceVariant,
                    if (isDark) AppColors.darkSurfaceElevated else AppColors.lightSurface,
                  ],
                ),
                border: Border.all(
                  color: isDark
                      ? AppColors.darkOutline.withValues(alpha: 0.3)
                      : AppColors.lightOutline.withValues(alpha: 0.5),
                  width: 2,
                ),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
              ),
              child: Icon(
                icon ?? Icons.inbox_outlined,
                size: 44,
                color: isDark
                    ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.6)
                    : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              title ?? appL10n.emptyWidgetDefaultTitle,
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.darkOnSurface
                    : context.colorScheme.onSurface,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.darkOnSurfaceVariant
                      : context.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
