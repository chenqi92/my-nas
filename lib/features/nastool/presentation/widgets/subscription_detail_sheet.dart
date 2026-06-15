import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/nastool/presentation/widgets/subscription_poster.dart';
import 'package:my_nas/service_adapters/nastool/models/subscribe_models.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/ep_grid.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';

/// NAStool 订阅详情浮层：展示订阅信息 + 搜索资源 / 删除订阅。
class SubscriptionDetailSheet extends ConsumerWidget {
  const SubscriptionDetailSheet({
    required this.sub,
    required this.sourceId,
    super.key,
  });

  final NtSubscribe sub;
  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: GlassPanel(
          strong: true,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 170,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SubscriptionPoster(path: sub.posterPath),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sub.name,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: t.text0,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                AppTag(sub.isMovie ? '电影' : '剧集'),
                                if (sub.year != null)
                                  AppTag(sub.year!, variant: TagVariant.neutral),
                                if (sub.seasonDisplay != null)
                                  AppTag(sub.seasonDisplay!,
                                      variant: TagVariant.neutral),
                                if (sub.isCompleted)
                                  const AppTag('已完成', variant: TagVariant.free),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (sub.isTv && sub.totalEp != null) ...[
                              Text(
                                '剧集进度 · ${sub.currentEp ?? 0}/${sub.totalEp}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: t.text2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              EpisodeGrid(
                                total: sub.totalEp!,
                                have: sub.currentEp ?? 0,
                              ),
                              const SizedBox(height: 14),
                            ],
                            if (sub.overview != null &&
                                sub.overview!.isNotEmpty)
                              Text(
                                sub.overview!,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: t.text2,
                                  height: 1.6,
                                ),
                              ),
                            if (sub.sites != null && sub.sites!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                '站点：${sub.sites}',
                                style:
                                    TextStyle(fontSize: 12, color: t.text2),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.hairline)),
                ),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _delete(context, ref),
                      icon: const Icon(Icons.delete_outline_rounded, size: 15),
                      label: const Text('删除订阅'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => _search(context, ref),
                      icon: const Icon(Icons.search_rounded, size: 16),
                      label: const Text('立即搜索资源'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _search(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(nastoolActionsProvider(sourceId))
          .searchSubscribe(sub.id, sub.type);
      if (context.mounted) {
        Navigator.of(context).pop();
        context.showSuccessToast('已触发资源搜索');
      }
    } on Object catch (e) {
      if (context.mounted) context.showErrorToast('搜索失败：$e');
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(nastoolActionsProvider(sourceId))
          .deleteSubscribe(sub.id, sub.type);
      ref.invalidate(nastoolSubscribesProvider(sourceId));
      if (context.mounted) {
        Navigator.of(context).pop();
        context.showSuccessToast('已删除订阅');
      }
    } on Object catch (e) {
      if (context.mounted) context.showErrorToast('删除失败：$e');
    }
  }
}
