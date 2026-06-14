import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/data/services/audio_effects_service.dart';
import 'package:my_nas/features/music/data/services/lyrics_translation_service.dart';
import 'package:my_nas/features/music/data/services/music_audio_handler_interface.dart';
import 'package:my_nas/features/music/data/services/scrobble/music_scrobble_service.dart';
import 'package:my_nas/features/music/presentation/pages/music_scraper_sources_page.dart';
import 'package:my_nas/features/music/presentation/pages/scrobble_settings_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_settings_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 桌面「音乐播放」设置 pane。
///
/// 对齐设计稿 `settings_panes.jsx · PaneMusic`：引擎与解码 / 均衡器 / 歌词 /
/// Scrobble 与刮削。主开关、引擎、播放模式、淡入淡出、歌词翻译均接
/// [musicSettingsProvider]；均衡器（eq-bank）内联读写
/// [AudioEffectsService]，Scrobble 总开关与连接状态内联读写
/// [MusicScrobbleService]（凭证 / 授权仍走「配置」页）。
class MusicPane extends ConsumerStatefulWidget {
  const MusicPane({super.key});

  @override
  ConsumerState<MusicPane> createState() => _MusicPaneState();
}

class _MusicPaneState extends ConsumerState<MusicPane> {
  final _eqService = AudioEffectsService.instance;
  final _scrobble = MusicScrobbleService.instance;

  EqualizerState? _eq;
  ScrobbleSettings? _scrobbleSettings;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    await _eqService.init();
    await _scrobble.init();
    if (!mounted) return;
    setState(() {
      _eq = _eqService.state;
      _scrobbleSettings = _scrobble.settings;
    });
  }

  // ----------------------------- 均衡器 -----------------------------

  Future<void> _setEqEnabled(bool enabled) async {
    await _eqService.setEnabled(enabled: enabled);
    if (!mounted) return;
    setState(() => _eq = _eqService.state);
  }

  Future<void> _applyEqPreset(String id) async {
    await _eqService.applyPreset(id);
    if (!mounted) return;
    setState(() => _eq = _eqService.state);
  }

  Future<void> _setEqBand(int index, double gainDb) async {
    await _eqService.setBandGain(index, gainDb);
    if (!mounted) return;
    setState(() => _eq = _eqService.state);
  }

  Future<void> _resetEqFlat() async {
    await _eqService.resetFlat();
    if (!mounted) return;
    setState(() => _eq = _eqService.state);
  }

  // ----------------------------- Scrobble -----------------------------

  Future<void> _setScrobbleEnabled(bool enabled) async {
    final cur = _scrobbleSettings ?? const ScrobbleSettings();
    final next = cur.copyWith(enabled: enabled);
    await _scrobble.applySettings(next);
    if (!mounted) return;
    setState(() => _scrobbleSettings = _scrobble.settings);
  }

  Future<void> _openScrobbleConfig() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ScrobbleSettingsPage()),
    );
    // 配置页可能改了凭证 / 开关，回来刷新内联状态。
    if (!mounted) return;
    setState(() => _scrobbleSettings = _scrobble.settings);
  }

  @override
  Widget build(BuildContext context) {
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

        // 均衡器（内联 eq-bank）
        SetSection(
          title: '均衡器',
          hint: '10 段 · 8 预设 + 自定义',
          children: [
            SetRow(
              title: '启用均衡器',
              desc: _eqPlatformNote,
              last: _eq == null,
              trailing: AppSwitch(
                value: _eq?.enabled ?? false,
                onChanged: _eq == null ? null : _setEqEnabled,
              ),
            ),
            if (_eq != null) ...[
              _EqPresetChips(
                presetId: _eq!.presetId,
                enabled: _eq!.enabled,
                onSelect: _applyEqPreset,
                onReset: _resetEqFlat,
              ),
              _EqBank(
                gains: _eq!.gains,
                enabled: _eq!.enabled,
                onChanged: _setEqBand,
              ),
            ],
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
              desc: '译文双行显示 · Google 翻译（免费，需联网）',
              trailing: AppSwitch(
                value: settings.lyricsTranslateEnabled,
                onChanged: (v) =>
                    notifier.setLyricsTranslateEnabled(enabled: v),
              ),
            ),
            SetRow(
              title: '翻译目标语言',
              desc: '译文显示为该语言',
              last: true,
              trailing: Opacity(
                opacity: settings.lyricsTranslateEnabled ? 1 : 0.5,
                child: _LangDropdown(
                  value: LyricsTranslationLang.fromBcp47(
                    settings.lyricsTranslateLang,
                  ),
                  enabled: settings.lyricsTranslateEnabled,
                  onChanged: (lang) =>
                      notifier.setLyricsTranslateLang(lang.bcp47),
                ),
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
              desc: '听满阈值后上报，离线自动重试',
              trailing: AppSwitch(
                value: _scrobbleSettings?.enabled ?? false,
                onChanged:
                    _scrobbleSettings == null ? null : _setScrobbleEnabled,
              ),
            ),
            SetRow(
              title: 'Last.fm',
              desc: _lastfmConfigured ? '已连接 · 凭证已配置' : '未连接 · 需 API key/secret/sk',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusDot(_lastfmConfigured ? DotStatus.ok : DotStatus.off),
                  const SizedBox(width: 10),
                  AppButton(
                    label: '配置',
                    icon: Icons.podcasts_rounded,
                    variant: AppButtonVariant.ghost,
                    dense: true,
                    onPressed: _openScrobbleConfig,
                  ),
                ],
              ),
            ),
            SetRow(
              title: 'ListenBrainz',
              desc: _listenbrainzConfigured ? '已连接 · token 已配置' : '未连接 · 需 user token',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusDot(
                    _listenbrainzConfigured ? DotStatus.ok : DotStatus.off,
                  ),
                  const SizedBox(width: 10),
                  AppButton(
                    label: '配置',
                    icon: Icons.key_rounded,
                    variant: AppButtonVariant.ghost,
                    dense: true,
                    onPressed: _openScrobbleConfig,
                  ),
                ],
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

  bool get _lastfmConfigured {
    final s = _scrobbleSettings;
    if (s == null) return false;
    return (s.lastfmApiKey?.isNotEmpty ?? false) &&
        (s.lastfmApiSecret?.isNotEmpty ?? false) &&
        (s.lastfmSessionKey?.isNotEmpty ?? false);
  }

  bool get _listenbrainzConfigured =>
      _scrobbleSettings?.listenbrainzToken?.isNotEmpty ?? false;

  String get _eqPlatformNote {
    if (Platform.isAndroid) return '系统硬件均衡器（AudioEffect）';
    if (Platform.isIOS) return 'iOS 当前播放引擎暂不支持 EQ';
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return '桌面端：仅 FFmpeg 引擎生效（mpv af 滤镜）';
    }
    return '10 段 EQ + 8 个预设';
  }
}

/// 均衡器预设 chip 行（+ 重置）。对应设计稿 EQ 预设按钮组。
class _EqPresetChips extends StatelessWidget {
  const _EqPresetChips({
    required this.presetId,
    required this.enabled,
    required this.onSelect,
    required this.onReset,
  });

  final String presetId;
  final bool enabled;
  final ValueChanged<String> onSelect;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final p in kEqPresets)
                      AppChip(
                        label: p.name,
                        active: presetId == p.id,
                        compact: true,
                        onTap: () => onSelect(p.id),
                      ),
                    if (presetId == 'custom')
                      const AppChip(
                        label: '自定义',
                        active: true,
                        compact: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: '重置为平直',
                icon: Icon(Icons.restart_alt_rounded, size: 18, color: t.text2),
                onPressed: onReset,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 内联 eq-bank：10 段垂直滑块。对应设计稿 `.eq-bank`。
class _EqBank extends StatelessWidget {
  const _EqBank({
    required this.gains,
    required this.enabled,
    required this.onChanged,
  });

  final List<double> gains;
  final bool enabled;
  final void Function(int index, double gainDb) onChanged;

  String _bandLabel(int hz) => hz >= 1000 ? '${hz ~/ 1000}k' : '$hz';

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SizedBox(
          height: 168,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < kEqBands.length; i++)
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 16,
                        child: Text(
                          gains[i].toStringAsFixed(0),
                          style: TextStyle(
                            fontSize: 10,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: t.text3,
                          ),
                        ),
                      ),
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 4,
                              activeTrackColor: t.accent,
                              inactiveTrackColor: t.insetBg,
                              thumbColor: t.accentBright,
                              overlayColor: t.accent.withValues(alpha: 0.18),
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                            ),
                            child: Slider(
                              value: gains[i].clamp(kEqMinGain, kEqMaxGain),
                              min: kEqMinGain,
                              max: kEqMaxGain,
                              divisions: 48,
                              onChanged:
                                  enabled ? (v) => onChanged(i, v) : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 14,
                        child: Text(
                          _bandLabel(kEqBands[i]),
                          style: TextStyle(
                            fontSize: 9,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: t.text3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 歌词翻译目标语言下拉。对应设计稿 `.input` 下拉框风格。
class _LangDropdown extends StatelessWidget {
  const _LangDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final LyricsTranslationLang value;
  final bool enabled;
  final ValueChanged<LyricsTranslationLang> onChanged;

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
        child: DropdownButton<LyricsTranslationLang>(
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
          onChanged: enabled
              ? (v) {
                  if (v != null) onChanged(v);
                }
              : null,
          items: [
            for (final lang in LyricsTranslationLang.values)
              DropdownMenuItem(
                value: lang,
                child: Text(lang.displayName),
              ),
          ],
        ),
      ),
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
