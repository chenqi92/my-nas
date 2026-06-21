import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';

/// 未连接到 NAS 的提示组件
class NotConnectedWidget extends StatelessWidget {
  const NotConnectedWidget({
    super.key,
    this.icon,
    this.title,
    this.message,
    this.showAddButton = true,
  });

  final IconData? icon;
  final String? title;
  final String? message;
  final bool showAddButton;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon ?? Icons.cloud_off_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title ?? context.l10n.filesNotConnectedTitle,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message ?? context.l10n.filesNotConnectedMessage,
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (showAddButton) ...[
              const SizedBox(height: 32),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
                    ),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            context.l10n.filesAddConnection,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
