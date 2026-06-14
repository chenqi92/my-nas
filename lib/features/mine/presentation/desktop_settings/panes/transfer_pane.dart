import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/transfer/data/services/cache_config_service.dart';
import 'package:my_nas/features/transfer/data/services/transfer_service.dart';
import 'package:my_nas/features/transfer/presentation/pages/transfer_manager_page.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 桌面「设置 · 传输与缓存」详情 pane。
///
/// 对应设计稿 `settings_panes.jsx` 的 `PaneTransfer`：传输并发 / 后台 / 启动恢复 /
/// 去重，以及缓存占用统计 + 上限 + 清理。
///
/// 真实接入：
/// - 缓存占用统计来自 [cacheStatsProvider]（聚合各缓存服务的真实计数与体积）。
/// - 「清理缓存」chip 调用 [TransferTasksNotifier.clearAllCache] 按类型/全部清除。
/// - 「打开传输队列」push 现有 [TransferManagerPage]。
/// - 「上传去重」是 [uploadedMarkService] 既有行为（跳过已上传），始终开启、只读展示。
///
/// 降级说明（无对应可写 provider，标「即将推出」）：
/// - 并发任务数固定为 [TransferService.maxConcurrentTransfers]，暂无可写设置。
/// - 后台传输 / 启动恢复暂无开关。
/// - 全局缓存上限暂无单一 API（现按媒体类型在 [CacheConfigService] 各自配置）。
class TransferPane extends ConsumerWidget {
  const TransferPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final statsAsync = ref.watch(cacheStatsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.swap_vert_rounded,
          title: '传输与缓存',
          subtitle: '上传 / 下载 / 缓存三类任务的并发与缓存策略。实时进度请见控制台 › '
              '传输队列。',
          actions: [
            AppButton(
              label: '打开传输队列',
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
          title: '传输',
          hint: '上传 / 下载 / 缓存',
          children: [
            SetRow(
              title: '并发任务数',
              desc: '同时进行的传输上限（固定 '
                  '${TransferService.maxConcurrentTransfers}）',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${TransferService.maxConcurrentTransfers}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.text1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const AppTag('可调并发即将推出', variant: TagVariant.plan),
                ],
              ),
            ),
            const SetRow(
              title: '后台传输',
              desc: '窗口最小化后继续传输',
              trailing: AppTag('即将推出', variant: TagVariant.plan),
            ),
            const SetRow(
              title: '启动恢复',
              desc: '启动时恢复未完成的任务',
              trailing: AppTag('即将推出', variant: TagVariant.plan),
            ),
            SetRow(
              title: '上传去重',
              desc: '跳过目标已存在的同名同尺寸文件（默认开启）',
              last: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: t.ok),
                  const SizedBox(width: 6),
                  Text(
                    '已启用',
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
          title: '缓存',
          hint: '三类聚合 · LRU',
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
            const SetRow(
              title: '缓存上限',
              desc: '超出后按 LRU 自动清理最久未用（当前按媒体类型分别配置）',
              trailing: AppTag('全局上限即将推出', variant: TagVariant.plan),
            ),
            SetRow(
              title: '清理缓存',
              desc: '按类型或全部清除已缓存文件',
              last: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    label: '图片',
                    variant: AppButtonVariant.ghost,
                    dense: true,
                    onPressed: () => _clear(context, ref, MediaType.photo),
                  ),
                  const SizedBox(width: 6),
                  AppButton(
                    label: '流式',
                    variant: AppButtonVariant.ghost,
                    dense: true,
                    onPressed: () => _clear(context, ref, MediaType.video),
                  ),
                  const SizedBox(width: 6),
                  AppButton(
                    label: '全部',
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
    final label = switch (mediaType) {
      MediaType.photo => '图片缓存',
      MediaType.video => '流式缓存',
      null => '全部缓存',
      _ => '${mediaType.displayName}缓存',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('清理$label'),
        content: Text('确定要清除$label吗？此操作不可撤销，但不会影响 NAS 上的原文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清除'),
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
    final total = stats.values.fold<int>(0, (sum, v) => sum + v.size);
    final cells = <(String, String)>[
      (CacheConfigService.formatSize(total), '总占用'),
      (CacheConfigService.formatSize(_sizeOf(const [MediaType.photo])),
          '图片 / 封面'),
      (
        CacheConfigService.formatSize(
          _sizeOf(const [MediaType.video, MediaType.music]),
        ),
        '流式缓存',
      ),
      (
        CacheConfigService.formatSize(
          _sizeOf(const [MediaType.book, MediaType.comic, MediaType.note]),
        ),
        '阅读 / 元数据',
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
