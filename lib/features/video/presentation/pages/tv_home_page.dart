import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart';
import 'package:my_nas/features/video/presentation/providers/video_history_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';

/// TV 首页：横向 shelves 堆叠布局，展示「继续观看」「最近添加」。
///
/// - **继续观看**：从 [continueWatchingProvider] 读取进行中的视频（进度 5%-95%）。
/// - **最近添加**：从 [videoListProvider] 读取最近修改的前 20 项。
/// - **Shelf 布局**：每行一个 shelf，左侧标题，右侧横向卡片滚动。
/// - **焦点导航**：当前骨架版未接 tv_focus 基础设施（等 A3 完成），临时用
///   普通 InkWell 占位。
///
/// 结构：
/// ```
/// SafeArea
///   SingleChildScrollView(vertical)
///     Column
///       ├─ _ContinueWatchingShelf
///       └─ _RecentVideosShelf
/// ```
class TvHomePage extends ConsumerWidget {
  const TvHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D12),
      body: SafeArea(
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
  Widget build(BuildContext context) => ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 48),
        itemCount: items.length,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(right: index < items.length - 1 ? 16 : 0),
          child: _TvHistoryCard(item: items[index]),
        ),
      );
}

/// 元数据横向行。
class _MetadataShelfRow extends StatelessWidget {
  const _MetadataShelfRow({required this.items});

  final List<VideoMetadata> items;

  @override
  Widget build(BuildContext context) => ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 48),
        itemCount: items.length,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(right: index < items.length - 1 ? 16 : 0),
          child: _TvMetadataCard(metadata: items[index]),
        ),
      );
}

/// 历史记录卡片。
class _TvHistoryCard extends StatefulWidget {
  const _TvHistoryCard({required this.item});

  final VideoHistoryItem item;

  @override
  State<_TvHistoryCard> createState() => _TvHistoryCardState();
}

class _TvHistoryCardState extends State<_TvHistoryCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () {
          // TODO(A4): 导航到视频播放页
        },
        onFocusChange: (focused) => setState(() => _focused = focused),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 180,
          decoration: BoxDecoration(
            color: const Color(0xFF161D2B),
            borderRadius: BorderRadius.circular(8),
            border: _focused ? Border.all(color: Colors.white, width: 2) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: const Center(
                  child: Icon(
                    Icons.movie_filter_outlined,
                    size: 48,
                    color: Colors.white38,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  widget.item.videoName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _focused ? Colors.white : Colors.white70,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
}

/// 元数据卡片。
class _TvMetadataCard extends StatefulWidget {
  const _TvMetadataCard({required this.metadata});

  final VideoMetadata metadata;

  @override
  State<_TvMetadataCard> createState() => _TvMetadataCardState();
}

class _TvMetadataCardState extends State<_TvMetadataCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.metadata.title ?? widget.metadata.fileName;

    return InkWell(
      onTap: () {
        // TODO(A4): 导航到视频详情页
      },
      onFocusChange: (focused) => setState(() => _focused = focused),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF161D2B),
          borderRadius: BorderRadius.circular(8),
          border: _focused ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: const Center(
                child: Icon(
                  Icons.movie_filter_outlined,
                  size: 48,
                  color: Colors.white38,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _focused ? Colors.white : Colors.white70,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
          'No items in $title',
          style: const TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
}
