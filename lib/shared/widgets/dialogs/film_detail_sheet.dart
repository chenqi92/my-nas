import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/pt_sites/presentation/providers/pt_site_provider.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_player_page.dart';
import 'package:my_nas/features/video/presentation/providers/video_detail_provider.dart';
import 'package:my_nas/features/video/presentation/providers/video_history_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/cast/cast_device_sheet.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';

/// 设计稿 dialogs.jsx 中 FilmDetail：影视详情 sheet（720x90vh）。
///
/// 现阶段从 [VideoMetadata] 取数据铺 hero + 简介 + 操作按钮 + tabs
/// （版本 / 演职员 / 相关）。多版本列表与剧集分集网格留作后续，由
/// `videoDetailProvider` 提供详细数据。
class FilmDetailSheet extends ConsumerStatefulWidget {
  const FilmDetailSheet({required this.meta, super.key});

  final VideoMetadata meta;

  @override
  ConsumerState<FilmDetailSheet> createState() => _FilmDetailSheetState();
}

class _FilmDetailSheetState extends ConsumerState<FilmDetailSheet> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final m = widget.meta;
    final isTv = (m.seasonNumber ?? 0) > 0;
    final tabs = isTv
        ? [
            l.filmDetailTabSeasons,
            l.filmDetailTabVersions,
            l.filmDetailTabCast,
            l.filmDetailTabRelated,
          ]
        : [
            l.filmDetailTabVersions,
            l.filmDetailTabCast,
            l.filmDetailTabRelated,
          ];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 800),
        child: GlassPanel(
          strong: true,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Hero(meta: m, onClose: () => Navigator.of(context).pop(), t: t),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (m.overview != null) ...[
                        Text(
                          m.overview!,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: t.text1,
                            height: 1.65,
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      _Actions(meta: m),
                      const SizedBox(height: 16),
                      _TabBar(
                        tabs: tabs,
                        current: _tab,
                        onTap: (i) => setState(() => _tab = i),
                        t: t,
                      ),
                      const SizedBox(height: 14),
                      _tabBody(isTv, _tab, t),
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

  Widget _tabBody(bool isTv, int index, DesignTokens t) {
    final m = widget.meta;
    // 非剧集时无 “剧集” tab，整体索引前移一位。
    final logical = isTv ? index : index + 1;
    switch (logical) {
      case 0:
        return _Seasons(meta: m, t: t);
      case 1:
        return _Versions(meta: m, t: t);
      case 2:
        return _Cast(meta: m, t: t);
      case 3:
        return _Related(t: t);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.meta, required this.onClose, required this.t});
  final VideoMetadata meta;
  final VoidCallback onClose;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final backdrop = meta.backdropUrl ?? meta.localPosterUrl ?? meta.posterUrl;
    return SizedBox(
      height: 220,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _FsImage(url: backdrop, fallbackColor: t.bgStrong),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0x260A0A0E),
                  const Color(0x4D0A0A0E),
                  t.panelBgStrong,
                ],
                stops: const [0.02, 0.45, 0.98],
              ),
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: IconButton(
              onPressed: onClose,
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 18,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.45),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    if (meta.hdrFormat != null) AppTag(meta.hdrFormat!),
                    if (meta.resolution != null) AppTag(meta.resolution!),
                    if (meta.videoCodec != null) AppTag(meta.videoCodec!),
                    for (final g in meta.genreList.take(3))
                      if (g.trim().isNotEmpty) AppTag(g.trim()),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  meta.title ?? meta.fileName,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (meta.rating != null)
                      _stat(
                        Icons.star_rounded,
                        meta.rating!.toStringAsFixed(1),
                        color: t.warn,
                      ),
                    if (meta.year != null) _stat(null, '${meta.year}'),
                    if (meta.director != null && meta.director!.isNotEmpty)
                      _stat(null, meta.director!),
                    if (meta.runtime != null)
                      _stat(null, l.filmDetailRuntimeMinutes(meta.runtime!)),
                    if (meta.countries != null && meta.countries!.isNotEmpty)
                      _stat(null, meta.countries!),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData? icon, String text, {Color? color}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[
        Icon(icon, color: color ?? Colors.white, size: 14),
        const SizedBox(width: 4),
      ],
      Text(
        text,
        style: TextStyle(
          color: color ?? Colors.white.withValues(alpha: 0.82),
          fontSize: 12.5,
          fontWeight: icon != null ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ],
  );
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.meta});
  final VideoMetadata meta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final quality = meta.resolution ?? meta.hdrFormat;
    final playLabel =
        (meta.isWatched ? l.filmDetailContinuePlay : l.filmDetailPlay) +
        (quality != null ? ' · $quality' : '');
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => _play(context, ref),
          icon: const Icon(Icons.play_arrow_rounded, size: 16),
          label: Text(playLabel),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final watched = await toggleWatchedStatus(ref, meta.filePath);
            if (context.mounted) {
              context.showSuccessToast(
                watched
                    ? l.filmDetailMarkedWatched
                    : l.filmDetailMarkedUnwatched,
              );
            }
          },
          icon: Icon(
            meta.isWatched
                ? Icons.visibility_off_outlined
                : Icons.check_circle_outline,
            size: 15,
          ),
          label: Text(
            meta.isWatched
                ? l.filmDetailMarkUnwatched
                : l.filmDetailMarkWatched,
          ),
        ),
        OutlinedButton.icon(
          onPressed: () {
            final keyword = meta.title ?? meta.fileName;
            final router = GoRouter.of(context);
            ref.read(ptPendingSearchProvider.notifier).state = keyword;
            Navigator.of(context).pop();
            router.go('/pt');
          },
          icon: const Icon(Icons.travel_explore_rounded, size: 15),
          label: Text(l.filmDetailSearchPt),
        ),
        IconButton(
          onPressed: () => showAdaptiveModalSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (ctx) => CastDeviceSheet(
              onDeviceSelected: (_) => Navigator.of(ctx).pop(),
            ),
          ),
          icon: const Icon(Icons.cast_rounded, size: 16),
          tooltip: l.filmDetailCast,
        ),
      ],
    );
  }

  Future<void> _play(BuildContext context, WidgetRef ref) =>
      playVideoMetadata(context, ref, meta, closeSheet: true);
}

/// 取流并打开播放器。[closeSheet] 为 true 时先关闭当前详情弹窗再 push 播放器。
/// 供影视库 hero 主按钮与详情弹窗共用，避免重复取流逻辑。
Future<void> playVideoMetadata(
  BuildContext context,
  WidgetRef ref,
  VideoMetadata meta, {
  bool closeSheet = false,
}) async {
  final l = AppLocalizations.of(context);
  final connection = ref.read(activeConnectionsProvider)[meta.sourceId];
  if (connection == null) {
    context.showErrorToast(l.filmDetailSourceNotConnected);
    return;
  }
  try {
    final url = await connection.adapter.fileSystem.getFileUrl(meta.filePath);
    if (!context.mounted) return;
    final videoItem = VideoItem(
      name: meta.displayTitle,
      path: meta.filePath,
      url: url,
      sourceId: meta.sourceId,
      thumbnailUrl: meta.displayPosterUrl,
    );
    if (closeSheet) Navigator.of(context).pop();
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerPage(video: videoItem),
      ),
    );
  } on Object catch (e) {
    if (context.mounted) {
      context.showErrorToast(l.filmDetailPlayFailed(e.toString()));
    }
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.tabs,
    required this.current,
    required this.onTap,
    required this.t,
  });

  final List<String> tabs;
  final int current;
  final ValueChanged<int> onTap;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: t.hairline)),
    ),
    child: Row(
      children: [
        for (var i = 0; i < tabs.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: InkWell(
              onTap: () => onTap(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: i == current ? t.accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: i == current ? t.text0 : t.text2,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _Versions extends StatelessWidget {
  const _Versions({required this.meta, required this.t});
  final VideoMetadata meta;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.cardBg,
        border: Border.all(color: t.cardBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.dns_outlined, color: t.accent, size: 17),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      meta.sourceId,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.text0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppTag(l.filmDetailDefault, variant: TagVariant.free),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  meta.filePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: t.text2,
                    fontFamily: 'SF Mono',
                    fontFamilyFallback: const ['Menlo'],
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 6,
            children: [
              if (meta.resolution != null) AppTag(meta.resolution!),
              if (meta.hdrFormat != null) AppTag(meta.hdrFormat!),
              if (meta.videoCodec != null) AppTag(meta.videoCodec!),
              if (meta.fileSize != null)
                AppTag(_fmtSize(meta.fileSize!), variant: TagVariant.neutral),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtSize(int bytes) {
    if (bytes > 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}

class _Cast extends StatelessWidget {
  const _Cast({required this.meta, required this.t});
  final VideoMetadata meta;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cast = (meta.cast ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (cast.isEmpty) {
      return Text(
        l.filmDetailNoCast,
        style: TextStyle(fontSize: 12.5, color: t.text2),
      );
    }
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        for (final name in cast.take(18))
          SizedBox(
            width: 88,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: t.insetBg,
                    ),
                    child: Icon(Icons.person_outline_rounded, color: t.text3),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.text1,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Related extends StatelessWidget {
  const _Related({required this.t});
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      alignment: Alignment.center,
      child: Text(
        l.filmDetailRelatedHint,
        style: TextStyle(fontSize: 12.5, color: t.text2),
      ),
    );
  }
}

/// 剧集分季/分集：按 TMDB ID（或剧目录）查本地分集，季 chip + 集列表，
/// 点击集直接播放。数据来自 localEpisodeFilesProvider。
class _Seasons extends ConsumerStatefulWidget {
  const _Seasons({required this.meta, required this.t});
  final VideoMetadata meta;
  final DesignTokens t;

  @override
  ConsumerState<_Seasons> createState() => _SeasonsState();
}

class _SeasonsState extends ConsumerState<_Seasons> {
  int? _season;

  Widget _hint(String text) => Container(
    padding: const EdgeInsets.symmetric(vertical: 22),
    alignment: Alignment.center,
    child: Text(text, style: TextStyle(fontSize: 12.5, color: widget.t.text2)),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final m = widget.meta;
    final t = widget.t;
    final AsyncValue<Map<int, Map<int, VideoMetadata>>> episodesAsync;
    if (m.tmdbId != null) {
      episodesAsync = ref.watch(localEpisodeFilesProvider(m.tmdbId!));
    } else if (m.showDirectory != null && m.showDirectory!.isNotEmpty) {
      episodesAsync = ref.watch(
        localEpisodesByShowDirProvider(m.showDirectory!),
      );
    } else {
      return _hint(l.filmDetailSeasonsNoLocator);
    }

    return episodesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _hint(l.filmDetailSeasonsLoadFailed(e.toString())),
      data: (seasons) {
        if (seasons.isEmpty) return _hint(l.filmDetailSeasonsEmpty);
        final seasonNums = seasons.keys.toList()..sort();
        final sel = (_season != null && seasons.containsKey(_season))
            ? _season!
            : (seasonNums.contains(m.seasonNumber)
                  ? m.seasonNumber!
                  : seasonNums.first);
        final eps = (seasons[sel] ?? const {}).entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (seasonNums.length > 1)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in seasonNums)
                    AppChip(
                      label: l.filmDetailSeasonLabel(s),
                      active: s == sel,
                      compact: true,
                      onTap: () => setState(() => _season = s),
                    ),
                ],
              ),
            if (seasonNums.length > 1) const SizedBox(height: 14),
            for (final entry in eps)
              _EpisodeRow(ep: entry.key, meta: entry.value, t: t),
          ],
        );
      },
    );
  }
}

class _EpisodeRow extends ConsumerWidget {
  const _EpisodeRow({required this.ep, required this.meta, required this.t});
  final int ep;
  final VideoMetadata meta;
  final DesignTokens t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => playVideoMetadata(context, ref, meta, closeSheet: true),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.hairline)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '$ep',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.text2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  meta.episodeTitle?.isNotEmpty ?? false
                      ? meta.episodeTitle!
                      : l.filmDetailEpisodeLabel(ep),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.text0,
                  ),
                ),
              ),
              if (meta.isWatched) ...[
                Icon(Icons.check_circle, size: 15, color: t.ok),
                const SizedBox(width: 8),
              ],
              Icon(Icons.play_arrow_rounded, size: 18, color: t.accentBright),
            ],
          ),
        ),
      ),
    );
  }
}

class _FsImage extends StatelessWidget {
  const _FsImage({required this.url, required this.fallbackColor});
  final String? url;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(color: fallbackColor);
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
    );
  }
}
