import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/music/presentation/pages/playlist_detail_page.dart';
import 'package:my_nas/features/music/presentation/providers/home_layout_provider.dart';
import 'package:my_nas/features/music/presentation/providers/playlist_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/animated_components.dart';
import 'package:my_nas/features/music/presentation/widgets/browse_category_grid.dart';
import 'package:my_nas/features/music/presentation/widgets/hero_player_card.dart';
import 'package:my_nas/features/music/presentation/widgets/music_stats_card.dart';
import 'package:my_nas/features/music/presentation/widgets/recent_tracks_section.dart';

/// 音乐主页内容组件 - 现代化设计
///
/// 特性：
/// - 沉浸式顶部 Hero 区域
/// - 毛玻璃快捷访问卡片
/// - 横向胶囊分类按钮
/// - 大封面最近播放卡片
/// - 滚动视差效果
/// - 布局自定义支持
class MusicHomeContent extends ConsumerStatefulWidget {
  const MusicHomeContent({
    required this.tracks,
    required this.recentTracks,
    required this.favoriteTracks,
    required this.onTrackTap,
    required this.onCategoryTap,
    this.onShuffleTap,
    this.onPlayAllTap,
    this.totalCount = 0,
    this.artistCount = 0,
    this.albumCount = 0,
    this.genreCount = 0,
    this.yearCount = 0,
    this.folderCount = 0,
    this.playlistCount = 0,
    this.favoritesCount = 0,
    this.recentCount = 0,
    this.returnSlivers = false,
    super.key,
  });

  /// 是否直接返回 Slivers（用于嵌入到外部 CustomScrollView）
  final bool returnSlivers;

  final List<MusicFileWithSource> tracks;
  final List<MusicFileWithSource> recentTracks;
  final List<MusicFileWithSource> favoriteTracks;
  final int totalCount;
  final int artistCount;
  final int albumCount;
  final int genreCount;
  final int yearCount;
  final int folderCount;
  final int playlistCount;
  final int favoritesCount;
  final int recentCount;

  final void Function(MusicFileWithSource track, List<MusicFileWithSource> allTracks) onTrackTap;
  final void Function(MusicCategory category) onCategoryTap;
  final VoidCallback? onShuffleTap;
  final VoidCallback? onPlayAllTap;

  @override
  ConsumerState<MusicHomeContent> createState() => _MusicHomeContentState();
}

class _MusicHomeContentState extends ConsumerState<MusicHomeContent> {
  final ScrollController _scrollController = ScrollController();

  // 缓存推荐歌曲，避免每次滚动都重新随机
  List<MusicFileWithSource>? _cachedRecommendedTracks;
  int _lastTracksHashCode = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 获取缓存的推荐歌曲，只有当源列表变化时才重新生成
  List<MusicFileWithSource> _getCachedRandomTracks(int count) {
    final currentHashCode = widget.tracks.length;
    if (_cachedRecommendedTracks == null || _lastTracksHashCode != currentHashCode) {
      _lastTracksHashCode = currentHashCode;
      if (widget.tracks.isEmpty) {
        _cachedRecommendedTracks = [];
      } else {
        final shuffled = List<MusicFileWithSource>.from(widget.tracks)..shuffle();
        _cachedRecommendedTracks = shuffled.take(count).toList();
      }
    }
    return _cachedRecommendedTracks!;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;
    final layoutState = ref.watch(homeLayoutProvider);

    if (isDesktop) {
      return _buildDesktopLayout(context, isDark);
    }

    // 如果需要返回 Slivers，包装成一个简单的 Column
    if (widget.returnSlivers) {
      return _buildMobileContentOnly(context, isDark, layoutState);
    }

    return _buildMobileLayout(context, isDark, layoutState);
  }

  /// 移动端内容区域（不包含 CustomScrollView，用于嵌入外部滚动视图）
  Widget _buildMobileContentOnly(
    BuildContext context,
    bool isDark,
    HomeLayoutState layoutState,
  ) {
    final sections = <Widget>[];

    for (final config in layoutState.sections) {
      if (!config.visible) continue;

      final sectionWidget = _buildSectionByType(context, isDark, config.section);
      if (sectionWidget != null) {
        sections
          ..add(sectionWidget)
          ..add(const SizedBox(height: 20));
      }
    }

    return Column(
      children: [
        // Hero 播放卡片
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          child: HeroPlayerCard(
            isDark: isDark,
            onShuffleTap: widget.onShuffleTap,
            onPlayAllTap: widget.onPlayAllTap,
          ),
        ),
        // 内容区域
        ...sections,
      ],
    );
  }

  /// 移动端布局
  Widget _buildMobileLayout(
    BuildContext context,
    bool isDark,
    HomeLayoutState layoutState,
  ) {
    final sections = <Widget>[];

    for (final config in layoutState.sections) {
      if (!config.visible) continue;

      final sectionWidget = _buildSectionByType(context, isDark, config.section);
      if (sectionWidget != null) {
        sections
          ..add(sectionWidget)
          ..add(const SizedBox(height: 20));
      }
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // Hero 播放卡片 - 不参与布局自定义
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: HeroPlayerCard(
              isDark: isDark,
              onShuffleTap: widget.onShuffleTap,
              onPlayAllTap: widget.onPlayAllTap,
            ),
          ),
        ),
        // 可配置的内容区域 - 使用动态 padding 支持悬浮导航栏
        SliverPadding(
          padding: EdgeInsets.only(bottom: context.scrollBottomPadding),
          sliver: SliverList(
            delegate: SliverChildListDelegate(sections),
          ),
        ),
      ],
    );
  }

  /// 根据区块类型构建对应的 Widget
  Widget? _buildSectionByType(BuildContext context, bool isDark, HomeSection section) {
    switch (section) {
      case HomeSection.heroPlayer:
        // Hero 区域已经在外部单独处理，这里返回 null
        return null;
      case HomeSection.quickAccess:
        return _buildQuickAccessSection(isDark);
      case HomeSection.recommended:
        if (widget.tracks.isEmpty) return null;
        return PopularTracksSection(
          tracks: _getCachedRandomTracks(5),
          isDark: isDark,
          title: context.l10n.musicHomeRecommendedTitle,
          onTrackTap: (track) => widget.onTrackTap(track, widget.tracks),
          onMoreTap: () => widget.onCategoryTap(MusicCategory.all),
        );
      case HomeSection.playlists:
        if (widget.playlistCount <= 0) return null;
        return _PlaylistsSection(
          isDark: isDark,
          playlistCount: widget.playlistCount,
          onMoreTap: () => widget.onCategoryTap(MusicCategory.playlists),
        );
      case HomeSection.recentPlays:
        if (widget.recentTracks.isEmpty) return null;
        return RecentTracksSection(
          tracks: widget.recentTracks,
          isDark: isDark,
          onTrackTap: (track) => widget.onTrackTap(track, widget.tracks),
          onMoreTap: () => widget.onCategoryTap(MusicCategory.recent),
        );
      case HomeSection.browseLibrary:
        return _buildBrowseSection(isDark);
    }
  }

  /// 快捷访问区域
  Widget _buildQuickAccessSection(bool isDark) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context.l10n.musicHomeQuickAccessTitle, isDark),
        const SizedBox(height: 12),
        QuickAccessGrid(
          isDark: isDark,
          favoritesCount: widget.favoritesCount > 0 ? widget.favoritesCount : widget.favoriteTracks.length,
          recentCount: widget.recentCount > 0 ? widget.recentCount : widget.recentTracks.length,
          totalCount: widget.totalCount > 0 ? widget.totalCount : widget.tracks.length,
          playlistCount: widget.playlistCount,
          onFavoritesTap: () => widget.onCategoryTap(MusicCategory.favorites),
          onRecentTap: () => widget.onCategoryTap(MusicCategory.recent),
          onAllTap: () => widget.onCategoryTap(MusicCategory.all),
          onPlaylistTap: () => widget.onCategoryTap(MusicCategory.playlists),
        ),
      ],
    );

  /// 浏览音乐库区域
  Widget _buildBrowseSection(bool isDark) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context.l10n.musicHomeBrowseLibraryTitle, isDark),
        const SizedBox(height: 12),
        BrowseCategoryGrid(
          isDark: isDark,
          counts: _getCategoryCounts(),
          onCategoryTap: _onBrowseCategoryTap,
        ),
      ],
    );

  /// 桌面端布局
  Widget _buildDesktopLayout(BuildContext context, bool isDark) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧边栏
        _buildDesktopSidebar(context, isDark),
        // 主内容区域
        Expanded(
          child: _buildDesktopMainContent(context, isDark),
        ),
      ],
    );

  /// 桌面端侧边栏
  Widget _buildDesktopSidebar(BuildContext context, bool isDark) => Container(
      width: 280,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        border: Border(
          right: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Column(
        children: [
          // Logo 区域
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  context.l10n.musicLibraryLabel,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 统计卡片
          Padding(
            padding: const EdgeInsets.all(16),
            child: MusicStatsCard(
              totalTracks: widget.totalCount > 0 ? widget.totalCount : widget.tracks.length,
              totalArtists: widget.artistCount,
              totalAlbums: widget.albumCount,
              isDark: isDark,
              isDesktop: true,
            ),
          ),
          const Divider(height: 1),
          // 快捷导航
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSidebarItem(
                  icon: Icons.favorite_rounded,
                  label: context.l10n.musicHomeMyFavorites,
                  count: widget.favoritesCount > 0 ? widget.favoritesCount : widget.favoriteTracks.length,
                  color: const Color(0xFFE91E63),
                  isDark: isDark,
                  onTap: () => widget.onCategoryTap(MusicCategory.favorites),
                ),
                _buildSidebarItem(
                  icon: Icons.history_rounded,
                  label: context.l10n.musicHomeRecentlyPlayed,
                  count: widget.recentCount > 0 ? widget.recentCount : widget.recentTracks.length,
                  color: const Color(0xFF2196F3),
                  isDark: isDark,
                  onTap: () => widget.onCategoryTap(MusicCategory.recent),
                ),
                _buildSidebarItem(
                  icon: Icons.queue_music_rounded,
                  label: context.l10n.musicHomeAllSongs,
                  count: widget.totalCount > 0 ? widget.totalCount : widget.tracks.length,
                  color: AppColors.primary,
                  isDark: isDark,
                  onTap: () => widget.onCategoryTap(MusicCategory.all),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    context.l10n.musicHomeBrowseCategory,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white38 : Colors.black38,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                _buildSidebarItem(
                  icon: Icons.mic_rounded,
                  label: context.l10n.musicBrowseArtists,
                  count: widget.artistCount,
                  color: const Color(0xFF9C27B0),
                  isDark: isDark,
                  onTap: () => widget.onCategoryTap(MusicCategory.artists),
                ),
                _buildSidebarItem(
                  icon: Icons.album_rounded,
                  label: context.l10n.musicBrowseAlbums,
                  count: widget.albumCount,
                  color: const Color(0xFFFF9800),
                  isDark: isDark,
                  onTap: () => widget.onCategoryTap(MusicCategory.albums),
                ),
                _buildSidebarItem(
                  icon: Icons.library_music_rounded,
                  label: context.l10n.musicBrowseGenres,
                  count: widget.genreCount,
                  color: const Color(0xFFE91E63),
                  isDark: isDark,
                  onTap: () => widget.onCategoryTap(MusicCategory.genres),
                ),
                _buildSidebarItem(
                  icon: Icons.folder_open_rounded,
                  label: context.l10n.musicBrowseFolders,
                  count: widget.folderCount,
                  color: const Color(0xFF795548),
                  isDark: isDark,
                  onTap: () => widget.onCategoryTap(MusicCategory.folders),
                ),
              ],
            ),
          ),
        ],
      ),
    );

  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) => AnimatedPressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );

  /// 桌面端主内容区域
  Widget _buildDesktopMainContent(BuildContext context, bool isDark) => CustomScrollView(
      slivers: [
        // 顶部 Hero 区域
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 欢迎语
                Text(
                  _getGreeting(),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 24),
                // Hero 播放卡片
                HeroPlayerCard(
                  isDark: isDark,
                  isDesktop: true,
                  onShuffleTap: widget.onShuffleTap,
                  onPlayAllTap: widget.onPlayAllTap,
                ),
              ],
            ),
          ),
        ),
        // 快捷访问
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.musicHomeQuickAccessTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                QuickAccessGrid(
                  isDark: isDark,
                  isDesktop: true,
                  favoritesCount: widget.favoritesCount > 0 ? widget.favoritesCount : widget.favoriteTracks.length,
                  recentCount: widget.recentCount > 0 ? widget.recentCount : widget.recentTracks.length,
                  totalCount: widget.totalCount > 0 ? widget.totalCount : widget.tracks.length,
                  playlistCount: widget.playlistCount,
                  onFavoritesTap: () => widget.onCategoryTap(MusicCategory.favorites),
                  onRecentTap: () => widget.onCategoryTap(MusicCategory.recent),
                  onAllTap: () => widget.onCategoryTap(MusicCategory.all),
                  onPlaylistTap: () => widget.onCategoryTap(MusicCategory.playlists),
                ),
              ],
            ),
          ),
        ),
        // 最近播放
        if (widget.recentTracks.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: RecentTracksSection(
                tracks: widget.recentTracks,
                isDark: isDark,
                isDesktop: true,
                onTrackTap: (track) => widget.onTrackTap(track, widget.tracks),
                onMoreTap: () => widget.onCategoryTap(MusicCategory.recent),
              ),
            ),
          ),
        // 推荐歌曲
        if (widget.tracks.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: PopularTracksSection(
                tracks: _getCachedRandomTracks(8),
                isDark: isDark,
                isDesktop: true,
                title: context.l10n.musicHomeRecommendedTitle,
                maxItems: 8,
                onTrackTap: (track) => widget.onTrackTap(track, widget.tracks),
                onMoreTap: () => widget.onCategoryTap(MusicCategory.all),
              ),
            ),
          ),
        // 底部间距
        const SliverToBoxAdapter(
          child: SizedBox(height: 100),
        ),
      ],
    );

  Widget _buildSectionTitle(String title, bool isDark) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return context.l10n.musicHomeGreetingNight;
    if (hour < 12) return context.l10n.musicHomeGreetingMorning;
    if (hour < 14) return context.l10n.musicHomeGreetingNoon;
    if (hour < 18) return context.l10n.musicHomeGreetingAfternoon;
    return context.l10n.musicHomeGreetingEvening;
  }

  Map<MusicBrowseCategory, int> _getCategoryCounts() => {
      MusicBrowseCategory.all: widget.totalCount > 0 ? widget.totalCount : widget.tracks.length,
      MusicBrowseCategory.favorites: widget.favoritesCount > 0 ? widget.favoritesCount : widget.favoriteTracks.length,
      MusicBrowseCategory.recent: widget.recentCount > 0 ? widget.recentCount : widget.recentTracks.length,
      MusicBrowseCategory.artists: widget.artistCount,
      MusicBrowseCategory.albums: widget.albumCount,
      MusicBrowseCategory.genres: widget.genreCount,
      MusicBrowseCategory.years: widget.yearCount,
      MusicBrowseCategory.folders: widget.folderCount,
    };

  void _onBrowseCategoryTap(MusicBrowseCategory browseCategory) {
    switch (browseCategory) {
      case MusicBrowseCategory.all:
        widget.onCategoryTap(MusicCategory.all);
      case MusicBrowseCategory.favorites:
        widget.onCategoryTap(MusicCategory.favorites);
      case MusicBrowseCategory.recent:
        widget.onCategoryTap(MusicCategory.recent);
      case MusicBrowseCategory.artists:
        widget.onCategoryTap(MusicCategory.artists);
      case MusicBrowseCategory.albums:
        widget.onCategoryTap(MusicCategory.albums);
      case MusicBrowseCategory.genres:
        widget.onCategoryTap(MusicCategory.genres);
      case MusicBrowseCategory.years:
        widget.onCategoryTap(MusicCategory.years);
      case MusicBrowseCategory.folders:
        widget.onCategoryTap(MusicCategory.folders);
    }
  }
}

/// 歌单区块 - 现代化横向滚动设计
class _PlaylistsSection extends ConsumerWidget {
  const _PlaylistsSection({
    required this.isDark,
    required this.playlistCount,
    required this.onMoreTap,
  });

  final bool isDark;
  final int playlistCount;
  final VoidCallback onMoreTap;

  // 歌单渐变色列表
  static const List<List<Color>> _gradientColors = [
    [Color(0xFF9C27B0), Color(0xFF7B1FA2)], // 紫色
    [Color(0xFF2196F3), Color(0xFF1976D2)], // 蓝色
    [Color(0xFFE91E63), Color(0xFFC2185B)], // 粉色
    [Color(0xFF00BCD4), Color(0xFF0097A7)], // 青色
    [Color(0xFFFF9800), Color(0xFFF57C00)], // 橙色
    [Color(0xFF4CAF50), Color(0xFF388E3C)], // 绿色
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistState = ref.watch(playlistProvider);
    final playlists = playlistState.playlists;

    if (playlists.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFF9C27B0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    context.l10n.musicHomePlaylistsTitle,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              if (playlists.length > 5)
                AnimatedPressable(
                  onTap: onMoreTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.l10n.musicHomeViewAll,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // 歌单横向滚动列表
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: playlists.length > 10 ? 10 : playlists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final colors = _gradientColors[index % _gradientColors.length];
              return _ModernPlaylistCard(
                playlist: playlist,
                isDark: isDark,
                gradientColors: colors,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 现代化歌单卡片 - 与其他卡片风格统一
class _ModernPlaylistCard extends StatelessWidget {
  const _ModernPlaylistCard({
    required this.playlist,
    required this.isDark,
    required this.gradientColors,
  });

  final PlaylistEntry playlist;
  final bool isDark;
  final List<Color> gradientColors;

  @override
  Widget build(BuildContext context) => AnimatedPressable(
      onTap: () => PlaylistDetailPage.open(context, playlist),
      child: Container(
        width: 130,
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面区域 - 渐变色
            Container(
              height: 90,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
              ),
              child: Stack(
                children: [
                  // 装饰性图标
                  Positioned(
                    right: -10,
                    bottom: -10,
                    child: Icon(
                      Icons.queue_music_rounded,
                      size: 60,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  // 中心图标
                  Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.queue_music_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 信息区域
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 歌单名称
                    Text(
                      playlist.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // 歌曲数量
                    Text(
                      context.l10n.musicPlaylistTrackCount(playlist.trackPaths.length),
                      style: TextStyle(
                        fontSize: 11,
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
    );
}
