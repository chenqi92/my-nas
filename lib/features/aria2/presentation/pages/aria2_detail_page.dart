import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/aria2/presentation/providers/aria2_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/service_adapters/aria2/api/aria2_api.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// Aria2 详情页面
class Aria2DetailPage extends ConsumerStatefulWidget {
  const Aria2DetailPage({
    required this.source,
    super.key,
    this.rpcSecret,
  });

  final SourceEntity source;
  final String? rpcSecret;

  @override
  ConsumerState<Aria2DetailPage> createState() => _Aria2DetailPageState();
}

class _Aria2DetailPageState extends ConsumerState<Aria2DetailPage>
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

    await ref.read(aria2ConnectionProvider(widget.source.id).notifier).connect(
          widget.source,
          rpcSecret: widget.rpcSecret,
        );
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(aria2ConnectionProvider(widget.source.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          _buildHeader(context, isDark, connection),
          Expanded(child: _buildBody(context, isDark, connection)),
        ],
      ),
      floatingActionButton: connection?.status == Aria2ConnectionStatus.connected
          ? FloatingActionButton(
              onPressed: () => _showAddDownloadDialog(context),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add_rounded, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildHeader(
    BuildContext context,
    bool isDark,
    Aria2Connection? connection,
  ) {
    final stats = ref.watch(aria2StatsAutoRefreshProvider(widget.source.id));

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
                      onTap: connection?.status == Aria2ConnectionStatus.connected
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
                  // 筛选按钮
                  if (connection?.status == Aria2ConnectionStatus.connected)
                    IconButton(
                      icon: const Icon(Icons.filter_alt_rounded),
                      tooltip: context.l10n.aria2FilterTooltip,
                      onPressed: () => _showFilterDialog(context),
                    ),
                  // 排序按钮
                  if (connection?.status == Aria2ConnectionStatus.connected)
                    IconButton(
                      icon: const Icon(Icons.swap_vert_rounded),
                      tooltip: context.l10n.aria2SortTooltip,
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
                      PopupMenuItem(
                        value: 'pause_all',
                        child: ListTile(
                          leading: const Icon(Icons.pause_rounded),
                          title: Text(context.l10n.aria2PauseAllMenuLabel),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'resume_all',
                        child: ListTile(
                          leading: const Icon(Icons.play_arrow_rounded),
                          title: Text(context.l10n.aria2ResumeAllMenuLabel),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'purge',
                        child: ListTile(
                          leading: const Icon(Icons.cleaning_services),
                          title: Text(context.l10n.aria2PurgeMenuLabel),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'refresh',
                        child: ListTile(
                          leading: const Icon(Icons.refresh_rounded),
                          title: Text(context.l10n.aria2RefreshMenuLabel),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // 速度信息
              if (stats != null &&
                  connection?.status == Aria2ConnectionStatus.connected) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SpeedCard(
                        icon: Icons.download_rounded,
                        label: context.l10n.aria2SpeedCardDownloadLabel,
                        speed: stats.downloadSpeed,
                        count: stats.numActive,
                        countLabel: context.l10n.aria2SpeedCardActiveLabel,
                        color: AppColors.success,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SpeedCard(
                        icon: Icons.upload_rounded,
                        label: context.l10n.aria2SpeedCardUploadLabel,
                        speed: stats.uploadSpeed,
                        count: stats.numWaiting,
                        countLabel: context.l10n.aria2SpeedCardWaitingLabel,
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
    Aria2Connection? connection,
  ) {
    if (connection == null || connection.status == Aria2ConnectionStatus.connecting) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(context.l10n.aria2ConnectingStatus),
          ],
        ),
      );
    }

    if (connection.status == Aria2ConnectionStatus.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(context.l10n.aria2ConnectionFailedTitle, style: context.textTheme.titleLarge),
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
              label: Text(context.l10n.aria2RetryButton),
            ),
          ],
        ),
      );
    }

    return _DownloadList(sourceId: widget.source.id, isDark: isDark);
  }

  void _handleMenuAction(String action, BuildContext context) {
    final actions = ref.read(aria2ActionsProvider(widget.source.id));

    switch (action) {
      case 'pause_all':
        actions.pauseAll();
      case 'resume_all':
        actions.resumeAll();
      case 'purge':
        actions.purgeResults();
      case 'refresh':
        ref.invalidate(aria2AutoRefreshProvider(widget.source.id));
        ref.invalidate(aria2StatsAutoRefreshProvider(widget.source.id));
    }
  }

  void _showAddDownloadDialog(BuildContext context) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: GestureDetector(
          onTap: () {}, // 阻止内部点击事件冒泡
          child: _AddDownloadDialog(sourceId: widget.source.id),
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

  void _showVersionInfoDialog(BuildContext context, Aria2Connection connection) {
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
            Text(context.l10n.aria2VersionInfoDialogTitle),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(
              label: context.l10n.aria2ServiceNameLabel,
              value: widget.source.displayName,
              isDark: isDark,
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: context.l10n.aria2VersionLabel,
              value: info.version ?? context.l10n.aria2UnknownVersion,
              isDark: isDark,
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: context.l10n.aria2ServerAddressLabel,
              value: '${widget.source.host}:${widget.source.port}',
              isDark: isDark,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.aria2CloseButton),
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
    required this.count,
    required this.countLabel,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final int speed;
  final int count;
  final String countLabel;
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
                  '$countLabel: $count',
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

/// 信息行组件
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

/// 下载列表
class _DownloadList extends ConsumerWidget {
  const _DownloadList({required this.sourceId, required this.isDark});

  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(aria2AutoRefreshProvider(sourceId));
    final sortSettings = ref.watch(aria2SortSettingsProvider(sourceId));

    if (downloads.isEmpty) {
      return _buildEmptyState(context);
    }

    // 过滤
    var filtered = downloads.toList();
    if (sortSettings.filterStatus != null && sortSettings.filterStatus != Aria2StatusFilter.all) {
      filtered = filtered.where((d) => switch (sortSettings.filterStatus!) {
          Aria2StatusFilter.all => true,
          Aria2StatusFilter.active => d.isActive,
          Aria2StatusFilter.waiting => d.isWaiting,
          Aria2StatusFilter.paused => d.isPaused,
          Aria2StatusFilter.complete => d.isComplete,
          Aria2StatusFilter.error => d.hasError,
        }).toList();
    }

    // 排序
    filtered.sort((a, b) {
      int result;
      switch (sortSettings.sortMode) {
        case Aria2SortMode.name:
          result = a.name.compareTo(b.name);
        case Aria2SortMode.size:
          result = a.totalLength.compareTo(b.totalLength);
        case Aria2SortMode.progress:
          result = a.progress.compareTo(b.progress);
        case Aria2SortMode.status:
          result = a.status.compareTo(b.status);
        case Aria2SortMode.dlSpeed:
          result = a.downloadSpeed.compareTo(b.downloadSpeed);
        case Aria2SortMode.upSpeed:
          result = a.uploadSpeed.compareTo(b.uploadSpeed);
      }
      return sortSettings.reverse ? -result : result;
    });

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _DownloadTile(
          download: filtered[index],
          sourceId: sourceId,
          isDark: isDark,
        ),
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
              borderRadius: BorderRadius.circular(50),
            ),
            child: Icon(Icons.download_rounded, size: 48, color: AppColors.primary),
          ),
          const SizedBox(height: 24),
          Text(context.l10n.aria2EmptyDownloadTasksTitle, style: context.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            context.l10n.aria2EmptyDownloadTasksHint,
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ],
      ),
    );
}

/// 单个下载项
class _DownloadTile extends ConsumerWidget {
  const _DownloadTile({
    required this.download,
    required this.sourceId,
    required this.isDark,
  });

  final Aria2Download download;
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardColor = _getCardColor();

    return Card(
      margin: EdgeInsets.zero,
      color: cardColor,
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark
            ? BorderSide(color: AppColors.darkOutline.withValues(alpha: 0.2))
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _showDownloadDetails(context, ref),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 名称和操作按钮
              Row(
                children: [
                  _buildStatusIcon(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      download.name,
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkOnSurface : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildActionButtons(context, ref),
                ],
              ),
              const SizedBox(height: 8),
              // 进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: download.progress,
                  backgroundColor: isDark
                      ? AppColors.darkOutline.withValues(alpha: 0.3)
                      : AppColors.lightOutline.withValues(alpha: 0.3),
                  valueColor: AlwaysStoppedAnimation(_getProgressColor()),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              // 详细信息
              Row(
                children: [
                  // 进度百分比
                  Text(
                    '${(download.progress * 100).toStringAsFixed(1)}%',
                    style: context.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _getProgressColor(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 大小
                  Icon(Icons.folder_outlined, size: 14,
                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '${_formatSize(download.completedLength)} / ${_formatSize(download.totalLength)}',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  // 下载速度
                  if (download.downloadSpeed > 0) ...[
                    const Icon(Icons.arrow_downward, size: 14, color: AppColors.success),
                    const SizedBox(width: 2),
                    Text(
                      _formatSpeed(download.downloadSpeed),
                      style: context.textTheme.bodySmall?.copyWith(color: AppColors.success),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // 上传速度
                  if (download.uploadSpeed > 0) ...[
                    Icon(Icons.arrow_upward, size: 14, color: AppColors.primary),
                    const SizedBox(width: 2),
                    Text(
                      _formatSpeed(download.uploadSpeed),
                      style: context.textTheme.bodySmall?.copyWith(color: AppColors.primary),
                    ),
                  ],
                ],
              ),
              // 第二行：上传量
              if (download.uploadLength > 0) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.cloud_upload_outlined, size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      '${context.l10n.aria2UploadedLabel}${_formatSize(download.uploadLength)}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getCardColor() {
    if (download.hasError) return AppColors.error.withValues(alpha: isDark ? 0.08 : 0.05);
    if (download.isComplete) return AppColors.success.withValues(alpha: isDark ? 0.08 : 0.05);
    if (download.isActive) return AppColors.primary.withValues(alpha: isDark ? 0.08 : 0.05);
    if (download.isPaused) return AppColors.warning.withValues(alpha: isDark ? 0.08 : 0.05);
    return isDark ? AppColors.darkSurface : Colors.white;
  }

  Color _getProgressColor() {
    if (download.hasError) return AppColors.error;
    if (download.isComplete) return AppColors.success;
    if (download.isPaused) return AppColors.warning;
    return AppColors.primary;
  }

  Widget _buildStatusIcon() {
    IconData icon;
    Color color;

    if (download.hasError) {
      icon = Icons.error;
      color = AppColors.error;
    } else if (download.isComplete) {
      icon = Icons.check_circle;
      color = AppColors.success;
    } else if (download.isActive) {
      icon = Icons.downloading;
      color = AppColors.primary;
    } else if (download.isPaused) {
      icon = Icons.pause_circle_rounded;
      color = AppColors.warning;
    } else if (download.isWaiting) {
      icon = Icons.hourglass_empty;
      color = AppColors.lightOnSurfaceVariant;
    } else {
      icon = Icons.help_outline_rounded;
      color = AppColors.lightOnSurfaceVariant;
    }

    return Icon(icon, size: 20, color: color);
  }

  Widget _buildActionButtons(BuildContext context, WidgetRef ref) {
    final actions = ref.read(aria2ActionsProvider(sourceId));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (download.isPaused || download.isWaiting)
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            onPressed: () => actions.resume(download.gid),
            tooltip: context.l10n.aria2ResumeTooltip,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          )
        else if (download.isActive)
          IconButton(
            icon: const Icon(Icons.pause_rounded, size: 20),
            onPressed: () => actions.pause(download.gid),
            tooltip: context.l10n.aria2PauseTooltip,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: () => _showDeleteDialog(ref),
          tooltip: context.l10n.aria2DeleteTooltip,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ],
    );
  }

  void _showDeleteDialog(WidgetRef ref) {
    final context = ref.context;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.aria2DeleteTaskDialogTitle),
        content: Text(context.l10n.aria2DeleteTaskDialogContent(download.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.aria2CancelButton),
          ),
          FilledButton(
            onPressed: () {
              ref.read(aria2ActionsProvider(sourceId)).remove(download.gid);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(context.l10n.aria2DeleteButton),
          ),
        ],
      ),
    );
  }

  void _showDownloadDetails(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
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
              const SheetDragHandle(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _buildStatusIcon(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        download.name,
                        style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    _DetailItem(label: context.l10n.aria2DetailItemStatusLabel, value: _getStatusText(context.l10n)),
                    _DetailItem(label: context.l10n.aria2DetailItemSizeLabel, value: _formatSize(download.totalLength)),
                    _DetailItem(label: context.l10n.aria2DetailItemDownloadedLabel, value: _formatSize(download.completedLength)),
                    _DetailItem(label: context.l10n.aria2DetailItemProgressLabel, value: '${(download.progress * 100).toStringAsFixed(1)}%'),
                    if (download.uploadLength > 0)
                      _DetailItem(label: context.l10n.aria2DetailItemUploadedLabel, value: _formatSize(download.uploadLength)),
                    if (download.dir != null)
                      _DetailItem(label: context.l10n.aria2DetailItemSavePathLabel, value: download.dir!),
                    _DetailItem(label: context.l10n.aria2DetailItemGidLabel, value: download.gid),
                    if (download.hasError && download.errorMessage != null)
                      _DetailItem(label: context.l10n.aria2DetailItemErrorLabel, value: download.errorMessage!),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getStatusText(AppLocalizations l10n) {
    if (download.hasError) return l10n.aria2StatusError;
    if (download.isComplete) return l10n.aria2StatusComplete;
    if (download.isActive) return l10n.aria2StatusDownloading;
    if (download.isPaused) return l10n.aria2StatusPaused;
    if (download.isWaiting) return l10n.aria2StatusWaiting;
    if (download.isRemoved) return l10n.aria2StatusRemoved;
    return download.status;
  }
}

/// 详情项
class _DetailItem extends StatelessWidget {
  const _DetailItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: context.textTheme.bodyMedium)),
        ],
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
    final settings = ref.watch(aria2SortSettingsProvider(sourceId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.3,
      maxChildSize: 0.6,
      expand: false,
      builder: (context, scrollController) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SheetDragHandle(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_rounded),
                  const SizedBox(width: 8),
                  Text(context.l10n.aria2FilterSheetTitle, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: Aria2StatusFilter.values.map((status) {
                      final isSelected = (settings.filterStatus == status) ||
                          (settings.filterStatus == null && status == Aria2StatusFilter.all);

                      return FilterChip(
                        label: Text(status.label),
                        selected: isSelected,
                        onSelected: (_) {
                          ref.read(aria2SortSettingsProvider(sourceId).notifier).setFilterStatus(status);
                          Navigator.pop(context);
                        },
                      );
                    }).toList(),
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

/// 排序选项弹框
class _SortOptionsSheet extends ConsumerWidget {
  const _SortOptionsSheet({required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(aria2SortSettingsProvider(sourceId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SheetDragHandle(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.swap_vert_rounded),
                  const SizedBox(width: 8),
                  Text(context.l10n.aria2SortSheetTitle, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      ref.read(aria2SortSettingsProvider(sourceId).notifier).toggleReverse();
                    },
                    icon: Icon(settings.reverse ? Icons.arrow_downward : Icons.arrow_upward, size: 18),
                    label: Text(settings.reverse ? context.l10n.aria2SortDescending : context.l10n.aria2SortAscending),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: Aria2SortMode.values.map((mode) {
                  final isSelected = settings.sortMode == mode;

                  return ListTile(
                    leading: Icon(_getSortIcon(mode), color: isSelected ? AppColors.primary : null),
                    title: Text(mode.label),
                    trailing: isSelected ? Icon(Icons.check_rounded, color: AppColors.primary) : null,
                    selected: isSelected,
                    onTap: () {
                      ref.read(aria2SortSettingsProvider(sourceId).notifier).setSortMode(mode);
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getSortIcon(Aria2SortMode mode) => switch (mode) {
    Aria2SortMode.name => Icons.sort_by_alpha,
    Aria2SortMode.size => Icons.storage,
    Aria2SortMode.progress => Icons.trending_up,
    Aria2SortMode.status => Icons.info_outline,
    Aria2SortMode.dlSpeed => Icons.download_rounded,
    Aria2SortMode.upSpeed => Icons.upload_rounded,
  };
}

/// 添加下载底部弹框
class _AddDownloadDialog extends ConsumerStatefulWidget {
  const _AddDownloadDialog({required this.sourceId});

  final String sourceId;

  @override
  ConsumerState<_AddDownloadDialog> createState() => _AddDownloadDialogState();
}

class _AddDownloadDialogState extends ConsumerState<_AddDownloadDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
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
              const SheetDragHandle(),
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
                      child: Icon(Icons.add_link, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.aria2AddDownloadDialogTitle,
                            style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            context.l10n.aria2AddDownloadDialogSubtitle,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
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
                      label: Text(context.l10n.aria2AddButton),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(context.l10n.aria2DownloadLinkLabel, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: context.l10n.aria2DownloadLinkHint,
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
                                tooltip: context.l10n.aria2PasteTooltip,
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
                      style: context.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', fontSize: 13),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (value == null || value.isEmpty) return context.l10n.aria2ValidationEmptyLink;
                        if (!value.startsWith('magnet:') &&
                            !value.startsWith('http://') &&
                            !value.startsWith('https://') &&
                            !value.startsWith('ftp://')) {
                          return context.l10n.aria2ValidationInvalidLink;
                        }
                        return null;
                      },
                    ),
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
                              child: Text(_errorMessage!, style: context.textTheme.bodySmall?.copyWith(color: AppColors.error)),
                            ),
                          ],
                        ),
                      ),
                    ],
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

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(aria2ActionsProvider(widget.sourceId)).addUri(
            [_controller.text.trim()],
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(context.l10n.aria2TaskAddedSnackbar),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
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
  if (bytesPerSecond < 1024 * 1024 * 1024) return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s';
  return '${(bytesPerSecond / 1024 / 1024 / 1024).toStringAsFixed(2)} GB/s';
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  if (bytes < 1024 * 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  return '${(bytes / 1024 / 1024 / 1024 / 1024).toStringAsFixed(2)} TB';
}
