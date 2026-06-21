import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/presentation/widgets/animated_components.dart';

/// 音乐分类
enum MusicBrowseCategory {
  all('全部歌曲', Icons.queue_music_rounded, Color(0xFF1DB954)),
  favorites('我喜欢', Icons.favorite_rounded, Color(0xFFE91E63)),
  recent('最近播放', Icons.history_rounded, Color(0xFF2196F3)),
  artists('艺术家', Icons.mic_rounded, Color(0xFF9C27B0)),
  albums('专辑', Icons.album_rounded, Color(0xFFFF9800)),
  genres('流派', Icons.library_music_rounded, Color(0xFFE91E63)),
  years('年代', Icons.schedule_rounded, Color(0xFF00BCD4)),
  folders('文件夹', Icons.folder_open_rounded, Color(0xFF795548));

  const MusicBrowseCategory(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

/// 分类浏览 - 横向胶囊按钮组
///
/// 现代化设计：
/// - 横向可滚动胶囊按钮
/// - 渐变色背景
/// - 数量 badge
class BrowseCategoryGrid extends StatelessWidget {
  const BrowseCategoryGrid({
    required this.isDark,
    required this.onCategoryTap,
    this.isDesktop = false,
    this.counts = const {},
    super.key,
  });

  final bool isDark;
  final bool isDesktop;
  final Map<MusicBrowseCategory, int> counts;
  final void Function(MusicBrowseCategory category) onCategoryTap;

  @override
  Widget build(BuildContext context) {
    // 分类列表（排除快捷访问中已有的）
    final categories = [
      MusicBrowseCategory.artists,
      MusicBrowseCategory.albums,
      MusicBrowseCategory.genres,
      MusicBrowseCategory.years,
      MusicBrowseCategory.folders,
    ];

    if (isDesktop) {
      return _buildDesktopGrid(categories, context);
    }

    return _buildMobileChips(categories, context);
  }

  /// 移动端：横向胶囊按钮
  Widget _buildMobileChips(List<MusicBrowseCategory> categories, BuildContext context) => SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (buildContext, index) {
          final category = categories[index];
          final count = counts[category] ?? 0;
          return GradientChip(
            label: category.label,
            count: count > 0 ? count : null,
            icon: category.icon,
            gradientColors: [
              category.color,
              category.color.withValues(alpha: 0.7),
            ],
            onTap: () => onCategoryTap(category),
          );
        },
      ),
    );

  /// 桌面端：网格布局
  Widget _buildDesktopGrid(List<MusicBrowseCategory> categories, BuildContext context) => GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return _DesktopCategoryCard(
          category: category,
          count: counts[category] ?? 0,
          isDark: isDark,
          onTap: () => onCategoryTap(category),
        );
      },
    );
}

/// 桌面端分类卡片
class _DesktopCategoryCard extends StatelessWidget {
  const _DesktopCategoryCard({
    required this.category,
    required this.count,
    required this.isDark,
    required this.onTap,
  });

  final MusicBrowseCategory category;
  final int count;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedPressable(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              category.color.withValues(alpha: isDark ? 0.3 : 0.2),
              category.color.withValues(alpha: isDark ? 0.15 : 0.08),
            ],
          ),
          border: Border.all(
            color: category.color.withValues(alpha: isDark ? 0.3 : 0.2),
          ),
        ),
        child: Stack(
          children: [
            // 装饰图标
            Positioned(
              right: -8,
              bottom: -8,
              child: Icon(
                category.icon,
                size: 50,
                color: category.color.withValues(alpha: 0.15),
              ),
            ),
            // 内容
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: category.color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      category.icon,
                      color: category.color,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    category.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
}

/// 快捷访问网格 - 毛玻璃卡片设计
///
/// 现代化设计：
/// - 2x2 网格布局
/// - 毛玻璃背景
/// - 彩色图标
/// - 按压动画效果
class QuickAccessGrid extends StatelessWidget {
  const QuickAccessGrid({
    required this.isDark,
    required this.favoritesCount,
    required this.recentCount,
    required this.totalCount,
    required this.onFavoritesTap,
    required this.onRecentTap,
    required this.onAllTap,
    @Deprecated('随机播放已集成到 HeroPlayerCard') this.onShuffleTap,
    this.playlistCount = 0,
    this.onPlaylistTap,
    this.isDesktop = false,
    super.key,
  });

  final bool isDark;
  final bool isDesktop;
  final int favoritesCount;
  final int recentCount;
  final int totalCount;
  final int playlistCount;
  final VoidCallback onFavoritesTap;
  final VoidCallback onRecentTap;
  final VoidCallback onAllTap;
  @Deprecated('随机播放已集成到 HeroPlayerCard')
  final VoidCallback? onShuffleTap;
  final VoidCallback? onPlaylistTap;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _QuickAccessCardData(
        icon: Icons.favorite_rounded,
        label: context.l10n.musicBrowseCategoryFavorites,
        count: favoritesCount,
        color: const Color(0xFFE91E63),
        onTap: onFavoritesTap,
      ),
      _QuickAccessCardData(
        icon: Icons.queue_music_rounded,
        label: context.l10n.musicBrowseCategoryAllSongs,
        count: totalCount,
        color: AppColors.primary,
        onTap: onAllTap,
      ),
      _QuickAccessCardData(
        icon: Icons.history_rounded,
        label: context.l10n.musicBrowseCategoryRecent,
        count: recentCount,
        color: const Color(0xFF2196F3),
        onTap: onRecentTap,
      ),
      if (playlistCount > 0 && onPlaylistTap != null)
        _QuickAccessCardData(
          icon: Icons.playlist_play_rounded,
          label: context.l10n.musicBrowseCategoryPlaylists,
          count: playlistCount,
          color: const Color(0xFF9C27B0),
          onTap: onPlaylistTap!,
        ),
    ];

    if (isDesktop) {
      return _buildDesktopGrid(cards);
    }

    return _buildMobileGrid(context, cards);
  }

  /// 移动端：2x2 毛玻璃卡片网格
  Widget _buildMobileGrid(BuildContext context, List<_QuickAccessCardData> cards) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth - 32 - 12) / 2; // 左右 padding 16 + 间距 12
    final cardHeight = 72.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: cards.map((data) => _GlassQuickCard(
              data: data,
              width: cardWidth,
              height: cardHeight,
              isDark: isDark,
            )).toList(),
      ),
    );
  }

  /// 桌面端：横向排列
  Widget _buildDesktopGrid(List<_QuickAccessCardData> cards) => GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: cards.length,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: cards.map((data) => _GlassQuickCard(
            data: data,
            isDark: isDark,
            isDesktop: true,
          )).toList(),
    );
}

class _QuickAccessCardData {
  const _QuickAccessCardData({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;
}

/// 毛玻璃快捷访问卡片
class _GlassQuickCard extends StatelessWidget {
  const _GlassQuickCard({
    required this.data,
    required this.isDark,
    this.width,
    this.height,
    this.isDesktop = false,
  });

  final _QuickAccessCardData data;
  final bool isDark;
  final double? width;
  final double? height;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) => AnimatedPressable(
      onTap: data.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.85),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.9),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                // 装饰性图标
                Positioned(
                  right: -10,
                  bottom: -10,
                  child: Icon(
                    data.icon,
                    size: 60,
                    color: data.color.withValues(alpha: 0.1),
                  ),
                ),
                // 内容
                Padding(
                  padding: EdgeInsets.all(isDesktop ? 16 : 14),
                  child: Row(
                    children: [
                      // 彩色图标容器
                      Container(
                        width: isDesktop ? 48 : 44,
                        height: isDesktop ? 48 : 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              data.color,
                              data.color.withValues(alpha: 0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: data.color.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          data.icon,
                          color: Colors.white,
                          size: isDesktop ? 24 : 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 文字信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              data.label,
                              style: TextStyle(
                                fontSize: isDesktop ? 15 : 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatCount(context, data.count),
                              style: TextStyle(
                                fontSize: isDesktop ? 13 : 12,
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // 箭头指示器
                      Icon(
                        Icons.chevron_right_rounded,
                        color: isDark ? Colors.white24 : Colors.black26,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

  String _formatCount(BuildContext context, int count) {
    if (count >= 10000) {
      return context.l10n.musicBrowseCategoryFormatCountWan((count / 10000).toStringAsFixed(1));
    } else if (count >= 1000) {
      return context.l10n.musicBrowseCategoryFormatCountK((count / 1000).toStringAsFixed(1));
    }
    return context.l10n.musicBrowseCategoryFormatCountUnit(count.toString());
  }
}
