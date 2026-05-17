import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';

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
                  Icons.audiotrack_rounded,
                  color: Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  '音轨选择',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white70),
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
                children: const [
                  Icon(
                    Icons.music_off_rounded,
                    size: 48,
                    color: Colors.white38,
                  ),
                  SizedBox(height: 12),
                  Text(
                    '无可用音轨',
                    style: TextStyle(
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
                  final trackInfo = _getTrackInfo(track);

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

  _TrackInfo _getTrackInfo(AudioTrack track) {
    final title = track.title ?? '音轨 ${track.id}';
    String? subtitle;

    // 解析语言
    if (track.language != null && track.language!.isNotEmpty) {
      final langName = _getLanguageName(track.language!);
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
      final channelInfo = _getChannelInfo(channelCount);
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

  String _getLanguageName(String langCode) {
    final code = langCode.toLowerCase();
    const langMap = {
      'chi': '中文',
      'chs': '简体中文',
      'cht': '繁体中文',
      'zho': '中文',
      'zh': '中文',
      'zh-cn': '简体中文',
      'zh-tw': '繁体中文',
      'zh-hk': '粤语',
      'eng': '英语',
      'en': '英语',
      'jpn': '日语',
      'ja': '日语',
      'kor': '韩语',
      'ko': '韩语',
      'fra': '法语',
      'fr': '法语',
      'deu': '德语',
      'de': '德语',
      'spa': '西班牙语',
      'es': '西班牙语',
      'ita': '意大利语',
      'it': '意大利语',
      'rus': '俄语',
      'ru': '俄语',
      'por': '葡萄牙语',
      'pt': '葡萄牙语',
      'ara': '阿拉伯语',
      'ar': '阿拉伯语',
      'hin': '印地语',
      'hi': '印地语',
      'tha': '泰语',
      'th': '泰语',
      'vie': '越南语',
      'vi': '越南语',
      'und': '未知语言',
    };
    return langMap[code] ?? langCode;
  }

  String _getChannelInfo(int channels) => switch (channels) {
        1 => '单声道',
        2 => '立体声',
        6 => '5.1声道',
        8 => '7.1声道',
        _ => '$channels声道',
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
