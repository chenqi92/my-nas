import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/core/services/background_transfer_guard.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/transfer/data/services/cache_config_service.dart';
import 'package:my_nas/features/transfer/data/services/transfer_service.dart';
import 'package:my_nas/features/transfer/presentation/pages/transfer_manager_page.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';
import 'package:my_nas/shared/providers/transfer_background_provider.dart';
import 'package:my_nas/shared/providers/transfer_concurrency_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 缓存上限可配置的媒体类型（与 [CacheConfigService] 持久化的键一致）。
const _cacheLimitTypes = <MediaType>[
  MediaType.photo,
  MediaType.music,
  MediaType.video,
  MediaType.book,
  MediaType.comic,
  MediaType.note,
];

/// 按媒体类型返回缓存上限行的本地化标签。
String _cacheLimitLabel(AppLocalizations l, MediaType type) => switch (type) {
      MediaType.photo => l.paneTransferCacheTypePhoto,
      MediaType.music => l.paneTransferCacheTypeMusic,
      MediaType.video => l.paneTransferCacheTypeVideo,
      MediaType.book => l.paneTransferCacheTypeBook,
      MediaType.comic => l.paneTransferCacheTypeComic,
      MediaType.note => l.paneTransferCacheTypeNote,
    };

/// 桌面「设置 · 传输与缓存」详情 pane。
///
/// 对应设计稿 `settings_panes.jsx` 的 `PaneTransfer`：传输并发 / 后台 / 启动恢复 /
/// 去重，以及缓存占用统计 + 上限 + 清理。
///
/// 真实接入：
/// - 并发任务数读写 [transferConcurrencyProvider]（持久化 1-3，实时写入
///   [TransferService.maxConcurrentTransfers]，下次调度队列即生效）。
/// - 缓存占用统计来自 [cacheStatsProvider]（聚合各缓存服务的真实计数与体积）。
/// - 「清理缓存」chip 调用 [TransferTasksNotifier.clearAllCache] 按类型/全部清除。
/// - 「打开传输队列」push 现有 [TransferManagerPage]。
/// - 「上传去重」是 [uploadedMarkService] 既有行为（跳过已上传），始终开启、只读展示。
/// - 「缓存上限」按媒体类型读写 [CacheConfigService]（[cacheConfigProvider]），
///   每类一个下拉档位（[CacheSizeOption.options]），超限按 LRU 自动清理。
/// - 「后台传输」读写 [backgroundTransferProvider]（默认开），关闭后桌面窗口
///   最小化时由 [BackgroundTransferGuard] 暂停传输、恢复时续传。
/// - 「启动恢复」读写 [resumeOnStartupProvider]（默认开），关闭后启动时不再把
///   上次未完成的任务恢复到队列（任务仍保留在数据库）。
class TransferPane extends ConsumerWidget {
  const TransferPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final statsAsync = ref.watch(cacheStatsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.swap_vert_rounded,
          title: l.paneTransferTitle,
          subtitle: l.paneTransferSubtitle,
          actions: [
            AppButton(
              label: l.paneTransferOpenQueue,
              icon: Icons.swap_vert_rounded,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => const TransferManagerPage(),
                ),
              ),
            ),
          ],
        ),

        // ---- 传输 ----
        SetSection(
          title: l.paneTransferSectionTransfer,
          hint: l.paneTransferSectionTransferHint,
          children: [
            SetRow(
              title: l.paneTransferConcurrencyTitle,
              desc: l.paneTransferConcurrencyDesc,
              trailing: AppSegmented<int>(
                value: ref.watch(transferConcurrencyProvider),
                options: const [
                  AppSegmentedOption(value: 1, label: '1'),
                  AppSegmentedOption(value: 2, label: '2'),
                  AppSegmentedOption(value: 3, label: '3'),
                ],
                onChanged: (v) =>
                    ref.read(transferConcurrencyProvider.notifier).setValue(v),
              ),
            ),
            SetRow(
              title: l.paneTransferBackgroundTitle,
              desc: l.paneTransferBackgroundDesc,
              trailing: AppSwitch(
                value: ref.watch(backgroundTransferProvider),
                onChanged: (v) => ref
                    .read(backgroundTransferProvider.notifier)
                    .setEnabled(enabled: v),
              ),
            ),
            SetRow(
              title: l.paneTransferResumeTitle,
              desc: l.paneTransferResumeDesc,
              trailing: AppSwitch(
                value: ref.watch(resumeOnStartupProvider),
                onChanged: (v) => ref
                    .read(resumeOnStartupProvider.notifier)
                    .setEnabled(enabled: v),
              ),
            ),
            SetRow(
              title: l.paneTransferDedupTitle,
              desc: l.paneTransferDedupDesc,
              last: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: t.ok),
                  const SizedBox(width: 6),
                  Text(
                    l.paneTransferDedupEnabled,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: t.text1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // ---- 缓存 ----
        SetSection(
          title: l.paneTransferSectionCache,
          hint: l.paneTransferSectionCacheHint,
          bottomMargin: false,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
              child: statsAsync.when(
                data: (stats) => _CacheKvStrip(stats: stats),
                loading: _CacheKvStrip.placeholder,
                error: (_, _) => const _CacheKvStrip.placeholder(),
              ),
            ),
            const _CacheLimitRow(),
            SetRow(
              title: l.paneTransferClearTitle,
              desc: l.paneTransferClearDesc,
              last: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    label: l.paneTransferClearImages,
                    variant: AppButtonVariant.ghost,
                    dense: true,
                    onPressed: () => _clear(context, ref, MediaType.photo),
                  ),
                  const SizedBox(width: 6),
                  AppButton(
                    label: l.paneTransferClearStream,
                    variant: AppButtonVariant.ghost,
                    dense: true,
                    onPressed: () => _clear(context, ref, MediaType.video),
                  ),
                  const SizedBox(width: 6),
                  AppButton(
                    label: l.paneTransferClearAll,
                    icon: Icons.delete_outline_rounded,
                    dense: true,
                    onPressed: () => _clear(context, ref, null),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _clear(
    BuildContext context,
    WidgetRef ref,
    MediaType? mediaType,
  ) async {
    final l = AppLocalizations.of(context);
    final label = switch (mediaType) {
      MediaType.photo => l.paneTransferClearLabelImages,
      MediaType.video => l.paneTransferClearLabelStream,
      null => l.paneTransferClearLabelAll,
      _ => l.paneTransferClearLabelTyped(mediaType.displayName),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.paneTransferClearDialogTitle(label)),
        content: Text(l.paneTransferClearDialogContent(label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.paneTransferClearCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.paneTransferClearConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(transferTasksProvider.notifier)
        .clearAllCache(mediaType: mediaType);
    ref
      ..invalidate(cacheStatsProvider)
      ..invalidate(allCachedItemsProvider);
  }
}

/// 「缓存上限」行：按媒体类型逐项读写 [CacheConfigService] 的缓存大小限制。
///
/// 后端无单一「全局上限」API，各类型在 [CacheConfigService] 独立持久化，故此处
/// 平铺为每类一个下拉档位（[CacheSizeOption.options]，含「无限制」）。改值即时
/// 调用 [CacheConfigService.setCacheSizeLimit] 持久化，并刷新 [cacheConfigProvider]。
class _CacheLimitRow extends ConsumerWidget {
  const _CacheLimitRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final configAsync = ref.watch(cacheConfigProvider);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.paneTransferCacheLimitTitle,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: t.text0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l.paneTransferCacheLimitDesc,
            style: TextStyle(fontSize: 12, color: t.text2),
          ),
          const SizedBox(height: 12),
          configAsync.when(
            data: (limits) => Column(
              children: [
                for (final type in _cacheLimitTypes)
                  _CacheLimitTile(
                    label: _cacheLimitLabel(l, type),
                    sizeMB: limits[type] ??
                        CacheConfigService.defaultCacheSizesMB[type] ??
                        1024,
                    onChanged: (sizeMB) async {
                      await ref
                          .read(cacheConfigServiceProvider)
                          .setCacheSizeLimit(type, sizeMB);
                      ref.invalidate(cacheConfigProvider);
                    },
                  ),
              ],
            ),
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                l.paneTransferCacheLimitLoading,
                style: TextStyle(fontSize: 12, color: t.text3),
              ),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                l.paneTransferCacheLimitError,
                style: TextStyle(fontSize: 12, color: t.text3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个媒体类型的缓存上限行：标签 + 档位下拉。
class _CacheLimitTile extends StatelessWidget {
  const _CacheLimitTile({
    required this.label,
    required this.sizeMB,
    required this.onChanged,
  });

  final String label;
  final int sizeMB;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: t.text1,
              ),
            ),
          ),
          _CacheLimitDropdown(sizeMB: sizeMB, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 缓存档位下拉（[CacheSizeOption.options]，0 = 无限制）。
///
/// 当前值不在预定义选项内时（历史自定义值），临时补一个选项以免 [DropdownButton]
/// 因 value 不匹配抛错。
class _CacheLimitDropdown extends StatelessWidget {
  const _CacheLimitDropdown({required this.sizeMB, required this.onChanged});

  final int sizeMB;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final values = CacheSizeOption.options.map((o) => o.sizeMB).toList();
    final items = <DropdownMenuItem<int>>[
      for (final o in CacheSizeOption.options)
        DropdownMenuItem(value: o.sizeMB, child: Text(o.label)),
      if (!values.contains(sizeMB))
        DropdownMenuItem(
          value: sizeMB,
          child: Text(CacheConfigService.formatSizeMB(sizeMB)),
        ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: t.insetBg,
        border: Border.all(color: t.hairline, width: 0.5),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: sizeMB,
          isDense: true,
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          dropdownColor: t.cardBg,
          icon: Icon(Icons.expand_more_rounded, size: 18, color: t.text2),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: t.text0,
          ),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          items: items,
        ),
      ),
    );
  }
}

/// 设计稿 `.kv-strip`：缓存占用四格（总占用 / 图片封面 / 流式 / 阅读元数据）。
///
/// 数据来自 [cacheStatsProvider] 的真实聚合，按媒体类型归并到设计四类：
/// - 图片 / 封面 → photo
/// - 流式缓存 → video + music
/// - 阅读 / 元数据 → book + comic + note
class _CacheKvStrip extends StatelessWidget {
  const _CacheKvStrip({required this.stats});

  const _CacheKvStrip.placeholder() : stats = const {};

  final Map<MediaType, ({int count, int size})> stats;

  int _sizeOf(List<MediaType> types) => types.fold<int>(
        0,
        (sum, type) => sum + (stats[type]?.size ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final total = stats.values.fold<int>(0, (sum, v) => sum + v.size);
    final cells = <(String, String)>[
      (CacheConfigService.formatSize(total), l.paneTransferKvTotal),
      (
        CacheConfigService.formatSize(_sizeOf(const [MediaType.photo])),
        l.paneTransferKvImages,
      ),
      (
        CacheConfigService.formatSize(
          _sizeOf(const [MediaType.video, MediaType.music]),
        ),
        l.paneTransferKvStream,
      ),
      (
        CacheConfigService.formatSize(
          _sizeOf(const [MediaType.book, MediaType.comic, MediaType.note]),
        ),
        l.paneTransferKvReading,
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < cells.length; i++)
          Expanded(
            child: _KvCell(
              value: cells[i].$1,
              label: cells[i].$2,
              showDivider: i != 0,
            ),
          ),
      ],
    );
  }
}

class _KvCell extends StatelessWidget {
  const _KvCell({
    required this.value,
    required this.label,
    required this.showDivider,
  });

  final String value;
  final String label;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(left: BorderSide(color: t.hairline))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: t.text0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: t.text3),
          ),
        ],
      ),
    );
  }
}
