import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart'
    show VideoListLoaded, VideoListLoading, VideoTab, videoListProvider;
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_progress_bar.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';
import 'package:my_nas/shared/widgets/dialogs/film_detail_sheet.dart';

/// 桌面端「影视库」。
///
/// 接 `videoListProvider`：取 VideoListLoaded 状态后铺 hero（topRatedMovies
/// 首条） + 类型 chips + 海报网格。点击海报弹出 [FilmDetailSheet]。
class VideoListDesktopPage extends ConsumerStatefulWidget {
  const VideoListDesktopPage({super.key});

  @override
  ConsumerState<VideoListDesktopPage> createState() =>
      _VideoListDesktopPageState();
}

class _VideoListDesktopPageState extends ConsumerState<VideoListDesktopPage> {
  String _view = 'grid';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoListProvider);
    final t = DesignTokens.of(context);

    return DesktopPageScaffold(
      title: '影视',
      subtitle: 'Trakt 同步 · 多版本 · 智能续播 · TMDB / 豆瓣 刮削',
      actions: AppSegmented<String>(
        value: _view,
        onChanged: (v) => setState(() => _view = v),
        dense: true,
        options: const [
          AppSegmentedOption(
            value: 'grid',
            label: '网格',
            icon: Icons.grid_view_rounded,
          ),
          AppSegmentedOption(
            value: 'list',
            label: '列表',
            icon: Icons.view_list_rounded,
          ),
        ],
      ),
      body: switch (state) {
        VideoListLoading() => _Loading(t: t),
        VideoListLoaded(:final totalCount) when totalCount == 0 =>
          const DesktopComingSoon(
            icon: Icons.movie_outlined,
            message: '映射「影视」媒体库后，此处显示海报网格 + 继续观看 strip。\n'
                '点击海报会打开「影视详情」浮层（多版本 / 剧集分集 / 演职 / 相关）。',
          ),
        VideoListLoaded() => _Loaded(state: state, view: _view),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.t});
  final DesignTokens t;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 80),
        alignment: Alignment.center,
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              '正在扫描影视库…',
              style: TextStyle(color: t.text2, fontSize: 13),
            ),
          ],
        ),
      );
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.state, required this.view});
  final VideoListLoaded state;
  final String view;

  static const _tabs = [
    ('全部', VideoTab.all),
    ('电影', VideoTab.movies),
    ('剧集', VideoTab.tvShows),
    ('其他', VideoTab.other),
    ('最近添加', VideoTab.recent),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final notifier = ref.read(videoListProvider.notifier);

    // Hero 用最高分（topRated）第一项，没有时退到 recent / movies 第一项。
    final hero = state.topRatedMovies.isNotEmpty
        ? state.topRatedMovies.first
        : state.recentVideos.isNotEmpty
            ? state.recentVideos.first
            : state.movies.isNotEmpty
                ? state.movies.first
                : null;

    final items = state.filteredMetadata;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hero != null) ...[
          _Hero(meta: hero),
          const SizedBox(height: 22),
        ],
        Row(
          children: [
            for (final (label, tab) in _tabs)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AppChip(
                  label: label,
                  active: state.currentTab == tab,
                  compact: true,
                  onTap: () => notifier.setTab(tab),
                ),
              ),
            const Spacer(),
            Text(
              '${state.totalCount} 项',
              style: TextStyle(fontSize: 12, color: t.text3),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (view == 'grid')
          _PosterGrid(items: items)
        else
          _PosterList(items: items),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.meta});
  final VideoMetadata meta;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final backdrop = meta.backdropUrl ?? meta.localPosterUrl ?? meta.posterUrl;
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (_) => FilmDetailSheet(meta: meta),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        child: SizedBox(
          height: 300,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Image(url: backdrop, fallbackColor: t.bgStrong),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.92),
                      Colors.black.withValues(alpha: 0.34),
                      Colors.black.withValues(alpha: 0.10),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 32, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        if (meta.hdrFormat != null)
                          AppTag(meta.hdrFormat!),
                        if (meta.resolution != null)
                          AppTag(meta.resolution!),
                        if (meta.videoCodec != null)
                          AppTag(meta.videoCodec!),
                        for (final g
                            in (meta.genres ?? '').split(',').take(3))
                          if (g.trim().isNotEmpty) AppTag(g.trim()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      meta.title ?? meta.fileName,
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.8,
                        shadows: [
                          Shadow(color: Colors.black87, blurRadius: 14),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (meta.rating != null) ...[
                          Icon(Icons.star_rounded,
                              color: t.warn, size: 17),
                          const SizedBox(width: 4),
                          Text(
                            meta.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 14),
                        ],
                        if (meta.year != null) ...[
                          Text(
                            '${meta.year}',
                            style: const TextStyle(
                              color: Color(0xFFD9D9DC),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 14),
                        ],
                        if (meta.runtime != null) ...[
                          Text(
                            '${meta.runtime} 分钟',
                            style: const TextStyle(
                              color: Color(0xFFD9D9DC),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (meta.overview != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        meta.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Colors.white.withValues(alpha: 0.82),
                          height: 1.55,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterGrid extends StatelessWidget {
  const _PosterGrid({required this.items});
  final List<VideoMetadata> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const DesktopComingSoon(
        icon: Icons.search_off_rounded,
        message: '该分类下暂无项目。',
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        crossAxisSpacing: 18,
        mainAxisSpacing: 22,
        childAspectRatio: 0.62,
      ),
      itemBuilder: (_, i) => _PosterCard(meta: items[i]),
    );
  }
}

class _PosterList extends StatelessWidget {
  const _PosterList({required this.items});
  final List<VideoMetadata> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const DesktopComingSoon(
        icon: Icons.search_off_rounded,
        message: '该分类下暂无项目。',
      );
    }
    return Column(
      children: [
        for (final meta in items.take(120))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              onTap: () => _open(context, meta),
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: _Image(
                        url: meta.localPosterUrl ?? meta.posterUrl,
                        fallbackColor:
                            DesignTokens.of(context).insetBg,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          meta.title ?? meta.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: DesignTokens.of(context).text0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (meta.year != null) '${meta.year}',
                            if (meta.runtime != null) '${meta.runtime} 分钟',
                            if (meta.rating != null)
                              '★ ${meta.rating!.toStringAsFixed(1)}',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: DesignTokens.of(context).text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.meta});
  final VideoMetadata meta;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final poster = meta.localPosterUrl ?? meta.posterUrl;
    return GestureDetector(
      onTap: () => _open(context, meta),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DesignTokens.radius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Image(url: poster, fallbackColor: t.insetBg),
                    if (meta.rating != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '★ ${meta.rating!.toStringAsFixed(1)}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              meta.title ?? meta.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t.text0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (meta.year != null) '${meta.year}',
                if (meta.resolution != null) meta.resolution!,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: t.text2),
            ),
          ],
        ),
      ),
    );
  }
}

void _open(BuildContext context, VideoMetadata meta) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => FilmDetailSheet(meta: meta),
  );
}

/// 兼容 NetworkImage / file:// / 缺图三种来源。无图时画一个占位色块。
class _Image extends StatelessWidget {
  const _Image({required this.url, required this.fallbackColor});
  final String? url;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        color: fallbackColor,
        alignment: Alignment.center,
        child: Icon(
          Icons.movie_outlined,
          color: DesignTokens.of(context).text3,
          size: 28,
        ),
      );
    }
    if (url!.startsWith('file://')) {
      return Image.file(
        File(url!.substring(7)),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(color: fallbackColor),
      );
    }
    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(color: fallbackColor),
      loadingBuilder: (_, c, p) =>
          p == null ? c : Container(color: fallbackColor),
    );
  }
}

/// 一行小封面 + 进度（继续观看 strip 占位）。
class ContinueStripItem extends StatelessWidget {
  const ContinueStripItem({
    required this.meta,
    required this.progress,
    super.key,
  });

  final VideoMetadata meta;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return SizedBox(
      width: 230,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DesignTokens.radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Image(
                    url: meta.backdropUrl ?? meta.localPosterUrl,
                    fallbackColor: t.insetBg,
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: AppProgressBar(value: progress, height: 3),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            meta.title ?? meta.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: t.text0,
            ),
          ),
        ],
      ),
    );
  }
}
