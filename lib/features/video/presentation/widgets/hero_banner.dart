import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/services/nas_file_system_registry.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

/// 英雄横幅组件 - Netflix/Infuse 风格的大图推荐展示
class HeroBanner extends StatefulWidget {
  const HeroBanner({
    required this.items,
    required this.onItemTap,
    required this.onPlayTap,
    this.height = 400,
    this.autoPlayDuration = const Duration(seconds: 8),
    super.key,
  });

  final List<VideoMetadata> items;
  final void Function(VideoMetadata item) onItemTap;
  final void Function(VideoMetadata item) onPlayTap;
  final double height;
  final Duration autoPlayDuration;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _autoPlayTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startAutoPlay();
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoPlay() {
    if (widget.items.length <= 1) return;

    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer.periodic(widget.autoPlayDuration, (timer) {
      if (!mounted) return;

      final nextPage = (_currentPage + 1) % widget.items.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  void _pauseAutoPlay() {
    _autoPlayTimer?.cancel();
  }

  void _resumeAutoPlay() {
    _startAutoPlay();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onPanDown: (_) => _pauseAutoPlay(),
      onPanEnd: (_) => _resumeAutoPlay(),
      onPanCancel: _resumeAutoPlay,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            // 背景轮播
            PageView.builder(
              controller: _pageController,
              onPageChanged: (page) {
                setState(() => _currentPage = page);
              },
              itemCount: widget.items.length,
              itemBuilder: (context, index) => _HeroBannerItem(
                  metadata: widget.items[index],
                  onTap: () => widget.onItemTap(widget.items[index]),
                  onPlayTap: () => widget.onPlayTap(widget.items[index]),
                  isDark: isDark,
                ),
            ),

            // 底部指示器
            if (widget.items.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.items.length,
                    (index) => _buildIndicator(index, isDark),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicator(int index, bool isDark) {
    final isActive = index == _currentPage;

    return GestureDetector(
      onTap: () {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: isActive ? 24 : 8,
        height: 8,
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary
              : (isDark ? Colors.white38 : Colors.black26),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

/// 英雄横幅单项
class _HeroBannerItem extends StatelessWidget {
  const _HeroBannerItem({
    required this.metadata,
    required this.onTap,
    required this.onPlayTap,
    required this.isDark,
  });

  final VideoMetadata metadata;
  final VoidCallback onTap;
  final VoidCallback onPlayTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // 优先使用背景图，没有则使用海报
    // 背景图: backdropUrl (TMDB) 或 localBackdropPath (本地)
    // 海报: displayPosterUrl (会自动处理本地缓存)
    final imageUrl = metadata.backdropUrl ?? metadata.displayPosterUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景图片 - 使用智能加载支持 NAS 路径
          if (hasImage)
            _buildSmartImage(imageUrl, metadata.sourceId)
          else
            _buildPlaceholder(),

          // 渐变遮罩
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.3),
                  Colors.black.withValues(alpha: 0.9),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // 左侧渐变（用于显示信息）
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.7),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.6],
              ),
            ),
          ),

          // 内容区域
          Positioned(
            left: 24,
            right: 24,
            bottom: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 分类标签
                if (metadata.category != MediaCategory.unknown)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: metadata.category == MediaCategory.tvShow
                          ? AppColors.accent
                          : AppColors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      metadata.category == MediaCategory.tvShow ? '剧集' : '电影',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),

                // 标题
                Text(
                  metadata.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                    shadows: [
                      Shadow(
                        offset: Offset(0, 2),
                        blurRadius: 4,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // 元信息行
                Row(
                  children: [
                    if (metadata.year != null) ...[
                      Text(
                        '${metadata.year}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    if (metadata.rating != null && metadata.rating! > 0) ...[
                      Icon(
                        Icons.star_rounded,
                        color: Colors.amber,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        metadata.ratingText,
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    if (metadata.runtimeText.isNotEmpty) ...[
                      Icon(
                        Icons.access_time_rounded,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        metadata.runtimeText,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                // 类型标签
                if (metadata.genreList.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: metadata.genreList.take(3).map((genre) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          genre,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 11,
                          ),
                        ),
                      )).toList(),
                  ),
                const SizedBox(height: 16),

                // 简介
                if (metadata.overview != null &&
                    metadata.overview!.isNotEmpty)
                  Text(
                    metadata.overview!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                const SizedBox(height: 20),

                // 操作按钮
                Row(
                  children: [
                    // 播放按钮
                    ElevatedButton.icon(
                      onPressed: onPlayTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 24),
                      label: const Text(
                        '播放',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 详情按钮
                    OutlinedButton.icon(
                      onPressed: onTap,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.info_outline_rounded, size: 20),
                      label: const Text(
                        '详情',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 智能图片加载 - 支持 NAS 路径和网络 URL
  Widget _buildSmartImage(String imageUrl, String sourceId) {
    // 检查是否是 NAS 路径
    final isNasPath = imageUrl.startsWith('/') &&
        !imageUrl.startsWith('//') &&
        !imageUrl.contains('://');

    if (isNasPath) {
      // NAS 路径 - 使用 StreamImage
      final fileSystem = NasFileSystemRegistry.instance.get(sourceId);
      return StreamImage(
        path: imageUrl,
        fileSystem: fileSystem,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter, // 顶部对齐，优先显示图片上半部分
        placeholder: _buildPlaceholder(),
        errorWidget: _buildPlaceholder(),
      );
    }

    // 网络 URL - 使用 CachedNetworkImage
    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter, // 顶部对齐，优先显示图片上半部分
        placeholder: (_, _) => _buildPlaceholder(),
        errorWidget: (_, _, _) => _buildPlaceholder(),
      );
    }

    // 其他情况显示占位符
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() => ColoredBox(
      color: isDark ? AppColors.darkBackground : AppColors.lightOutline,
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          size: 80,
          color: isDark ? Colors.grey[700] : Colors.grey[400],
        ),
      ),
    );
}

/// 紧凑版英雄横幅（用于移动端）
class CompactHeroBanner extends StatefulWidget {
  const CompactHeroBanner({
    required this.items,
    required this.onItemTap,
    this.height = 220,
    super.key,
  });

  final List<VideoMetadata> items;
  final void Function(VideoMetadata item) onItemTap;
  final double height;

  @override
  State<CompactHeroBanner> createState() => _CompactHeroBannerState();
}

class _CompactHeroBannerState extends State<CompactHeroBanner> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: widget.height,
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (page) => setState(() => _currentPage = page),
              itemCount: widget.items.length,
              itemBuilder: (context, index) => AnimatedBuilder(
                  animation: _pageController,
                  builder: (context, child) {
                    double value = 1;
                    if (_pageController.position.haveDimensions) {
                      value = (_pageController.page! - index).abs();
                      value = (1 - (value * 0.2)).clamp(0.8, 1.0);
                    }
                    return Transform.scale(
                      scale: value,
                      child: child,
                    );
                  },
                  child: _CompactBannerCard(
                    metadata: widget.items[index],
                    onTap: () => widget.onItemTap(widget.items[index]),
                    isDark: isDark,
                  ),
                ),
            ),
          ),
          const SizedBox(height: 12),
          // 指示器
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.items.length,
              (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: index == _currentPage ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: index == _currentPage
                      ? AppColors.primary
                      : (isDark ? AppColors.darkOutline : AppColors.lightOutline),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactBannerCard extends StatelessWidget {
  const _CompactBannerCard({
    required this.metadata,
    required this.onTap,
    required this.isDark,
  });

  final VideoMetadata metadata;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final imageUrl = metadata.backdropUrl ?? metadata.displayPosterUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 背景图 - 使用智能加载支持 NAS 路径
              if (hasImage)
                _buildSmartImage(imageUrl, metadata.sourceId)
              else
                _buildPlaceholder(),

              // 渐变遮罩
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                    stops: const [0.5, 1.0],
                  ),
                ),
              ),

              // 信息
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metadata.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (metadata.year != null)
                          Text(
                            '${metadata.year}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                        if (metadata.rating != null && metadata.rating! > 0) ...[
                          const SizedBox(width: 12),
                          Icon(
                            Icons.star_rounded,
                            color: Colors.amber,
                            size: 16,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            metadata.ratingText,
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // 播放按钮
              Positioned(
                right: 16,
                bottom: 16,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 智能图片加载 - 支持 NAS 路径和网络 URL
  Widget _buildSmartImage(String imageUrl, String sourceId) {
    // 检查是否是 NAS 路径
    final isNasPath = imageUrl.startsWith('/') &&
        !imageUrl.startsWith('//') &&
        !imageUrl.contains('://');

    if (isNasPath) {
      final fileSystem = NasFileSystemRegistry.instance.get(sourceId);
      return StreamImage(
        path: imageUrl,
        fileSystem: fileSystem,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter, // 顶部对齐，优先显示图片上半部分
        placeholder: _buildPlaceholder(),
        errorWidget: _buildPlaceholder(),
      );
    }

    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter, // 顶部对齐，优先显示图片上半部分
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() => ColoredBox(
      color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
      child: Icon(
        Icons.movie_rounded,
        size: 50,
        color: isDark ? Colors.grey[600] : Colors.grey[400],
      ),
    );
}
