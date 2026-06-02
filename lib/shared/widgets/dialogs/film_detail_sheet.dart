import 'dart:io';

import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';

/// 设计稿 dialogs.jsx 中 FilmDetail：影视详情 sheet（720x90vh）。
///
/// 现阶段从 [VideoMetadata] 取数据铺 hero + 简介 + 操作按钮 + tabs
/// （版本 / 演职员 / 相关）。多版本列表与剧集分集网格留作后续，由
/// `videoDetailProvider` 提供详细数据。
class FilmDetailSheet extends StatefulWidget {
  const FilmDetailSheet({required this.meta, super.key});

  final VideoMetadata meta;

  @override
  State<FilmDetailSheet> createState() => _FilmDetailSheetState();
}

class _FilmDetailSheetState extends State<FilmDetailSheet> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final m = widget.meta;
    final isTv = (m.seasonNumber ?? 0) > 0;
    final tabs = isTv
        ? const ['剧集', '版本', '演职员', '相关']
        : const ['版本', '演职员', '相关'];

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
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
                      _tabBody(tabs[_tab], t),
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

  Widget _tabBody(String name, DesignTokens t) {
    final m = widget.meta;
    switch (name) {
      case '剧集':
        return _SeasonsStub(t: t);
      case '版本':
        return _Versions(meta: m, t: t);
      case '演职员':
        return _Cast(meta: m, t: t);
      case '相关':
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
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.92),
                ],
                stops: const [0.45, 1.0],
              ),
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 18),
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
                    for (final g
                        in (meta.genres ?? '').split(',').take(3))
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
                      _stat(null, '${meta.runtime} 分钟'),
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

class _Actions extends StatelessWidget {
  const _Actions({required this.meta});
  final VideoMetadata meta;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: 接 videoPlayerProvider.play(meta)
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: Text(meta.isWatched ? '重新播放' : '播放'),
          ),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.favorite_border_rounded, size: 14),
            label: const Text('收藏'),
          ),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.download_rounded, size: 14),
            label: const Text('下载'),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.cast_rounded, size: 16),
            tooltip: '投屏',
          ),
        ],
      );
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
  Widget build(BuildContext context) => Container(
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
                          color: i == current
                              ? t.accent
                              : Colors.transparent,
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
                    const AppTag('默认', variant: TagVariant.free),
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
                AppTag(_fmtSize(meta.fileSize!),
                    variant: TagVariant.neutral),
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
    final cast = (meta.cast ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (cast.isEmpty) {
      return Text('暂无演职员信息。',
          style: TextStyle(fontSize: 12.5, color: t.text2));
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final name in cast.take(18))
          SizedBox(
            width: 86,
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.insetBg,
                  ),
                  child: Icon(Icons.person_outline_rounded,
                      color: t.text3),
                ),
                const SizedBox(height: 6),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
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
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        alignment: Alignment.center,
        child: Text(
          '相关推荐由 TMDB / 豆瓣 提供，可在影视设置中启用。',
          style: TextStyle(fontSize: 12.5, color: t.text2),
        ),
      );
}

class _SeasonsStub extends StatelessWidget {
  const _SeasonsStub({required this.t});
  final DesignTokens t;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        alignment: Alignment.center,
        child: Text(
          '剧集分集（按季 + 集网格）由 videoDetailProvider 提供，迁移中。',
          style: TextStyle(fontSize: 12.5, color: t.text2),
        ),
      );
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
