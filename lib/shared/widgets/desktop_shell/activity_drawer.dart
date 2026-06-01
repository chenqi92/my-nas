import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 设计稿 `.drawer` 活动中心：右侧 400px 抽屉，聚合传输 / 下载 / 扫描 /
/// 刮削 / 人脸 / 同步进度。
///
/// 现阶段先接入「传输队列」一路；其余 stream 在后续 Group B 迭代中通过
/// `activity_aggregator.dart` 合并。
class ActivityDrawer extends ConsumerWidget {
  const ActivityDrawer({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final transfers = ref.watch(transferTasksProvider).tasks;
    final running = transfers
        .where((x) =>
            x.status == TransferStatus.transferring ||
            x.status == TransferStatus.queued ||
            x.status == TransferStatus.pending)
        .toList(growable: false);

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
              constraints:
                  BoxConstraints.tightFor(width: 400, height: double.infinity),
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
                            '活动中心',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: t.text0,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '统一进度',
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
                              '所有传输 · 下载 · 扫描 · 刮削 · 人脸识别 · 同步 的进度都汇聚于此。',
                              style: TextStyle(
                                fontSize: 12,
                                color: t.text2,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (running.isEmpty)
                            _EmptyState()
                          else
                            for (final task in running) _TaskTile(task: task),
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

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});
  final TransferTask task;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final group = switch (task.type) {
      TransferType.upload => '上传',
      TransferType.download => '下载',
      TransferType.cache => '缓存',
    };
    final groupIcon = switch (task.type) {
      TransferType.upload => Icons.upload_rounded,
      TransferType.download => Icons.download_rounded,
      TransferType.cache => Icons.inventory_2_outlined,
    };

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
                child: Icon(groupIcon, size: 16, color: t.accentBright),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.text0,
                      ),
                    ),
                    Text(
                      task.status.name,
                      style: TextStyle(fontSize: 11.5, color: t.text2),
                    ),
                  ],
                ),
              ),
              AppTag(group),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
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
            '当前没有进行中的任务',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: t.text1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '上传 / 下载 / 扫描 / 刮削 / 同步开始时会自动出现在这里。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: t.text2, height: 1.4),
          ),
        ],
      ),
    );
  }
}
