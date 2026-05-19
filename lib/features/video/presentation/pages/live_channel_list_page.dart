import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_app_bar.dart';
import 'package:my_nas/features/video/domain/entities/live_stream_models.dart';
import 'package:my_nas/features/video/presentation/pages/live_player_page.dart';
import 'package:my_nas/features/video/presentation/pages/live_stream_settings_page.dart';
import 'package:my_nas/features/video/presentation/providers/live_stream_provider.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 直播频道列表页面
class LiveChannelListPage extends ConsumerStatefulWidget {
  const LiveChannelListPage({super.key});

  @override
  ConsumerState<LiveChannelListPage> createState() =>
      _LiveChannelListPageState();
}

class _LiveChannelListPageState extends ConsumerState<LiveChannelListPage>
    with ConsumerTabBarVisibilityMixin {
  final _searchController = TextEditingController();
  bool _isGridView = true;
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    hideTabBar();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final channels = ref.watch(searchedLiveChannelsProvider);
    final hasLiveSources = ref.watch(hasLiveSourcesProvider);
    final uiStyle = ref.watch(uiStyleProvider);
    final safeTop = MediaQuery.of(context).padding.top;

    // iOS 26 玻璃模式：使用悬浮头部
    if (uiStyle.isGlass) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            // 主内容 - 直接使用带滚动边距的视图，无需固定顶栏
            !hasLiveSources
                ? _buildEmptyState(context)
                : channels.isEmpty
                    ? _buildNoResultsState()
                    : _isGridView
                        ? _buildGlassGridView(channels, isDark, safeTop + 60)
                        : _buildGlassListView(channels, isDark, safeTop + 60),
            // 悬浮按钮 - 左侧返回按钮
            Positioned(
              top: safeTop + 8,
              left: 16,
              child: const GlassFloatingBackButton(),
            ),
            // 悬浮按钮组或搜索栏（右上角）
            Positioned(
              top: safeTop + 8,
              right: 16,
              child: _showSearch
                  ? _buildGlassSearchBar(context, isDark)
                  : GlassButtonGroup(
                      children: [
                        GlassGroupIconButton(
                          icon: Icons.search_rounded,
                          tooltip: '搜索频道',
                          onPressed: () => setState(() => _showSearch = true),
                        ),
                        GlassGroupIconButton(
                          icon: _isGridView ? Icons.list_rounded : Icons.grid_view_rounded,
                          tooltip: _isGridView ? '列表视图' : '网格视图',
                          onPressed: () => setState(() => _isGridView = !_isGridView),
                        ),
                        GlassGroupIconButton(
                          icon: Icons.settings_rounded,
                          tooltip: '直播源管理',
                          onPressed: () => _openSettings(context),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      );
    }

    // 经典模式：保留 AppBar
    return Scaffold(
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: const Text('直播频道'),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchController.clear();
                ref.read(liveChannelSearchQueryProvider.notifier).state = '';
              }
            }),
            tooltip: '搜索频道',
          ),
          IconButton(
            icon: Icon(_isGridView ? Icons.list_rounded : Icons.grid_view_rounded),
            onPressed: () => setState(() => _isGridView = !_isGridView),
            tooltip: _isGridView ? '列表视图' : '网格视图',
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => _openSettings(context),
            tooltip: '直播源管理',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildSearchField(isDark),
            ),
          Expanded(
            child: !hasLiveSources
                ? _buildEmptyState(context)
                : channels.isEmpty
                    ? _buildNoResultsState()
                    : _isGridView
                        ? _buildGridView(channels, isDark)
                        : _buildListView(channels, isDark),
          ),
        ],
      ),
    );
  }

  /// 构建搜索框
  Widget _buildSearchField(bool isDark) {
    return TextField(
      controller: _searchController,
      autofocus: true,
      decoration: InputDecoration(
        hintText: '搜索频道...',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _searchController.clear();
                  ref.read(liveChannelSearchQueryProvider.notifier).state = '';
                },
              )
            : null,
        filled: true,
        fillColor: isDark
            ? AppColors.darkSurfaceVariant
            : AppColors.lightSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (value) {
        ref.read(liveChannelSearchQueryProvider.notifier).state = value;
      },
    );
  }

  /// iOS 26 玻璃风格搜索栏
  Widget _buildGlassSearchBar(BuildContext context, bool isDark) {
    final screenWidth = MediaQuery.of(context).size.width;
    // 搜索栏宽度：屏幕宽度减去左侧返回按钮和间距
    final searchWidth = (screenWidth - 100).clamp(200.0, 400.0);

    return GlassFloatingSearchBar(
      controller: _searchController,
      hintText: '搜索频道...',
      width: searchWidth,
      onChanged: (query) {
        ref.read(liveChannelSearchQueryProvider.notifier).state = query;
      },
      onClose: () {
        _searchController.clear();
        ref.read(liveChannelSearchQueryProvider.notifier).state = '';
        setState(() => _showSearch = false);
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.live_tv_rounded,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '暂无直播源',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请先添加直播源配置',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _openSettings(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加直播源'),
            ),
          ],
        ),
      );

  Widget _buildNoResultsState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '未找到匹配的频道',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );

  Widget _buildGridView(List<LiveChannel> channels, bool isDark) =>
      GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          childAspectRatio: 0.8,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: channels.length,
        itemBuilder: (context, index) => _ChannelGridItem(
          channel: channels[index],
          isDark: isDark,
          onTap: () => _playChannel(channels[index]),
        ),
      );

  /// 玻璃模式网格视图 - 带顶部滚动边距
  Widget _buildGlassGridView(
    List<LiveChannel> channels,
    bool isDark,
    double topPadding,
  ) =>
      GridView.builder(
        padding: EdgeInsets.fromLTRB(16, topPadding + 16, 16, 16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          childAspectRatio: 0.8,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: channels.length,
        itemBuilder: (context, index) => _ChannelGridItem(
          channel: channels[index],
          isDark: isDark,
          onTap: () => _playChannel(channels[index]),
        ),
      );

  /// 玻璃模式列表视图 - 带顶部滚动边距
  Widget _buildGlassListView(
    List<LiveChannel> channels,
    bool isDark,
    double topPadding,
  ) =>
      ListView.separated(
        padding: EdgeInsets.fromLTRB(16, topPadding + 16, 16, 16),
        itemCount: channels.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) => _ChannelListItem(
          channel: channels[index],
          isDark: isDark,
          onTap: () => _playChannel(channels[index]),
        ),
      );

  Widget _buildListView(List<LiveChannel> channels, bool isDark) =>
      ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: channels.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) => _ChannelListItem(
          channel: channels[index],
          isDark: isDark,
          onTap: () => _playChannel(channels[index]),
        ),
      );

  void _playChannel(LiveChannel channel) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LivePlayerPage(channel: channel),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const LiveStreamSettingsPage(),
      ),
    );
  }
}

/// 网格视图频道项
class _ChannelGridItem extends StatelessWidget {
  const _ChannelGridItem({
    required this.channel,
    required this.isDark,
    required this.onTap,
  });

  final LiveChannel channel;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant
                : AppColors.lightSurfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: channel.logoUrl != null
                      ? CachedNetworkImage(
                          imageUrl: channel.logoUrl!,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => _buildPlaceholder(),
                          errorWidget: (_, __, ___) => _buildPlaceholder(),
                        )
                      : _buildPlaceholder(),
                ),
              ),
              const SizedBox(height: 8),
              // 名称
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  channel.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              // 分类
              if (channel.category != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    channel.category!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _buildPlaceholder() => Center(
        child: Icon(
          Icons.tv_rounded,
          size: 28,
          color: isDark ? Colors.grey[600] : Colors.grey[400],
        ),
      );
}

/// 列表视图频道项
class _ChannelListItem extends StatelessWidget {
  const _ChannelListItem({
    required this.channel,
    required this.isDark,
    required this.onTap,
  });

  final LiveChannel channel;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant
                : AppColors.lightSurfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: channel.logoUrl != null
                ? CachedNetworkImage(
                    imageUrl: channel.logoUrl!,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => _buildPlaceholder(),
                    errorWidget: (_, __, ___) => _buildPlaceholder(),
                  )
                : _buildPlaceholder(),
          ),
        ),
        title: Text(channel.displayName),
        subtitle: channel.category != null ? Text(channel.category!) : null,
        trailing: const Icon(Icons.play_circle_outline_rounded),
      );

  Widget _buildPlaceholder() => Center(
        child: Icon(
          Icons.tv_rounded,
          size: 24,
          color: isDark ? Colors.grey[600] : Colors.grey[400],
        ),
      );
}
