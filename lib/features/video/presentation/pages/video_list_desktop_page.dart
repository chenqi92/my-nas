import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/video_scanner_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart'
    show VideoListLoaded, VideoListLoading, VideoTab, videoListProvider;
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';
import 'package:my_nas/shared/widgets/dialogs/film_detail_sheet.dart';

/// 影视库桌面筛选谓词（纯函数，便于测试）。
///
/// [watched]：`all` 不限 / `watched` 仅已看 / `unwatched` 仅未看。
/// [genres]：为空表示不限类型；非空时只要命中其一即通过。
/// [sources]：为空表示不限数据源；非空时仅保留属于所选 sourceId 的条目。
bool videoMatchesFilter(
  VideoMetadata m, {
  required String watched,
  required Set<String> genres,
  Set<String> sources = const {},
}) {
  if (watched == 'watched' && !m.isWatched) return false;
  if (watched == 'unwatched' && m.isWatched) return false;
  if (genres.isNotEmpty && !m.genreList.any(genres.contains)) return false;
  if (sources.isNotEmpty && !sources.contains(m.sourceId)) return false;
  return true;
}

/// 影视库扫描 / 刮削进度（订阅 [VideoScannerService.progressStream]），
/// 供页面顶部进度条展示。
final _videoScanProgressProvider = StreamProvider<VideoScanProgress?>(
  (ref) => VideoScannerService().progressStream,
);

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
    final l = AppLocalizations.of(context);

    return DesktopPageScaffold(
      title: l.videoPageTitle,
      subtitle: l.videoPageSubtitle,
      actions: AppSegmented<String>(
        value: _view,
        onChanged: (v) => setState(() => _view = v),
        dense: true,
        options: [
          AppSegmentedOption(
            value: 'grid',
            label: l.videoPageViewGrid,
            icon: Icons.grid_view_rounded,
          ),
          AppSegmentedOption(
            value: 'list',
            label: l.videoPageViewList,
            icon: Icons.view_list_rounded,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ScanProgressBanner(),
          switch (state) {
            VideoListLoading() => _Loading(t: t),
            VideoListLoaded(:final totalCount) when totalCount == 0 =>
              DesktopComingSoon(
                icon: Icons.movie_outlined,
                message: l.videoPageEmptyLibraryHint,
              ),
            VideoListLoaded() => _Loaded(state: state, view: _view),
            _ => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}

/// 影视库顶部扫描 / 刮削进度条。无进行中任务时不占位。
class _ScanProgressBanner extends ConsumerWidget {
  const _ScanProgressBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(_videoScanProgressProvider).valueOrNull;
    if (scan == null ||
        scan.phase == VideoScanPhase.completed ||
        scan.phase == VideoScanPhase.error) {
      return const SizedBox.shrink();
    }
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final isScraping = scan.phase == VideoScanPhase.scraping;
    final label = isScraping ? l.actAggGroupScrape : l.actAggGroupScan;
    final detail = scan.currentFile ?? scan.currentPath ?? '';
    final countText = scan.totalCount > 0
        ? '${scan.scannedCount}/${scan.totalCount}'
        : '';
    final progress = scan.progress > 0 ? scan.progress : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: t.cardBg,
          border: Border.all(color: t.cardBorder),
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.accentBright,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  isScraping
                      ? Icons.auto_fix_high_rounded
                      : Icons.image_search_rounded,
                  size: 15,
                  color: t.accentBright,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.text0,
                  ),
                ),
                if (countText.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    countText,
                    style: TextStyle(fontSize: 12, color: t.text2),
                  ),
                ],
                if (detail.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12, color: t.text2),
                    ),
                  ),
                ] else
                  const Spacer(),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: t.insetBg,
                  valueColor: AlwaysStoppedAnimation<Color>(t.accentBright),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.t});
  final DesignTokens t;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 80),
      alignment: Alignment.center,
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(
            l.videoPageScanningHint,
            style: TextStyle(color: t.text2, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _Loaded extends ConsumerStatefulWidget {
  const _Loaded({required this.state, required this.view});
  final VideoListLoaded state;
  final String view;

  @override
  ConsumerState<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends ConsumerState<_Loaded> {
  // 排序仅影响网格展示，属纯前端表现层状态，本地维护即可（默认评分降序）。
  String _sort = 'rating';

  // 筛选同样是纯前端表现层状态：在 provider 的 tab/搜索结果之上再做过滤。
  // _watched: all | watched | unwatched。
  String _watched = 'all';
  final Set<String> _genres = {};
  final Set<String> _sources = {};

  bool get _hasFilter =>
      _watched != 'all' || _genres.isNotEmpty || _sources.isNotEmpty;

  List<VideoMetadata> _applyFilter(List<VideoMetadata> input) => input
      .where(
        (m) => videoMatchesFilter(
          m,
          watched: _watched,
          genres: _genres,
          sources: _sources,
        ),
      )
      .toList();

  Future<void> _openFilter(
    List<String> allGenres,
    List<(String, String)> sourceOptions,
  ) async {
    final l = AppLocalizations.of(context);
    final result = await showAdaptiveSheet<(String, Set<String>, Set<String>)>(
      context: context,
      title: l.videoFilterTitle,
      size: AdaptiveSheetSize.small,
      builder: (ctx, _) => _VideoFilterContent(
        watched: _watched,
        genres: _genres,
        sources: _sources,
        allGenres: allGenres,
        sourceOptions: sourceOptions,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _watched = result.$1;
        _genres
          ..clear()
          ..addAll(result.$2);
        _sources
          ..clear()
          ..addAll(result.$3);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final view = widget.view;
    final notifier = ref.read(videoListProvider.notifier);
    final l = AppLocalizations.of(context);

    final tabs = <(String, VideoTab)>[
      (l.videoPageTabAll, VideoTab.all),
      (l.videoPageTabMovies, VideoTab.movies),
      (l.videoPageTabTvShows, VideoTab.tvShows),
      (l.videoPageTabOther, VideoTab.other),
      (l.videoPageTabRecent, VideoTab.recent),
    ];

    // Hero 用最高分（topRated）第一项，没有时退到 recent / movies 第一项。
    final hero = state.topRatedMovies.isNotEmpty
        ? state.topRatedMovies.first
        : state.recentVideos.isNotEmpty
        ? state.recentVideos.first
        : state.movies.isNotEmpty
        ? state.movies.first
        : null;

    // 当前 tab/搜索结果中出现过的全部类型，供筛选弹框列出。
    final allGenres =
        (state.filteredMetadata.expand((m) => m.genreList).toSet().toList()
          ..sort());

    // 数据源名称映射 + 库内出现过的数据源（用于源筛选与多源标识）。
    final sourceList =
        ref.watch(sourcesProvider).valueOrNull ?? const <SourceEntity>[];
    final sourceNames = {for (final s in sourceList) s.id: s.displayName};
    final presentSourceIds = state.filteredMetadata
        .map((m) => m.sourceId)
        .toSet();
    final sourceOptions =
        presentSourceIds.map((id) => (id, sourceNames[id] ?? id)).toList()
          ..sort((a, b) => a.$2.compareTo(b.$2));
    // 仅当库横跨多个数据源时才在卡片上标注来源，单源时不加噪。
    final badgeNames = presentSourceIds.length > 1
        ? sourceNames
        : const <String, String>{};

    final items = _applyFilter(state.filteredMetadata)
      ..sort((a, b) {
        if (_sort == 'year') {
          return (b.year ?? 0).compareTo(a.year ?? 0);
        }
        return (b.rating ?? 0).compareTo(a.rating ?? 0);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hero != null) ...[_Hero(meta: hero), const SizedBox(height: 22)],
        Row(
          children: [
            for (final (label, tab) in tabs)
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
            SizedBox(
              width: 220,
              child: _VideoSearchField(
                initial: state.searchQuery,
                onChanged: notifier.setSearchQuery,
              ),
            ),
            const SizedBox(width: 8),
            AppSegmented<String>(
              value: _sort,
              dense: true,
              onChanged: (v) => setState(() => _sort = v),
              options: [
                AppSegmentedOption(
                  value: 'rating',
                  label: l.videoPageSortRating,
                ),
                AppSegmentedOption(value: 'year', label: l.videoPageSortYear),
              ],
            ),
            const SizedBox(width: 8),
            _FilterIconButton(
              active: _hasFilter,
              onTap: () => _openFilter(allGenres, sourceOptions),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          _FilteredEmpty(
            message: state.searchQuery.isNotEmpty
                ? l.videoSearchNoResults(state.searchQuery)
                : l.videoPageEmptyLibraryHint,
            onReset: _hasFilter ? _resetFilter : null,
          )
        else if (view == 'grid')
          _PosterGrid(items: items, sourceNames: badgeNames)
        else
          _PosterList(items: items, sourceNames: badgeNames),
      ],
    );
  }

  void _resetFilter() {
    setState(() {
      _watched = 'all';
      _genres.clear();
      _sources.clear();
    });
  }
}

/// 设计稿 `.icon-btn`：32×32 透明底图标按钮，hover 浅底。点击弹出筛选弹框，
/// [active] 为真时右上角显示强调小圆点表示有生效的筛选。
class _FilterIconButton extends StatelessWidget {
  const _FilterIconButton({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.tune_rounded,
                size: 17,
                color: active ? t.accentBright : t.text2,
              ),
              if (active)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: t.accentBright,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 筛选 / 搜索后无结果时的占位（有生效筛选时提供一键重置）。
class _FilteredEmpty extends StatelessWidget {
  const _FilteredEmpty({required this.message, required this.onReset});
  final String message;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.filter_alt_off_outlined, size: 40, color: t.text2),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.text2, fontSize: 13),
          ),
          if (onReset != null) ...[
            const SizedBox(height: 14),
            AppButton(
              label: l.videoFilterReset,
              dense: true,
              onPressed: onReset,
            ),
          ],
        ],
      ),
    );
  }
}

/// 桌面影视库搜索框：输入防抖 300ms 后回调 [onChanged]，清空时立即回调空串。
class _VideoSearchField extends StatefulWidget {
  const _VideoSearchField({required this.initial, required this.onChanged});
  final String initial;
  final void Function(String query) onChanged;

  @override
  State<_VideoSearchField> createState() => _VideoSearchFieldState();
}

class _VideoSearchFieldState extends State<_VideoSearchField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => widget.onChanged(v.trim()),
    );
    setState(() {}); // 刷新清空按钮显隐
  }

  void _clear() {
    _debounce?.cancel();
    _ctrl.clear();
    widget.onChanged('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      borderSide: BorderSide(color: t.cardBorder),
    );
    return SizedBox(
      height: 34,
      child: TextField(
        controller: _ctrl,
        onChanged: _onChanged,
        style: TextStyle(fontSize: 13, color: t.text0),
        cursorColor: t.accentBright,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: t.cardBg,
          hintText: l.videoSearchHint,
          hintStyle: TextStyle(fontSize: 13, color: t.text2),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          prefixIcon: Icon(Icons.search_rounded, size: 16, color: t.text2),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          suffixIcon: _ctrl.text.isEmpty
              ? null
              : IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 30),
                  iconSize: 14,
                  icon: Icon(Icons.close_rounded, color: t.text2),
                  onPressed: _clear,
                ),
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            borderSide: BorderSide(color: t.accentBright),
          ),
        ),
      ),
    );
  }
}

/// 影视筛选弹框内容：观看状态（全部/未看/已看）+ 类型多选。
/// 点击「应用」以 `(watched, genres)` 记录形式 pop；「重置」清空。
class _VideoFilterContent extends StatefulWidget {
  const _VideoFilterContent({
    required this.watched,
    required this.genres,
    required this.sources,
    required this.allGenres,
    required this.sourceOptions,
  });

  final String watched;
  final Set<String> genres;
  final Set<String> sources;
  final List<String> allGenres;

  /// (sourceId, displayName) 列表，仅当多于一个时展示数据源筛选。
  final List<(String, String)> sourceOptions;

  @override
  State<_VideoFilterContent> createState() => _VideoFilterContentState();
}

class _VideoFilterContentState extends State<_VideoFilterContent> {
  late String _watched = widget.watched;
  late final Set<String> _genres = {...widget.genres};
  late final Set<String> _sources = {...widget.sources};

  Widget _sectionLabel(DesignTokens t, String text) => Text(
    text,
    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.text1),
  );

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sectionLabel(t, l.videoFilterWatchStatus),
        const SizedBox(height: 10),
        AppSegmented<String>(
          value: _watched,
          dense: true,
          onChanged: (v) => setState(() => _watched = v),
          options: [
            AppSegmentedOption(value: 'all', label: l.videoPageTabAll),
            AppSegmentedOption(
              value: 'unwatched',
              label: l.videoFilterUnwatched,
            ),
            AppSegmentedOption(value: 'watched', label: l.videoFilterWatched),
          ],
        ),
        const SizedBox(height: 20),
        _sectionLabel(t, l.videoFilterGenre),
        const SizedBox(height: 10),
        if (widget.allGenres.isEmpty)
          Text(
            l.videoFilterNoGenres,
            style: TextStyle(fontSize: 12, color: t.text2),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in widget.allGenres)
                AppChip(
                  label: g,
                  compact: true,
                  active: _genres.contains(g),
                  onTap: () => setState(() {
                    if (!_genres.add(g)) _genres.remove(g);
                  }),
                ),
            ],
          ),
        if (widget.sourceOptions.length > 1) ...[
          const SizedBox(height: 20),
          _sectionLabel(t, l.videoFilterSource),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (id, name) in widget.sourceOptions)
                AppChip(
                  label: name,
                  compact: true,
                  active: _sources.contains(id),
                  onTap: () => setState(() {
                    if (!_sources.add(id)) _sources.remove(id);
                  }),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: l.videoFilterReset,
              variant: AppButtonVariant.ghost,
              dense: true,
              onPressed: () => setState(() {
                _watched = 'all';
                _genres.clear();
                _sources.clear();
              }),
            ),
            const SizedBox(width: 10),
            AppButton(
              label: l.videoFilterApply,
              variant: AppButtonVariant.primary,
              dense: true,
              onPressed: () =>
                  Navigator.of(context).pop((_watched, _genres, _sources)),
            ),
          ],
        ),
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 300),
          child: Stack(
            alignment: AlignmentDirectional.bottomStart,
            children: [
              Positioned.fill(
                child: _Image(url: backdrop, fallbackColor: t.bgStrong),
              ),
              Positioned.fill(
                child: Container(
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
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(44, 40, 44, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        spacing: 8,
                        children: [
                          if (meta.hdrFormat != null) AppTag(meta.hdrFormat!),
                          if (meta.resolution != null) AppTag(meta.resolution!),
                          if (meta.videoCodec != null) AppTag(meta.videoCodec!),
                          for (final g in meta.genreList.take(3))
                            if (g.trim().isNotEmpty) AppTag(g.trim()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      meta.title ?? meta.fileName,
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.84,
                        shadows: [
                          Shadow(color: Colors.black87, blurRadius: 14),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _HeroMeta(meta: meta),
                    const SizedBox(height: 16),
                    if (meta.overview != null) ...[
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
                      const SizedBox(height: 20),
                    ],
                    _HeroActions(meta: meta),
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

/// 设计稿 `.hero-meta`：★ 评分(accent 粗) · 年份 · 类型 · 时长，以 `·` 间隔。
class _HeroMeta extends StatelessWidget {
  const _HeroMeta({required this.meta});
  final VideoMetadata meta;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    const muted = Color(0xFFD9D9DC);
    final segs = <Widget>[];

    if (meta.rating != null) {
      segs.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, color: t.accentBright, size: 16),
            const SizedBox(width: 4),
            Text(
              meta.rating!.toStringAsFixed(1),
              style: TextStyle(
                color: t.accentBright,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    if (meta.year != null) {
      segs.add(
        Text(
          '${meta.year}',
          style: const TextStyle(color: muted, fontSize: 13),
        ),
      );
    }
    final genre = meta.genreList.take(2).join(' / ');
    if (genre.isNotEmpty) {
      segs.add(Text(genre, style: const TextStyle(color: muted, fontSize: 13)));
    }
    final runtime = meta.runtimeText;
    if (runtime.isNotEmpty) {
      segs.add(
        Text(runtime, style: const TextStyle(color: muted, fontSize: 13)),
      );
    }

    final children = <Widget>[];
    for (var i = 0; i < segs.length; i++) {
      if (i > 0) {
        children.add(
          Text(
            '·',
            style: TextStyle(color: muted.withValues(alpha: 0.6), fontSize: 13),
          ),
        );
      }
      children.add(segs[i]);
    }
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

/// 设计稿 `.hero-actions`：主按钮（继续观看/播放/重新播放）+ 描边「详情」。
class _HeroActions extends ConsumerWidget {
  const _HeroActions({required this.meta});
  final VideoMetadata meta;

  /// 由播放位置 ticks（10M/秒）与片长（分钟）派生续播百分比；任一缺失返回 null。
  int? get _progressPct {
    final ticks = meta.playbackPositionTicks;
    final runtime = meta.runtime;
    if (ticks == null || ticks <= 0 || runtime == null || runtime <= 0) {
      return null;
    }
    final watchedSec = ticks / 10000000;
    final totalSec = runtime * 60;
    return (watchedSec / totalSec * 100).round();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final pct = _progressPct;
    // 已看完（≥95%）或标记已看 → 重新播放；进行中（1~94%）→ 继续观看；否则播放。
    final String label;
    if (meta.isWatched || (pct != null && pct >= 95)) {
      label = l.videoPageActionReplay;
    } else if (pct != null && pct >= 1) {
      label = l.videoPageActionResume(pct);
    } else {
      label = l.videoPageActionPlay;
    }
    return Row(
      children: [
        _HeroButton(
          label: label,
          icon: Icons.play_arrow_rounded,
          variant: _HeroBtnVariant.primary,
          onTap: () => playVideoMetadata(context, ref, meta),
        ),
        const SizedBox(width: 12),
        _HeroButton(
          label: l.videoPageActionDetails,
          icon: Icons.add_rounded,
          variant: _HeroBtnVariant.outline,
          onTap: () => _open(context, meta),
        ),
      ],
    );
  }
}

enum _HeroBtnVariant { primary, outline, ghost }

class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.icon,
    required this.variant,
    required this.onTap,
    this.label,
  });

  final IconData icon;
  final _HeroBtnVariant variant;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final Color bg;
    final Color fg;
    final Border? border;
    final FontWeight weight;
    switch (variant) {
      case _HeroBtnVariant.primary:
        bg = t.accent;
        fg = t.accentContrast;
        border = null;
        weight = FontWeight.w600;
      case _HeroBtnVariant.outline:
        bg = Colors.transparent;
        fg = Colors.white;
        border = Border.all(color: t.cardBorder);
        weight = FontWeight.w500;
      case _HeroBtnVariant.ghost:
        bg = Colors.transparent;
        fg = Colors.white;
        border = null;
        weight = FontWeight.w500;
    }

    final iconOnly = label == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        child: Container(
          padding: iconOnly
              ? const EdgeInsets.all(8)
              : const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            border: border,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              if (!iconOnly) ...[
                const SizedBox(width: 7),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: weight,
                    color: fg,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterGrid extends StatelessWidget {
  const _PosterGrid({required this.items, required this.sourceNames});
  final List<VideoMetadata> items;

  /// sourceId → 展示名。为空表示不在卡片上标注来源（单源库）。
  final Map<String, String> sourceNames;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (items.isEmpty) {
      return DesktopComingSoon(
        icon: Icons.search_off_rounded,
        message: l.videoPageCategoryEmpty,
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
        childAspectRatio: 0.62,
      ),
      itemBuilder: (_, i) => _PosterCard(
        key: ValueKey(items[i].uniqueKey),
        meta: items[i],
        sourceLabel: sourceNames[items[i].sourceId],
      ),
    );
  }
}

class _PosterList extends StatelessWidget {
  const _PosterList({required this.items, required this.sourceNames});
  final List<VideoMetadata> items;

  /// sourceId → 展示名。为空表示不在行内标注来源（单源库）。
  final Map<String, String> sourceNames;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (items.isEmpty) {
      return DesktopComingSoon(
        icon: Icons.search_off_rounded,
        message: l.videoPageCategoryEmpty,
      );
    }
    return Column(
      children: [
        for (final meta in items.take(120))
          Padding(
            key: ValueKey(meta.uniqueKey),
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
                        fallbackColor: DesignTokens.of(context).insetBg,
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
                            if (meta.runtime != null)
                              l.videoPageRuntimeMinutes(meta.runtime!),
                            if (meta.rating != null)
                              '★ ${meta.rating!.toStringAsFixed(1)}',
                            if (sourceNames[meta.sourceId] != null)
                              sourceNames[meta.sourceId]!,
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
  const _PosterCard({required this.meta, this.sourceLabel, super.key});
  final VideoMetadata meta;

  /// 多源库下展示的数据源名称；null 表示不标注。
  final String? sourceLabel;

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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(6),
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
                        ),
                      ),
                    if (sourceLabel != null)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        right: 8,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.dns_outlined,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      sourceLabel!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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
                fontSize: 13.5,
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
              style: TextStyle(fontSize: 11.5, color: t.text2),
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
    // 网络海报走磁盘缓存（VID-SCR-04），避免每次滚动重拉。
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 150),
      errorWidget: (_, _, _) => Container(color: fallbackColor),
      placeholder: (_, _) => Container(color: fallbackColor),
    );
  }
}
