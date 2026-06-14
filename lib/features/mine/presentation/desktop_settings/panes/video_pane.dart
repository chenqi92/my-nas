import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/data/services/capability/playback_capability_service.dart';
import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_translation_service.dart';
import 'package:my_nas/features/video/domain/entities/audio_capability.dart';
import 'package:my_nas/features/video/domain/entities/hdr_capability.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';
import 'package:my_nas/features/video/presentation/pages/scraper_sources_page.dart';
import 'package:my_nas/features/video/presentation/providers/cast_provider.dart';
import 'package:my_nas/features/video/presentation/providers/hdr_audio_settings_provider.dart';
import 'package:my_nas/features/video/presentation/providers/playback_settings_provider.dart';
import 'package:my_nas/features/video/presentation/providers/quality_provider.dart';
import 'package:my_nas/features/video/presentation/providers/subtitle_translation_settings_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 桌面「设置 · 视频播放」详情 pane（对齐设计稿 settings_panes.jsx PaneVideo）。
///
/// 播放 / HDR 与后端 / 音频直通 / 投屏与转码 / 字幕 五张卡片。能接的开关、
/// 分段、滑块直接读写真实 provider（清晰度、HDR/音频、字幕翻译、自动续播 /
/// 自动下一集、投屏设备发现）；视频刮削源用按钮打开现有管理页；视频后端、
/// 服务端 / 客户端转码无可写的全局设置（运行时按源能力自动判定），字幕源无
/// 现成管理页，这些项以「即将推出」只读行降级。
class VideoPane extends ConsumerWidget {
  const VideoPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);

    final quality = ref.watch(qualitySettingsProvider);
    final qualityNotifier = ref.read(qualitySettingsProvider.notifier);

    final hdrAudio = ref.watch(hdrAudioSettingsProvider);
    final hdrAudioNotifier = ref.read(hdrAudioSettingsProvider.notifier);
    final hdrSettings = hdrAudio.settings;

    final subtitle = ref.watch(subtitleTranslationSettingsProvider);
    final subtitleNotifier =
        ref.read(subtitleTranslationSettingsProvider.notifier);

    final playback = ref.watch(playbackSettingsProvider);
    final playbackNotifier = ref.read(playbackSettingsProvider.notifier);

    final cast = ref.watch(castProvider);
    final castNotifier = ref.read(castProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SetHead(
          icon: Icons.movie_outlined,
          title: '视频播放',
          subtitle:
              '清晰度、HDR 色调映射、音频直通、投屏转码与字幕翻译。video_quality_settings。',
        ),

        // ---- 播放 ----
        SetSection(
          title: '播放',
          hint: '续播 · 自动下一集',
          children: [
            SetRow(
              title: '清晰度',
              desc: '自适应码率，或手动锁定档位',
              trailing: AppSegmented<bool>(
                value: quality.enableAdaptiveSuggestion,
                onChanged: (v) =>
                    qualityNotifier.setEnableAdaptiveSuggestion(enabled: v),
                options: const [
                  AppSegmentedOption(value: true, label: '自适应'),
                  AppSegmentedOption(value: false, label: '手动'),
                ],
              ),
            ),
            if (!quality.enableAdaptiveSuggestion)
              SetRow(
                title: '默认档位',
                desc: '手动模式下播放时锁定的清晰度',
                trailing: _QualityDropdown(
                  value: quality.defaultQuality,
                  onChanged: qualityNotifier.setDefaultQuality,
                ),
              ),
            SetRow(
              title: '记住清晰度选择',
              desc: '下次播放同一视频时自动应用',
              trailing: AppSwitch(
                value: quality.rememberPerVideo,
                onChanged: (v) =>
                    qualityNotifier.setRememberPerVideo(enabled: v),
              ),
            ),
            SetRow(
              title: '自动续播',
              desc: '从上次停止处继续',
              trailing: AppSwitch(
                value: playback.rememberPosition,
                onChanged: (v) =>
                    playbackNotifier.setRememberPosition(enabled: v),
              ),
            ),
            SetRow(
              title: '自动下一集',
              desc: '剧集结束自动播放下一集',
              trailing: AppSwitch(
                value: playback.autoPlayNext,
                onChanged: (v) => playbackNotifier.setAutoPlayNext(enabled: v),
              ),
            ),
            SetRow(
              title: '缓冲阈值',
              desc: '缓冲达到该秒数再开始播放',
              last: true,
              trailing: _SliderField(
                value: quality.bufferThresholdSeconds.toDouble(),
                min: 1,
                max: 15,
                label: '${quality.bufferThresholdSeconds} s',
                onChanged: (v) =>
                    qualityNotifier.setBufferThreshold(v.round()),
              ),
            ),
          ],
        ),

        // ---- HDR 与后端 ----
        SetSection(
          title: 'HDR 与后端',
          hint: 'HDR10 / HLG · 色调映射',
          children: [
            SetRow(
              title: 'HDR10 / HLG',
              desc: '启用 HDR 通道与元数据透传',
              trailing: AppSwitch(
                value: hdrSettings.hdrMode != HdrMode.disabled,
                onChanged: (v) => hdrAudioNotifier.setHdrMode(
                  v ? HdrMode.auto : HdrMode.disabled,
                ),
              ),
            ),
            SetRow(
              title: '色调映射',
              desc: 'HDR → SDR 显示时的映射算法',
              trailing: _ToneMappingDropdown(
                value: hdrSettings.toneMappingMode,
                onChanged: hdrAudioNotifier.setToneMappingMode,
              ),
            ),
            SetRow(
              title: '视频后端',
              desc: 'media_kit ⟷ 原生播放器，按 HDR / 杜比能力切换',
              last: true,
              trailing: const AppTag('即将推出', variant: TagVariant.plan),
            ),
          ],
        ),

        // ---- 音频直通 ----
        SetSection(
          title: '音频直通',
          hint: 'AC3 / DTS / TrueHD / PCM',
          children: [
            _PassthroughTiles(
              settings: hdrSettings,
              capability: hdrAudio.audioCapability,
              onChanged: hdrAudioNotifier.setEnabledPassthroughCodecs,
            ),
            SetRow(
              title: '输出端口',
              desc: '直通目标设备',
              trailing: Text(
                _outputDeviceText(hdrAudio.audioCapability),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: t.text1,
                ),
              ),
            ),
            SetRow(
              title: '始终解码后输出',
              desc: '不支持直通时强制本地解码为 PCM',
              last: true,
              trailing: AppSwitch(
                value: hdrSettings.audioPassthroughMode ==
                    AudioPassthroughMode.disabled,
                onChanged: (v) => hdrAudioNotifier.setAudioPassthroughMode(
                  v
                      ? AudioPassthroughMode.disabled
                      : AudioPassthroughMode.auto,
                ),
              ),
            ),
          ],
        ),

        // ---- 投屏与转码 ----
        SetSection(
          title: '投屏与转码',
          children: [
            SetRow(
              title: 'DLNA / AirPlay 投屏',
              desc: cast.isCasting
                  ? '投屏中 · ${cast.session?.device.name ?? '已连接设备'}'
                  : cast.isDiscovering
                      ? '正在搜索设备…'
                      : '设备发现 · 远程控制（播放 / 暂停 / 音量 / 进度）',
              trailing: AppButton(
                label: cast.isDiscovering ? '搜索中…' : '搜索设备',
                icon: Icons.wifi_tethering_rounded,
                dense: true,
                onPressed:
                    cast.isDiscovering ? null : castNotifier.startDiscovery,
              ),
            ),
            SetRow(
              title: '服务端转码',
              desc: 'Synology / Jellyfin 服务端转码',
              trailing: const AppTag('即将推出', variant: TagVariant.plan),
            ),
            SetRow(
              title: '客户端转码',
              desc: '本地软件转码 — 受平台编解码能力限制',
              trailing: const AppTag('即将推出', variant: TagVariant.plan),
            ),
            SetRow(
              title: '不支持转码提示',
              desc: '当源与设备都不支持目标编码时弹出提示',
              trailing: AppSwitch(
                value: quality.showUnsupportedHint,
                onChanged: (v) =>
                    qualityNotifier.setShowUnsupportedHint(enabled: v),
              ),
            ),
            _NoteRow(
              text:
                  '当源与设备都不支持目标编码、且服务端 / 客户端转码均不可用时，播放器会提示「不支持转码」并给出可播放的备选版本。',
            ),
          ],
        ),

        // ---- 字幕 ----
        SetSection(
          title: '字幕',
          hint: '翻译 · 缓存 · 源',
          bottomMargin: false,
          children: [
            SetRow(
              title: '双语显示',
              desc: '原文 + 译文双行',
              trailing: AppSwitch(
                value: subtitle.bilingual,
                onChanged: (v) => subtitleNotifier.setBilingual(value: v),
              ),
            ),
            SetRow(
              title: '翻译引擎',
              desc: '字幕实时翻译',
              trailing: AppSegmented<bool>(
                value: subtitle.providerId != 'off',
                onChanged: (v) =>
                    subtitleNotifier.setProvider(v ? 'google_free' : 'off'),
                options: const [
                  AppSegmentedOption(value: true, label: 'Google 免费'),
                  AppSegmentedOption(value: false, label: '关闭'),
                ],
              ),
            ),
            SetRow(
              title: '翻译缓存',
              desc: '缓存译文，重复播放免翻译',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppSwitch(
                    value: subtitle.useCache,
                    onChanged: (v) => subtitleNotifier.setUseCache(value: v),
                  ),
                  const SizedBox(width: 10),
                  AppChip(
                    label: '清译文存档',
                    icon: Icons.delete_outline_rounded,
                    onTap: () async {
                      await SubtitleTranslationService.instance.clearCache();
                      if (!context.mounted) return;
                      context.showSuccessSnackBar('翻译缓存已清除');
                    },
                  ),
                ],
              ),
            ),
            SetRow(
              title: '字幕源',
              desc: 'OpenSubtitles 等在线字幕',
              trailing: const AppTag('即将推出', variant: TagVariant.plan),
            ),
            SetRow(
              title: '视频刮削源',
              desc: 'TMDB / 豆瓣 NFO 元数据来源',
              last: true,
              trailing: AppButton(
                label: '管理刮削源',
                icon: Icons.tune_rounded,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ScraperSourcesPage(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _outputDeviceText(AudioPassthroughCapability? capability) {
    if (capability == null) return '检测中…';
    final device = switch (capability.outputDevice) {
      AudioOutputDevice.hdmi => 'HDMI',
      AudioOutputDevice.spdif => 'S/PDIF 光纤',
      AudioOutputDevice.arc => 'HDMI ARC/eARC',
      AudioOutputDevice.bluetooth => '蓝牙',
      AudioOutputDevice.speaker => '内置扬声器',
      AudioOutputDevice.headphones => '耳机',
      AudioOutputDevice.unknown => '未知',
    };
    final name = capability.deviceName;
    if (name != null && name.isNotEmpty) return '$device · $name';
    return device;
  }
}

/// 音频直通编码的 toggle-tiles（对齐设计稿 `.toggle-tiles`）。
///
/// 每个 tile 控制是否把对应编码加入 [HdrAudioSettings.enabledPassthroughCodecs]。
/// null 表示「设备支持的全部」，首次切换时以设备能力作为初始集合。
class _PassthroughTiles extends StatelessWidget {
  const _PassthroughTiles({
    required this.settings,
    required this.capability,
    required this.onChanged,
  });

  final HdrAudioSettings settings;
  final AudioPassthroughCapability? capability;
  final ValueChanged<List<AudioCodec>?> onChanged;

  static const _codecs = [
    AudioCodec.ac3,
    AudioCodec.dts,
    AudioCodec.truehd,
    AudioCodec.pcm,
  ];

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final enabled = settings.enabledPassthroughCodecs ??
        capability?.supportedCodecs ??
        const <AudioCodec>[];

    void toggle(AudioCodec codec, bool on) {
      final next = {...enabled};
      if (on) {
        next.add(codec);
      } else {
        next.remove(codec);
      }
      onChanged(next.toList());
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 10.0;
          final colWidth = (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final codec in _codecs)
                SizedBox(
                  width: colWidth,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: t.insetBg,
                      border: Border.all(color: t.hairline, width: 0.5),
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusSm),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${codec.displayName} 直通',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: t.text0,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '原始码流直出功放',
                                style:
                                    TextStyle(fontSize: 11.5, color: t.text2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        AppSwitch(
                          value: enabled.contains(codec),
                          onChanged: (v) => toggle(codec, v),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 清晰度下拉（手动模式下选择默认档位）。
class _QualityDropdown extends StatelessWidget {
  const _QualityDropdown({required this.value, required this.onChanged});

  final VideoQuality value;
  final ValueChanged<VideoQuality> onChanged;

  @override
  Widget build(BuildContext context) => _Dropdown<VideoQuality>(
        value: value,
        onChanged: onChanged,
        items: [
          for (final q in VideoQuality.values)
            DropdownMenuItem(value: q, child: Text(q.label)),
        ],
      );
}

/// 色调映射算法下拉。
class _ToneMappingDropdown extends StatelessWidget {
  const _ToneMappingDropdown({required this.value, required this.onChanged});

  final ToneMappingMode value;
  final ValueChanged<ToneMappingMode> onChanged;

  @override
  Widget build(BuildContext context) => _Dropdown<ToneMappingMode>(
        value: value,
        onChanged: onChanged,
        items: [
          for (final m in ToneMappingMode.values)
            DropdownMenuItem(value: m, child: Text(m.displayName)),
        ],
      );
}

/// 设计稿 `.input` 下拉框风格的通用包装。
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: t.insetBg,
        border: Border.all(color: t.hairline, width: 0.5),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          dropdownColor: t.cardBg,
          icon: Icon(Icons.expand_more_rounded, size: 18, color: t.text2),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: t.text0,
          ),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          items: items,
        ),
      ),
    );
  }
}

/// 设计稿 `.rng` 滑块 + 右侧数值。
class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 150,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: t.accent,
              inactiveTrackColor: t.insetBg,
              thumbColor: t.accentBright,
              overlayColor: t.accent.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: (max - min).round(),
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 11),
        SizedBox(
          width: 34,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: t.text2,
            ),
          ),
        ),
      ],
    );
  }
}

/// 设计稿 `<Note>`：卡片内的浅底说明段落。
class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: t.insetBg,
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          border: Border.all(color: t.hairline, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 15, color: t.text3),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 12, height: 1.5, color: t.text2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
