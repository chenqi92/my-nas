import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/data/services/lyrics_translation_service.dart';
import 'package:my_nas/features/music/data/services/music_audio_handler_interface.dart';
import 'package:my_nas/features/music/presentation/pages/audio_effects_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_scraper_sources_page.dart';
import 'package:my_nas/features/music/presentation/pages/scrobble_settings_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_settings_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 桌面「音乐播放」设置 pane。
///
/// 对齐设计稿 `settings_panes.jsx · PaneMusic`：引擎与解码 / 均衡器 / 歌词 /
/// Scrobble 与刮削。主开关、引擎、播放模式、淡入淡出、歌词翻译均接 [musicSettingsProvider]
/// 真实状态读写；均衡器、Scrobble、刮削源用按钮打开现有功能页保留完整能力。
class MusicPane extends ConsumerWidget {
  const MusicPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(musicSettingsProvider);
    final notifier = ref.read(musicSettingsProvider.notifier);
    final crossfadeOn = settings.crossfadeDuration > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.library_music_outlined,
          title: '音乐播放',
          subtitle: '解码引擎、均衡器、无缝与淡入淡出、歌词翻译与 Scrobble。music_settings。',
        ),

        // 引擎与解码
        SetSection(
          title: '引擎与解码',
          hint: '切换引擎需重启',
          children: [
            SetRow(
              title: '播放引擎',
              desc: '平台原生（低功耗）/ FFmpeg（格式最全）',
              trailing: AppSegmented<MusicPlayerEngine>(
                options: const [
                  AppSegmentedOption(
                    value: MusicPlayerEngine.justAudio,
                    label: '平台原生',
                  ),
                  AppSegmentedOption(
                    value: MusicPlayerEngine.mediaKit,
                    label: 'FFmpeg',
                  ),
                ],
                value: settings.playerEngine,
                onChanged: notifier.setPlayerEngine,
              ),
            ),
            SetRow(
              title: '无缝播放 Gapless',
              desc: '专辑曲目间无静音间隙',
              trailing: AppSwitch(
                value: settings.gaplessPlayback,
                onChanged: (v) => notifier.setGaplessPlayback(enabled: v),
              ),
            ),
            SetRow(
              title: '交叉淡入淡出',
              desc: '切歌时上一首淡出、下一首淡入',
              trailing: AppSwitch(
                value: crossfadeOn,
                onChanged: (v) =>
                    notifier.setCrossfadeDuration(v ? 6 : 0),
              ),
            ),
            SetRow(
              title: '淡入淡出时长',
              trailing: _CrossfadeSlider(
                seconds: settings.crossfadeDuration,
                enabled: crossfadeOn,
                onChanged: notifier.setCrossfadeDuration,
              ),
            ),
            SetRow(
              title: '默认播放模式',
              desc: '随机 / 列表循环 / 单曲循环',
              trailing: AppSegmented<PlayMode>(
                options: const [
                  AppSegmentedOption(value: PlayMode.shuffle, label: '随机'),
                  AppSegmentedOption(value: PlayMode.loop, label: '列表'),
                  AppSegmentedOption(value: PlayMode.repeatOne, label: '单曲'),
                ],
                value: settings.playMode,
                onChanged: notifier.setPlayMode,
              ),
            ),
            SetRow(
              title: '连接后自动播放',
              desc: '连接源后自动续播上次队列',
              last: true,
              trailing: AppSwitch(
                value: settings.autoPlayOnConnect,
                onChanged: (v) => notifier.setAutoPlayOnConnect(enabled: v),
              ),
            ),
          ],
        ),

        // 均衡器
        SetSection(
          title: '均衡器',
          hint: '10 段 · 8 预设 + 自定义',
          children: [
            SetRow(
              title: '均衡器',
              desc: '10 段 EQ + 8 个预设；桌面走 mpv af，Android 走系统硬件 EQ',
              last: true,
              trailing: AppButton(
                label: '打开均衡器',
                icon: Icons.tune_rounded,
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const AudioEffectsPage()),
                ),
              ),
            ),
          ],
        ),

        // 歌词
        SetSection(
          title: '歌词',
          children: [
            SetRow(
              title: '显示歌词',
              desc: '播放页与桌面浮窗显示同步歌词',
              trailing: AppSwitch(
                value: settings.showLyrics,
                onChanged: (v) => notifier.setShowLyrics(enabled: v),
              ),
            ),
            SetRow(
              title: '歌词翻译',
              desc: settings.lyricsTranslateEnabled
                  ? '译文双行显示 · ${LyricsTranslationLang.fromBcp47(settings.lyricsTranslateLang).displayName} · Google 翻译'
                  : '译文双行显示 · Google 翻译（免费，需联网）',
              last: true,
              trailing: AppSwitch(
                value: settings.lyricsTranslateEnabled,
                onChanged: (v) =>
                    notifier.setLyricsTranslateEnabled(enabled: v),
              ),
            ),
          ],
        ),

        // Scrobble 与刮削
        SetSection(
          title: 'Scrobble 与刮削',
          hint: 'Last.fm · ListenBrainz',
          bottomMargin: false,
          children: [
            SetRow(
              title: 'Scrobble 上报',
              desc: 'Last.fm / ListenBrainz · 听满阈值后上报，离线自动重试',
              trailing: AppButton(
                label: '配置',
                icon: Icons.podcasts_rounded,
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const ScrobbleSettingsPage(),
                  ),
                ),
              ),
            ),
            SetRow(
              title: '音乐刮削源',
              desc: 'MusicBrainz / 网易云 / AcoustID 指纹',
              last: true,
              trailing: AppButton(
                label: '管理刮削源',
                icon: Icons.fingerprint_rounded,
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const MusicScraperSourcesPage(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 淡入淡出时长滑块（0–12 秒），跟随 [SetRow] trailing 右对齐显示数值。
class _CrossfadeSlider extends StatelessWidget {
  const _CrossfadeSlider({
    required this.seconds,
    required this.enabled,
    required this.onChanged,
  });

  final int seconds;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: SizedBox(
        width: 196,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 150,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: t.accent,
                  inactiveTrackColor: t.insetBg,
                  thumbColor: t.accentBright,
                  overlayColor: t.accent.withValues(alpha: 0.18),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  min: 0,
                  max: 12,
                  divisions: 12,
                  value: seconds.toDouble().clamp(0, 12),
                  onChanged:
                      enabled ? (v) => onChanged(v.round()) : null,
                ),
              ),
            ),
            const SizedBox(width: 11),
            SizedBox(
              width: 34,
              child: Text(
                '$seconds s',
                style: TextStyle(
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: t.text2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
