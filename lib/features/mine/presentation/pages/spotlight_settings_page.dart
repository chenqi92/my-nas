import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_indexer.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_item.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_reindex_coordinator.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_settings.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// macOS Spotlight 索引设置（高级）
class SpotlightSettingsPage extends ConsumerStatefulWidget {
  const SpotlightSettingsPage({super.key});

  @override
  ConsumerState<SpotlightSettingsPage> createState() =>
      _SpotlightSettingsPageState();
}

class _SpotlightSettingsPageState extends ConsumerState<SpotlightSettingsPage>
    with ConsumerTabBarVisibilityMixin {
  @override
  void initState() {
    super.initState();
    hideTabBar();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = ref.watch(spotlightEnabledProvider);
    final rebuilding = ref.watch(SpotlightReindexCoordinator.progressProvider);
    final lastReport =
        ref.watch(SpotlightReindexCoordinator.lastReportProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      appBar: AppBar(
        leading: const RoundedBackButton(),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        title: Text(
          context.l10n.spotlightSettingsPageTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: AppSpacing.paddingMd,
        children: [
          if (!Platform.isMacOS)
            _NotSupportedHint(isDark: isDark)
          else ...[
            _Card(
              isDark: isDark,
              children: [
                SwitchListTile.adaptive(
                  value: enabled,
                  onChanged: rebuilding ? null : _toggle,
                  title: Text(context.l10n.spotlightSettingsEnableToggleTitle),
                  subtitle: Text(context.l10n.spotlightSettingsEnableToggleSubtitle),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _Card(
              isDark: isDark,
              children: [
                ListTile(
                  leading: const Icon(Icons.refresh_rounded),
                  title: Text(context.l10n.spotlightSettingsRebuildTitle),
                  subtitle: Text(
                    rebuilding
                        ? context.l10n.spotlightSettingsRebuildingStatus
                        : lastReport == null
                            ? context.l10n.spotlightSettingsRebuildIdleStatus
                            : _summarize(lastReport),
                  ),
                  trailing: rebuilding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  enabled: enabled && !rebuilding,
                  onTap: enabled && !rebuilding ? _rebuild : null,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                context.l10n.spotlightSettingsHintText,
                style: context.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _summarize(Map<SpotlightItemKind, int> report) {
    final total = report.values.fold<int>(0, (a, b) => a + b);
    final parts = <String>[];
    for (final kind in SpotlightItemKind.values) {
      final n = report[kind] ?? 0;
      if (n > 0) parts.add('${_label(context, kind)} $n');
    }
    if (parts.isEmpty) return context.l10n.spotlightSettingsSummaryNoEntries;
    return context.l10n.spotlightSettingsSummaryWithCount(total, parts.join(' · '));
  }

  String _label(BuildContext context, SpotlightItemKind kind) => switch (kind) {
        SpotlightItemKind.video => context.l10n.spotlightItemKindVideo,
        SpotlightItemKind.music => context.l10n.spotlightItemKindMusic,
        SpotlightItemKind.book => context.l10n.spotlightItemKindBook,
        SpotlightItemKind.comic => context.l10n.spotlightItemKindComic,
        SpotlightItemKind.note => context.l10n.spotlightItemKindNote,
      };

  Future<void> _toggle(bool value) async {
    await ref.read(spotlightEnabledProvider.notifier).setEnabled(value);
    if (value) {
      // 开启 → 立即触发一次全量索引
      await ref.read(spotlightReindexCoordinatorProvider).rebuildAll();
    } else {
      // 关闭 → 清空索引
      await ref.read(spotlightIndexerProvider).clearAll();
      ref.read(SpotlightReindexCoordinator.lastReportProvider.notifier).state =
          null;
    }
  }

  Future<void> _rebuild() async {
    await ref.read(spotlightReindexCoordinatorProvider).rebuildAll();
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.isDark, required this.children});

  final bool isDark;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
      color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
}

class _NotSupportedHint extends StatelessWidget {
  const _NotSupportedHint({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Text(
        context.l10n.spotlightSettingsNotSupportedHint,
        style: context.textTheme.bodyMedium?.copyWith(
          color: isDark
              ? AppColors.darkOnSurfaceVariant
              : AppColors.lightOnSurfaceVariant,
        ),
      ),
    );
}
