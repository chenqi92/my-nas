import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/qbittorrent/presentation/providers/qbittorrent_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/qbittorrent/api/qbittorrent_api.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// qBittorrent 详情页面
class QBittorrentDetailPage extends ConsumerStatefulWidget {
  const QBittorrentDetailPage({
    required this.source,
    super.key,
    this.password,
  });

  final SourceEntity source;
  final String? password;

  @override
  ConsumerState<QBittorrentDetailPage> createState() =>
      _QBittorrentDetailPageState();
}

class _QBittorrentDetailPageState extends ConsumerState<QBittorrentDetailPage>
    with ConsumerTabBarVisibilityMixin {
  bool _hasConnected = false;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connect();
    });
  }

  Future<void> _connect() async {
    if (_hasConnected) return;
    _hasConnected = true;

    await ref.read(qbittorrentConnectionProvider(widget.source.id).notifier).connect(
          widget.source,
          password: widget.password,
        );
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(qbittorrentConnectionProvider(widget.source.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          _buildHeader(context, isDark, connection),
          Expanded(child: _buildBody(context, isDark, connection)),
        ],
      ),
      floatingActionButton: connection?.status == QBConnectionStatus.connected
          ? FloatingActionButton(
              onPressed: () => _showAddTorrentDialog(context),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add_rounded, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildHeader(
    BuildContext context,
    bool isDark,
    QBittorrentConnection? connection,
  ) {
    final transferInfo = ref.watch(qbTransferInfoAutoRefreshProvider(widget.source.id));
    final prefsAsync = ref.watch(qbPreferencesProvider(widget.source.id));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : context.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
          child: Column(
            children: [
              // 标题栏
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: connection?.status == QBConnectionStatus.connected
                          ? () => _showVersionInfoDialog(context, connection!)
                          : null,
                      child: Text(
                        widget.source.displayName,
                        style: context.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkOnSurface : null,
                        ),
                      ),
                    ),
                  ),
                  // 备用速度限制按钮（带文字切换）
                  if (connection?.status == QBConnectionStatus.connected)
                    _AltSpeedButton(
                      isEnabled: transferInfo?.useAltSpeedLimits ?? false,
                      onPressed: () {
                        ref.read(qbittorrentActionsProvider(widget.source.id))
                            .toggleAlternativeSpeedLimits();
                      },
                    ),
                  // 筛选按钮
                  if (connection?.status == QBConnectionStatus.connected)
                    IconButton(
                      icon: const Icon(Icons.filter_alt_rounded),
                      tooltip: '筛选',
                      onPressed: () => _showFilterDialog(context),
                    ),
                  // 排序按钮
                  if (connection?.status == QBConnectionStatus.connected)
                    IconButton(
                      icon: const Icon(Icons.swap_vert_rounded),
                      tooltip: '排序',
                      onPressed: () => _showSortDialog(context),
                    ),
                  // 更多操作菜单
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: isDark ? AppColors.darkOnSurface : null,
                    ),
                    onSelected: (value) => _handleMenuAction(value, context),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'pause_all',
                        child: ListTile(
                          leading: Icon(Icons.pause_rounded),
                          title: Text('全部暂停'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'resume_all',
                        child: ListTile(
                          leading: Icon(Icons.play_arrow_rounded),
                          title: Text('全部开始'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'speed_limit',
                        child: ListTile(
                          leading: Icon(Icons.tune_rounded),
                          title: Text('速度限制设置'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'refresh',
                        child: ListTile(
                          leading: Icon(Icons.refresh_rounded),
                          title: Text('刷新'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // 速度信息
              if (transferInfo != null &&
                  connection?.status == QBConnectionStatus.connected) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SpeedCard(
                        icon: Icons.download_rounded,
                        label: '下载',
                        speed: transferInfo.dlInfoSpeed,
                        total: transferInfo.dlInfoData,
                        limit: prefsAsync.valueOrNull?.dlLimit ?? 0,
                        color: AppColors.success,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SpeedCard(
                        icon: Icons.upload_rounded,
                        label: '上传',
                        speed: transferInfo.upInfoSpeed,
                        total: transferInfo.upInfoData,
                        limit: prefsAsync.valueOrNull?.upLimit ?? 0,
                        color: AppColors.primary,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    bool isDark,
    QBittorrentConnection? connection,
  ) {
    if (connection == null || connection.status == QBConnectionStatus.connecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在连接...'),
          ],
        ),
      );
    }

    if (connection.status == QBConnectionStatus.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text('连接失败', style: context.textTheme.titleLarge),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                connection.errorMessage ?? '未知错误',
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium?.copyWith(color: AppColors.error),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                _hasConnected = false;
                _connect();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return _TorrentList(sourceId: widget.source.id, isDark: isDark);
  }

  void _handleMenuAction(String action, BuildContext context) {
    final actions = ref.read(qbittorrentActionsProvider(widget.source.id));

    switch (action) {
      case 'pause_all':
        actions.pauseAll();
      case 'resume_all':
        actions.resumeAll();
      case 'speed_limit':
        _showSpeedLimitDialog(context);
      case 'refresh':
        ref.invalidate(qbittorrentAutoRefreshProvider(widget.source.id));
        ref.invalidate(qbTransferInfoAutoRefreshProvider(widget.source.id));
    }
  }

  void _showAddTorrentDialog(BuildContext context) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: GestureDetector(
          onTap: () {}, // 阻止内部点击事件冒泡
          child: _AddTorrentDialog(sourceId: widget.source.id),
        ),
      ),
    );
  }

  void _showSpeedLimitDialog(BuildContext context) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: GestureDetector(
          onTap: () {}, // 阻止内部点击事件冒泡
          child: _SpeedLimitSheet(sourceId: widget.source.id),
        ),
      ),
    );
  }

  void _showFilterDialog(BuildContext context) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FilterOptionsSheet(sourceId: widget.source.id),
    );
  }

  void _showSortDialog(BuildContext context) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SortOptionsSheet(sourceId: widget.source.id),
    );
  }

  void _showVersionInfoDialog(BuildContext context, QBittorrentConnection connection) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final info = connection.adapter.info;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : null,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.info_outline, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            const Text('版本信息'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(
              label: '服务名称',
              value: widget.source.displayName,
              isDark: isDark,
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: '版本',
              value: info.version ?? '未知',
              isDark: isDark,
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: '服务器地址',
              value: '${widget.source.host}:${widget.source.port}',
              isDark: isDark,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

/// 速度卡片
class _SpeedCard extends StatelessWidget {
  const _SpeedCard({
    required this.icon,
    required this.label,
    required this.speed,
    required this.total,
    required this.color,
    required this.isDark,
    this.limit = 0,
  });

  final IconData icon;
  final String label;
  final int speed;
  final int total;
  final int limit;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
            : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatSpeed(speed),
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurface : color,
                  ),
                ),
                Text(
                  limit > 0
                      ? '$label: ${_formatSize(total)} (限速: ${_formatSpeed(limit)})'
                      : '$label: ${_formatSize(total)}',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
}

/// 信息行组件（用于版本信息弹框）
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.isDark,
  });

  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
}

/// Torrent 列表
class _TorrentList extends ConsumerWidget {
  const _TorrentList({required this.sourceId, required this.isDark});

  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final torrents = ref.watch(qbittorrentAutoRefreshProvider(sourceId));
    final sortSettings = ref.watch(qbSortSettingsProvider(sourceId));

    if (torrents.isEmpty) {
      return _buildEmptyState(context);
    }

    // 过滤
    var filtered = torrents.toList();
    if (sortSettings.filterCategory != null) {
      filtered = filtered.where((t) => t.category == sortSettings.filterCategory).toList();
    }
    if (sortSettings.filterTag != null) {
      filtered = filtered
          .where((t) => t.tags?.split(',').contains(sortSettings.filterTag) ?? false)
          .toList();
    }

    // 排序
    filtered.sort((a, b) {
      int result;
      switch (sortSettings.sortMode) {
        case QBSortMode.name:
          result = a.name.compareTo(b.name);
        case QBSortMode.size:
          result = a.size.compareTo(b.size);
        case QBSortMode.progress:
          result = a.progress.compareTo(b.progress);
        case QBSortMode.state:
          result = a.state.compareTo(b.state);
        case QBSortMode.dlSpeed:
          result = a.dlSpeed.compareTo(b.dlSpeed);
        case QBSortMode.upSpeed:
          result = a.upSpeed.compareTo(b.upSpeed);
        case QBSortMode.addedOn:
          result = (a.addedOn ?? 0).compareTo(b.addedOn ?? 0);
        case QBSortMode.ratio:
          result = (a.ratio ?? 0).compareTo(b.ratio ?? 0);
        case QBSortMode.eta:
          result = (a.eta ?? 0).compareTo(b.eta ?? 0);
        case QBSortMode.uploaded:
          result = (a.uploaded ?? 0).compareTo(b.uploaded ?? 0);
      }
      return sortSettings.reverse ? -result : result;
    });

    // 显示当前筛选状态
    final hasFilter = sortSettings.filterCategory != null || sortSettings.filterTag != null;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(qbittorrentAutoRefreshProvider(sourceId));
      },
      child: Column(
        children: [
          // 筛选状态提示
          if (hasFilter)
            _buildFilterHint(context, ref, sortSettings),
          // 列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: filtered.length + 1, // +1 for bottom padding
              itemBuilder: (context, index) {
                if (index == filtered.length) {
                  return SizedBox(height: MediaQuery.of(context).padding.bottom + 80);
                }
                return _TorrentTile(
                  torrent: filtered[index],
                  sourceId: sourceId,
                  isDark: isDark,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterHint(BuildContext context, WidgetRef ref, QBSortSettings sortSettings) {
    final filters = <String>[];
    if (sortSettings.filterCategory != null) {
      filters.add('分类: ${sortSettings.filterCategory!.isEmpty ? "(未分类)" : sortSettings.filterCategory}');
    }
    if (sortSettings.filterTag != null) {
      filters.add('标签: ${sortSettings.filterTag}');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark
          ? AppColors.primary.withValues(alpha: 0.1)
          : AppColors.primary.withValues(alpha: 0.05),
      child: Row(
        children: [
          Icon(Icons.filter_alt, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              filters.join(' • '),
              style: context.textTheme.bodySmall?.copyWith(color: AppColors.primary),
            ),
          ),
          GestureDetector(
            onTap: () {
              ref.read(qbSortSettingsProvider(sourceId).notifier).setFilterCategory(null);
              ref.read(qbSortSettingsProvider(sourceId).notifier).setFilterTag(null);
            },
            child: Icon(Icons.close_rounded, size: 16, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.download_done, size: 48, color: AppColors.primary),
          ),
          const SizedBox(height: 24),
          Text('暂无下载任务', style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(
            '点击右下角按钮添加任务',
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ],
      ),
    );
}

/// 单个 Torrent 项
class _TorrentTile extends ConsumerWidget {
  const _TorrentTile({
    required this.torrent,
    required this.sourceId,
    required this.isDark,
  });

  final QBTorrent torrent;
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (statusColor, statusIcon) = _getStatusInfo();
    final tagList = torrent.tags?.split(',').where((t) => t.isNotEmpty).toList() ?? [];

    // 根据完成状态确定卡片背景色
    final cardColor = _getCardColor();

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.2)
              : AppColors.lightOutline.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        onTap: () => _showTorrentDetails(context, ref),
        onLongPress: () => _showTorrentActions(context, ref),
        onSecondaryTap: () => _showTorrentActions(context, ref),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 名称和状态
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          torrent.name,
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              _formatSize(torrent.size),
                              style: context.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : AppColors.lightOnSurfaceVariant,
                              ),
                            ),
                            if (torrent.category != null && torrent.category!.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  torrent.category!,
                                  style: context.textTheme.labelSmall?.copyWith(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  _buildQuickAction(context, ref),
                ],
              ),
              // 标签
              if (tagList.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: tagList.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  )).toList(),
                ),
              ],
              // 进度条
              if (torrent.isDownloading || torrent.isPaused) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: torrent.progress,
                    backgroundColor: isDark
                        ? AppColors.darkSurfaceElevated
                        : AppColors.lightSurfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (torrent.dlSpeed > 0 || torrent.upSpeed > 0)
                      Row(
                        children: [
                          if (torrent.dlSpeed > 0) ...[
                            const Icon(Icons.arrow_downward, size: 12, color: AppColors.success),
                            Text(
                              _formatSpeed(torrent.dlSpeed),
                              style: context.textTheme.labelSmall?.copyWith(color: AppColors.success),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (torrent.upSpeed > 0) ...[
                            Icon(Icons.arrow_upward, size: 12, color: AppColors.primary),
                            Text(
                              _formatSpeed(torrent.upSpeed),
                              style: context.textTheme.labelSmall?.copyWith(color: AppColors.primary),
                            ),
                          ],
                        ],
                      )
                    else
                      const SizedBox.shrink(),
                    Text(
                      '${(torrent.progress * 100).toStringAsFixed(1)}%',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              // 做种信息（完成后显示）
              if (torrent.isCompleted) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (torrent.upSpeed > 0) ...[
                      Icon(Icons.arrow_upward, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        _formatSpeed(torrent.upSpeed),
                        style: context.textTheme.bodySmall?.copyWith(color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                    ],
                    const Icon(Icons.sync_rounded, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '分享率: ${torrent.ratio?.toStringAsFixed(2) ?? '-'}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                    if (torrent.uploaded != null && torrent.uploaded! > 0) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.cloud_upload_outlined, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '已上传: ${_formatSize(torrent.uploaded!)}',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  (Color, IconData) _getStatusInfo() {
    if (torrent.hasError) return (AppColors.error, Icons.error);
    if (torrent.isPaused) return (AppColors.warning, Icons.pause_circle_rounded);
    if (torrent.isDownloading) return (AppColors.success, Icons.downloading);
    if (torrent.isUploading) return (AppColors.primary, Icons.upload_rounded);
    if (torrent.isCompleted) return (AppColors.success, Icons.check_circle);
    return (Colors.grey, Icons.help_outline_rounded);
  }

  /// 根据种子状态获取卡片背景色
  Color _getCardColor() {
    if (torrent.hasError) {
      // 错误状态 - 红色调
      return isDark
          ? AppColors.error.withValues(alpha: 0.08)
          : AppColors.error.withValues(alpha: 0.05);
    }
    if (torrent.isCompleted) {
      // 已完成 - 绿色调
      return isDark
          ? AppColors.success.withValues(alpha: 0.08)
          : AppColors.success.withValues(alpha: 0.05);
    }
    if (torrent.isDownloading) {
      // 下载中 - 蓝色调
      return isDark
          ? AppColors.primary.withValues(alpha: 0.08)
          : AppColors.primary.withValues(alpha: 0.05);
    }
    if (torrent.isPaused) {
      // 暂停 - 橙色调
      return isDark
          ? AppColors.warning.withValues(alpha: 0.08)
          : AppColors.warning.withValues(alpha: 0.05);
    }
    // 默认颜色
    return isDark
        ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
        : AppColors.lightSurface;
  }

  Widget _buildQuickAction(BuildContext context, WidgetRef ref) {
    final actions = ref.read(qbittorrentActionsProvider(sourceId));

    if (torrent.isPaused) {
      return IconButton(
        icon: const Icon(Icons.play_arrow_rounded),
        onPressed: () => actions.resume([torrent.hash]),
        tooltip: '继续',
      );
    }

    if (torrent.isDownloading || torrent.isUploading) {
      return IconButton(
        icon: const Icon(Icons.pause_rounded),
        onPressed: () => actions.pause([torrent.hash]),
        tooltip: '暂停',
      );
    }

    return IconButton(
      icon: const Icon(Icons.more_vert_rounded),
      onPressed: () => _showTorrentActions(context, ref),
    );
  }

  void _showTorrentDetails(BuildContext context, WidgetRef ref) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            const SheetDragHandle(topPadding: 0, bottomPadding: 16),
            Text(
              torrent.name,
              style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _DetailItem(label: '大小', value: _formatSize(torrent.size)),
            _DetailItem(label: '进度', value: '${(torrent.progress * 100).toStringAsFixed(1)}%'),
            _DetailItem(label: '状态', value: torrent.state),
            if (torrent.dlSpeed > 0)
              _DetailItem(label: '下载速度', value: _formatSpeed(torrent.dlSpeed)),
            if (torrent.upSpeed > 0)
              _DetailItem(label: '上传速度', value: _formatSpeed(torrent.upSpeed)),
            if (torrent.ratio != null)
              _DetailItem(label: '分享率', value: torrent.ratio!.toStringAsFixed(2)),
            if (torrent.numSeeds != null)
              _DetailItem(label: '种子数', value: torrent.numSeeds.toString()),
            if (torrent.numLeechers != null)
              _DetailItem(label: '下载者', value: torrent.numLeechers.toString()),
            if (torrent.category != null && torrent.category!.isNotEmpty)
              _DetailItem(label: '分类', value: torrent.category!),
            if (torrent.tags != null && torrent.tags!.isNotEmpty)
              _DetailItem(label: '标签', value: torrent.tags!),
            if (torrent.savePath != null)
              _DetailItem(label: '保存路径', value: torrent.savePath!),
            if (torrent.addedOn != null)
              _DetailItem(
                label: '添加时间',
                value: DateTime.fromMillisecondsSinceEpoch(torrent.addedOn! * 1000)
                    .toString()
                    .substring(0, 19),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: torrent.hash));
                      context.showSuccessToast('已复制 Hash');
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('复制 Hash'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTorrentActions(BuildContext context, WidgetRef ref) {
    showAdaptiveModalSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetDragHandle(),
            ListTile(
              leading: Icon(torrent.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
              title: Text(torrent.isPaused ? '继续' : '暂停'),
              onTap: () {
                Navigator.pop(context);
                final actions = ref.read(qbittorrentActionsProvider(sourceId));
                if (torrent.isPaused) {
                  actions.resume([torrent.hash]);
                } else {
                  actions.pause([torrent.hash]);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('更改保存位置'),
              onTap: () {
                Navigator.pop(context);
                _showLocationDialog(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.category),
              title: const Text('修改分类'),
              onTap: () {
                Navigator.pop(context);
                _showCategoryDialog(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.label),
              title: const Text('管理标签'),
              onTap: () {
                Navigator.pop(context);
                _showTagsDialog(context, ref);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除任务'),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, ref, deleteFiles: false);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_forever, color: AppColors.error),
              title: Text('删除任务和文件', style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, ref, deleteFiles: true);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: torrent.name);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '新名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(qbittorrentActionsProvider(sourceId)).rename(
                    torrent.hash,
                    controller.text,
                  );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showLocationDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: torrent.savePath);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('更改保存位置'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '保存路径',
            hintText: '/path/to/save',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(qbittorrentActionsProvider(sourceId)).setLocation(
                [torrent.hash],
                controller.text,
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showCategoryDialog(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.read(qbCategoriesProvider(sourceId));
    final categories = categoriesAsync.valueOrNull?.keys.toList() ?? [];

    showAdaptiveModalSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('无分类'),
              onTap: () {
                Navigator.pop(context);
                ref.read(qbittorrentActionsProvider(sourceId)).setCategory([torrent.hash], '');
              },
            ),
            ...categories.map(
              (c) => ListTile(
                title: Text(c),
                trailing: torrent.category == c ? const Icon(Icons.check_rounded) : null,
                onTap: () {
                  Navigator.pop(context);
                  ref.read(qbittorrentActionsProvider(sourceId)).setCategory([torrent.hash], c);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('创建新分类'),
              onTap: () {
                Navigator.pop(context);
                _showCreateCategoryDialog(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateCategoryDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final pathController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建分类'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '分类名称'),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pathController,
              decoration: const InputDecoration(
                labelText: '保存路径（可选）',
                hintText: '/path/to/save',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final actions = ref.read(qbittorrentActionsProvider(sourceId));
              await actions.createCategory(
                nameController.text,
                savePath: pathController.text.isNotEmpty ? pathController.text : null,
              );
              await actions.setCategory([torrent.hash], nameController.text);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showTagsDialog(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.read(qbTagsProvider(sourceId));
    final allTags = tagsAsync.valueOrNull ?? [];
    final currentTags = torrent.tags?.split(',').where((t) => t.isNotEmpty).toList() ?? [];

    showAdaptiveModalSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('选择标签', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ...allTags.map(
                (tag) => CheckboxListTile(
                  title: Text(tag),
                  value: currentTags.contains(tag),
                  onChanged: (checked) {
                    final actions = ref.read(qbittorrentActionsProvider(sourceId));
                    if (checked ?? false) {
                      actions.addTags([torrent.hash], [tag]);
                      setState(() => currentTags.add(tag));
                    } else {
                      actions.removeTags([torrent.hash], [tag]);
                      setState(() => currentTags.remove(tag));
                    }
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: const Text('创建新标签'),
                onTap: () {
                  Navigator.pop(context);
                  _showCreateTagDialog(context, ref);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateTagDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建标签'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '标签名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final actions = ref.read(qbittorrentActionsProvider(sourceId));
              await actions.createTags([controller.text]);
              await actions.addTags([torrent.hash], [controller.text]);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, {required bool deleteFiles}) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
          deleteFiles
              ? '确定要删除 "${torrent.name}" 及其文件吗？\n此操作不可恢复。'
              : '确定要删除 "${torrent.name}" 吗？\n文件将保留在磁盘上。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(qbittorrentActionsProvider(sourceId)).delete(
                [torrent.hash],
                deleteFiles: deleteFiles,
              );
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 详情项
class _DetailItem extends StatelessWidget {
  const _DetailItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: context.textTheme.bodyMedium)),
        ],
      ),
    );
}

/// 备用速度限制按钮（只显示图标，切换时改变图标样式）
class _AltSpeedButton extends StatelessWidget {
  const _AltSpeedButton({
    required this.isEnabled,
    required this.onPressed,
  });

  final bool isEnabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return IconButton(
      onPressed: onPressed,
      tooltip: isEnabled ? '恢复全局速度' : '启用备用限速',
      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isEnabled
              ? AppColors.warning.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isEnabled
              ? Border.all(color: AppColors.warning.withValues(alpha: 0.4))
              : null,
        ),
        child: Icon(
          isEnabled ? Icons.rocket_launch : Icons.speed_outlined,
          size: 20,
          color: isEnabled
              ? AppColors.warning
              : (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
        ),
      ),
    );
  }
}

/// 筛选选项弹框
class _FilterOptionsSheet extends ConsumerWidget {
  const _FilterOptionsSheet({required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(qbSortSettingsProvider(sourceId));
    final categoriesAsync = ref.watch(qbCategoriesProvider(sourceId));
    final tagsAsync = ref.watch(qbTagsProvider(sourceId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final categories = categoriesAsync.valueOrNull?.keys.toList() ?? [];
    final tags = tagsAsync.valueOrNull ?? [];

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 拖动指示器
            const SheetDragHandle(),
            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '筛选',
                    style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (settings.filterCategory != null || settings.filterTag != null)
                    TextButton(
                      onPressed: () {
                        ref.read(qbSortSettingsProvider(sourceId).notifier).setFilterCategory(null);
                        ref.read(qbSortSettingsProvider(sourceId).notifier).setFilterTag(null);
                      },
                      child: const Text('清除'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 内容
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  // 分类筛选
                  if (categories.isNotEmpty) ...[
                    Text(
                      '分类',
                      style: context.textTheme.titleSmall?.copyWith(
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _FilterChip(
                          label: '全部',
                          isSelected: settings.filterCategory == null,
                          onTap: () {
                            ref.read(qbSortSettingsProvider(sourceId).notifier).setFilterCategory(null);
                          },
                        ),
                        ...categories.map((c) => _FilterChip(
                          label: c.isEmpty ? '(未分类)' : c,
                          isSelected: settings.filterCategory == c,
                          onTap: () {
                            ref.read(qbSortSettingsProvider(sourceId).notifier).setFilterCategory(c);
                          },
                        )),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                  // 标签筛选
                  if (tags.isNotEmpty) ...[
                    Text(
                      '标签',
                      style: context.textTheme.titleSmall?.copyWith(
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _FilterChip(
                          label: '全部',
                          isSelected: settings.filterTag == null,
                          onTap: () {
                            ref.read(qbSortSettingsProvider(sourceId).notifier).setFilterTag(null);
                          },
                        ),
                        ...tags.map((t) => _FilterChip(
                          label: t,
                          isSelected: settings.filterTag == t,
                          onTap: () {
                            ref.read(qbSortSettingsProvider(sourceId).notifier).setFilterTag(t);
                          },
                        )),
                      ],
                    ),
                  ],
                  if (categories.isEmpty && tags.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.filter_alt_off,
                              size: 48,
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '暂无可用的筛选选项',
                              style: context.textTheme.bodyMedium?.copyWith(
                                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '添加分类或标签后可在此筛选',
                              style: context.textTheme.bodySmall?.copyWith(
                                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 筛选选项 Chip
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.15)
              : (isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant),
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.5))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? AppColors.primary
                : (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
          ),
        ),
      ),
    );
  }
}

/// 排序选项
class _SortOptionsSheet extends ConsumerWidget {
  const _SortOptionsSheet({required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(qbSortSettingsProvider(sourceId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 拖动指示器
            const SheetDragHandle(),
            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.swap_vert_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '排序',
                    style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  // 升序/降序切换
                  TextButton.icon(
                    onPressed: () {
                      ref.read(qbSortSettingsProvider(sourceId).notifier).toggleReverse();
                    },
                    icon: Icon(
                      settings.reverse ? Icons.arrow_downward : Icons.arrow_upward,
                      size: 18,
                    ),
                    label: Text(settings.reverse ? '降序' : '升序'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 排序选项列表
            Expanded(
              child: ListView(
                controller: scrollController,
                children: QBSortMode.values.map(
                  (mode) => ListTile(
                    leading: Icon(
                      _getSortModeIcon(mode),
                      color: settings.sortMode == mode ? AppColors.primary : null,
                    ),
                    title: Text(
                      mode.label,
                      style: TextStyle(
                        fontWeight: settings.sortMode == mode ? FontWeight.w600 : null,
                        color: settings.sortMode == mode ? AppColors.primary : null,
                      ),
                    ),
                    trailing: settings.sortMode == mode
                        ? Icon(Icons.check_rounded, color: AppColors.primary)
                        : null,
                    onTap: () {
                      ref.read(qbSortSettingsProvider(sourceId).notifier).setSortMode(mode);
                    },
                  ),
                ).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getSortModeIcon(QBSortMode mode) => switch (mode) {
        QBSortMode.name => Icons.sort_by_alpha,
        QBSortMode.size => Icons.storage,
        QBSortMode.progress => Icons.percent,
        QBSortMode.state => Icons.circle,
        QBSortMode.dlSpeed => Icons.download_rounded,
        QBSortMode.upSpeed => Icons.upload_rounded,
        QBSortMode.addedOn => Icons.schedule_rounded,
        QBSortMode.ratio => Icons.sync_rounded,
        QBSortMode.eta => Icons.timer,
        QBSortMode.uploaded => Icons.cloud_upload,
      };
}

/// 速度限制设置底部弹框（可拖动）
class _SpeedLimitSheet extends ConsumerStatefulWidget {
  const _SpeedLimitSheet({required this.sourceId});

  final String sourceId;

  @override
  ConsumerState<_SpeedLimitSheet> createState() => _SpeedLimitSheetState();
}

class _SpeedLimitSheetState extends ConsumerState<_SpeedLimitSheet> {
  final _dlLimitController = TextEditingController();
  final _upLimitController = TextEditingController();
  final _altDlLimitController = TextEditingController();
  final _altUpLimitController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await ref.read(qbPreferencesProvider(widget.sourceId).future);
    if (prefs != null && mounted) {
      setState(() {
        _dlLimitController.text = prefs.dlLimit > 0 ? (prefs.dlLimit ~/ 1024).toString() : '';
        _upLimitController.text = prefs.upLimit > 0 ? (prefs.upLimit ~/ 1024).toString() : '';
        _altDlLimitController.text = prefs.altDlLimit > 0 ? (prefs.altDlLimit ~/ 1024).toString() : '';
        _altUpLimitController.text = prefs.altUpLimit > 0 ? (prefs.altUpLimit ~/ 1024).toString() : '';
      });
    }
  }

  @override
  void dispose() {
    _dlLimitController.dispose();
    _upLimitController.dispose();
    _altDlLimitController.dispose();
    _altUpLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, scrollController) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 拖动指示器
            const SheetDragHandle(),
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.speed,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '速度限制设置',
                          style: context.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '设置全局和备用速度限制',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 保存按钮
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('保存'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 内容区域
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  // 全局限速
                  Text(
                    '全局限速',
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '设置为 0 表示不限速',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSpeedInput(
                          controller: _dlLimitController,
                          label: '下载',
                          icon: Icons.download_rounded,
                          color: AppColors.success,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSpeedInput(
                          controller: _upLimitController,
                          label: '上传',
                          icon: Icons.upload_rounded,
                          color: AppColors.primary,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // 备用限速
                  Text(
                    '备用限速',
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '可通过快捷按钮临时切换到备用限速',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSpeedInput(
                          controller: _altDlLimitController,
                          label: '下载',
                          icon: Icons.download_rounded,
                          color: AppColors.warning,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSpeedInput(
                          controller: _altUpLimitController,
                          label: '上传',
                          icon: Icons.upload_rounded,
                          color: AppColors.warning,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) => TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: '$label (KB/s)',
        hintText: '0',
        prefixIcon: Icon(icon, color: color, size: 20),
        filled: true,
        fillColor: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
            : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    );

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      final actions = ref.read(qbittorrentActionsProvider(widget.sourceId));

      final dlLimit = (int.tryParse(_dlLimitController.text) ?? 0) * 1024;
      final upLimit = (int.tryParse(_upLimitController.text) ?? 0) * 1024;
      final altDlLimit = (int.tryParse(_altDlLimitController.text) ?? 0) * 1024;
      final altUpLimit = (int.tryParse(_altUpLimitController.text) ?? 0) * 1024;

      await actions.setGlobalSpeedLimits(dlLimit: dlLimit, upLimit: upLimit);
      await actions.setAlternativeSpeedLimits(dlLimit: altDlLimit, upLimit: altUpLimit);

      if (mounted) {
        Navigator.pop(context);
        context.showSuccessSnackBar('速度限制已保存');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

/// 添加 Torrent 底部弹框（可拖动）
class _AddTorrentDialog extends ConsumerStatefulWidget {
  const _AddTorrentDialog({required this.sourceId});

  final String sourceId;

  @override
  ConsumerState<_AddTorrentDialog> createState() => _AddTorrentDialogState();
}

class _AddTorrentDialogState extends ConsumerState<_AddTorrentDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _paused = false;
  String? _selectedCategory;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(qbCategoriesProvider(widget.sourceId));
    final categories = categoriesAsync.valueOrNull?.keys.toList() ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scrollController) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 拖动指示器
              const SheetDragHandle(),
              // 标题（固定）
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.add_link,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '添加下载任务',
                            style: context.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '粘贴 Magnet 链接或 Torrent URL',
                            style: context.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? AppColors.darkOnSurfaceVariant
                                  : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 添加按钮（移到右上角）
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _submit,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_rounded, size: 18),
                      label: const Text('添加'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 内容区域（可滚动）
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // 链接输入框
                    Text(
                      '下载链接',
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'magnet:?xt=urn:btih:... 或 https://...',
                        hintStyle: TextStyle(
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.5)
                              : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        filled: true,
                        fillColor: isDark
                            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                            : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.primary, width: 2),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.error),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                        suffixIcon: _controller.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _controller.clear();
                                  setState(() {});
                                },
                              )
                            : IconButton(
                                icon: const Icon(Icons.content_paste_rounded, size: 18),
                                tooltip: '粘贴',
                                onPressed: () async {
                                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                                  if (data?.text != null) {
                                    _controller.text = data!.text!;
                                    setState(() {});
                                  }
                                },
                              ),
                      ),
                      maxLines: 4,
                      minLines: 3,
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (value == null || value.isEmpty) return '请输入链接';
                        if (!value.startsWith('magnet:') &&
                            !value.startsWith('http://') &&
                            !value.startsWith('https://')) {
                          return '请输入有效的 Magnet 链接或 HTTP URL';
                        }
                        return null;
                      },
                    ),
                    // 错误提示
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: context.textTheme.bodySmall?.copyWith(color: AppColors.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    // 分类选择
                    if (categories.isNotEmpty) ...[
                      Text(
                        '分类',
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildCategoryChip(
                            context,
                            label: '无',
                            isSelected: _selectedCategory == null,
                            onTap: () => setState(() => _selectedCategory = null),
                          ),
                          ...categories.map(
                            (category) => _buildCategoryChip(
                              context,
                              label: category.isEmpty ? '(未分类)' : category,
                              isSelected: _selectedCategory == category,
                              onTap: () => setState(() => _selectedCategory = category),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    // 选项
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                            : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => setState(() => _paused = !_paused),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Icon(
                                  _paused ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                                  color: _paused ? AppColors.warning : AppColors.success,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '添加后暂停',
                                        style: context.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        _paused ? '任务将不会自动开始下载' : '任务将立即开始下载',
                                        style: context.textTheme.bodySmall?.copyWith(
                                          color: isDark
                                              ? AppColors.darkOnSurfaceVariant
                                              : AppColors.lightOnSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _paused,
                                  onChanged: (value) => setState(() => _paused = value),
                                  activeTrackColor: AppColors.warning.withValues(alpha: 0.5),
                                  thumbColor: WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return AppColors.warning;
                                    }
                                    return null;
                                  }),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 底部空白
                    SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.15)
              : (isDark
                  ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                  : AppColors.lightSurfaceVariant),
          borderRadius: BorderRadius.circular(18),
          border: isSelected
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.5))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? AppColors.primary
                : (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(qbittorrentActionsProvider(widget.sourceId)).addTorrent(
            _controller.text.trim(),
            category: _selectedCategory,
            paused: _paused,
          );

      if (mounted) {
        Navigator.pop(context);
        context.showSuccessSnackBar('任务已添加');
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }
}

// === 工具函数 ===

String _formatSpeed(int bytesPerSecond) {
  if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
  if (bytesPerSecond < 1024 * 1024) return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
  if (bytesPerSecond < 1024 * 1024 * 1024) {
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes < 1024 * 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(1)} TB';
}
