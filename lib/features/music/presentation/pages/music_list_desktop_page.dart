import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';

/// 桌面端「音乐」——接 musicListProvider 真实数据。
///
/// 歌曲视图为 dense-table（编号 / 标题 / 艺术家 / 专辑 / 时长），专辑 / 艺术家
/// 由曲库聚合派生，右侧保留歌单 / EQ 占位面板。
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
    final state = ref.watch(musicListProvider);

    final subtitle = state is MusicListLoaded
        ? '${state.totalCount} 首 · ${state.artistCount} 位艺术家 · '
            '${state.albumCount} 张专辑'
        : 'Gapless · 10 段 EQ · NCM 解密 · MusicBrainz / AcoustID 刮削';

    return DesktopPageScaffold(
      title: '音乐',
      subtitle: subtitle,
      actions: AppSegmented<String>(
        value: _view,
        onChanged: (v) => setState(() => _view = v),
        dense: true,
        options: const [
          AppSegmentedOption(value: 'songs', label: '歌曲'),
          AppSegmentedOption(value: 'albums', label: '专辑'),
          AppSegmentedOption(value: 'artists', label: '艺术家'),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 7,
            child: GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: _MainView(state: state, view: _view),
            ),
          ),
          const SizedBox(width: 18),
          const Expanded(
            flex: 3,
            child: Column(
              children: [
                _SidePanel(
                  title: '歌单',
                  icon: Icons.library_music_outlined,
                  message: '我喜欢 / 自建歌单将显示在这里。',
                ),
                SizedBox(height: 18),
                _SidePanel(
                  title: '均衡器',
                  icon: Icons.equalizer_rounded,
                  message: '10 段 EQ + 8 预设 + 自定义保存。',
                ),
              ],
            ),
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
    if (state is MusicListLoading) {
      return const SizedBox(
        height: 380,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state is MusicListError) {
      return SizedBox(
        height: 380,
        child: _Empty(
          icon: Icons.error_outline_rounded,
          message: (state as MusicListError).message,
        ),
      );
    }
    if (state is! MusicListLoaded) {
      return const SizedBox(
        height: 380,
        child: _Empty(
          icon: Icons.queue_music_rounded,
          message: '映射「音乐」媒体库后，此处显示曲库。',
        ),
      );
    }
    final loaded = state as MusicListLoaded;
    if (loaded.allTracks.isEmpty) {
      return const SizedBox(
        height: 380,
        child: _Empty(
          icon: Icons.queue_music_rounded,
          message: '曲库为空，扫描「音乐」媒体库后会出现在这里。',
        ),
      );
    }
    return switch (view) {
      'albums' => _AlbumGrid(tracks: loaded.allTracks),
      'artists' => _ArtistList(tracks: loaded.allTracks),
      _ => _SongTable(tracks: loaded.allTracks),
    };
  }
}

class _SongTable extends StatelessWidget {
  const _SongTable({required this.tracks});
  final List<MusicTrackEntity> tracks;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              SizedBox(width: 34, child: Text('#', style: _h(t))),
              Expanded(flex: 5, child: Text('标题', style: _h(t))),
              Expanded(flex: 3, child: Text('专辑', style: _h(t))),
              SizedBox(width: 56, child: Text('时长', style: _h(t))),
            ],
          ),
        ),
        Flexible(
          child: ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (_, i) => _SongRow(track: tracks[i], index: i + 1),
          ),
        ),
      ],
    );
  }

  TextStyle _h(DesignTokens t) =>
      TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: t.text3);
}

class _SongRow extends StatelessWidget {
  const _SongRow({required this.track, required this.index});
  final MusicTrackEntity track;
  final int index;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        hoverColor: t.chipBg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '$index',
                  style: TextStyle(
                    fontSize: 12,
                    color: t.text3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              _Cover(path: track.displayCoverPath),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.text0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: t.text2),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  track.displayAlbum,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: t.text2),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  track.durationText,
                  style: TextStyle(
                    fontSize: 12,
                    color: t.text2,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({required this.tracks});
  final List<MusicTrackEntity> tracks;

  @override
  Widget build(BuildContext context) {
    final albums = <String, MusicTrackEntity>{};
    for (final track in tracks) {
      albums.putIfAbsent(track.displayAlbum, () => track);
    }
    final entries = albums.entries.toList();
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.78,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final track = entries[i].value;
        return _AlbumCard(album: entries[i].key, sample: track);
      },
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.sample});
  final String album;
  final MusicTrackEntity sample;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _Cover(path: sample.displayCoverPath, size: 999),
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
          sample.displayArtist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: t.text2),
        ),
      ],
    );
  }
}

class _ArtistList extends StatelessWidget {
  const _ArtistList({required this.tracks});
  final List<MusicTrackEntity> tracks;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final artists = <String, int>{};
    for (final track in tracks) {
      artists.update(track.displayArtist, (v) => v + 1, ifAbsent: () => 1);
    }
    final entries = artists.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ListView.builder(
      padding: const EdgeInsets.all(6),
      itemCount: entries.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.insetBg,
              ),
              child: Icon(Icons.person_outline_rounded, size: 18, color: t.text3),
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
              '${entries[i].value} 首',
              style: TextStyle(fontSize: 12, color: t.text2),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.path, this.size = 34});
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
    if (path == null || path!.isEmpty || !File(path!).existsSync()) {
      return size == 999
          ? fallback
          : ClipRRect(borderRadius: BorderRadius.circular(6), child: fallback);
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
        : ClipRRect(borderRadius: BorderRadius.circular(6), child: img);
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

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.title,
    required this.icon,
    required this.message,
  });

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: t.accentBright),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: t.text0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(fontSize: 12, color: t.text2, height: 1.5),
          ),
        ],
      ),
    );
  }
}
