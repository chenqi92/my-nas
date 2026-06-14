import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/atoms/app_progress_bar.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';
import 'package:my_nas/shared/widgets/desktop_shell/activity_aggregator.dart';

/// 设计稿 `.drawer` 活动中心：右侧 400px 抽屉。从 [activityItemsProvider]
/// 取聚合项（传输 / 视频扫描 / 媒体扫描），空状态显示提示。
class ActivityDrawer extends ConsumerWidget {
  const ActivityDrawer({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final items = buildActivityItems(ref, l);

    return GestureDetector(
      onTap: onClose,
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.35),
        child: Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () {},
            child: ConstrainedBox(
              constraints: const BoxConstraints.tightFor(
                width: 400,
                height: double.infinity,
              ),
              child: GlassPanel(
                strong: true,
                radius: 0,
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
                      decoration: BoxDecoration(
                        border:
                            Border(bottom: BorderSide(color: t.hairline)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.notifications_none_rounded,
                              size: 18, color: t.accentBright),
                          const SizedBox(width: 10),
                          Text(
                            l.shellActTitle,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: t.text0,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            items.isEmpty
                                ? l.shellActNoTasks
                                : l.shellActInProgressCount(items.length),
                            style: TextStyle(fontSize: 12, color: t.text2),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: onClose,
                            icon: Icon(Icons.close_rounded,
                                size: 16, color: t.text2),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 4),
                            child: Text(
                              l.shellActAggregationHint,
                              style: TextStyle(
                                fontSize: 12,
                                color: t.text2,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (items.isEmpty)
                            _EmptyState()
                          else
                            for (final it in items) _ItemTile(item: it),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});
  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: t.chipBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon, size: 16, color: t.accentBright),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.text0,
                      ),
                    ),
                    if (item.detail.isNotEmpty)
                      Text(
                        item.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: t.text2),
                      ),
                  ],
                ),
              ),
              AppTag(item.group),
            ],
          ),
          if (item.progress != null) ...[
            const SizedBox(height: 9),
            AppProgressBar(value: item.progress!),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        children: [
          const StatusDot(DotStatus.off, size: 10, glow: false),
          const SizedBox(height: 10),
          Text(
            l.shellActEmptyTitle,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: t.text1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.shellActEmptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: t.text2, height: 1.4),
          ),
        ],
      ),
    );
  }
}
