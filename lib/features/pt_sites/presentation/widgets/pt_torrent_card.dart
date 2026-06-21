import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/pt_sites/domain/entities/pt_torrent.dart';
import 'package:my_nas/l10n/app_localizations.dart';

/// PT 种子卡片
class PTTorrentCard extends StatelessWidget {
  const PTTorrentCard({
    required this.torrent,
    this.onTap,
    this.onDownload,
    super.key,
  });

  final PTTorrent torrent;
  final VoidCallback? onTap;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：名称
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 促销标签
                  if (torrent.status.hasPromotion) ...[
                    _buildPromotionBadge(torrent.status),
                    const SizedBox(width: 8),
                  ],
                  // 名称
                  Expanded(
                    child: Text(
                      torrent.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppColors.darkOnSurface
                            : AppColors.lightOnSurface,
                      ),
                    ),
                  ),
                ],
              ),

              // 描述（副标题）
              if (torrent.smallDescr != null &&
                  torrent.smallDescr!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  torrent.smallDescr!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                  ),
                ),
              ],

              const SizedBox(height: 8),

              // 第二行：大小、分类、标签
              Row(
                children: [
                  // 大小
                  _buildInfoChip(
                    Icons.storage,
                    torrent.formattedSize,
                    isDark,
                  ),
                  const SizedBox(width: 12),
                  // 分类
                  if (torrent.category != null) ...[
                    _buildInfoChip(
                      Icons.folder_outlined,
                      torrent.category!,
                      isDark,
                    ),
                    const SizedBox(width: 12),
                  ],
                  // 上传时间
                  Expanded(
                    child: _buildInfoChip(
                      Icons.access_time,
                      _formatTime(l, torrent.uploadTime),
                      isDark,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // 第三行：做种/下载/完成 + 下载按钮
              Row(
                children: [
                  // 做种人数
                  _buildStatChip(
                    Icons.upload_rounded,
                    '${torrent.seeders}',
                    torrent.seeders > 0 ? AppColors.success : AppColors.disabled,
                  ),
                  const SizedBox(width: 16),
                  // 下载人数
                  _buildStatChip(
                    Icons.download_rounded,
                    '${torrent.leechers}',
                    torrent.leechers > 0 ? AppColors.warning : AppColors.disabled,
                  ),
                  const SizedBox(width: 16),
                  // 完成次数
                  _buildStatChip(
                    Icons.check_circle_outline,
                    '${torrent.snatched}',
                    theme.colorScheme.primary,
                  ),
                  const Spacer(),
                  // 下载按钮
                  IconButton(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download_rounded),
                    color: theme.colorScheme.primary,
                    tooltip: l.ptCardDownload,
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.primaryContainer,
                    ),
                  ),
                ],
              ),

              // 标签（如果有）
              if (torrent.labels.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: torrent.labels
                      .take(5)
                      .map((label) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : AppColors.lightOnSurfaceVariant,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromotionBadge(PTTorrentStatus status) {
    final label = status.promotionLabel;
    if (label == null) return const SizedBox.shrink();

    final color = status.isFree || status.isDoubleFree
        ? AppColors.success
        : status.isDoubleUp
            ? AppColors.primary
            : AppColors.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text, bool isDark) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: isDark
              ? AppColors.darkOnSurfaceVariant
              : AppColors.lightOnSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? AppColors.darkOnSurfaceVariant
                  : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ),
      ],
    );

  Widget _buildStatChip(IconData icon, String text, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );

  String _formatTime(AppLocalizations l, DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 60) {
      return l.ptCardMinutesAgo(diff.inMinutes);
    } else if (diff.inHours < 24) {
      return l.ptCardHoursAgo(diff.inHours);
    } else if (diff.inDays < 30) {
      return l.ptCardDaysAgo(diff.inDays);
    } else {
      return l.ptCardMonthDay(dateTime.month, dateTime.day);
    }
  }
}
