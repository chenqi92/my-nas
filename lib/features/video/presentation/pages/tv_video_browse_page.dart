import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/widgets/tv_focus/tv_focusable.dart';
import 'package:my_nas/core/widgets/tv_focus/tv_grid.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/models/tv_browse_category.dart';
import 'package:my_nas/features/video/presentation/pages/video_detail_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart';
import 'package:my_nas/features/video/presentation/widgets/video_poster.dart';
import 'package:my_nas/l10n/app_localizations.dart';

/// TV 视频库浏览页：海报网格。
///
/// 存在的原因是 TvScaffold 用 TvHomePage 顶替了整个 video branch，TV 上看不到
/// go_router 在该 branch 内的跳转。所以这里和 TvHomePage 一样，用
/// `rootNavigator: true` 直接 push 详情页。
///
/// - **布局**：[TvGrid]（内含 `FocusTraversalGroup` + `TvFocusScroll`，D-pad
///   移到下一行时会把卡片滚进视口）。
/// - **海报**：[VideoPoster]，剧集用分组自己的海报/标题，电影和其他用
///   [VideoMetadata.displayPosterUrl]。
class TvVideoBrowsePage extends ConsumerWidget {
  const TvVideoBrowsePage({required this.category, super.key});

  final TvBrowseCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(videoListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D12),
      body: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tvBrowseCategoryLabel(l, category),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: switch (state) {
                VideoListLoaded() => _BrowseGrid(
                    items: tvBrowseItems(state, category),
                    emptyLabel: l.tvEmptySection(
                      tvBrowseCategoryLabel(l, category),
                    ),
                  ),
                VideoListLoading() => const Center(
                    child: CircularProgressIndicator(),
                  ),
                VideoListError() => Center(
                    child: Text(
                      l.tvLoadFailed,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 16,
                      ),
                    ),
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 一张 TV 海报卡要显示的东西。
///
/// 剧集分组的标题/海报/年份挂在 [TvShowGroup] 上，不在任何单集的
/// [VideoMetadata] 上；但点进去要打开的是具体某一集。两者拆开放，卡片才不会
/// 显示成「第一季第一集」的文件名。
typedef TvBrowseItem = ({
  String title,
  String? posterUrl,
  int? year,
  VideoMetadata target,
});

/// 按分类从已加载状态里取出要展示的条目。
@visibleForTesting
List<TvBrowseItem> tvBrowseItems(
  VideoListLoaded state,
  TvBrowseCategory category,
) =>
    switch (category) {
      TvBrowseCategory.all => state.filteredMetadata.map(_fromMetadata).toList(),
      TvBrowseCategory.movies => state.movies.map(_fromMetadata).toList(),
      TvBrowseCategory.others => state.others.map(_fromMetadata).toList(),
      TvBrowseCategory.recent => state.recentVideos.map(_fromMetadata).toList(),
      TvBrowseCategory.tvShows => state.tvShowGroupList.map((g) {
          final rep = g.representative;
          return (
            title: g.title,
            posterUrl: g.displayPosterUrl,
            year: g.year ?? rep.year,
            target: rep,
          );
        }).toList(),
    };

TvBrowseItem _fromMetadata(VideoMetadata m) => (
      title: m.title ?? m.fileName,
      posterUrl: m.displayPosterUrl,
      year: m.year,
      target: m,
    );

class _BrowseGrid extends StatelessWidget {
  const _BrowseGrid({required this.items, required this.emptyLabel});

  final List<TvBrowseItem> items;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          emptyLabel,
          style: const TextStyle(color: Colors.white38, fontSize: 16),
        ),
      );
    }

    return TvGrid(
      itemCount: items.length,
      crossAxisCount: 5,
      // 海报是 2:3，卡片底部还要塞标题和年份，所以整卡比海报更瘦一点。
      childAspectRatio: 0.58,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) => _TvPosterCard(
        item: items[index],
        autofocus: index == 0,
      ),
    );
  }
}

class _TvPosterCard extends StatelessWidget {
  const _TvPosterCard({required this.item, this.autofocus = false});

  final TvBrowseItem item;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TvFocusable(
        autofocus: autofocus,
        onPressed: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => VideoDetailPage(
              metadata: item.target,
              sourceId: item.target.sourceId,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: VideoPoster(
                  posterUrl: item.posterUrl,
                  sourceId: item.target.sourceId,
                  width: double.infinity,
                  height: double.infinity,
                  placeholder: const _PosterFallback(),
                  errorWidget: const _PosterFallback(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            if (item.year != null)
              Text(
                '${item.year}',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
          ],
        ),
      );
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Color(0xFF161D2B),
        child: Center(
          child: Icon(
            Icons.movie_filter_outlined,
            size: 40,
            color: Colors.white24,
          ),
        ),
      );
}
