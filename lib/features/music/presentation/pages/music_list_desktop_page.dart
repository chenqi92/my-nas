import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';

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
    final state = ref.watch(musicListProvider);
    final loaded = state is MusicListLoaded ? state : null;

    final subtitle = loaded != null
        ? '${loaded.totalCount} 首 · ${loaded.albumCount} 张专辑 · '
            'Gapless · 10 段 EQ · NCM 解密'
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
          AppSegmentedOption(value: 'folders', label: '文件夹'),
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
    final tracks = loaded?.allTracks ?? const [];
    final totalMs = tracks.fold<int>(0, (a, t) => a + (t.duration ?? 0));
    final hours = (totalMs / 3600000);
    final hoursText = hours >= 1
        ? hours.toStringAsFixed(hours >= 10 ? 0 : 1)
        : (totalMs / 60000).toStringAsFixed(0);
    final hoursUnit = hours >= 1 ? '小时' : '分钟';

    return Row(
      children: [
        Expanded(
          child: _Stat(
            value: '${loaded?.totalCount ?? 0}',
            unit: '首',
            label: '曲目',
            icon: Icons.library_music_outlined,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Stat(value: hoursText, unit: hoursUnit, label: '总时长'),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Stat(
            value: '${loaded?.artistCount ?? 0}',
            unit: '位',
            label: '艺术家',
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: _Stat(
            value: '年度报告',
            valueMuted: true,
            label: 'Last.fm 可接',
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
                const AppTag('即将推出', variant: TagVariant.plan),
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
      return const _Empty(
        icon: Icons.queue_music_rounded,
        message: '曲库为空，扫描「音乐」媒体库后会出现在这里。',
      );
    }
    final tracks = loaded.allTracks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TableHeader(view: view),
        Expanded(
          child: switch (view) {
            'albums' => _AlbumGrid(tracks: tracks),
            'artists' => _GroupList(tracks: tracks, byArtist: true),
            'folders' => _GroupList(tracks: tracks, byArtist: false),
            _ => _SongTable(tracks: tracks),
          },
        ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.view});
  final String view;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final title = switch (view) {
      'albums' => '专辑',
      'artists' => '艺术家',
      'folders' => '文件夹',
      _ => '全部歌曲',
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
          const AppChip(label: '播放全部', icon: Icons.play_arrow_rounded, compact: true),
          const SizedBox(width: 8),
          const AppChip(label: '随机', icon: Icons.shuffle_rounded, compact: true),
        ],
      ),
    );
  }
}

class _SongTable extends StatelessWidget {
  const _SongTable({required this.tracks});
  final List<MusicTrackEntity> tracks;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (_, i) => _SongRow(track: tracks[i], index: i + 1),
    );
  }
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
                onPressed: () {},
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.favorite_border_rounded,
                    size: 15, color: t.text3),
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
        final t = DesignTokens.of(context);
        return Column(
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
              entries[i].key,
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
        );
      },
    );
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({required this.tracks, required this.byArtist});
  final List<MusicTrackEntity> tracks;
  final bool byArtist;

  @override
  Widget build(BuildContext context) {
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
      itemBuilder: (_, i) => Padding(
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
            Text('${entries[i].value} 首',
                style: TextStyle(fontSize: 12, color: t.text2)),
          ],
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
              Text('歌单',
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
                  '我喜欢的音乐',
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
            '自建歌单与「我喜欢」会显示在这里。',
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
              Text('均衡器',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: t.text0)),
              const Spacer(),
              Text('流行', style: TextStyle(fontSize: 11, color: t.text2)),
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
    if (path == null || path!.isEmpty || !File(path!).existsSync()) {
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
