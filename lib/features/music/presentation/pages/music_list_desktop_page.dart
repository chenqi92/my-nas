import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(musicListProvider);
    final loaded = state is MusicListLoaded ? state : null;

    final subtitle = loaded != null
        ? l.musicPageSubtitleLoaded(loaded.totalCount, loaded.albumCount)
        : l.musicPageSubtitleDefault;

    return DesktopPageScaffold(
      title: l.musicPageTitle,
      subtitle: subtitle,
      actions: AppSegmented<String>(
        value: _view,
        onChanged: (v) => setState(() => _view = v),
        dense: true,
        options: [
          AppSegmentedOption(value: 'songs', label: l.musicPageTabSongs),
          AppSegmentedOption(value: 'albums', label: l.musicPageTabAlbums),
          AppSegmentedOption(value: 'artists', label: l.musicPageTabArtists),
          AppSegmentedOption(value: 'folders', label: l.musicPageTabFolders),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
    final hours = (totalMs / 3600000);
    final hoursText = hours >= 1
        ? hours.toStringAsFixed(hours >= 10 ? 0 : 1)
        : (totalMs / 60000).toStringAsFixed(0);
    final hoursUnit = hours >= 1 ? l.musicPageUnitHours : l.musicPageUnitMinutes;

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
            valueMuted: true,
            label: l.musicPageStatLastFmReady,
            planTag: true,
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
    this.valueMuted = false,
    this.planTag = false,
  });

  final String value;
  final String? unit;
  final String label;
  final IconData? icon;
  final bool valueMuted;
  final bool planTag;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return Container(
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
            TextSpan(children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  fontSize: valueMuted ? 18 : 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: valueMuted ? t.text2 : t.text0,
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
            ]),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (planTag) ...[
                AppTag(l.musicPageComingSoon, variant: TagVariant.plan),
                const SizedBox(width: 6),
              ] else if (icon != null) ...[
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
    final tracks = loaded.allTracks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TableHeader(view: view, tracks: tracks),
        Expanded(
          child: switch (view) {
            'albums' => _AlbumGrid(tracks: tracks),
            'artists' => _GroupList(tracks: tracks, byArtist: true),
            'folders' => _GroupList(tracks: tracks, byArtist: false),
            _ => _SongTable(tracks: tracks, hasMore: loaded.hasMoreTracks),
          },
        ),
      ],
    );
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

class _SongTable extends ConsumerWidget {
  const _SongTable({required this.tracks, required this.hasMore});
  final List<MusicTrackEntity> tracks;
  final bool hasMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // 触底前 300px 触发加载下一页（曲库分页 100 首/页）。
        if (hasMore &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
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
    final t = DesignTokens.of(context);
    final isFav =
        ref.watch(isMusicFavoriteProvider(track.filePath)).valueOrNull ??
            false;
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
              _Cover(path: track.displayCoverPath, size: 38),
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
            final albumTracks =
                tracks.where((x) => x.displayAlbum == album).toList();
            _playFromList(ref, albumTracks, 0);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _Cover(path: track.displayCoverPath, size: 999),
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
              .where((x) =>
                  (byArtist ? x.displayArtist : x.folderName) == key)
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
                borderRadius:
                    byArtist ? null : BorderRadius.circular(8),
                color: t.insetBg,
              ),
              child: Icon(
                byArtist ? Icons.person_outline_rounded : Icons.folder_outlined,
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
            Text(l.musicPageTrackCount(entries[i].value),
                style: TextStyle(fontSize: 12, color: t.text2)),
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
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _PlaylistPanel(),
        SizedBox(height: 18),
        _EqPanel(),
      ],
    );
  }
}

class _PlaylistPanel extends StatelessWidget {
  const _PlaylistPanel();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.library_music_outlined, size: 15, color: t.accentBright),
              const SizedBox(width: 8),
              Text(l.musicPagePlaylists,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: t.text0)),
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
                child: Icon(Icons.favorite_rounded,
                    size: 14, color: t.accentContrast),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  l.musicPageFavorites,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.text0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l.musicPagePlaylistHint,
            style: TextStyle(fontSize: 12, color: t.text2, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _EqPanel extends StatelessWidget {
  const _EqPanel();

  static const _bars = [.4, .7, .9, .6, .3, .5, .75, .85, .5, .35];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.equalizer_rounded, size: 15, color: t.accentBright),
              const SizedBox(width: 8),
              Text(l.musicPageEqualizer,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: t.text0)),
              const Spacer(),
              // 10 段 EQ 调节尚未在桌面接入，标注规划而非伪装可用预设。
              AppTag(l.musicPageComingSoon, variant: TagVariant.plan),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < _bars.length; i++) ...[
                  Expanded(
                    child: FractionallySizedBox(
                      heightFactor: _bars[i],
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [t.accentBright, t.accentDeep],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (i != _bars.length - 1) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.path, required this.size});
  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final fallback = Container(
      width: size == 999 ? null : size,
      height: size == 999 ? null : size,
      color: t.insetBg,
      child: Icon(Icons.music_note_rounded, size: 16, color: t.text3),
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
          Icon(icon, size: 38, color: t.text3),
          const SizedBox(height: 10),
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
