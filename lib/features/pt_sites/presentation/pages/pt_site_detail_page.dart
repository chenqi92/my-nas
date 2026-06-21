import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/pt_sites/data/services/pt_site_api.dart';
import 'package:my_nas/features/pt_sites/domain/entities/pt_torrent.dart';
import 'package:my_nas/features/pt_sites/presentation/providers/pt_site_provider.dart';
import 'package:my_nas/features/pt_sites/presentation/widgets/pt_torrent_card.dart';
import 'package:my_nas/features/pt_sites/presentation/widgets/send_to_downloader_sheet.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// PT 站点详情页
class PTSiteDetailPage extends ConsumerStatefulWidget {
  const PTSiteDetailPage({
    required this.source,
    this.initialQuery,
    super.key,
  });

  final SourceEntity source;

  /// 进入页面时自动填充并触发搜索的关键词
  ///
  /// 用于从视频详情/相似推荐等位置带着电影/剧集名称跳转到此页面，
  /// 避免用户再手动输入。
  final String? initialQuery;

  @override
  ConsumerState<PTSiteDetailPage> createState() => _PTSiteDetailPageState();
}

class _PTSiteDetailPageState extends ConsumerState<PTSiteDetailPage>
    with ConsumerTabBarVisibilityMixin {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  bool _isSearching = false;
  bool _hasConnected = false;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _scrollController.addListener(_onScroll);

    // 如果有预填关键词，立刻进入搜索模式并填入，避免用户再手动输入
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _isSearching = true;
      _searchController.text = widget.initialQuery!.trim();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connect();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(ptTorrentListProvider(widget.source.id).notifier).loadMore();
    }
  }

  Future<void> _connect() async {
    if (_hasConnected) return;
    _hasConnected = true;

    await ref
        .read(ptSiteConnectionProvider(widget.source.id).notifier)
        .connect(widget.source);

    // 等待状态同步（Riverpod 状态更新可能在下一个事件循环）
    await Future<void>.delayed(Duration.zero);

    if (!mounted) return;

    final connection = ref.read(ptSiteConnectionProvider(widget.source.id));
    if (connection.status == PTSiteConnectionStatus.connected) {
      // 有预填关键词时直接按它搜索，否则走默认列表
      final initial = widget.initialQuery?.trim();
      if (initial != null && initial.isNotEmpty) {
        ref
            .read(ptTorrentListProvider(widget.source.id).notifier)
            .setKeyword(initial);
      }
      await ref
          .read(ptTorrentListProvider(widget.source.id).notifier)
          .loadTorrents(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(ptSiteConnectionProvider(widget.source.id));
    final torrentListState = ref.watch(ptTorrentListProvider(widget.source.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.l10n.ptSiteDetailSearchHint,
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                  ),
                ),
                style: TextStyle(
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
                onSubmitted: (value) {
                  ref
                      .read(ptTorrentListProvider(widget.source.id).notifier)
                      .setKeyword(value.isEmpty ? null : value);
                  ref
                      .read(ptTorrentListProvider(widget.source.id).notifier)
                      .loadTorrents(refresh: true);
                },
              )
            : Text(widget.source.name.isEmpty
                ? widget.source.type.displayName
                : widget.source.name),
        actions: [
          // 搜索按钮
          IconButton(
            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  ref
                      .read(ptTorrentListProvider(widget.source.id).notifier)
                      .setKeyword(null);
                  ref
                      .read(ptTorrentListProvider(widget.source.id).notifier)
                      .loadTorrents(refresh: true);
                }
              });
            },
          ),
          // 筛选按钮
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => _showFilterSheet(context),
          ),
          // 排序按钮
          IconButton(
            icon: const Icon(Icons.swap_vert),
            onPressed: () => _showSortSheet(context),
          ),
          // 更多菜单
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  ref
                      .read(ptTorrentListProvider(widget.source.id).notifier)
                      .loadTorrents(refresh: true);
                case 'user_info':
                  _showUserInfoSheet(context, connection.userInfo);
                case 'stats':
                  _showStatsSheet(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh_rounded),
                    SizedBox(width: 12),
                    Text(context.l10n.ptSiteDetailRefresh),
                  ],
                ),
              ),
              if (connection.userInfo != null)
                PopupMenuItem(
                  value: 'user_info',
                  child: Row(
                    children: [
                      Icon(Icons.person_rounded),
                      SizedBox(width: 12),
                      Text(context.l10n.ptSiteDetailUserInfo),
                    ],
                  ),
                ),
              if (connection.status == PTSiteConnectionStatus.connected)
                PopupMenuItem(
                  value: 'stats',
                  child: Row(
                    children: [
                      Icon(Icons.cloud_sync),
                      SizedBox(width: 12),
                      Text(context.l10n.ptSiteDetailTransferList),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _buildBody(connection, torrentListState, isDark),
    );
  }

  Widget _buildBody(
    PTSiteConnection connection,
    PTTorrentListState torrentListState,
    bool isDark,
  ) {
    // 连接中
    if (connection.status == PTSiteConnectionStatus.connecting) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(context.l10n.ptSiteDetailConnecting),
          ],
        ),
      );
    }

    // 连接错误
    if (connection.status == PTSiteConnectionStatus.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: isDark ? AppColors.errorLight : AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.ptSiteDetailConnectFailed,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                connection.errorMessage ?? context.l10n.ptSiteDetailUnknownError,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                _hasConnected = false;
                _connect();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.l10n.ptSiteDetailRetry),
            ),
          ],
        ),
      );
    }

    // 加载中
    if (torrentListState.isLoading && torrentListState.torrents.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // 加载错误
    if (torrentListState.error != null && torrentListState.torrents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 16),
            Text(torrentListState.error!),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref
                  .read(ptTorrentListProvider(widget.source.id).notifier)
                  .loadTorrents(refresh: true),
              child: Text(context.l10n.ptSiteDetailRetry),
            ),
          ],
        ),
      );
    }

    // 空列表
    if (torrentListState.torrents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: isDark
                  ? AppColors.darkOnSurfaceVariant
                  : AppColors.lightOnSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              torrentListState.keyword != null ? context.l10n.ptSiteDetailNoMatchTorrent : context.l10n.ptSiteDetailNoTorrent,
              style: TextStyle(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // 种子列表
    return RefreshIndicator(
      onRefresh: () => ref
          .read(ptTorrentListProvider(widget.source.id).notifier)
          .loadTorrents(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: torrentListState.torrents.length +
            (torrentListState.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == torrentListState.torrents.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final torrent = torrentListState.torrents[index];
          return PTTorrentCard(
            torrent: torrent,
            onTap: () => _showTorrentDetail(context, torrent),
            onDownload: () => _showDownloadOptions(context, torrent),
          );
        },
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    final categories = ref.read(ptCategoriesProvider(widget.source.id));
    final currentState = ref.read(ptTorrentListProvider(widget.source.id));

    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: GestureDetector(
          onTap: () {}, // 阻止内部点击事件冒泡
          child: DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.8,
            expand: false,
            builder: (context, scrollController) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return DecoratedBox(
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.tune_rounded,
                              color: AppColors.primary,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            context.l10n.ptSiteDetailFilterCategory,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // 分类列表
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        children: [
                          ListTile(
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: currentState.category == null
                                    ? AppColors.primary.withValues(alpha: 0.12)
                                    : (isDark ? Colors.white10 : Colors.grey[100]),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.all_inclusive,
                                color: currentState.category == null
                                    ? AppColors.primary
                                    : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                                size: 18,
                              ),
                            ),
                            title: Text(
                              context.l10n.ptSiteDetailAllCategories,
                              style: TextStyle(
                                fontWeight: currentState.category == null ? FontWeight.w600 : null,
                                color: currentState.category == null ? AppColors.primary : null,
                              ),
                            ),
                            trailing: currentState.category == null
                                ? Icon(Icons.check_rounded, color: AppColors.primary, size: 20)
                                : null,
                            onTap: () {
                              ref
                                  .read(ptTorrentListProvider(widget.source.id).notifier)
                                  .setCategory(null);
                              ref
                                  .read(ptTorrentListProvider(widget.source.id).notifier)
                                  .loadTorrents(refresh: true);
                              Navigator.pop(context);
                            },
                          ),
                          categories.when(
                            data: (cats) => Column(
                              children: cats.map((cat) {
                                final isSelected = currentState.category == cat.id;
                                return ListTile(
                                  leading: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.primary.withValues(alpha: 0.12)
                                          : (isDark ? Colors.white10 : Colors.grey[100]),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.folder_rounded,
                                      color: isSelected
                                          ? AppColors.primary
                                          : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(
                                    cat.name,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.w600 : null,
                                      color: isSelected ? AppColors.primary : null,
                                    ),
                                  ),
                                  trailing: isSelected
                                      ? Icon(Icons.check_rounded, color: AppColors.primary, size: 20)
                                      : null,
                                  onTap: () {
                                    ref
                                        .read(ptTorrentListProvider(widget.source.id).notifier)
                                        .setCategory(cat.id);
                                    ref
                                        .read(ptTorrentListProvider(widget.source.id).notifier)
                                        .loadTorrents(refresh: true);
                                    Navigator.pop(context);
                                  },
                                );
                              }).toList(),
                            ),
                            loading: () => const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                            error: (_, _) => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    final currentState = ref.read(ptTorrentListProvider(widget.source.id));

    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: GestureDetector(
          onTap: () {}, // 阻止内部点击事件冒泡
          child: DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.8,
            expand: false,
            builder: (context, scrollController) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return DecoratedBox(
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.swap_vert,
                              color: AppColors.primary,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            context.l10n.ptSiteDetailSortMethod,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          // 升序/降序切换
                          TextButton.icon(
                            onPressed: () {
                              ref
                                  .read(ptTorrentListProvider(widget.source.id).notifier)
                                  .toggleSortDirection();
                              ref
                                  .read(ptTorrentListProvider(widget.source.id).notifier)
                                  .loadTorrents(refresh: true);
                              Navigator.pop(context);
                            },
                            icon: Icon(
                              currentState.descending
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                              size: 18,
                            ),
                            label: Text(currentState.descending ? context.l10n.ptSiteDetailDescending : context.l10n.ptSiteDetailAscending),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // 排序选项列表
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        children: [
                          (PTTorrentSortBy.uploadTime, context.l10n.ptSiteDetailSortUploadTime, Icons.access_time),
                          (PTTorrentSortBy.size, context.l10n.ptSiteDetailSortSize, Icons.storage),
                          (PTTorrentSortBy.seeders, context.l10n.ptSiteDetailSortSeeders, Icons.upload_rounded),
                          (PTTorrentSortBy.leechers, context.l10n.ptSiteDetailSortLeechers, Icons.download_rounded),
                          (PTTorrentSortBy.snatched, context.l10n.ptSiteDetailSortSnatched, Icons.check_circle),
                        ].map((item) {
                          final isSelected = currentState.sortBy == item.$1;
                          return ListTile(
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.12)
                                    : (isDark ? Colors.white10 : Colors.grey[100]),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                item.$3,
                                color: isSelected
                                    ? AppColors.primary
                                    : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                                size: 18,
                              ),
                            ),
                            title: Text(
                              item.$2,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.w600 : null,
                                color: isSelected ? AppColors.primary : null,
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(Icons.check_rounded, color: AppColors.primary, size: 20)
                                : null,
                            onTap: () {
                              ref
                                  .read(ptTorrentListProvider(widget.source.id).notifier)
                                  .setSortBy(item.$1);
                              ref
                                  .read(ptTorrentListProvider(widget.source.id).notifier)
                                  .loadTorrents(refresh: true);
                              Navigator.pop(context);
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showUserInfoSheet(BuildContext context, PTUserInfo? userInfo) {
    if (userInfo == null) return;

    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: GestureDetector(
          onTap: () {}, // 阻止内部点击事件冒泡
          child: DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return DecoratedBox(
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.person_rounded,
                              color: AppColors.primary,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            context.l10n.ptSiteDetailUserInfo,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
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
                          // 用户头像和名称
                          Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: Text(
                                    userInfo.username.isNotEmpty
                                        ? userInfo.username[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      userInfo.username,
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (userInfo.userClass != null)
                                      Container(
                                        margin: const EdgeInsets.only(top: 4),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          userInfo.userClass!,
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w500,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // 分享数据统计
                          _buildSectionHeader(context, context.l10n.ptSiteDetailDataOverview, isDark),
                          const SizedBox(height: 8),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                _buildUserInfoTile(
                                  context,
                                  icon: Icons.upload_rounded,
                                  iconColor: AppColors.success,
                                  label: context.l10n.ptSiteDetailUploadAmount,
                                  value: userInfo.formattedUploaded,
                                  isDark: isDark,
                                ),
                                Divider(height: 1, indent: 56, color: isDark ? Colors.white10 : Colors.grey[200]),
                                _buildUserInfoTile(
                                  context,
                                  icon: Icons.download_rounded,
                                  iconColor: AppColors.primary,
                                  label: context.l10n.ptSiteDetailDownloadAmount,
                                  value: userInfo.formattedDownloaded,
                                  isDark: isDark,
                                ),
                                Divider(height: 1, indent: 56, color: isDark ? Colors.white10 : Colors.grey[200]),
                                _buildUserInfoTile(
                                  context,
                                  icon: Icons.swap_horiz,
                                  iconColor: AppColors.warning,
                                  label: context.l10n.ptSiteDetailShareRatio,
                                  value: userInfo.formattedRatio,
                                  isDark: isDark,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 活动数据
                          _buildSectionHeader(context, context.l10n.ptSiteDetailActivityData, isDark),
                          const SizedBox(height: 8),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                _buildUserInfoTile(
                                  context,
                                  icon: Icons.auto_awesome,
                                  iconColor: Colors.purple,
                                  label: context.l10n.ptSiteDetailBonus,
                                  value: userInfo.formattedBonus,
                                  isDark: isDark,
                                ),
                                Divider(height: 1, indent: 56, color: isDark ? Colors.white10 : Colors.grey[200]),
                                _buildUserInfoTile(
                                  context,
                                  icon: Icons.cloud_upload,
                                  iconColor: AppColors.success,
                                  label: context.l10n.ptSiteDetailSeedingCount,
                                  value: userInfo.seedingCount.toString(),
                                  isDark: isDark,
                                ),
                                Divider(height: 1, indent: 56, color: isDark ? Colors.white10 : Colors.grey[200]),
                                _buildUserInfoTile(
                                  context,
                                  icon: Icons.cloud_download,
                                  iconColor: AppColors.primary,
                                  label: context.l10n.ptSiteDetailLeechingCount,
                                  value: userInfo.leechingCount.toString(),
                                  isDark: isDark,
                                ),
                                if (userInfo.invites > 0) ...[
                                  Divider(height: 1, indent: 56, color: isDark ? Colors.white10 : Colors.grey[200]),
                                  _buildUserInfoTile(
                                    context,
                                    icon: Icons.card_giftcard,
                                    iconColor: Colors.teal,
                                    label: context.l10n.ptSiteDetailInviteCount,
                                    value: userInfo.invites.toString(),
                                    isDark: isDark,
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // 账户信息（如果有日期数据）
                          if (userInfo.joinTime != null || userInfo.lastAccess != null) ...[
                            const SizedBox(height: 16),
                            _buildSectionHeader(context, context.l10n.ptSiteDetailAccountInfo, isDark),
                            const SizedBox(height: 8),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white10 : Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  if (userInfo.joinTime != null)
                                    _buildUserInfoTile(
                                      context,
                                      icon: Icons.calendar_today,
                                      iconColor: Colors.blue,
                                      label: context.l10n.ptSiteDetailJoinTime,
                                      value: userInfo.formattedJoinTime ?? '-',
                                      isDark: isDark,
                                    ),
                                  if (userInfo.joinTime != null && userInfo.lastAccess != null)
                                    Divider(height: 1, indent: 56, color: isDark ? Colors.white10 : Colors.grey[200]),
                                  if (userInfo.lastAccess != null)
                                    _buildUserInfoTile(
                                      context,
                                      icon: Icons.access_time,
                                      iconColor: Colors.grey,
                                      label: context.l10n.ptSiteDetailLastAccess,
                                      value: userInfo.formattedLastAccess ?? '-',
                                      isDark: isDark,
                                    ),
                                ],
                              ),
                            ),
                          ],

                          // 底部留白
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, bool isDark) => Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
        ),
      ),
    );


  Widget _buildUserInfoTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required bool isDark,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
          ],
        ),
      );



  void _showTorrentDetail(BuildContext context, PTTorrent torrent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SafeArea(
          child: Column(
            children: [
              // 拖动指示器
              const SheetDragHandle(topPadding: 12, bottomPadding: 12),
              // 内容
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 种子名称
                      Text(
                        torrent.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 促销标签
                      if (torrent.status.hasPromotion) ...[
                        Wrap(
                          spacing: 8,
                          children: [
                            _buildPromotionChip(torrent.status),
                            if (torrent.status.formattedRemainingTime != null)
                              Chip(
                                label: Text(
                                  context.l10n.ptSiteDetailRemaining(torrent.status.formattedRemainingTime!),
                                ),
                                backgroundColor: AppColors.warning.withValues(alpha: 0.2),
                                labelStyle: TextStyle(
                                  color: AppColors.warning,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 基本信息
                      _buildDetailRow(context, Icons.storage, context.l10n.ptSiteDetailSortSize, torrent.formattedSize),
                      _buildDetailRow(context, Icons.upload_rounded, context.l10n.ptSiteDetailStatSeeding, '${torrent.seeders}'),
                      _buildDetailRow(context, Icons.download_rounded, context.l10n.ptSiteDetailStatDownloading, '${torrent.leechers}'),
                      _buildDetailRow(
                          context, Icons.check_circle, context.l10n.ptSiteDetailStatCompleted, '${torrent.snatched}'),
                      _buildDetailRow(
                        context,
                        Icons.access_time,
                        context.l10n.ptSiteDetailSortUploadTime,
                        _formatDateTime(context, torrent.uploadTime),
                      ),

                      if (torrent.category != null)
                        _buildDetailRow(context, Icons.folder_rounded, context.l10n.ptSiteDetailCategory, torrent.category!),

                      if (torrent.subCategory != null &&
                          torrent.subCategory!.isNotEmpty)
                        _buildDetailRow(
                            context, Icons.folder_open_rounded, context.l10n.ptSiteDetailSubCategory, torrent.subCategory!),

                      // IMDB / 豆瓣 信息
                      if (torrent.imdbId != null &&
                          torrent.imdbId!.isNotEmpty)
                        _buildDetailRow(
                            context, Icons.movie, context.l10n.ptSiteDetailImdb, torrent.imdbId!),

                      if (torrent.doubanId != null &&
                          torrent.doubanId!.isNotEmpty)
                        _buildDetailRow(
                            context, Icons.star_rounded, context.l10n.ptSiteDetailDouban, torrent.doubanId!),

                      // 种子 ID
                      _buildDetailRow(context, Icons.tag, context.l10n.ptSiteDetailTorrentId, torrent.id),

                      if (torrent.smallDescr != null &&
                          torrent.smallDescr!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          context.l10n.ptSiteDetailIntroduction,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.darkOnSurface
                                : AppColors.lightOnSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          torrent.smallDescr!,
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ],

                      // 标签
                      if (torrent.labels.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: torrent.labels
                              .map((label) => Chip(
                                    label: Text(
                                      label,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                  ))
                              .toList(),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // 操作按钮
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _copyDownloadUrl(torrent),
                              icon: const Icon(Icons.copy_rounded),
                              label: Text(context.l10n.ptSiteDetailCopyLink),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _showDownloadOptions(context, torrent);
                              },
                              icon: const Icon(Icons.download_rounded),
                              label: Text(context.l10n.ptSiteDetailDownload),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromotionChip(PTTorrentStatus status) {
    final label = status.promotionLabel;
    if (label == null) return const SizedBox.shrink();

    final color = status.isFree || status.isDoubleFree
        ? AppColors.success
        : status.isDoubleUp
            ? AppColors.primary
            : AppColors.warning;

    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: color,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );

  String _formatDateTime(BuildContext context, DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 60) {
      return context.l10n.ptSiteDetailTimeFormatMinutesAgo(diff.inMinutes);
    } else if (diff.inHours < 24) {
      return context.l10n.ptSiteDetailTimeFormatHoursAgo(diff.inHours);
    } else if (diff.inDays < 30) {
      return context.l10n.ptSiteDetailTimeFormatDaysAgo(diff.inDays);
    } else {
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _copyDownloadUrl(PTTorrent torrent) async {
    try {
      final api = ref.read(ptSiteConnectionProvider(widget.source.id)).api;
      if (api == null) return;

      final url = await api.getDownloadUrl(torrent.id);
      await Clipboard.setData(ClipboardData(text: url));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.ptSiteDetailCopyUrlSuccess),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.ptSiteDetailCopyUrlFailed(e)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showDownloadOptions(BuildContext context, PTTorrent torrent) {
    showAdaptiveModalSheet<void>(
      context: context,
      builder: (context) => SendToDownloaderSheet(
        torrent: torrent,
        sourceId: widget.source.id,
      ),
    );
  }

  void _showStatsSheet(BuildContext context) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TransferStatsSheet(sourceId: widget.source.id),
    );
  }
}

/// 传输统计弹框组件
class _TransferStatsSheet extends ConsumerStatefulWidget {
  const _TransferStatsSheet({required this.sourceId});

  final String sourceId;

  @override
  ConsumerState<_TransferStatsSheet> createState() => _TransferStatsSheetState();
}

class _TransferStatsSheetState extends ConsumerState<_TransferStatsSheet> {
  PTTransferLogType _selectedType = PTTransferLogType.all;
  PTTransferStats? _stats;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(ptSiteConnectionProvider(widget.sourceId)).api;
      if (api == null) {
        setState(() {
          _error = context.l10n.ptSiteDetailNotConnected;
          _isLoading = false;
        });
        return;
      }

      final stats = await api.getTransferStats(type: _selectedType);
      if (!mounted) return;

      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        onTap: () {},
        child: DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
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
                // 标题栏
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.cloud_sync,
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        context.l10n.ptSiteDetailTransferList,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                // 类型选择
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: PTTransferLogType.values.map((type) {
                      final isSelected = _selectedType == type;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(type.label),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() => _selectedType = type);
                            _loadStats();
                          },
                          selectedColor: AppColors.primary.withValues(alpha: 0.2),
                          checkmarkColor: AppColors.primary,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                // 内容
                Expanded(
                  child: _buildContent(isDark, scrollController),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark, ScrollController scrollController) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: isDark ? AppColors.errorLight : AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(_error!),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadStats,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.l10n.ptSiteDetailRetry),
            ),
          ],
        ),
      );
    }

    final stats = _stats;
    if (stats == null) {
      return Center(child: Text(context.l10n.ptSiteDetailEmptyData));
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        // 数据总览（固定显示）
        _buildOverviewSection(stats, isDark),
        const SizedBox(height: 16),
        // 种子列表（根据类型切换）
        _buildLogsSection(stats, isDark),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildOverviewSection(PTTransferStats stats, bool isDark) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.primary.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.ptSiteDetailTransferOverview,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // 第一行：上传、下载、分享率
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.upload_rounded,
                    iconColor: AppColors.success,
                    label: context.l10n.ptSiteDetailTransferTotalUpload,
                    value: stats.formattedTotalUploaded,
                    isDark: isDark,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.download_rounded,
                    iconColor: AppColors.primary,
                    label: context.l10n.ptSiteDetailTransferTotalDownload,
                    value: stats.formattedTotalDownloaded,
                    isDark: isDark,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.swap_horiz,
                    iconColor: AppColors.warning,
                    label: context.l10n.ptSiteDetailShareRatio,
                    value: stats.formattedTotalRatio,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 第二行：做种数、下载数
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.cloud_upload,
                    iconColor: Colors.teal,
                    label: context.l10n.ptSiteDetailTransferSeeding,
                    value: '${stats.seedingCount}',
                    isDark: isDark,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.cloud_download,
                    iconColor: Colors.blue,
                    label: context.l10n.ptSiteDetailTransferLeeching,
                    value: '${stats.leechingCount}',
                    isDark: isDark,
                  ),
                ),
                const Expanded(child: SizedBox()), // 占位
              ],
            ),
          ],
        ),
      ),
    );

  Widget _buildLogsSection(PTTransferStats stats, bool isDark) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.ptSiteDetailTransferLogsList(_selectedType.label),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (stats.logs.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 48,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.ptSiteDetailNoData(_selectedType.label),
                  style: TextStyle(
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          )
        else
          ...stats.logs.map((log) => _buildLogItem(log, isDark)),
      ],
    );

  Widget _buildLogItem(PTTransferLog log, bool isDark) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            log.torrentName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMiniStat('↑', log.formattedUploaded, AppColors.success),
              const SizedBox(width: 16),
              _buildMiniStat('↓', log.formattedDownloaded, AppColors.primary),
              const SizedBox(width: 16),
              _buildMiniStat('R', log.formattedRatio, AppColors.warning),
              const SizedBox(width: 16),
              _buildMiniStat('T', log.formattedSeedTime, Colors.purple),
            ],
          ),
        ],
      ),
    );

  Widget _buildMiniStat(String prefix, String value, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          prefix,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );

  Widget _buildStatItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required bool isDark,
  }) =>
      Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ],
      );
}
