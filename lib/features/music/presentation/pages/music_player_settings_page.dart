import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/data/services/lyrics_translation_service.dart';
import 'package:my_nas/features/music/data/services/music_audio_handler_interface.dart';
import 'package:my_nas/features/music/presentation/pages/audio_effects_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_settings_provider.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 音乐播放器设置页面
///
/// 提供音乐播放器的各项设置，包括：
/// - 播放引擎选择（平台原生 / FFmpeg）
/// - 播放模式
/// - 音量控制
/// - 淡入淡出时长
/// - 无缝播放、歌词显示等开关选项
class MusicPlayerSettingsPage extends ConsumerWidget {
  const MusicPlayerSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(musicSettingsProvider);
    final notifier = ref.read(musicSettingsProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return HideBottomNavWrapper(
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : null,
        appBar: AppBar(
          leading: const RoundedBackButton(),
          backgroundColor: isDark ? AppColors.darkSurface : null,
          title: Text(
            context.l10n.musicPlayerSettingsPageTitle,
            style: TextStyle(
              color: isDark ? AppColors.darkOnSurface : null,
              fontWeight: FontWeight.bold,
            ),
          ),
          iconTheme: IconThemeData(
            color: isDark ? AppColors.darkOnSurface : null,
          ),
        ),
        body: ListView(
          padding: AppSpacing.paddingMd,
          children: [
            // 播放引擎
            _buildEngineSection(context, settings, notifier, isDark),
            const SizedBox(height: AppSpacing.lg),
            // 播放模式
            _buildPlayModeSection(context, settings, notifier, isDark),
            const SizedBox(height: AppSpacing.lg),
            // 音量控制
            _buildVolumeSection(context, settings, notifier, isDark),
            const SizedBox(height: AppSpacing.lg),
            // 淡入淡出
            _buildCrossfadeSection(context, settings, notifier, isDark),
            const SizedBox(height: AppSpacing.lg),
            // 开关选项
            _buildSwitchOptions(context, settings, notifier, isDark),
            const SizedBox(height: AppSpacing.lg),
            // 均衡器入口
            _buildEqualizerEntry(context, isDark),
            const SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineSection(
    BuildContext context,
    MusicSettings settings,
    MusicSettingsNotifier notifier,
    bool isDark,
  ) => _SettingsSection(
      title: context.l10n.musicPlayerEngineSection,
      subtitle: context.l10n.musicPlayerEngineHint,
      icon: Icons.memory_rounded,
      isDark: isDark,
      child: Column(
        children: [
          Row(
            children: [
              _EngineButton(
                icon: Icons.phone_android_rounded,
                title: context.l10n.musicPlayerEnginePlatformNativeTitle,
                subtitle: context.l10n.musicPlayerEnginePlatformNativeDesc,
                isSelected: settings.playerEngine == MusicPlayerEngine.justAudio,
                isDark: isDark,
                onTap: () => _switchEngine(
                  context,
                  notifier,
                  MusicPlayerEngine.justAudio,
                  settings.playerEngine,
                ),
              ),
              const SizedBox(width: 12),
              _EngineButton(
                icon: Icons.graphic_eq_rounded,
                title: context.l10n.musicPlayerEngineFFmpegTitle,
                subtitle: context.l10n.musicPlayerEngineFFmpegDesc,
                isSelected: settings.playerEngine == MusicPlayerEngine.mediaKit,
                isDark: isDark,
                onTap: () => _switchEngine(
                  context,
                  notifier,
                  MusicPlayerEngine.mediaKit,
                  settings.playerEngine,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.amber.withValues(alpha: 0.15)
                  : Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Colors.amber[700],
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    settings.playerEngine == MusicPlayerEngine.mediaKit
                        ? context.l10n.musicPlayerEngineFFmpegInfoText
                        : Platform.isIOS
                            ? context.l10n.musicPlayerEngineNativeInfoIOS
                            : context.l10n.musicPlayerEngineNativeInfoOther,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.amber[300] : Colors.amber[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

  void _switchEngine(
    BuildContext context,
    MusicSettingsNotifier notifier,
    MusicPlayerEngine newEngine,
    MusicPlayerEngine currentEngine,
  ) {
    if (newEngine == currentEngine) return;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.musicPlayerEngineSwitchDialogTitle),
        content: Text(
          newEngine == MusicPlayerEngine.mediaKit
              ? context.l10n.musicPlayerEngineSwitchToFFmpegContent
              : context.l10n.musicPlayerEngineSwitchToNativeContent,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.musicPlayerEngineSwitchCancel),
          ),
          FilledButton(
            onPressed: () {
              notifier.setPlayerEngine(newEngine);
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.l10n.musicPlayerEngineChangedSnackBar),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Text(context.l10n.musicPlayerEngineSwitchConfirm),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayModeSection(
    BuildContext context,
    MusicSettings settings,
    MusicSettingsNotifier notifier,
    bool isDark,
  ) => _SettingsSection(
      title: context.l10n.musicPlayerPlayModeSection,
      icon: Icons.repeat_rounded,
      isDark: isDark,
      child: Row(
        children: [
          _PlayModeButton(
            icon: Icons.repeat_rounded,
            label: context.l10n.musicPlayerPlayModeLoop,
            isSelected: settings.playMode == PlayMode.loop,
            isDark: isDark,
            onTap: () => notifier.setPlayMode(PlayMode.loop),
          ),
          const SizedBox(width: 12),
          _PlayModeButton(
            icon: Icons.repeat_one_rounded,
            label: context.l10n.musicPlayerPlayModeRepeatOne,
            isSelected: settings.playMode == PlayMode.repeatOne,
            isDark: isDark,
            onTap: () => notifier.setPlayMode(PlayMode.repeatOne),
          ),
          const SizedBox(width: 12),
          _PlayModeButton(
            icon: Icons.shuffle_rounded,
            label: context.l10n.musicPlayerPlayModeShuffle,
            isSelected: settings.playMode == PlayMode.shuffle,
            isDark: isDark,
            onTap: () => notifier.setPlayMode(PlayMode.shuffle),
          ),
        ],
      ),
    );

  Widget _buildVolumeSection(
    BuildContext context,
    MusicSettings settings,
    MusicSettingsNotifier notifier,
    bool isDark,
  ) => _SettingsSection(
      title: context.l10n.musicPlayerVolumeSection,
      icon: Icons.volume_up_rounded,
      isDark: isDark,
      child: Row(
        children: [
          Icon(
            settings.volume == 0
                ? Icons.volume_off_rounded
                : settings.volume < 0.5
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
            color: AppColors.primary,
            size: 22,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.08),
                thumbColor: AppColors.primary,
                overlayColor: AppColors.primary.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: settings.volume,
                onChanged: notifier.setVolume,
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 52),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${(settings.volume * 100).round()}%',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );

  Widget _buildCrossfadeSection(
    BuildContext context,
    MusicSettings settings,
    MusicSettingsNotifier notifier,
    bool isDark,
  ) => _SettingsSection(
      title: context.l10n.musicPlayerCrossfadeSection,
      subtitle: context.l10n.musicPlayerCrossfadeSubtitle,
      icon: Icons.compare_arrows_rounded,
      isDark: isDark,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: availableCrossfadeDurations.map((duration) {
          final isSelected = duration == settings.crossfadeDuration;
          return _DurationChip(
            label: duration == 0 ? context.l10n.musicPlayerCrossfadeOff : context.l10n.musicPlayerCrossfadeDuration(duration),
            isSelected: isSelected,
            isDark: isDark,
            onTap: () => notifier.setCrossfadeDuration(duration),
          );
        }).toList(),
      ),
    );

  Widget _buildEqualizerEntry(BuildContext context, bool isDark) =>
      _SettingsSection(
        title: context.l10n.musicPlayerEqualizerSection,
        subtitle: context.l10n.musicPlayerEqualizerHint,
        icon: Icons.equalizer_rounded,
        isDark: isDark,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.tune_rounded),
          title: Text(context.l10n.musicPlayerEqualizerOpen),
          subtitle: Text(context.l10n.musicPlayerEqualizerNote),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const AudioEffectsPage()),
          ),
        ),
      );

  Widget _buildSwitchOptions(
    BuildContext context,
    MusicSettings settings,
    MusicSettingsNotifier notifier,
    bool isDark,
  ) => Column(
      children: [
        _SettingsSwitch(
          icon: Icons.graphic_eq_rounded,
          title: context.l10n.musicPlayerGaplessPlaybackTitle,
          subtitle: context.l10n.musicPlayerGaplessPlaybackDesc,
          value: settings.gaplessPlayback,
          isDark: isDark,
          onChanged: (value) => notifier.setGaplessPlayback(enabled: value),
        ),
        const SizedBox(height: 12),
        _SettingsSwitch(
          icon: Icons.lyrics_rounded,
          title: context.l10n.musicPlayerLyricsShowTitle,
          subtitle: context.l10n.musicPlayerLyricsShowDesc,
          value: settings.showLyrics,
          isDark: isDark,
          onChanged: (value) => notifier.setShowLyrics(enabled: value),
        ),
        const SizedBox(height: 12),
        _SettingsSwitch(
          icon: Icons.play_circle_outline_rounded,
          title: context.l10n.musicPlayerAutoPlayOnConnectTitle,
          subtitle: context.l10n.musicPlayerAutoPlayOnConnectDesc,
          value: settings.autoPlayOnConnect,
          isDark: isDark,
          onChanged: (value) => notifier.setAutoPlayOnConnect(enabled: value),
        ),
        const SizedBox(height: 12),
        _SettingsSwitch(
          icon: Icons.translate_rounded,
          title: context.l10n.musicPlayerLyricsTranslateTitle,
          subtitle: context.l10n.musicPlayerLyricsTranslateDesc,
          value: settings.lyricsTranslateEnabled,
          isDark: isDark,
          onChanged: (value) => notifier.setLyricsTranslateEnabled(enabled: value),
        ),
        if (settings.lyricsTranslateEnabled) ...[
          const SizedBox(height: 8),
          _LyricsTranslateLangTile(settings: settings, notifier: notifier, isDark: isDark),
        ],
      ],
    );
}

class _LyricsTranslateLangTile extends StatelessWidget {
  const _LyricsTranslateLangTile({
    required this.settings,
    required this.notifier,
    required this.isDark,
  });

  final MusicSettings settings;
  final MusicSettingsNotifier notifier;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final current = LyricsTranslationLang.fromBcp47(settings.lyricsTranslateLang);
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.language_rounded,
              size: 20,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.musicPlayerLyricsTranslateLangTitle,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
            Text(
              current.displayName,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<LyricsTranslationLang>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.l10n.musicPlayerLyricsTranslateLangDialogTitle),
        children: [
          for (final lang in LyricsTranslationLang.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, lang),
              child: Text(lang.displayName),
            ),
        ],
      ),
    );
    if (picked != null) {
      await notifier.setLyricsTranslateLang(picked.bcp47);
    }
  }
}

/// 设置区块组件
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.isDark,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
}

/// 播放模式按钮
class _PlayModeButton extends StatelessWidget {
  const _PlayModeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? null
                : Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black54),
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
}

/// 时长选择芯片
class _DurationChip extends StatelessWidget {
  const _DurationChip({
    required this.label,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.08),
                ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.black54),
          ),
        ),
      ),
    );
}

/// 设置开关组件
class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: value
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: value
                  ? AppColors.primary
                  : (isDark ? Colors.white54 : Colors.black45),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.primary,
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return null;
            }),
          ),
        ],
      ),
    );
}

/// 引擎选择按钮
class _EngineButton extends StatelessWidget {
  const _EngineButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(14),
            border: isSelected
                ? null
                : Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.2)
                      : AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? Colors.white : AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white : Colors.black87),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.8)
                      : (isDark ? Colors.white54 : Colors.black45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
}
