import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/widgets/tv_focus/tv_focus_scroll.dart';
import 'package:my_nas/core/widgets/tv_focus/tv_focusable.dart';
import 'package:my_nas/core/widgets/tv_focus/tv_shelf.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/models/tv_browse_category.dart'
    as model;
import 'package:my_nas/features/video/presentation/pages/tv_video_browse_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_detail_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_player_page.dart';
import 'package:my_nas/features/video/presentation/providers/video_history_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/video_poster.dart';
import 'package:my_nas/l10n/app_localizations.dart';

/// TV 首页：分类入口行 + 横向 shelves，展示「继续观看」「最近添加」。
///
/// - **分类入口**：[_BrowseCategoriesRow] 通往 [TvVideoBrowsePage]，是 TV 上
///   到达完整媒体库（电影 / 剧集 / 其他 / 全部）的唯一路径。
/// - **继续观看**：从 [continueWatchingProvider] 读取进行中的视频（进度 5%-95%），
///   卡片海报底部带进度条。
/// - **最近添加**：从 [videoListProvider] 读取最近修改的前 20 项。
/// - **Shelf 布局**：每行一个 [TvShelf]（内部是 [FocusTraversalGroup]），左右键
///   在 shelf 内走，上下键跨 shelf。
/// - **焦点导航**：卡片用 [TvFocusable]（SELECT 激活 + 焦点高亮），外层
///   [TvFocusScroll] 负责把获得焦点的卡片滚进视口。
///
/// 结构：
/// ```
/// SafeArea
///   TvFocusScroll
///     SingleChildScrollView(vertical)
///       Column
///         ├─ _BrowseCategoriesRow
///         ├─ _ContinueWatchingShelf
///         └─ _RecentVideosShelf
/// ```
class TvHomePage extends ConsumerWidget {
  const TvHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D12),
      body: SafeArea(
        // 纵向滚动挂在外层：卡片获得焦点时 ensureVisible 需要能同时驱动
        // 纵向（跨 shelf）和 shelf 内的横向 ListView。
        child: TvFocusScroll(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(48, 0, 48, 24),
                  child: _BrowseCategoriesRow(),
                ),
                _ContinueWatchingShelf(title: l.homeSectionContinue),
                const SizedBox(height: 40),
                _RecentVideosShelf(title: l.homeSectionRecentlyAdded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 继续观看 shelf：从历史记录提取。
class _ContinueWatchingShelf extends ConsumerWidget {
  const _ContinueWatchingShelf({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(continueWatchingProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 48),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 240,
          child: asyncValue.when(
            data: (items) {
              if (items.isEmpty) {
                return _EmptyShelf(title: title);
              }
              return _HistoryShelfRow(items: items);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            // 错误详情不往电视上摆：坐三米外看不清，也无从处理。
            // 详细异常由 continueWatchingProvider 内部记进日志。
            error: (e, st) => Center(
              child: Text(
                AppLocalizations.of(context).tvLoadFailed,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 最近添加 shelf：从视频列表提取 recentVideos。
class _RecentVideosShelf extends ConsumerWidget {
  const _RecentVideosShelf({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(videoListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 48),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 240,
          child: switch (state) {
            VideoListLoaded(:final recentVideos) => () {
                final items = recentVideos.take(20).toList();
                if (items.isEmpty) {
                  return _EmptyShelf(title: title);
                }
                return _MetadataShelfRow(items: items);
              }(),
            VideoListLoading() => const Center(child: CircularProgressIndicator()),
            _ => _EmptyShelf(title: title),
          },
        ),
      ],
    );
  }
}

/// 历史记录横向行。
class _HistoryShelfRow extends StatelessWidget {
  const _HistoryShelfRow({required this.items});

  final List<VideoHistoryItem> items;

  @override
  Widget build(BuildContext context) => TvShelf(
        height: 240,
        itemCount: items.length,
        itemBuilder: (context, index) => _TvHistoryCard(item: items[index]),
      );
}

/// 元数据横向行。
class _MetadataShelfRow extends StatelessWidget {
  const _MetadataShelfRow({required this.items});

  final List<VideoMetadata> items;

  @override
  Widget build(BuildContext context) => TvShelf(
        height: 240,
        itemCount: items.length,
        itemBuilder: (context, index) => _TvMetadataCard(metadata: items[index]),
      );
}

/// 历史记录卡片：SELECT 直接续播。
class _TvHistoryCard extends ConsumerWidget {
  const _TvHistoryCard({required this.item});

  final VideoHistoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TvFocusable(
        onPressed: () => _play(context, ref),
        child: _TvCardBody(
          title: item.videoName,
          // 历史记录只存了缩略图，没有海报字段。
          posterUrl: item.thumbnailUrl,
          sourceId: item.sourceId,
          progress: item.progressPercent,
        ),
      );

  /// 续播：带 lastPosition 进播放器，返回后刷新「继续观看」。
  Future<void> _play(BuildContext context, WidgetRef ref) async {
    final video = tvHistoryToVideoItem(item);
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerPage(video: video),
      ),
    );
    if (!context.mounted) return;
    ref.invalidate(continueWatchingProvider);
  }
}

/// 历史记录项 → 播放器入参。
///
/// 与 video_list_page 的「继续观看」卡片走同一组字段（含 lastPosition），
/// 保证 TV 上续播落点与手机端一致。
@visibleForTesting
VideoItem tvHistoryToVideoItem(VideoHistoryItem item) => VideoItem(
      name: item.videoName,
      path: item.videoPath,
      url: item.videoUrl,
      sourceId: item.sourceId,
      size: item.size,
      thumbnailUrl: item.thumbnailUrl,
      lastPosition: item.lastPosition,
    );

/// 元数据卡片：SELECT 打开详情页（可选剧集 / 字幕后再播）。
class _TvMetadataCard extends StatelessWidget {
  const _TvMetadataCard({required this.metadata});

  final VideoMetadata metadata;

  @override
  Widget build(BuildContext context) => TvFocusable(
        onPressed: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => VideoDetailPage(
              metadata: metadata,
              sourceId: metadata.sourceId,
            ),
          ),
        ),
        child: _TvCardBody(
          title: metadata.title ?? metadata.fileName,
          posterUrl: metadata.displayPosterUrl,
          sourceId: metadata.sourceId,
        ),
      );
}

/// 卡片视觉主体。焦点高亮（缩放 + 白边）由外层 [TvFocusable] 统一负责，
/// 这里只画静态内容，避免两处各画一份边框。
///
/// [posterUrl] 走 [VideoPoster]：http(s) 用网络缓存，NAS 路径用 StreamImage，
/// 空值或加载失败回落到占位图标。[progress] 非空时在海报底部压一条进度条
/// （只有「继续观看」传，最近添加没有进度概念）。
class _TvCardBody extends StatelessWidget {
  const _TvCardBody({
    required this.title,
    this.posterUrl,
    this.sourceId,
    this.progress,
  });

  final String title;
  final String? posterUrl;
  final String? sourceId;
  final double? progress;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF161D2B),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SizedBox(
          width: 180,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 160,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoPoster(
                        posterUrl: posterUrl,
                        sourceId: sourceId,
                        width: double.infinity,
                        height: 160,
                        placeholder: const _CardPosterFallback(),
                        errorWidget: const _CardPosterFallback(),
                      ),
                      if (progress case final p? when p > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _CardProgressBar(progress: p),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _CardPosterFallback extends StatelessWidget {
  const _CardPosterFallback();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.white.withValues(alpha: 0.05),
        child: const Center(
          child: Icon(
            Icons.movie_filter_outlined,
            size: 48,
            color: Colors.white38,
          ),
        ),
      );
}

/// 观看进度条。压在海报底部，几米外要能看清，所以给了 4px 而不是 2px。
class _CardProgressBar extends StatelessWidget {
  const _CardProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) => Container(
        height: 4,
        color: Colors.black54,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: progress.clamp(0.0, 1.0),
          child: ColoredBox(color: Theme.of(context).colorScheme.primary),
        ),
      );
}

/// 通往完整媒体库的入口行。
///
/// TV 上 [TvScaffold] 用本页顶替了整个 video branch，两个 shelf 之外的内容
/// （电影 / 剧集 / 其他 / 全部）原本没有任何到达路径 —— 这一行就是那条路径。
class _BrowseCategoriesRow extends StatelessWidget {
  const _BrowseCategoriesRow();

  static const _categories = <(model.TvBrowseCategory, IconData)>[
    (model.TvBrowseCategory.all, Icons.video_library_outlined),
    (model.TvBrowseCategory.movies, Icons.movie_outlined),
    (model.TvBrowseCategory.tvShows, Icons.tv_outlined),
    (model.TvBrowseCategory.others, Icons.folder_outlined),
    (model.TvBrowseCategory.recent, Icons.schedule_outlined),
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        // 横向一行也要成组：左右键在分类之间走，上下键才会跳到下面的 shelf。
        child: FocusTraversalGroup(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final (category, icon) = _categories[index];
              return _BrowseCategoryChip(
                category: category,
                icon: icon,
                // 进页面时焦点落在第一个分类上：这是最靠上的可聚焦元素，
                // 从这里往下走才是自然顺序。
                autofocus: index == 0,
              );
            },
          ),
        ),
      );
}

class _BrowseCategoryChip extends StatelessWidget {
  const _BrowseCategoryChip({
    required this.category,
    required this.icon,
    this.autofocus = false,
  });

  final model.TvBrowseCategory category;
  final IconData icon;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TvFocusable(
      autofocus: autofocus,
      // 和本页的卡片一样走 rootNavigator：TvScaffold 顶替了 video branch，
      // 用 branch 内的 navigator 推页面在 TV 上看不见。
      onPressed: () => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => TvVideoBrowsePage(category: category),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF161D2B),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: Colors.white70),
            const SizedBox(width: 8),
            Text(
              model.tvBrowseCategoryLabel(l, category),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          AppLocalizations.of(context).tvEmptySection(title),
          style: const TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
}
