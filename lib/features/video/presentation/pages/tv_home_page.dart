import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/widgets/tv_focus/tv_focus_scroll.dart';
import 'package:my_nas/core/widgets/tv_focus/tv_focusable.dart';
import 'package:my_nas/core/widgets/tv_focus/tv_shelf.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_detail_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_player_page.dart';
import 'package:my_nas/features/video/presentation/providers/video_history_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';

/// TV 首页：横向 shelves 堆叠布局，展示「继续观看」「最近添加」。
///
/// - **继续观看**：从 [continueWatchingProvider] 读取进行中的视频（进度 5%-95%）。
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
            error: (e, st) => Center(
              child: Text(
                'Error: $e',
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
        child: _TvCardBody(title: item.videoName),
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
        child: _TvCardBody(title: metadata.title ?? metadata.fileName),
      );
}

/// 卡片视觉主体。焦点高亮（缩放 + 白边）由外层 [TvFocusable] 统一负责，
/// 这里只画静态内容，避免两处各画一份边框。
class _TvCardBody extends StatelessWidget {
  const _TvCardBody({required this.title});

  final String title;

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
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: const Center(
                  child: Icon(
                    Icons.movie_filter_outlined,
                    size: 48,
                    color: Colors.white38,
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

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          'No items in $title',
          style: const TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
}
