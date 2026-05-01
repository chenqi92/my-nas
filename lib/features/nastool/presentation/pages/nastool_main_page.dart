// ignore_for_file: dead_code, dead_null_aware_expression

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';
import 'package:my_nas/service_adapters/nastool/nastool_adapter.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';

/// NASTool 主页面
class NasToolMainPage extends ConsumerStatefulWidget {
  const NasToolMainPage({required this.source, super.key});

  final SourceEntity source;

  @override
  ConsumerState<NasToolMainPage> createState() => _NasToolMainPageState();
}

class _NasToolMainPageState extends ConsumerState<NasToolMainPage>
    with ConsumerTabBarVisibilityMixin {
  int _selectedIndex = 0;

  static const _navItems = [
    _NavItem(icon: Icons.dashboard_rounded, label: '仪表盘'),
    _NavItem(icon: Icons.bookmark_rounded, label: '订阅'),
    _NavItem(icon: Icons.download_rounded, label: '下载'),
    _NavItem(icon: Icons.search_rounded, label: '搜索'),
    _NavItem(icon: Icons.movie_rounded, label: '媒体'),
    _NavItem(icon: Icons.language_rounded, label: '站点'),
    _NavItem(icon: Icons.extension_rounded, label: '高级'),
    _NavItem(icon: Icons.settings_rounded, label: '设置'),
  ];

  @override
  void initState() {
    super.initState();
    hideTabBar();
    // 自动连接到 NASTool
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectToNasTool();
    });
  }

  Future<void> _connectToNasTool() async {
    final notifier = ref.read(nastoolConnectionProvider(widget.source.id).notifier);
    final connection = ref.read(nastoolConnectionProvider(widget.source.id));

    // 如果未连接，则自动连接
    if (connection == null || connection.status == NasToolConnectionStatus.disconnected ||
        connection.status == NasToolConnectionStatus.error) {
      await notifier.connect(widget.source);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connection = ref.watch(nastoolConnectionProvider(widget.source.id));
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: Row(
        children: [
          _buildNavRail(context, isDark, isWide),
          Expanded(
            child: Column(
              children: [
                _buildHeader(context, isDark, connection),
                Expanded(child: _buildContent(context, isDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavRail(BuildContext context, bool isDark, bool isWide) => Container(
        width: isWide ? 200 : 72,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          border: Border(
            right: BorderSide(
              color: isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.1)
                  : AppColors.lightOutline.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                mainAxisAlignment: isWide ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryLight],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.movie_filter_rounded, size: 20, color: Colors.white),
                  ),
                  if (isWide) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'NASTool',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                itemCount: _navItems.length,
                itemBuilder: (context, index) {
                  final item = _navItems[index];
                  final isSelected = _selectedIndex == index;
                  return _buildNavItem(
                    context, item, isSelected, isDark, isWide,
                    () => setState(() => _selectedIndex = index),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: _buildNavItem(
                context,
                const _NavItem(icon: Icons.arrow_back_rounded, label: '返回'),
                false, isDark, isWide,
                () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      );

  Widget _buildNavItem(
    BuildContext context,
    _NavItem item,
    bool isSelected,
    bool isDark,
    bool isWide,
    VoidCallback onTap,
  ) {
    final color = isSelected
        ? AppColors.primary
        : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      child: Material(
        color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: isWide ? AppSpacing.md : AppSpacing.sm),
            child: Row(
              mainAxisAlignment: isWide ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(item.icon, color: color, size: 22),
                if (isWide) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    item.label,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, NasToolConnection? connection) => Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          border: Border(
            bottom: BorderSide(
              color: isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.1)
                  : AppColors.lightOutline.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: Row(
          children: [
            Text(
              _navItems[_selectedIndex].label,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
            const Spacer(),
            if (connection != null && connection.status == NasToolConnectionStatus.connected) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(connection.adapter.username ?? '已连接', style: context.textTheme.bodySmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.read(nastoolActionsProvider(widget.source.id)).refreshAll(),
              tooltip: '刷新',
            ),
          ],
        ),
      );

  Widget _buildContent(BuildContext context, bool isDark) {
    switch (_selectedIndex) {
      case 0: return _DashboardContent(sourceId: widget.source.id, isDark: isDark);
      case 1: return _SubscribesContent(sourceId: widget.source.id, isDark: isDark);
      case 2: return _DownloadsContent(sourceId: widget.source.id, isDark: isDark);
      case 3: return _SearchContent(sourceId: widget.source.id, isDark: isDark);
      case 4: return _MediaContent(sourceId: widget.source.id, isDark: isDark);
      case 5: return _SitesContent(sourceId: widget.source.id, isDark: isDark);
      case 6: return _AdvancedContent(sourceId: widget.source.id, isDark: isDark);
      case 7: return _SettingsContent(sourceId: widget.source.id, isDark: isDark);
      default: return const Center(child: Text('404'));
    }
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

// ============================================================
// Dashboard Content - Enhanced
// ============================================================

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(nastoolStatsProvider(sourceId));
    final systemAsync = ref.watch(nastoolSystemInfoProvider(sourceId));
    final siteStatsAsync = ref.watch(nastoolSiteStatisticsProvider(sourceId));
    final transfersAsync = ref.watch(nastoolTransferHistoryProvider(sourceId));

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (stats) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(nastoolStatsProvider(sourceId));
          ref.invalidate(nastoolSystemInfoProvider(sourceId));
          ref.invalidate(nastoolSiteStatisticsProvider(sourceId));
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // System Info Section
            systemAsync.when(
              data: (sys) => _buildSystemInfo(context, sys),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Stats Cards
            _buildSectionTitle(context, '媒体库统计'),
            const SizedBox(height: AppSpacing.md),
            _buildStatsGrid(context, stats),
            const SizedBox(height: AppSpacing.xl),

            // Site Statistics Summary
            _buildSectionTitle(context, '站点数据'),
            const SizedBox(height: AppSpacing.md),
            siteStatsAsync.when(
              data: (sites) => _buildSiteStats(context, sites),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _buildEmptyState('暂无站点数据'),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Recent Transfers
            _buildSectionTitle(context, '最近转移'),
            const SizedBox(height: AppSpacing.md),
            transfersAsync.when(
              data: (transfers) => _buildTransferList(context, transfers.take(5).toList()),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _buildEmptyState('暂无转移记录'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) => Text(
        title,
        style: context.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
        ),
      );

  Widget _buildSystemInfo(BuildContext context, NtSystemInfo sys) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [AppColors.primary.withValues(alpha: 0.2), AppColors.primaryLight.withValues(alpha: 0.1)]
                : [AppColors.primary.withValues(alpha: 0.1), AppColors.primaryLight.withValues(alpha: 0.05)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.dns_rounded, color: AppColors.primary, size: 28),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NASTool ${sys.version ?? ""}', style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  if (sys.totalSpace != null)
                    Text(
                      '存储: ${_formatBytes(sys.freeSpace ?? 0)} / ${_formatBytes(sys.totalSpace!)}',
                      style: context.textTheme.bodySmall?.copyWith(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (sys.latestVersion != null && sys.version != sys.latestVersion)
              Chip(label: Text('有更新: ${sys.latestVersion}'), backgroundColor: AppColors.warning.withValues(alpha: 0.2)),
          ],
        ),
      );

  Widget _buildStatsGrid(BuildContext context, NasToolOverviewStats? stats) => LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = constraints.maxWidth > 600 ? 160.0 : (constraints.maxWidth - AppSpacing.md * 3) / 2;
          return Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              _StatCard(icon: Icons.movie_rounded, label: '电影', value: '${stats?.movieCount ?? 0}', color: AppColors.primary, isDark: isDark, width: cardWidth),
              _StatCard(icon: Icons.tv_rounded, label: '剧集', value: '${stats?.tvCount ?? 0}', color: AppColors.success, isDark: isDark, width: cardWidth),
              _StatCard(icon: Icons.animation_rounded, label: '动漫', value: '${stats?.animeCount ?? 0}', color: const Color(0xFF9C27B0), isDark: isDark, width: cardWidth),
              _StatCard(icon: Icons.bookmark_rounded, label: '订阅', value: '${stats?.subscribeCount ?? 0}', color: const Color(0xFF009688), isDark: isDark, width: cardWidth),
              _StatCard(icon: Icons.downloading_rounded, label: '下载中', value: '${stats?.activeDownloads ?? 0}', color: AppColors.warning, isDark: isDark, width: cardWidth),
              _StatCard(icon: Icons.check_circle_rounded, label: '已完成', value: '${stats?.completedDownloads ?? 0}', color: AppColors.success, isDark: isDark, width: cardWidth),
            ],
          );
        },
      );

  Widget _buildSiteStats(BuildContext context, List<NtSiteStatistics> sites) {
    if (sites.isEmpty) return _buildEmptyState('暂无站点');
    final totalUp = sites.fold<int>(0, (sum, s) => sum + (s.upload ?? 0));
    final totalDown = sites.fold<int>(0, (sum, s) => sum + (s.download ?? 0));
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkOutline.withValues(alpha: 0.1) : AppColors.lightOutline.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildDataItem(context, Icons.upload_rounded, '总上传', _formatBytes(totalUp), AppColors.success)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _buildDataItem(context, Icons.download_rounded, '总下载', _formatBytes(totalDown), AppColors.primary)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _buildDataItem(context, Icons.language_rounded, '站点数', '${sites.length}', Colors.purple)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataItem(BuildContext context, IconData icon, String label, String value, Color color) => Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurface : color)),
          Text(label, style: context.textTheme.bodySmall?.copyWith(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)),
        ],
      );

  Widget _buildTransferList(BuildContext context, List<NtTransferHistory> transfers) {
    if (transfers.isEmpty) return _buildEmptyState('暂无转移记录');
    return Column(
      children: transfers.map((t) => Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: ListTile(
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.check_circle_rounded, color: AppColors.success),
          ),
          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(t.date != null ? '${t.date!.year}-${t.date!.month.toString().padLeft(2, '0')}-${t.date!.day.toString().padLeft(2, '0')}' : '', style: context.textTheme.bodySmall),
        ),
      )).toList(),
    );
  }

  Widget _buildEmptyState(String message) => Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: Text(message, style: TextStyle(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)),
        ),
      );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    if (bytes < 1024 * 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    return '${(bytes / 1024 / 1024 / 1024 / 1024).toStringAsFixed(2)} TB';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value, required this.color, required this.isDark, this.width = 160});

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isDark;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? AppColors.darkOutline.withValues(alpha: 0.1) : color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(value, style: context.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurface : color)),
            Text(label, style: context.textTheme.bodySmall?.copyWith(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)),
          ],
        ),
      );
}

// ============================================================
// Subscribes Content - Enhanced with tabs and actions
// ============================================================

class _SubscribesContent extends ConsumerStatefulWidget {
  const _SubscribesContent({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  ConsumerState<_SubscribesContent> createState() => _SubscribesContentState();
}

class _SubscribesContentState extends ConsumerState<_SubscribesContent> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subscribesAsync = ref.watch(nastoolSubscribesProvider(widget.sourceId));

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [Tab(text: '电影'), Tab(text: '剧集')],
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
        ),
        Expanded(
          child: subscribesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败: $e')),
            data: (subscribes) {
              final movies = subscribes.where((s) => s.isMovie).toList();
              final tvs = subscribes.where((s) => !s.isMovie).toList();
              return TabBarView(
                controller: _tabController,
                children: [
                  _buildSubscribeList(context, movies, true),
                  _buildSubscribeList(context, tvs, false),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSubscribeList(BuildContext context, List<NtSubscribe> items, bool isMovie) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isMovie ? Icons.movie_outlined : Icons.tv_outlined, size: 64, color: widget.isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text('暂无${isMovie ? '电影' : '剧集'}订阅', style: context.textTheme.titleMedium?.copyWith(color: widget.isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(nastoolSubscribesProvider(widget.sourceId)),
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final sub = items[index];
          return Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              leading: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: (sub.isMovie ? AppColors.primary : AppColors.success).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(sub.isMovie ? Icons.movie_rounded : Icons.tv_rounded, color: sub.isMovie ? AppColors.primary : AppColors.success),
              ),
              title: Text(sub.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${sub.year ?? ""} ${sub.season != null ? "第${sub.season}季" : ""}'),
              trailing: PopupMenuButton<String>(
                onSelected: (action) => _handleAction(action, sub),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'search', child: Row(children: [Icon(Icons.search, size: 20), SizedBox(width: 8), Text('搜索资源')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: AppColors.error, size: 20), SizedBox(width: 8), Text('删除', style: TextStyle(color: AppColors.error))])),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleAction(String action, NtSubscribe sub) {
    final actions = ref.read(nastoolActionsProvider(widget.sourceId));
    switch (action) {
      case 'search':
        actions.searchSubscribe(sub.id, sub.isMovie ? 'MOV' : 'TV');
        break;
      case 'delete':
        actions.deleteSubscribe(sub.id, sub.isMovie ? 'MOV' : 'TV');
        break;
    }
  }
}

// ============================================================
// Downloads Content - Enhanced with tabs and controls
// ============================================================

class _DownloadsContent extends ConsumerStatefulWidget {
  const _DownloadsContent({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  ConsumerState<_DownloadsContent> createState() => _DownloadsContentState();
}

class _DownloadsContentState extends ConsumerState<_DownloadsContent> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloadsAsync = ref.watch(nastoolDownloadsProvider(widget.sourceId));
    final historyAsync = ref.watch(nastoolDownloadHistoryProvider(widget.sourceId));

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [Tab(text: '进行中'), Tab(text: '历史')],
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              downloadsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('加载失败: $e')),
                data: (downloads) => _buildDownloadList(context, downloads),
              ),
              historyAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('加载失败: $e')),
                data: (history) => _buildHistoryList(context, history),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadList(BuildContext context, List<NtDownloadTask> downloads) {
    if (downloads.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_done_rounded, size: 64, color: widget.isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text('暂无下载任务', style: context.textTheme.titleMedium?.copyWith(color: widget.isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(nastoolDownloadsProvider(widget.sourceId)),
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: downloads.length,
        itemBuilder: (context, index) {
          final task = downloads[index];
          return Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textTheme.titleSmall)),
                      Text('${(task.progress * 100).toStringAsFixed(1)}%', style: context.textTheme.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: task.progress, minHeight: 6, backgroundColor: AppColors.lightOutline.withValues(alpha: 0.2)),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      if (task.speed != null) Text('${task.speed}', style: context.textTheme.bodySmall),
                      const Spacer(),
                      IconButton(
                        icon: Icon(task.isCompleted ? Icons.check_circle : Icons.pause, size: 20),
                        onPressed: task.isCompleted ? null : () => ref.read(nastoolActionsProvider(widget.sourceId)).stopDownload(task.id),
                        tooltip: '暂停',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                        onPressed: () => ref.read(nastoolActionsProvider(widget.sourceId)).removeDownload(task.id),
                        tooltip: '删除',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryList(BuildContext context, List<NtDownloadHistory> history) {
    if (history.isEmpty) {
      return Center(child: Text('暂无下载历史', style: context.textTheme.titleMedium?.copyWith(color: widget.isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final item = history[index];
        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ListTile(
            leading: Icon(Icons.check_circle_rounded, color: AppColors.success),
            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(item.date != null ? '${item.date!.year}-${item.date!.month.toString().padLeft(2, '0')}-${item.date!.day.toString().padLeft(2, '0')}' : ''),
          ),
        );
      },
    );
  }
}

// ============================================================
// Search Content - Functional
// ============================================================

class _SearchContent extends ConsumerStatefulWidget {
  const _SearchContent({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  ConsumerState<_SearchContent> createState() => _SearchContentState();
}

class _SearchContentState extends ConsumerState<_SearchContent> {
  final _searchController = TextEditingController();
  List<NtMediaSearchResult> _results = [];
  bool _isSearching = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    setState(() { _isSearching = true; _error = null; });
    try {
      final results = await ref.read(nastoolActionsProvider(widget.sourceId)).searchMediaResources(keyword);
      setState(() { _results = results; _isSearching = false; });
    } on Exception catch (e) {
      setState(() { _error = e.toString(); _isSearching = false; });
    }
  }

  void _showTorrentDetail(NtMediaSearchResult media) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _TorrentDetailSheet(
          media: media,
          sourceId: widget.sourceId,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索资源...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _isSearching
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(icon: const Icon(Icons.send_rounded), onPressed: _search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text('搜索失败: $_error'))
                      : _results.isEmpty
                          ? Center(child: Text('输入关键词搜索资源', style: context.textTheme.bodyMedium?.copyWith(color: widget.isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)))
                          : ListView.builder(
                              itemCount: _results.length,
                              itemBuilder: (context, index) {
                                final r = _results[index];
                                final torrentCount = r.torrents.fold<int>(0, (sum, g) => sum + g.items.length);
                                return Card(
                                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                                  child: ListTile(
                                    leading: r.coverImage != null
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: Image.network(r.coverImage!, width: 48, height: 64, fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Container(width: 48, height: 64, color: AppColors.lightOnSurfaceVariant.withValues(alpha: 0.2), child: const Icon(Icons.movie_rounded))),
                                          )
                                        : null,
                                    title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                                    subtitle: Text('${r.year ?? ""} • ${r.torrents.length}个分组 • $torrentCount个资源'),
                                    trailing: const Icon(Icons.chevron_right_rounded),
                                    onTap: () => _showTorrentDetail(r),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      );
}

/// 种子详情底部弹窗
class _TorrentDetailSheet extends ConsumerWidget {
  const _TorrentDetailSheet({
    required this.media,
    required this.sourceId,
    required this.scrollController,
  });

  final NtMediaSearchResult media;
  final String sourceId;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // 拖动指示器
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                if (media.coverImage != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(media.coverImage!, width: 60, height: 80, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(width: 60, height: 80, color: AppColors.lightOnSurfaceVariant.withValues(alpha: 0.2), child: const Icon(Icons.movie_rounded))),
                  ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(media.title, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (media.year != null) Text(media.year!, style: context.textTheme.bodySmall),
                      Text('${media.torrents.length}个分组', style: context.textTheme.bodySmall?.copyWith(color: AppColors.primary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          // 种子列表
          Expanded(
            child: media.torrents.isEmpty
                ? const Center(child: Text('暂无可用资源'))
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: media.torrents.length,
                    itemBuilder: (context, groupIndex) {
                      final group = media.torrents[groupIndex];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 分组标题
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                                  child: Text(group.displayTitle, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                Text('${group.items.length}个资源', style: context.textTheme.bodySmall),
                              ],
                            ),
                          ),
                          // 种子项
                          ...group.items.map((torrent) => Card(
                            margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: ListTile(
                              dense: true,
                              title: Text(torrent.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.textTheme.bodySmall),
                              subtitle: Row(
                                children: [
                                  Text(torrent.displaySite, style: context.textTheme.labelSmall?.copyWith(color: AppColors.primary)),
                                  const SizedBox(width: 8),
                                  Text(torrent.formattedSize, style: context.textTheme.labelSmall),
                                  if (torrent.seeders != null) ...[
                                    const SizedBox(width: 8),
                                    Icon(Icons.arrow_upward_rounded, size: 12, color: AppColors.success),
                                    Text('${torrent.seeders}', style: context.textTheme.labelSmall),
                                  ],
                                  if (torrent.isFree) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(2)),
                                      child: const Text('免费', style: TextStyle(color: Colors.white, fontSize: 10)),
                                    ),
                                  ],
                                  if (torrent.is2xUpload) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(2)),
                                      child: const Text('2x', style: TextStyle(color: Colors.white, fontSize: 10)),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.download_rounded, color: AppColors.primary),
                                onPressed: torrent.enclosure != null ? () async {
                                  await ref.read(nastoolActionsProvider(sourceId)).downloadResource(enclosure: torrent.enclosure!, title: torrent.title);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加下载任务')));
                                  }
                                } : null,
                              ),
                            ),
                          )),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Media Content - Recommendations
// ============================================================

class _MediaContent extends ConsumerStatefulWidget {
  const _MediaContent({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  ConsumerState<_MediaContent> createState() => _MediaContentState();
}

class _MediaContentState extends ConsumerState<_MediaContent> {
  final _searchController = TextEditingController();
  List<NtMediaDetail> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchMedia() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;
    setState(() => _isSearching = true);
    try {
      final adapter = ref.read(nastoolConnectionProvider(widget.sourceId))?.adapter;
      if (adapter != null) {
        final results = await adapter.searchMedia(keyword);
        setState(() { _searchResults = results; _isSearching = false; });
      }
    } on Exception {
      setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索电影/剧集 (TMDB/豆瓣)...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(icon: const Icon(Icons.send_rounded), onPressed: _searchMedia),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (_) => _searchMedia(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : _searchResults.isEmpty
                      ? Center(child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.movie_filter_rounded, size: 64, color: widget.isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                            const SizedBox(height: AppSpacing.md),
                            Text('搜索电影或剧集添加到订阅', style: context.textTheme.bodyMedium?.copyWith(color: widget.isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)),
                          ],
                        ))
                      : GridView.builder(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, childAspectRatio: 0.7, crossAxisSpacing: 12, mainAxisSpacing: 12),
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final m = _searchResults[index];
                            return Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _showMediaActions(context, m),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: m.posterPath != null
                                          ? Image.network('https://image.tmdb.org/t/p/w500${m.posterPath}', fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: AppColors.primary.withValues(alpha: 0.1), child: const Icon(Icons.movie_rounded, size: 48)))
                                          : Container(color: AppColors.primary.withValues(alpha: 0.1), child: const Icon(Icons.movie_rounded, size: 48)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(m.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                                          Text('${m.year ?? ""} • ${m.type == 'movie' ? '电影' : '剧集'}', style: context.textTheme.bodySmall?.copyWith(fontSize: 10)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      );

  void _showMediaActions(BuildContext context, NtMediaDetail media) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(media.title ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
            ListTile(
              leading: const Icon(Icons.bookmark_add_rounded),
              title: const Text('添加订阅'),
              onTap: () {
                Navigator.pop(context);
                ref.read(nastoolActionsProvider(widget.sourceId)).addSubscribe(
                  name: media.title,
                  type: media.type == 'movie' ? 'MOV' : 'TV',
                  year: media.year?.toString(),
                  mediaId: media.tmdbId?.toString(),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.search_rounded),
              title: const Text('搜索资源'),
              onTap: () {
                Navigator.pop(context);
                _searchController.text = media.title ?? '';
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Sites Content - Enhanced with statistics
// ============================================================

class _SitesContent extends ConsumerWidget {
  const _SitesContent({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sitesAsync = ref.watch(nastoolSitesProvider(sourceId));
    final statsAsync = ref.watch(nastoolSiteStatisticsProvider(sourceId));

    return sitesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (sites) {
        if (sites.isEmpty) {
          return Center(child: Text('暂无站点', style: context.textTheme.titleMedium?.copyWith(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)));
        }

        final statsMap = <String, NtSiteStatistics>{};
        statsAsync.whenData((stats) {
          for (final s in stats) {
            statsMap[s.siteName] = s;
          }
        });

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(nastoolSitesProvider(sourceId));
            ref.invalidate(nastoolSiteStatisticsProvider(sourceId));
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: sites.length,
            itemBuilder: (context, index) {
              final site = sites[index];
              final stats = statsMap[site.name];
              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ListTile(
                  leading: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.language_rounded, color: AppColors.primary),
                  ),
                  title: Text(site.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: stats != null
                      ? Text('↑ ${_formatBytes(stats.upload ?? 0)} ↓ ${_formatBytes(stats.download ?? 0)}', style: context.textTheme.bodySmall)
                      : Text(site.signUrl ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.speed_rounded),
                    onPressed: () async {
                      // 显示测试中状态
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('正在测试连接...'), duration: Duration(seconds: 1)),
                      );
                      final success = await ref.read(nastoolActionsProvider(sourceId)).testSite(site.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success ? '连接成功' : '连接失败'),
                            backgroundColor: success ? AppColors.success : AppColors.error,
                          ),
                        );
                      }
                    },
                    tooltip: '测试连接',
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    if (bytes < 1024 * 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    return '${(bytes / 1024 / 1024 / 1024 / 1024).toStringAsFixed(2)} TB';
  }
}

// ============================================================
// Advanced Content - RSS, BrushTask, Plugins
// ============================================================

class _AdvancedContent extends ConsumerStatefulWidget {
  const _AdvancedContent({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  ConsumerState<_AdvancedContent> createState() => _AdvancedContentState();
}

class _AdvancedContentState extends ConsumerState<_AdvancedContent> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [Tab(text: 'RSS订阅'), Tab(text: '刷流任务'), Tab(text: '插件')],
            labelColor: AppColors.primary,
            indicatorColor: AppColors.primary,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRssTab(context),
                _buildBrushTaskTab(context),
                _buildPluginsTab(context),
              ],
            ),
          ),
        ],
      );

  Widget _buildRssTab(BuildContext context) {
    final rssAsync = ref.watch(nastoolRssTasksProvider(widget.sourceId));
    return rssAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (tasks) => tasks.isEmpty
          ? Center(child: Text('暂无RSS任务', style: context.textTheme.bodyMedium?.copyWith(color: widget.isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)))
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final t = tasks[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ListTile(
                    leading: Icon(Icons.rss_feed_rounded, color: t.state == 'Y' ? AppColors.success : AppColors.lightOnSurfaceVariant),
                    title: Text(t.name),
                    subtitle: Text('间隔: ${t.interval}分钟'),
                    trailing: IconButton(
                      icon: const Icon(Icons.preview_rounded),
                      onPressed: () async {
                        final articles = await ref.read(nastoolActionsProvider(widget.sourceId)).previewRssTask(t.id);
                        if (context.mounted) {
                          showDialog<void>(context: context, builder: (_) => AlertDialog(
                            title: Text('RSS预览: ${t.name}'),
                            content: SizedBox(
                              width: double.maxFinite,
                              height: 300,
                              child: ListView(children: articles.map((a) => ListTile(title: Text(a.title ?? '', maxLines: 2))).toList()),
                            ),
                            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
                          ));
                        }
                      },
                      tooltip: '预览',
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildBrushTaskTab(BuildContext context) {
    final brushAsync = ref.watch(nastoolBrushTasksProvider(widget.sourceId));
    return brushAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (tasks) => tasks.isEmpty
          ? Center(child: Text('暂无刷流任务', style: context.textTheme.bodyMedium?.copyWith(color: widget.isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)))
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final t = tasks[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ListTile(
                    leading: Icon(Icons.speed_rounded, color: t.state == 'Y' ? AppColors.success : AppColors.lightOnSurfaceVariant),
                    title: Text(t.name),
                    subtitle: Text('保种: ${t.totalSize ?? 0}GB • 间隔: ${t.interval}分钟'),
                    trailing: IconButton(icon: Icon(Icons.play_circle_rounded, color: AppColors.primary), onPressed: () => ref.read(nastoolActionsProvider(widget.sourceId)).runBrushTask(int.tryParse(t.id) ?? 0), tooltip: '运行'),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildPluginsTab(BuildContext context) {
    final pluginsAsync = ref.watch(nastoolPluginsProvider(widget.sourceId));
    return pluginsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (plugins) => plugins.isEmpty
          ? Center(child: Text('暂无已安装插件', style: context.textTheme.bodyMedium?.copyWith(color: widget.isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)))
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: plugins.length,
              itemBuilder: (context, index) {
                final p = plugins[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ListTile(
                    leading: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.extension_rounded, color: Colors.purple),
                    ),
                    title: Text(p.name),
                    subtitle: Text(p.version ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.error),
                      onPressed: () => ref.read(nastoolActionsProvider(widget.sourceId)).uninstallPlugin(p.id),
                      tooltip: '卸载',
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ============================================================
// Settings Content - Enhanced
// ============================================================

class _SettingsContent extends ConsumerWidget {
  const _SettingsContent({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systemAsync = ref.watch(nastoolSystemInfoProvider(sourceId));
    final syncDirsAsync = ref.watch(nastoolSyncDirsProvider(sourceId));
    final actions = ref.read(nastoolActionsProvider(sourceId));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // System Info
        systemAsync.when(
          data: (sys) => Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('系统信息', style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.md),
                  _buildInfoRow(context, '版本', sys.version ?? '未知'),
                  if (sys.latestVersion != null) _buildInfoRow(context, '最新版本', sys.latestVersion!),
                  if (sys.totalSpace != null) _buildInfoRow(context, '总空间', _formatBytes(sys.totalSpace!)),
                  if (sys.freeSpace != null) _buildInfoRow(context, '可用空间', _formatBytes(sys.freeSpace!)),
                ],
              ),
            ),
          ),
          loading: () => const Card(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Center(child: CircularProgressIndicator()))),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: AppSpacing.md),

        // Sync Directories
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text('同步目录', style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
              syncDirsAsync.when(
                data: (dirs) => dirs.isEmpty
                    ? const Padding(padding: EdgeInsets.all(AppSpacing.md), child: Text('暂无同步目录'))
                    : Column(
                        children: dirs.map((d) => ListTile(
                          leading: Icon(Icons.folder_rounded, color: d.isEnabled ? AppColors.success : AppColors.lightOnSurfaceVariant),
                          title: Text(d.name ?? d.from ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${d.from ?? ''} → ${d.to ?? "媒体库"}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.sync_rounded),
                            onPressed: d.id != null ? () async {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('正在同步...'), duration: Duration(seconds: 1)),
                              );
                              try {
                                await actions.runSyncDir(d.id!);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('同步已启动'), backgroundColor: AppColors.success),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('同步失败: $e'), backgroundColor: AppColors.error),
                                  );
                                }
                              }
                            } : null,
                            tooltip: '同步',
                          ),
                        )).toList(),
                      ),
                loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.md), child: Center(child: CircularProgressIndicator())),
                error: (_, __) => const Padding(padding: EdgeInsets.all(AppSpacing.md), child: Text('加载失败')),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Actions
        Card(
          child: Column(
            children: [
              ListTile(leading: const Icon(Icons.refresh_rounded), title: const Text('刷新媒体库'), subtitle: const Text('同步媒体库数据'), onTap: actions.refreshLibrary),
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.update_rounded), title: const Text('检查更新'), subtitle: const Text('检查 NASTool 更新'), onTap: () async {
                final hasUpdate = await actions.checkUpdate();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hasUpdate ? '发现新版本' : '已是最新版本')));
                }
              }),
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.restart_alt_rounded, color: AppColors.warning), title: const Text('重启服务'), onTap: () => _showConfirmDialog(context, '确定要重启 NASTool 服务吗?', actions.restartService)),
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.logout_rounded, color: AppColors.error), title: const Text('退出登录'), onTap: () => Navigator.pop(context)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: context.textTheme.bodyMedium?.copyWith(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)),
            Text(value, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
          ],
        ),
      );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    if (bytes < 1024 * 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    return '${(bytes / 1024 / 1024 / 1024 / 1024).toStringAsFixed(2)} TB';
  }

  void _showConfirmDialog(BuildContext context, String message, VoidCallback onConfirm) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () { Navigator.pop(context); onConfirm(); }, child: const Text('确定')),
        ],
      ),
    );
  }
}
