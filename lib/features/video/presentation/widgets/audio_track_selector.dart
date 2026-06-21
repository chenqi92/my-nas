import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 显示音轨选择器（Infuse 暗色风格）
void showAudioTrackSelector(BuildContext context) {
  showAdaptiveModalSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => const AudioTrackSelector(),
  );
}

class AudioTrackSelector extends ConsumerWidget {
  const AudioTrackSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerNotifier = ref.watch(videoPlayerControllerProvider.notifier);
    final audioTracks = playerNotifier.audioTracks;
    final currentTrack = playerNotifier.currentAudioTrack;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示器
          const SheetDragHandle(bottomPadding: 0),

          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.audiotrack_rounded,
                  color: Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.videoAudioTrackSelectorTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white24, height: 1),

          // 音轨列表
          if (audioTracks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Icon(
                    Icons.music_off_rounded,
                    size: 48,
                    color: Colors.white38,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.videoAudioTrackSelectorEmpty,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: audioTracks.length,
                itemBuilder: (context, index) {
                  final track = audioTracks[index];
                  final isSelected = _isTrackSelected(track, currentTrack);
                  final trackInfo = _getTrackInfo(track, context);

                  return _AudioTrackTile(
                    title: trackInfo.title,
                    subtitle: trackInfo.subtitle,
                    isSelected: isSelected,
                    onTap: () {
                      playerNotifier.setAudioTrack(track);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  bool _isTrackSelected(AudioTrack track, AudioTrack? currentTrack) {
    if (currentTrack == null) return false;
    return track.id == currentTrack.id;
  }

  _TrackInfo _getTrackInfo(AudioTrack track, BuildContext context) {
    final title = track.title ?? context.l10n.videoAudioTrackLabel(track.id);
    String? subtitle;

    // 解析语言
    if (track.language != null && track.language!.isNotEmpty) {
      final langName = _getLanguageName(track.language!, context);
      subtitle = langName;
    }

    // 添加编解码器信息
    if (track.codec != null && track.codec!.isNotEmpty) {
      final codecInfo = track.codec!.toUpperCase();
      if (subtitle != null) {
        subtitle = '$subtitle · $codecInfo';
      } else {
        subtitle = codecInfo;
      }
    }

    // 添加声道信息
    final channelCount = track.channelscount ?? track.audiochannels;
    if (channelCount != null && channelCount > 0) {
      final channelInfo = _getChannelInfo(channelCount, context);
      if (subtitle != null) {
        subtitle = '$subtitle · $channelInfo';
      } else {
        subtitle = channelInfo;
      }
    } else if (track.channels != null && track.channels!.isNotEmpty) {
      if (subtitle != null) {
        subtitle = '$subtitle · ${track.channels}';
      } else {
        subtitle = track.channels;
      }
    }

    return _TrackInfo(title: title, subtitle: subtitle);
  }

  String _getLanguageName(String langCode, BuildContext context) {
    final code = langCode.toLowerCase();
    final l10n = context.l10n;
    const langMap = {
      'chi': 'videoLanguageChinese',
      'chs': 'videoLanguageSimplifiedChinese',
      'cht': 'videoLanguageTraditionalChinese',
      'zho': 'videoLanguageChinese',
      'zh': 'videoLanguageChinese',
      'zh-cn': 'videoLanguageSimplifiedChinese',
      'zh-tw': 'videoLanguageTraditionalChinese',
      'zh-hk': 'videoLanguageCantonese',
      'eng': 'videoLanguageEnglish',
      'en': 'videoLanguageEnglish',
      'jpn': 'videoLanguageJapanese',
      'ja': 'videoLanguageJapanese',
      'kor': 'videoLanguageKorean',
      'ko': 'videoLanguageKorean',
      'fra': 'videoLanguageFrench',
      'fr': 'videoLanguageFrench',
      'deu': 'videoLanguageGerman',
      'de': 'videoLanguageGerman',
      'spa': 'videoLanguageSpanish',
      'es': 'videoLanguageSpanish',
      'ita': 'videoLanguageItalian',
      'it': 'videoLanguageItalian',
      'rus': 'videoLanguageRussian',
      'ru': 'videoLanguageRussian',
      'por': 'videoLanguagePortuguese',
      'pt': 'videoLanguagePortuguese',
      'ara': 'videoLanguageArabic',
      'ar': 'videoLanguageArabic',
      'hin': 'videoLanguageHindi',
      'hi': 'videoLanguageHindi',
      'tha': 'videoLanguageThai',
      'th': 'videoLanguageThai',
      'vie': 'videoLanguageVietnamese',
      'vi': 'videoLanguageVietnamese',
      'und': 'videoLanguageUnknown',
    };
    final keyName = langMap[code];
    if (keyName == null) return langCode;
    return _getLangNameByKey(l10n, keyName);
  }

  String _getLangNameByKey(AppLocalizations l10n, String keyName) => switch (keyName) {
      'videoLanguageChinese' => l10n.videoLanguageChinese,
      'videoLanguageSimplifiedChinese' => l10n.videoLanguageSimplifiedChinese,
      'videoLanguageTraditionalChinese' => l10n.videoLanguageTraditionalChinese,
      'videoLanguageCantonese' => l10n.videoLanguageCantonese,
      'videoLanguageEnglish' => l10n.videoLanguageEnglish,
      'videoLanguageJapanese' => l10n.videoLanguageJapanese,
      'videoLanguageKorean' => l10n.videoLanguageKorean,
      'videoLanguageFrench' => l10n.videoLanguageFrench,
      'videoLanguageGerman' => l10n.videoLanguageGerman,
      'videoLanguageSpanish' => l10n.videoLanguageSpanish,
      'videoLanguageItalian' => l10n.videoLanguageItalian,
      'videoLanguageRussian' => l10n.videoLanguageRussian,
      'videoLanguagePortuguese' => l10n.videoLanguagePortuguese,
      'videoLanguageArabic' => l10n.videoLanguageArabic,
      'videoLanguageHindi' => l10n.videoLanguageHindi,
      'videoLanguageThai' => l10n.videoLanguageThai,
      'videoLanguageVietnamese' => l10n.videoLanguageVietnamese,
      'videoLanguageUnknown' => l10n.videoLanguageUnknown,
      _ => '',
    };

  String _getChannelInfo(int channels, BuildContext context) => switch (channels) {
        1 => context.l10n.videoChannelMono,
        2 => context.l10n.videoChannelStereo,
        6 => context.l10n.videoChannelSurround51,
        8 => context.l10n.videoChannelSurround71,
        _ => context.l10n.videoChannelCustom(channels),
      };
}

/// 音轨选项（暗色风格）
class _AudioTrackTile extends StatelessWidget {
  const _AudioTrackTile({
    required this.title,
    this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool isSelected;
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
                  Icons.audiotrack_rounded,
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
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
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

class _TrackInfo {
  const _TrackInfo({required this.title, this.subtitle});
  final String title;
  final String? subtitle;
}
