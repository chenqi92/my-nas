import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/source_form_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/capability/playback_capability_service.dart';
import 'package:my_nas/features/video/data/services/opensubtitles_service.dart';
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
import 'package:my_nas/shared/providers/video_backend_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 桌面「设置 · 视频播放」详情 pane（对齐设计稿 settings_panes.jsx PaneVideo）。
///
/// 播放 / HDR 与后端 / 音频直通 / 投屏与转码 / 字幕 五张卡片。能接的开关、
/// 分段、滑块直接读写真实 provider（清晰度、HDR/音频、字幕翻译、自动续播 /
/// 自动下一集、视频后端、投屏设备发现）；视频刮削源用按钮打开现有管理页。
/// 服务端 / 客户端转码各为一个持久化开关（[QualitySettings.allowServerTranscoding]
/// / [allowClientTranscoding]），在播放初始化时若关闭则把对应能力降级为仅原画；
/// 字幕源接 [hasOpenSubtitlesConfigProvider] 显示连接状态点，「账户」按钮打开
/// [SourceFormPage]（账号 / API Key 配置是多步表单，保留弹窗）。
class VideoPane extends ConsumerWidget {
  const VideoPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);

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

    final videoBackend = ref.watch(videoBackendProvider);
    final videoBackendNotifier = ref.read(videoBackendProvider.notifier);

    final hasOpenSubtitles = ref.watch(hasOpenSubtitlesConfigProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.movie_outlined,
          title: l.paneVideoHeadTitle,
          subtitle: l.paneVideoHeadSubtitle,
        ),

        // ---- 播放 ----
        SetSection(
          title: l.paneVideoSectionPlayback,
          hint: l.paneVideoSectionPlaybackHint,
          children: [
            SetRow(
              title: l.paneVideoQualityTitle,
              desc: l.paneVideoQualityDesc,
              trailing: AppSegmented<bool>(
                value: quality.enableAdaptiveSuggestion,
                onChanged: (v) =>
                    qualityNotifier.setEnableAdaptiveSuggestion(enabled: v),
                options: [
                  AppSegmentedOption(value: true, label: l.paneVideoQualityAdaptive),
                  AppSegmentedOption(value: false, label: l.paneVideoQualityManual),
                ],
              ),
            ),
            if (!quality.enableAdaptiveSuggestion)
              SetRow(
                title: l.paneVideoDefaultQualityTitle,
                desc: l.paneVideoDefaultQualityDesc,
                trailing: _QualityDropdown(
                  value: quality.defaultQuality,
                  onChanged: qualityNotifier.setDefaultQuality,
                ),
              ),
            SetRow(
              title: l.paneVideoRememberQualityTitle,
              desc: l.paneVideoRememberQualityDesc,
              trailing: AppSwitch(
                value: quality.rememberPerVideo,
                onChanged: (v) =>
                    qualityNotifier.setRememberPerVideo(enabled: v),
              ),
            ),
            SetRow(
              title: l.paneVideoAutoResumeTitle,
              desc: l.paneVideoAutoResumeDesc,
              trailing: AppSwitch(
                value: playback.rememberPosition,
                onChanged: (v) =>
                    playbackNotifier.setRememberPosition(enabled: v),
              ),
            ),
            SetRow(
              title: l.paneVideoAutoNextTitle,
              desc: l.paneVideoAutoNextDesc,
              trailing: AppSwitch(
                value: playback.autoPlayNext,
                onChanged: (v) => playbackNotifier.setAutoPlayNext(enabled: v),
              ),
            ),
            SetRow(
              title: l.paneVideoBufferThresholdTitle,
              desc: l.paneVideoBufferThresholdDesc,
              last: true,
              trailing: _SliderField(
                value: quality.bufferThresholdSeconds.toDouble(),
                min: 1,
                max: 15,
                label: l.paneVideoSecondsLabel(quality.bufferThresholdSeconds),
                onChanged: (v) =>
                    qualityNotifier.setBufferThreshold(v.round()),
              ),
            ),
          ],
        ),

        // ---- HDR 与后端 ----
        SetSection(
          title: l.paneVideoSectionHdr,
          hint: l.paneVideoSectionHdrHint,
          children: [
            SetRow(
              title: 'HDR10 / HLG',
              desc: l.paneVideoHdrToggleDesc,
              trailing: AppSwitch(
                value: hdrSettings.hdrMode != HdrMode.disabled,
                onChanged: (v) => hdrAudioNotifier.setHdrMode(
                  v ? HdrMode.auto : HdrMode.disabled,
                ),
              ),
            ),
            SetRow(
              title: l.paneVideoToneMappingTitle,
              desc: l.paneVideoToneMappingDesc,
              trailing: _ToneMappingDropdown(
                value: hdrSettings.toneMappingMode,
                onChanged: hdrAudioNotifier.setToneMappingMode,
              ),
            ),
            SetRow(
              title: l.paneVideoBackendTitle,
              desc: l.paneVideoBackendDesc,
              last: true,
              trailing: AppSegmented<VideoBackendPreference>(
                value: videoBackend,
                onChanged: videoBackendNotifier.setPreference,
                options: [
                  AppSegmentedOption(
                    value: VideoBackendPreference.auto,
                    label: l.paneVideoBackendAuto,
                  ),
                  const AppSegmentedOption(
                    value: VideoBackendPreference.mediaKit,
                    label: 'media_kit',
                  ),
                  AppSegmentedOption(
                    value: VideoBackendPreference.native,
                    label: l.paneVideoBackendNative,
                  ),
                ],
              ),
            ),
          ],
        ),

        // ---- 音频直通 ----
        SetSection(
          title: l.paneVideoSectionAudio,
          hint: 'AC3 / DTS / TrueHD / PCM',
          children: [
            _PassthroughTiles(
              settings: hdrSettings,
              capability: hdrAudio.audioCapability,
              onChanged: hdrAudioNotifier.setEnabledPassthroughCodecs,
            ),
            SetRow(
              title: l.paneVideoOutputPortTitle,
              desc: l.paneVideoOutputPortDesc,
              trailing: Text(
                _outputDeviceText(l, hdrAudio.audioCapability),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: t.text1,
                ),
              ),
            ),
            SetRow(
              title: l.paneVideoAlwaysDecodeTitle,
              desc: l.paneVideoAlwaysDecodeDesc,
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
          title: l.paneVideoSectionCast,
          children: [
            SetRow(
              title: l.paneVideoCastTitle,
              desc: cast.isCasting
                  ? l.paneVideoCastDescCasting(
                      cast.session?.device.name ?? l.paneVideoCastConnectedDevice)
                  : cast.isDiscovering
                      ? l.paneVideoCastDescDiscovering
                      : l.paneVideoCastDescIdle,
              trailing: AppButton(
                label: cast.isDiscovering
                    ? l.paneVideoCastDiscoveringButton
                    : l.paneVideoCastDiscoverButton,
                icon: Icons.wifi_tethering_rounded,
                dense: true,
                onPressed:
                    cast.isDiscovering ? null : castNotifier.startDiscovery,
              ),
            ),
            SetRow(
              title: l.paneVideoServerTranscodeTitle,
              desc: l.paneVideoServerTranscodeDesc,
              trailing: AppSwitch(
                value: quality.allowServerTranscoding,
                onChanged: (v) =>
                    qualityNotifier.setAllowServerTranscoding(enabled: v),
              ),
            ),
            SetRow(
              title: l.paneVideoClientTranscodeTitle,
              desc: l.paneVideoClientTranscodeDesc,
              trailing: AppSwitch(
                value: quality.allowClientTranscoding,
                onChanged: (v) =>
                    qualityNotifier.setAllowClientTranscoding(enabled: v),
              ),
            ),
            SetRow(
              title: l.paneVideoUnsupportedHintTitle,
              desc: l.paneVideoUnsupportedHintDesc,
              trailing: AppSwitch(
                value: quality.showUnsupportedHint,
                onChanged: (v) =>
                    qualityNotifier.setShowUnsupportedHint(enabled: v),
              ),
            ),
            _NoteRow(
              text: l.paneVideoTranscodeNote,
            ),
          ],
        ),

        // ---- 字幕 ----
        SetSection(
          title: l.paneVideoSectionSubtitle,
          hint: l.paneVideoSectionSubtitleHint,
          bottomMargin: false,
          children: [
            SetRow(
              title: l.paneVideoBilingualTitle,
              desc: l.paneVideoBilingualDesc,
              trailing: AppSwitch(
                value: subtitle.bilingual,
                onChanged: (v) => subtitleNotifier.setBilingual(value: v),
              ),
            ),
            SetRow(
              title: l.paneVideoTranslateEngineTitle,
              desc: l.paneVideoTranslateEngineDesc,
              trailing: AppSegmented<bool>(
                value: subtitle.providerId != 'off',
                onChanged: (v) =>
                    subtitleNotifier.setProvider(v ? 'google_free' : 'off'),
                options: [
                  AppSegmentedOption(value: true, label: l.paneVideoTranslateEngineGoogle),
                  AppSegmentedOption(value: false, label: l.paneVideoTranslateEngineOff),
                ],
              ),
            ),
            SetRow(
              title: l.paneVideoTranslateCacheTitle,
              desc: l.paneVideoTranslateCacheDesc,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppSwitch(
                    value: subtitle.useCache,
                    onChanged: (v) => subtitleNotifier.setUseCache(value: v),
                  ),
                  const SizedBox(width: 10),
                  AppChip(
                    label: l.paneVideoClearCacheChip,
                    icon: Icons.delete_outline_rounded,
                    onTap: () async {
                      await SubtitleTranslationService.instance.clearCache();
                      if (!context.mounted) return;
                      context.showSuccessSnackBar(l.paneVideoCacheCleared);
                    },
                  ),
                ],
              ),
            ),
            SetRow(
              title: l.paneVideoSubtitleSourceTitle,
              desc: hasOpenSubtitles
                  ? l.paneVideoSubtitleSourceDescConfigured
                  : l.paneVideoSubtitleSourceDescPublic,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusDot(hasOpenSubtitles ? DotStatus.ok : DotStatus.off),
                  const SizedBox(width: 8),
                  AppChip(
                    label: l.paneVideoAccountChip,
                    onTap: () => _openOpenSubtitlesAccount(context, ref),
                  ),
                ],
              ),
            ),
            SetRow(
              title: l.paneVideoScraperSourceTitle,
              desc: l.paneVideoScraperSourceDesc,
              last: true,
              trailing: AppButton(
                label: l.paneVideoScraperSourceButton,
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

  String _outputDeviceText(
    AppLocalizations l,
    AudioPassthroughCapability? capability,
  ) {
    if (capability == null) return l.paneVideoOutputDetecting;
    final device = switch (capability.outputDevice) {
      AudioOutputDevice.hdmi => 'HDMI',
      AudioOutputDevice.spdif => l.paneVideoOutputSpdif,
      AudioOutputDevice.arc => 'HDMI ARC/eARC',
      AudioOutputDevice.bluetooth => l.paneVideoOutputBluetooth,
      AudioOutputDevice.speaker => l.paneVideoOutputSpeaker,
      AudioOutputDevice.headphones => l.paneVideoOutputHeadphones,
      AudioOutputDevice.unknown => l.paneVideoOutputUnknown,
    };
    final name = capability.deviceName;
    if (name != null && name.isNotEmpty) return '$device · $name';
    return device;
  }

  /// 打开 OpenSubtitles 账户配置表单。若已存在 opensubtitles 源则进入编辑模式，
  /// 否则新建。账号 / API Key / 密码属多步表单，复用 [SourceFormPage]。
  void _openOpenSubtitlesAccount(BuildContext context, WidgetRef ref) {
    final sources = ref.read(sourcesProvider).valueOrNull ?? const [];
    SourceEntity? existing;
    for (final s in sources) {
      if (s.type == SourceType.opensubtitles) {
        existing = s;
        break;
      }
    }
    SourceFormPage.openAdaptive<void>(
      context,
      sourceType: SourceType.opensubtitles,
      existingSource: existing,
    );
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
    final l = AppLocalizations.of(context);
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
                                l.paneVideoCodecPassthroughTitle(
                                    codec.displayName),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: t.text0,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l.paneVideoCodecPassthroughDesc,
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
