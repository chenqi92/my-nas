import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/data/services/audio_effects_service.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/data/services/music_scrape_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/pages/listening_stats_page.dart';
import 'package:my_nas/features/music/presentation/pages/manual_music_scraper_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_scraper_sources_page.dart';
import 'package:my_nas/features/music/presentation/pages/playlist_detail_page.dart';
import 'package:my_nas/features/music/presentation/providers/desktop_lyric_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/playlist_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';

/// MusicTrackEntity（曲库 DB 行）→ MusicItem（播放器/收藏用）。
/// 复用 MusicFileWithSource.toMusicItem，保持与移动端一致的 nas:// URL 语义。
MusicItem _entityToMusicItem(MusicTrackEntity m) => MusicFileWithSource(
  file: FileItem(
    name: m.fileName,
    path: m.filePath,
    size: m.size ?? 0,
    isDirectory: false,
    modifiedTime: m.modifiedTime,
  ),
  sourceId: m.sourceId,
  title: m.title,
  artist: m.artist,
  album: m.album,
  duration: m.duration,
  year: m.year,
  genre: m.genre,
  coverPath: m.coverPath,
  metadataExtracted: true,
).toMusicItem();

/// 把 [tracks] 装入播放队列并从 [startIndex] 开始播放；[shuffle] 时切随机模式。
Future<void> _playFromList(
  WidgetRef ref,
  List<MusicTrackEntity> tracks,
  int startIndex, {
  bool shuffle = false,
}) async {
  if (tracks.isEmpty) return;
  final queue = tracks.map(_entityToMusicItem).toList();
  final controller = ref.read(musicPlayerControllerProvider.notifier);
  if (shuffle) controller.setPlayMode(PlayMode.shuffle);
  ref.read(playQueueProvider.notifier).setQueue(queue);
  final idx = startIndex.clamp(0, queue.length - 1);
  controller.updateCurrentIndex(idx);
  await controller.play(queue[idx]);
}

/// 桌面列表也提供移动端已有的单曲手动刮削能力。
Future<void> _openManualScraper(
  BuildContext context,
  WidgetRef ref,
  MusicTrackEntity track,
) async {
  final connection = ref.read(activeConnectionsProvider)[track.sourceId];
  if (connection == null || connection.status != SourceStatus.connected) {
    if (context.mounted) {
      context.showWarningToast(context.l10n.musicSourceNotConnected);
    }
    return;
  }

  try {
    final url = await connection.adapter.fileSystem.getFileUrl(track.filePath);
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManualMusicScraperPage(
          music: _entityToMusicItem(track).copyWith(url: url),
          fileSystem: connection.adapter.fileSystem,
        ),
      ),
    );

    await ref
        .read(musicListProvider.notifier)
        .refreshTrackMetadata(track.sourceId, track.filePath);
  } catch (error) {
    if (context.mounted) {
      context.showErrorToast(
        context.l10n.mediaLibraryScrapeErrorToast('$error'),
      );
    }
  }
}

/// 桌面端「音乐」——对齐设计稿 media2.jsx `MusicLibrary`。
///
/// 统计条（曲目/总时长/艺术家/专辑）+ 左歌曲表（播放全部/随机 + dense rows）
/// + 右 300px 侧栏（歌单 + 10 段 EQ）。歌曲/专辑/艺术家/文件夹 四视图。
class MusicListDesktopPage extends ConsumerStatefulWidget {
  const MusicListDesktopPage({super.key});

  @override
  ConsumerState<MusicListDesktopPage> createState() =>
      _MusicListDesktopPageState();
}

class _MusicListDesktopPageState extends ConsumerState<MusicListDesktopPage> {
  String _view = 'songs';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    ref.read(musicListProvider.notifier).setSearchQuery('');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(musicListProvider);
    final loaded = state is MusicListLoaded ? state : null;
    if (loaded != null && _searchController.text != loaded.searchQuery) {
      _searchController.value = TextEditingValue(
        text: loaded.searchQuery,
        selection: TextSelection.collapsed(offset: loaded.searchQuery.length),
      );
    }

    final subtitle = loaded != null
        ? l.musicPageSubtitleLoaded(loaded.totalCount, loaded.albumCount)
        : l.musicPageSubtitleDefault;

    return DesktopPageScaffold(
      title: l.musicPageTitle,
      subtitle: subtitle,
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 210,
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l.musicSearchHintShort,
                prefixIcon: const Icon(Icons.search_rounded, size: 17),
                suffixIcon: loaded?.searchQuery.isNotEmpty ?? false
                    ? IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).deleteButtonTooltip,
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(musicListProvider.notifier)
                              .setSearchQuery('');
                        },
                        icon: const Icon(Icons.close_rounded, size: 16),
                      )
                    : null,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  ref.read(musicListProvider.notifier).setSearchQuery(value),
            ),
          ),
          const SizedBox(width: 8),
          AppChip(
            label: l.paneAdvancedManageButton,
            icon: Icons.library_music_rounded,
            compact: true,
            onTap: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute<void>(
                builder: (_) => desktopMusicFullManagerPage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const _DesktopLyricChip(),
          const SizedBox(width: 8),
          AppChip(
            label: l.musicScraperSourcesPageTitle,
            icon: Icons.tune_rounded,
            compact: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MusicScraperSourcesPage(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          AppSegmented<String>(
            value: _view,
            onChanged: (v) => setState(() => _view = v),
            dense: true,
            options: [
              AppSegmentedOption(value: 'songs', label: l.musicPageTabSongs),
              AppSegmentedOption(value: 'albums', label: l.musicPageTabAlbums),
              AppSegmentedOption(
                value: 'artists',
                label: l.musicPageTabArtists,
              ),
              AppSegmentedOption(
                value: 'folders',
                label: l.musicPageTabFolders,
              ),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatRow(loaded: loaded),
          const SizedBox(height: 24),
          SizedBox(
            height: 540,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GlassPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: _MainView(state: state, view: _view),
                  ),
                ),
                const SizedBox(width: 24),
                const SizedBox(
                  width: 300,
                  child: SingleChildScrollView(child: _RightRail()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.loaded});
  final MusicListLoaded? loaded;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // 全库总时长用 getStats 全量统计（totalDurationMs），不再只累加首页 100 首。
    final totalMs = loaded?.totalDurationMs ?? 0;
    final hours = totalMs / 3600000;
    final hoursText = hours >= 1
        ? hours.toStringAsFixed(hours >= 10 ? 0 : 1)
        : (totalMs / 60000).toStringAsFixed(0);
    final hoursUnit = hours >= 1
        ? l.musicPageUnitHours
        : l.musicPageUnitMinutes;

    return Row(
      children: [
        Expanded(
          child: _Stat(
            value: '${loaded?.totalCount ?? 0}',
            unit: l.musicPageUnitTracks,
            label: l.musicPageStatTracks,
            icon: Icons.library_music_outlined,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Stat(
            value: hoursText,
            unit: hoursUnit,
            label: l.musicPageStatTotalDuration,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Stat(
            value: '${loaded?.artistCount ?? 0}',
            unit: l.musicPageUnitArtists,
            label: l.musicPageStatArtists,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Stat(
            value: l.musicPageStatAnnualReport,
            label: l.musicPageStatListeningStats,
            icon: Icons.insights_rounded,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ListeningStatsPage(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.unit,
    this.icon,
    this.onTap,
  });

  final String value;
  final String? unit;
  final String label;
  final IconData? icon;

  /// 可点击时（如「听歌统计」打开统计页）展示水波纹。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: t.cardBg,
            border: Border.all(color: t.cardBorder),
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: t.text0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (unit != null)
                      TextSpan(
                        text: ' $unit',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: t.text2,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 13, color: t.text2),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: t.text2),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainView extends StatelessWidget {
  const _MainView({required this.state, required this.view});
  final MusicListState state;
  final String view;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (state is MusicListLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state is MusicListError) {
      return _Empty(
        icon: Icons.error_outline_rounded,
        message: (state as MusicListError).message,
      );
    }
    final loaded = state is MusicListLoaded ? state as MusicListLoaded : null;
    if (loaded == null || loaded.allTracks.isEmpty) {
      return _Empty(
        icon: Icons.queue_music_rounded,
        message: l.musicPageEmptyHint,
      );
    }
    final tracks = desktopMusicDisplayTracks(loaded);
    if (tracks.isEmpty) {
      return _Empty(
        icon: Icons.search_off_rounded,
        message: loaded.searchQuery.isNotEmpty
            ? l.musicSearchResultNotFound(loaded.searchQuery)
            : l.musicPageEmptyHint,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TableHeader(view: view, tracks: tracks),
        Expanded(
          child: switch (view) {
            'albums' => _AlbumGrid(tracks: tracks),
            'artists' => _GroupList(tracks: tracks, byArtist: true),
            'folders' => _GroupList(tracks: tracks, byArtist: false),
            _ => _SongTable(
              tracks: tracks,
              hasMore: loaded.searchQuery.isEmpty && loaded.hasMoreTracks,
            ),
          },
        ),
      ],
    );
  }
}

/// 搜索、流派/年代/最近分类与完整曲目操作的原生管理页。
@visibleForTesting
MusicListPage desktopMusicFullManagerPage() => const MusicListPage();

/// 桌面表格必须使用已应用搜索和来源筛选的数据。
@visibleForTesting
List<MusicTrackEntity> desktopMusicDisplayTracks(MusicListLoaded loaded) =>
    loaded.filteredMetadata;

/// 桌面曲目菜单与重构前的完整操作集合。
@visibleForTesting
const desktopMusicTrackMenuActions = <String>{
  'play_next',
  'add_to_queue',
  'add_to_playlist',
  'manual_scrape',
  'remove_from_library',
  'delete_from_source',
};

Future<void> _handleDesktopTrackAction(
  BuildContext context,
  WidgetRef ref,
  MusicTrackEntity track,
  String action,
) async {
  final l = AppLocalizations.of(context);
  final item = _entityToMusicItem(track);
  switch (action) {
    case 'play_next':
      final queue = ref.read(playQueueProvider);
      if (queue.isEmpty) {
        ref.read(playQueueProvider.notifier).setQueue([item]);
        ref.read(musicPlayerControllerProvider.notifier).updateCurrentIndex(0);
        await ref.read(musicPlayerControllerProvider.notifier).play(item);
      } else {
        final player = ref.read(musicPlayerControllerProvider);
        final next = [...queue];
        next.insert((player.currentIndex + 1).clamp(0, next.length), item);
        ref.read(playQueueProvider.notifier).setQueue(next);
        if (context.mounted) {
          context.showSuccessToast(l.musicToastPlayNextSuccess);
        }
      }
    case 'add_to_queue':
      ref.read(playQueueProvider.notifier).addToQueue(item);
      context.showSuccessToast(l.musicToastQueueSuccess);
    case 'add_to_playlist':
      await _addDesktopTrackToPlaylist(context, ref, track);
    case 'manual_scrape':
      await _openManualScraper(context, ref, track);
    case 'remove_from_library':
      final confirmed = await _confirmDesktopTrackAction(
        context,
        title: l.musicRemoveFromLibraryTitle,
        content: l.musicRemoveFromLibraryContent(track.displayTitle),
        destructive: false,
      );
      if (!confirmed) return;
      final success = await ref
          .read(musicListProvider.notifier)
          .removeFromLibrary(
            track.sourceId,
            track.filePath,
            track.displayTitle,
          );
      if (context.mounted) {
        (success ? context.showSuccessToast : context.showErrorToast)(
          success
              ? l.musicRemoveFromLibrarySuccess
              : l.musicRemoveFromLibraryFailed,
        );
      }
    case 'delete_from_source':
      final confirmed = await _confirmDesktopTrackAction(
        context,
        title: l.musicDeleteSourceFileTitle,
        content: l.musicDeleteSourceFileContent(track.displayTitle),
        destructive: true,
      );
      if (!confirmed) return;
      final success = await ref
          .read(musicListProvider.notifier)
          .deleteFromSource(track.sourceId, track.filePath, track.displayTitle);
      if (context.mounted) {
        (success ? context.showSuccessToast : context.showErrorToast)(
          success
              ? l.musicDeleteSourceFileSuccess
              : l.musicDeleteSourceFileFailed,
        );
      }
  }
}

Future<bool> _confirmDesktopTrackAction(
  BuildContext context, {
  required String title,
  required String content,
  required bool destructive,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    ) ??
    false;

Future<void> _addDesktopTrackToPlaylist(
  BuildContext context,
  WidgetRef ref,
  MusicTrackEntity track,
) async {
  final l = AppLocalizations.of(context);
  final playlists = ref.read(playlistProvider).playlists;
  final selected = await showDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(l.musicAddToPlaylistTitle),
      children: [
        for (final playlist in playlists)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(playlist.id),
            child: Text(playlist.name),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(dialogContext).pop('__new__'),
          child: Row(
            children: [
              const Icon(Icons.add_rounded, size: 18),
              const SizedBox(width: 8),
              Text(l.musicAddToPlaylistNew),
            ],
          ),
        ),
      ],
    ),
  );
  if (selected == null || !context.mounted) return;
  final trackKey = '${track.sourceId}_${track.filePath}';
  if (selected == '__new__') {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.musicPlaylistCreateTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l.musicPlaylistNameHint),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l.musicPlaylistCreateAction),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await ref
        .read(playlistProvider.notifier)
        .createPlaylist(name: name, initialTracks: [trackKey]);
    if (context.mounted) {
      context.showSuccessToast(l.musicAddToPlaylistSuccess(name));
    }
    return;
  }
  final playlist = playlists.where((item) => item.id == selected).firstOrNull;
  await ref.read(playlistProvider.notifier).addToPlaylist(selected, trackKey);
  if (context.mounted && playlist != null) {
    context.showSuccessToast(l.musicAddToPlaylistSuccess(playlist.name));
  }
}

class _TableHeader extends ConsumerWidget {
  const _TableHeader({required this.view, required this.tracks});
  final String view;
  final List<MusicTrackEntity> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final title = switch (view) {
      'albums' => l.musicPageHeaderAlbums,
      'artists' => l.musicPageHeaderArtists,
      'folders' => l.musicPageHeaderFolders,
      _ => l.musicPageHeaderAllSongs,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: t.text0,
            ),
          ),
          const Spacer(),
          _BatchScrapeChip(tracks: tracks),
          const SizedBox(width: 8),
          AppChip(
            label: l.musicPagePlayAll,
            icon: Icons.play_arrow_rounded,
            compact: true,
            onTap: () => _playFromList(ref, tracks, 0),
          ),
          const SizedBox(width: 8),
          AppChip(
            label: l.musicPageShuffle,
            icon: Icons.shuffle_rounded,
            compact: true,
            onTap: () => _playFromList(ref, tracks, 0, shuffle: true),
          ),
        ],
      ),
    );
  }
}

class _DesktopLyricChip extends ConsumerWidget {
  const _DesktopLyricChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(desktopLyricProvider);
    return AppChip(
      label: state.isVisible
          ? l.nowPlayDesktopLyricOff
          : l.nowPlayDesktopLyricOn,
      icon: Icons.desktop_windows_outlined,
      compact: true,
      active: state.isVisible,
      onTap: state.isInitialized
          ? ref.read(desktopLyricProvider.notifier).toggle
          : null,
    );
  }
}

class _BatchScrapeChip extends ConsumerStatefulWidget {
  const _BatchScrapeChip({required this.tracks});

  final List<MusicTrackEntity> tracks;

  @override
  ConsumerState<_BatchScrapeChip> createState() => _BatchScrapeChipState();
}

class _BatchScrapeChipState extends ConsumerState<_BatchScrapeChip> {
  bool _running = false;
  bool _stopRequested = false;
  MusicScrapeStats? _stats;
  StreamSubscription<MusicScrapeStats>? _statsSubscription;

  @override
  void initState() {
    super.initState();
    _statsSubscription = MusicScrapeService().statsStream.listen((stats) {
      if (mounted) setState(() => _stats = stats);
    });
  }

  @override
  void dispose() {
    _statsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    final scraper = MusicScrapeService();
    if (_running || scraper.isScraping) {
      _stopRequested = true;
      scraper.stopScraping();
      return;
    }

    final l = AppLocalizations.of(context);
    if (widget.tracks.isEmpty) {
      context.showWarningToast(l.mediaLibraryMusicScrapeNoItemsToast);
      return;
    }

    final sourceIds = widget.tracks.map((track) => track.sourceId).toSet();
    final connections = ref.read(activeConnectionsProvider);
    final connectedSourceIds = sourceIds.where(
      (id) => connections[id]?.status == SourceStatus.connected,
    );
    if (connectedSourceIds.isEmpty) {
      context.showWarningToast(l.mediaLibraryMusicScrapeConnectionErrorToast);
      return;
    }

    setState(() {
      _running = true;
      _stopRequested = false;
      _stats = null;
    });
    context.showSuccessToast(
      l.mediaLibraryMusicScrapeStartToast(widget.tracks.length),
    );

    try {
      for (final sourceId in connectedSourceIds) {
        if (_stopRequested) break;
        final connection = connections[sourceId];
        if (connection == null) continue;
        await scraper.startScraping(
          sourceId: sourceId,
          pathPrefix: '',
          connection: connection,
        );
      }
      await ref.read(musicListProvider.notifier).loadMusic();
      if (mounted) {
        if (_stopRequested) {
          context.showWarningToast(l.musicScrapeProgressCancelled);
        } else {
          final stats = _stats;
          context.showSuccessToast(
            stats == null
                ? l.mediaLibraryScrapeCompleteToast
                : l.musicScrapeProgressCompleted(
                    stats.success,
                    stats.skip,
                    stats.fail,
                  ),
          );
        }
      }
    } on Exception catch (error) {
      if (mounted) {
        context.showErrorToast(l.mediaLibraryScrapeErrorToast('$error'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _stopRequested = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final running = _running || MusicScrapeService().isScraping;
    final stats = _stats;
    return AppChip(
      label: running
          ? stats == null
                ? l.mediaLibraryScrapingMenuLabel
                : l.musicScrapeProgressScrapingCount(
                    stats.processed,
                    stats.total,
                  )
          : l.mediaLibraryMusicBatchScrapeMenuLabel,
      icon: running ? Icons.stop_circle_outlined : Icons.auto_fix_high_rounded,
      compact: true,
      active: running,
      onTap: _toggle,
    );
  }
}

class _SongTable extends ConsumerWidget {
  const _SongTable({required this.tracks, required this.hasMore});
  final List<MusicTrackEntity> tracks;
  final bool hasMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      NotificationListener<ScrollNotification>(
        onNotification: (n) {
          // 触底前 300px 触发加载下一页（曲库分页 100 首/页）。
          if (hasMore && n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
            ref.read(musicListProvider.notifier).loadMoreTracks();
          }
          return false;
        },
        child: ListView.builder(
          itemCount: tracks.length,
          itemBuilder: (_, i) => _SongRow(
            track: tracks[i],
            index: i + 1,
            allTracks: tracks,
            position: i,
          ),
        ),
      );
}

class _SongRow extends ConsumerWidget {
  const _SongRow({
    required this.track,
    required this.index,
    required this.allTracks,
    required this.position,
  });
  final MusicTrackEntity track;
  final int index;
  final List<MusicTrackEntity> allTracks;
  final int position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final isFav =
        ref.watch(isMusicFavoriteProvider(track.filePath)).valueOrNull ?? false;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _playFromList(ref, allTracks, position),
        hoverColor: t.chipBg,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.hairline)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '$index',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: t.text3,
                    fontFamily: 'SF Mono',
                    fontFamilyFallback: const ['Menlo'],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              _Cover(
                path: track.displayCoverPath,
                label: track.displayTitle,
                size: 38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.displayTitle,
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
                      track.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: t.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: Text(
                  track.displayAlbum,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: t.text2),
                ),
              ),
              IconButton(
                onPressed: () => ref
                    .read(musicFavoritesProvider.notifier)
                    .toggleFavorite(_entityToMusicItem(track)),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  isFav
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 15,
                  color: isFav ? t.accentBright : t.text3,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: l.musicMoreActionTooltip,
                iconSize: 17,
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_horiz_rounded, color: t.text2),
                onSelected: (value) =>
                    _handleDesktopTrackAction(context, ref, track, value),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'play_next',
                    child: Row(
                      children: [
                        const Icon(Icons.skip_next_rounded, size: 18),
                        const SizedBox(width: 10),
                        Text(l.musicMenuPlayNext),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'add_to_queue',
                    child: Row(
                      children: [
                        const Icon(Icons.queue_music_rounded, size: 18),
                        const SizedBox(width: 10),
                        Text(l.musicMenuAddToQueue),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'add_to_playlist',
                    child: Row(
                      children: [
                        const Icon(Icons.playlist_add_rounded, size: 18),
                        const SizedBox(width: 10),
                        Text(l.musicMenuAddToPlaylist),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'manual_scrape',
                    child: Row(
                      children: [
                        const Icon(Icons.auto_fix_high_rounded, size: 18),
                        const SizedBox(width: 10),
                        Text(l.musicMenuManualScrape),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'remove_from_library',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.remove_circle_outline_rounded,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(l.musicMenuRemoveFromLibrary),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete_from_source',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_forever_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          l.musicMenuDeleteSourceFile,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: 40,
                child: Text(
                  track.durationText,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: t.text2,
                    fontFamily: 'SF Mono',
                    fontFamilyFallback: const ['Menlo'],
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

class _AlbumGrid extends ConsumerWidget {
  const _AlbumGrid({required this.tracks});
  final List<MusicTrackEntity> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = <String, MusicTrackEntity>{};
    for (final track in tracks) {
      albums.putIfAbsent(track.displayAlbum, () => track);
    }
    final entries = albums.entries.toList();
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final track = entries[i].value;
        final album = entries[i].key;
        final t = DesignTokens.of(context);
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            final albumTracks = tracks
                .where((x) => x.displayAlbum == album)
                .toList();
            _playFromList(ref, albumTracks, 0);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _Cover(
                    path: track.displayCoverPath,
                    label: album,
                    size: 999,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: t.text0,
                ),
              ),
              Text(
                track.displayArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: t.text2),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GroupList extends ConsumerWidget {
  const _GroupList({required this.tracks, required this.byArtist});
  final List<MusicTrackEntity> tracks;
  final bool byArtist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final groups = <String, int>{};
    for (final track in tracks) {
      final key = byArtist ? track.displayArtist : track.folderName;
      groups.update(key, (v) => v + 1, ifAbsent: () => 1);
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      itemBuilder: (_, i) => InkWell(
        onTap: () {
          final key = entries[i].key;
          final groupTracks = tracks
              .where((x) => (byArtist ? x.displayArtist : x.folderName) == key)
              .toList();
          _playFromList(ref, groupTracks, 0);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: byArtist ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: byArtist ? null : BorderRadius.circular(8),
                  color: t.insetBg,
                ),
                child: Icon(
                  byArtist
                      ? Icons.person_outline_rounded
                      : Icons.folder_outlined,
                  size: 18,
                  color: t.text3,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entries[i].key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.text0,
                  ),
                ),
              ),
              Text(
                l.musicPageTrackCount(entries[i].value),
                style: TextStyle(fontSize: 12, color: t.text2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RightRail extends StatelessWidget {
  const _RightRail();

  @override
  Widget build(BuildContext context) => const Column(
    children: [_PlaylistPanel(), SizedBox(height: 18), _EqPanel()],
  );
}

class _PlaylistPanel extends ConsumerWidget {
  const _PlaylistPanel();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.musicPlaylistCreateTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l.musicPlaylistNameHint,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l.musicPlaylistCreateAction),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(playlistProvider.notifier).createPlaylist(name: name);
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    PlaylistEntry p,
  ) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.musicPlaylistRenameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l.musicPlaylistNameHint,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l.musicPlaylistRename),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && name != p.name) {
      await ref.read(playlistProvider.notifier).renamePlaylist(p.id, name);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PlaylistEntry p,
  ) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.musicPlaylistDeleteTitle),
        content: Text(l.musicPlaylistDeleteMessage(p.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.musicPlaylistDelete),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref.read(playlistProvider.notifier).deletePlaylist(p.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final playlists = ref.watch(playlistProvider).playlists;
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.library_music_outlined,
                size: 15,
                color: t.accentBright,
              ),
              const SizedBox(width: 8),
              Text(
                l.musicPagePlaylists,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: t.text0,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: l.musicPlaylistCreateTitle,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(Icons.add_rounded, color: t.accentBright),
                onPressed: () => _create(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [t.accent, t.accentDeep],
                  ),
                ),
                child: Icon(
                  Icons.favorite_rounded,
                  size: 14,
                  color: t.accentContrast,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  l.musicPageFavorites,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.text0,
                  ),
                ),
              ),
            ],
          ),
          if (playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                l.musicPlaylistEmpty,
                style: TextStyle(fontSize: 12, color: t.text2, height: 1.5),
              ),
            )
          else
            for (final p in playlists)
              _PlaylistRow(
                entry: p,
                onOpen: () => PlaylistDetailPage.open(context, p),
                onRename: () => _rename(context, ref, p),
                onDelete: () => _delete(context, ref, p),
              ),
        ],
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.entry,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final PlaylistEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  color: t.chipBg,
                ),
                child: Icon(
                  Icons.queue_music_rounded,
                  size: 15,
                  color: t.text1,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.text0,
                      ),
                    ),
                    Text(
                      l.musicPlaylistTrackCount(entry.trackPaths.length),
                      style: TextStyle(fontSize: 11, color: t.text2),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '',
                iconSize: 16,
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_horiz_rounded, color: t.text2),
                onSelected: (v) {
                  if (v == 'rename') onRename();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(l.musicPlaylistRename),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(l.musicPlaylistDelete),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 桌面端 10 段均衡器面板：接 [AudioEffectsService]（与移动端 audio_effects_page
/// 共享后端，桌面 media_kit 引擎通过 mpv `af` 滤镜实时生效）。
class _EqPanel extends StatefulWidget {
  const _EqPanel();

  @override
  State<_EqPanel> createState() => _EqPanelState();
}

class _EqPanelState extends State<_EqPanel> {
  EqualizerState? _state;
  StreamSubscription<EqualizerState>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await AudioEffectsService.instance.init();
    if (!mounted) return;
    setState(() => _state = AudioEffectsService.instance.state);
    _sub = AudioEffectsService.instance.onChange.listen((s) {
      if (mounted) setState(() => _state = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _bandLabel(int hz) => hz >= 1000 ? '${hz ~/ 1000}k' : '$hz';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final state = _state;
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.equalizer_rounded, size: 15, color: t.accentBright),
              const SizedBox(width: 8),
              Text(
                l.musicPageEqualizer,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: t.text0,
                ),
              ),
              const Spacer(),
              if (state != null)
                SizedBox(
                  height: 24,
                  child: Switch(
                    value: state.enabled,
                    onChanged: (v) =>
                        AudioEffectsService.instance.setEnabled(enabled: v),
                  ),
                ),
            ],
          ),
          if (state == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in kEqPresets)
                  ChoiceChip(
                    label: Text(p.name, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    selected: state.presetId == p.id,
                    onSelected: state.enabled
                        ? (_) => AudioEffectsService.instance.applyPreset(p.id)
                        : null,
                  ),
                if (state.presetId == 'custom')
                  ChoiceChip(
                    label: Text(
                      l.paneMusicEqCustom,
                      style: const TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    selected: true,
                    onSelected: (_) {},
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < kEqBands.length; i++)
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 2,
                                  overlayShape: SliderComponentShape.noOverlay,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 5,
                                  ),
                                ),
                                child: Slider(
                                  value: state.gains[i].clamp(
                                    kEqMinGain,
                                    kEqMaxGain,
                                  ),
                                  min: kEqMinGain,
                                  max: kEqMaxGain,
                                  divisions: 48,
                                  activeColor: t.accentBright,
                                  onChanged: state.enabled
                                      ? (v) => AudioEffectsService.instance
                                            .setBandGain(i, v)
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          Text(
                            _bandLabel(kEqBands[i]),
                            style: TextStyle(fontSize: 9, color: t.text3),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: AudioEffectsService.instance.resetFlat,
                child: Text(l.paneMusicEqReset),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.path, required this.label, required this.size});
  final String? path;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final normalizedLabel = label.trim();
    final initial = normalizedLabel.isEmpty
        ? '—'
        : String.fromCharCode(normalizedLabel.runes.first);
    final fallback = Container(
      width: size == 999 ? null : size,
      height: size == 999 ? null : size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.chipBgActive, t.insetBg],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: t.text2,
          fontSize: size == 999 ? 32 : 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    // 封面路径在加载时已校验（_validateCoverPaths），此处不再每帧同步
    // existsSync 触发磁盘 IO；缺图由 Image.file 的 errorBuilder 回退。
    if (path == null || path!.isEmpty) {
      return size == 999
          ? fallback
          : ClipRRect(borderRadius: BorderRadius.circular(7), child: fallback);
    }
    final img = Image.file(
      File(path!),
      width: size == 999 ? null : size,
      height: size == 999 ? null : size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback,
    );
    return size == 999
        ? img
        : ClipRRect(borderRadius: BorderRadius.circular(7), child: img);
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: t.chipBgActive,
              borderRadius: BorderRadius.circular(DesignTokens.radius),
              border: Border.all(color: t.accent.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, size: 24, color: t.accentBright),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: t.text2, height: 1.5),
          ),
        ],
      ),
    );
  }
}
