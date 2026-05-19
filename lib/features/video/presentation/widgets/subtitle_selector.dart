import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' show SubtitleTrack;
import 'package:my_nas/features/video/data/services/opensubtitles_service.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/subtitle_download_dialog.dart';
import 'package:my_nas/features/video/presentation/widgets/subtitle_style_sheet.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';

/// 字幕选择器弹窗（Infuse 暗色风格）
class SubtitleSelectorSheet extends ConsumerWidget {
  const SubtitleSelectorSheet({
    this.videoPath,
    this.tmdbId,
    this.title,
    this.seasonNumber,
    this.episodeNumber,
    this.isMovie = true,
    super.key,
  });

  /// 视频文件路径（用于确定字幕保存位置）
  final String? videoPath;

  /// TMDB ID（用于搜索字幕）
  final int? tmdbId;

  /// 视频标题（用于搜索字幕）
  final String? title;

  /// 季号
  final int? seasonNumber;

  /// 集号
  final int? episodeNumber;

  /// 是否为电影
  final bool isMovie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final externalSubtitles = ref.watch(availableSubtitlesProvider);
    final currentSubtitle = ref.watch(currentSubtitleProvider);
    final currentEmbeddedId = ref.watch(currentEmbeddedSubtitleIdProvider);
    final playerNotifier = ref.read(videoPlayerControllerProvider.notifier);
    final embeddedSubtitles = playerNotifier.embeddedSubtitles;
    final hasSubtitleConfig = ref.watch(hasOpenSubtitlesConfigProvider);

    // 过滤出有效的内嵌字幕（排除 no 和 auto）
    final validEmbedded = embeddedSubtitles.where((s) => s.id != 'no' && s.id != 'auto').toList();

    // 判断是否没有选中任何字幕
    final isSubtitleOff = currentSubtitle == null && currentEmbeddedId == null;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动条
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.subtitles_rounded,
                  color: Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  '字幕选择',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
                const Spacer(),
                // 在线字幕下载按钮
                if (hasSubtitleConfig && videoPath != null)
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showSubtitleDownloadDialog(context, ref);
                    },
                    icon: const Icon(Icons.download_rounded, color: Colors.white70),
                    tooltip: '下载在线字幕',
                  ),
                // 字幕样式按钮
                IconButton(
                  onPressed: () {
                    Navigator.pop(context);
                    showSubtitleStyleSheet(context);
                  },
                  icon: const Icon(Icons.text_format_rounded, color: Colors.white70),
                  tooltip: '字幕样式',
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white24, height: 1),

          // 字幕列表
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // 关闭字幕选项
                _SubtitleTile(
                  title: '关闭字幕',
                  subtitle: '不显示任何字幕',
                  isSelected: isSubtitleOff,
                  icon: Icons.subtitles_off_rounded,
                  onTap: () {
                    playerNotifier.setSubtitle(null);
                    // 清除内嵌字幕选择
                    ref.read(currentEmbeddedSubtitleIdProvider.notifier).state = null;
                    // 设置为 no 字幕轨道
                    final noTrack = embeddedSubtitles.where((s) => s.id == 'no').firstOrNull;
                    if (noTrack != null) {
                      playerNotifier.setEmbeddedSubtitleTrack(noTrack);
                    }
                    Navigator.pop(context);
                  },
                ),

                // 外部字幕
                if (externalSubtitles.isNotEmpty) ...[
                  _SectionHeader(
                    title: '外部字幕',
                    count: externalSubtitles.length,
                  ),
                  ...externalSubtitles.map(
                    (sub) => _SubtitleTile(
                      title: sub.language ?? sub.name,
                      subtitle: sub.name,
                      isSelected: currentSubtitle == sub ||
                          (currentSubtitle != null && currentSubtitle.path == sub.path),
                      icon: Icons.closed_caption_rounded,
                      onTap: () {
                        ref.read(currentEmbeddedSubtitleIdProvider.notifier).state = null;
                        playerNotifier.setSubtitle(sub);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],

                // 内嵌字幕
                if (validEmbedded.isNotEmpty) ...[
                  _SectionHeader(
                    title: '内嵌字幕',
                    count: validEmbedded.length,
                  ),
                  ...validEmbedded.map(
                    (track) => _EmbeddedSubtitleTile(
                      track: track,
                      isSelected: currentEmbeddedId == track.id,
                      onTap: () {
                        ref.read(currentSubtitleProvider.notifier).state = null;
                        playerNotifier.setEmbeddedSubtitleTrack(track);
                        ref.read(currentEmbeddedSubtitleIdProvider.notifier).state = track.id;
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],

                // 无字幕提示
                if (externalSubtitles.isEmpty && validEmbedded.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.subtitles_off_outlined,
                          size: 48,
                          color: Colors.white38,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '未找到字幕文件',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '请将 .srt, .ass, .vtt 字幕文件\n放在视频同目录下',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        if (hasSubtitleConfig && videoPath != null) ...[
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _showSubtitleDownloadDialog(context, ref);
                            },
                            icon: const Icon(Icons.download_rounded, color: Colors.white70),
                            label: const Text(
                              '下载在线字幕',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSubtitleDownloadDialog(BuildContext context, WidgetRef ref) {
    if (videoPath == null) return;

    // 获取视频目录
    final lastSlash = videoPath!.lastIndexOf('/');
    final savePath = lastSlash > 0 ? videoPath!.substring(0, lastSlash) : videoPath!;

    SubtitleDownloadDialog.show(
      context: context,
      tmdbId: tmdbId,
      title: title,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      isMovie: isMovie,
      savePath: savePath,
      onDownloaded: (path) {
        // 字幕下载成功后可以刷新字幕列表
      },
    );
  }
}

/// 分组标题（暗色风格）
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
  });

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white54,
                fontWeight: FontWeight.w500,
                fontSize: 12,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      );
}

/// 字幕选项（暗色风格）
class _SubtitleTile extends StatelessWidget {
  const _SubtitleTile({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool isSelected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? Colors.white : Colors.white60,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          decoration: TextDecoration.none,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      );
}

/// 内嵌字幕选项（暗色风格）
class _EmbeddedSubtitleTile extends StatelessWidget {
  const _EmbeddedSubtitleTile({
    required this.track,
    required this.isSelected,
    required this.onTap,
  });

  final SubtitleTrack track;
  final bool isSelected;
  final VoidCallback onTap;

  String get _title {
    if (track.title != null && track.title!.isNotEmpty) {
      return track.title!;
    }
    if (track.language != null && track.language!.isNotEmpty) {
      return _languageToName(track.language!);
    }
    return '轨道 ${track.id}';
  }

  String _languageToName(String code) {
    const map = {
      'chi': '中文',
      'chs': '简体中文',
      'cht': '繁体中文',
      'zho': '中文',
      'eng': 'English',
      'jpn': '日本語',
      'kor': '한국어',
    };
    return map[code.toLowerCase()] ?? code;
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.closed_caption_outlined,
                  color: isSelected ? Colors.white : Colors.white60,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.language ?? 'ID: ${track.id}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      );
}

/// 显示字幕选择器
void showSubtitleSelector(
  BuildContext context, {
  String? videoPath,
  int? tmdbId,
  String? title,
  int? seasonNumber,
  int? episodeNumber,
  bool isMovie = true,
}) {
  showAdaptiveModalSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SubtitleSelectorSheet(
      videoPath: videoPath,
      tmdbId: tmdbId,
      title: title,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      isMovie: isMovie,
    ),
  );
}
