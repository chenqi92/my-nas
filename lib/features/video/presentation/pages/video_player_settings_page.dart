import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/translation/translation_provider.dart';
import 'package:my_nas/core/translation/translation_providers.dart';
import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_translation_service.dart';
import 'package:my_nas/features/video/domain/entities/audio_capability.dart';
import 'package:my_nas/features/video/domain/entities/hdr_capability.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';
import 'package:my_nas/features/video/presentation/providers/hdr_audio_settings_provider.dart';
import 'package:my_nas/features/video/presentation/providers/quality_provider.dart';
import 'package:my_nas/features/video/presentation/providers/subtitle_translation_settings_provider.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 视频播放器设置页面
class VideoPlayerSettingsPage extends ConsumerWidget {
  const VideoPlayerSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(qualitySettingsProvider);
    final hdrAudioSettings = ref.watch(hdrAudioSettingsProvider);
    final translation = ref.watch(subtitleTranslationSettingsProvider);

    return HideBottomNavWrapper(
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : null,
        appBar: AppBar(
          leading: const RoundedBackButton(),
          backgroundColor: isDark ? AppColors.darkSurface : null,
          title: Text(
            context.l10n.videoPlayerSettingsPageTitle,
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
          // 清晰度设置
          _buildSectionHeader(context, context.l10n.videoPlayerSettingsSectionQuality, Icons.high_quality_rounded, isDark),
          const SizedBox(height: AppSpacing.sm),
          _buildSettingsCard(
            context,
            isDark,
            children: [
              // 默认清晰度
              _buildSettingsTile(
                context,
                isDark,
                icon: Icons.hd_rounded,
                iconColor: AppColors.primary,
                title: context.l10n.videoPlayerSettingsDefaultQuality,
                subtitle: settings.defaultQuality.label,
                onTap: () => _showQualityPicker(context, ref, settings.defaultQuality, isDark),
              ),
              _buildDivider(isDark),
              // 自适应建议
              _buildSwitchTile(
                context,
                isDark,
                icon: Icons.auto_awesome_rounded,
                iconColor: AppColors.accent,
                title: context.l10n.videoPlayerSettingsAdaptiveSuggestion,
                subtitle: context.l10n.videoPlayerSettingsAdaptiveSuggestionDesc,
                value: settings.enableAdaptiveSuggestion,
                onChanged: (value) {
                  ref.read(qualitySettingsProvider.notifier).setEnableAdaptiveSuggestion(enabled: value);
                },
              ),
              _buildDivider(isDark),
              // 记住选择
              _buildSwitchTile(
                context,
                isDark,
                icon: Icons.history_rounded,
                iconColor: AppColors.info,
                title: context.l10n.videoPlayerSettingsRememberQuality,
                subtitle: context.l10n.videoPlayerSettingsRememberQualityDesc,
                value: settings.rememberPerVideo,
                onChanged: (value) {
                  ref.read(qualitySettingsProvider.notifier).setRememberPerVideo(enabled: value);
                },
              ),
              _buildDivider(isDark),
              // 缓冲阈值
              _buildSettingsTile(
                context,
                isDark,
                icon: Icons.timer_rounded,
                iconColor: AppColors.warning,
                title: context.l10n.videoPlayerSettingsBufferThreshold,
                subtitle: context.l10n.videoPlayerSettingsBufferThresholdValue(settings.bufferThresholdSeconds),
                onTap: () => _showBufferThresholdPicker(context, ref, settings.bufferThresholdSeconds, isDark),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // 投屏设置
          _buildSectionHeader(context, context.l10n.videoPlayerSettingsSectionCasting, Icons.cast_rounded, isDark),
          const SizedBox(height: AppSpacing.sm),
          _buildSettingsCard(
            context,
            isDark,
            children: [
              _buildInfoTile(
                context,
                isDark,
                icon: Icons.devices_rounded,
                iconColor: AppColors.secondary,
                title: context.l10n.videoPlayerSettingsSupportedCastingProtocols,
                subtitle: context.l10n.videoPlayerSettingsCastingProtocols,
              ),
              _buildDivider(isDark),
              _buildInfoTile(
                context,
                isDark,
                icon: Icons.info_outline_rounded,
                iconColor: AppColors.tertiary,
                title: context.l10n.videoPlayerSettingsCastingUsage,
                subtitle: context.l10n.videoPlayerSettingsCastingUsageDesc,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // 转码设置
          _buildSectionHeader(context, context.l10n.videoPlayerSettingsSectionTranscoding, Icons.settings_applications_rounded, isDark),
          const SizedBox(height: AppSpacing.sm),
          _buildSettingsCard(
            context,
            isDark,
            children: [
              _buildInfoTile(
                context,
                isDark,
                icon: Icons.cloud_rounded,
                iconColor: AppColors.primary,
                title: context.l10n.videoPlayerSettingsServerTranscoding,
                subtitle: context.l10n.videoPlayerSettingsServerTranscodingDesc,
              ),
              _buildDivider(isDark),
              _buildInfoTile(
                context,
                isDark,
                icon: Icons.phone_android_rounded,
                iconColor: AppColors.accent,
                title: context.l10n.videoPlayerSettingsClientTranscoding,
                subtitle: context.l10n.videoPlayerSettingsClientTranscodingDesc,
              ),
              _buildDivider(isDark),
              _buildSwitchTile(
                context,
                isDark,
                icon: Icons.notifications_rounded,
                iconColor: AppColors.warning,
                title: context.l10n.videoPlayerSettingsUnsupportedTranscodingHint,
                subtitle: context.l10n.videoPlayerSettingsUnsupportedTranscodingHintDesc,
                value: settings.showUnsupportedHint,
                onChanged: (value) {
                  ref.read(qualitySettingsProvider.notifier).setShowUnsupportedHint(enabled: value);
                },
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // HDR 设置
          _buildSectionHeader(context, context.l10n.videoPlayerSettingsSectionHdr, Icons.hdr_on_rounded, isDark),
          const SizedBox(height: AppSpacing.sm),
          _buildSettingsCard(
            context,
            isDark,
            children: [
              // HDR 模式
              _buildSettingsTile(
                context,
                isDark,
                icon: Icons.auto_awesome_rounded,
                iconColor: AppColors.primary,
                title: context.l10n.videoPlayerSettingsHdrMode,
                subtitle: _getHdrModeLabel(hdrAudioSettings.settings.hdrMode, context),
                onTap: () => _showHdrModePicker(context, ref, hdrAudioSettings, isDark),
              ),
              _buildDivider(isDark),
              // 色调映射
              _buildSettingsTile(
                context,
                isDark,
                icon: Icons.tune_rounded,
                iconColor: AppColors.accent,
                title: context.l10n.videoPlayerSettingsToneMapping,
                subtitle: _getToneMappingLabel(hdrAudioSettings.settings.toneMappingMode, context),
                onTap: () => _showToneMappingPicker(context, ref, hdrAudioSettings, isDark),
              ),
              _buildDivider(isDark),
              // 设备能力
              _buildInfoTile(
                context,
                isDark,
                icon: Icons.monitor_rounded,
                iconColor: AppColors.info,
                title: context.l10n.videoPlayerSettingsDeviceHdrCapability,
                subtitle: _getHdrCapabilityText(hdrAudioSettings.hdrCapability, context),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // 音频直通设置
          _buildSectionHeader(context, context.l10n.videoPlayerSettingsSectionAudioPassthrough, Icons.surround_sound_rounded, isDark),
          const SizedBox(height: AppSpacing.sm),
          _buildSettingsCard(
            context,
            isDark,
            children: [
              // 音频直通模式
              _buildSettingsTile(
                context,
                isDark,
                icon: Icons.speaker_rounded,
                iconColor: AppColors.secondary,
                title: context.l10n.videoPlayerSettingsAudioPassthroughMode,
                subtitle: _getAudioPassthroughLabel(hdrAudioSettings.settings.audioPassthroughMode, context),
                onTap: () => _showAudioPassthroughPicker(context, ref, hdrAudioSettings, isDark),
              ),
              _buildDivider(isDark),
              // 当前输出设备
              _buildInfoTile(
                context,
                isDark,
                icon: Icons.output_rounded,
                iconColor: AppColors.tertiary,
                title: context.l10n.videoPlayerSettingsCurrentOutputDevice,
                subtitle: _getOutputDeviceText(hdrAudioSettings.audioCapability, context),
              ),
              _buildDivider(isDark),
              // 支持的编码
              _buildInfoTile(
                context,
                isDark,
                icon: Icons.audiotrack_rounded,
                iconColor: AppColors.warning,
                title: context.l10n.videoPlayerSettingsSupportedCodecs,
                subtitle: _getSupportedCodecsText(hdrAudioSettings.audioCapability, context),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // 字幕翻译
          _buildSectionHeader(context, context.l10n.videoPlayerSettingsSectionSubtitleTranslation, Icons.translate_rounded, isDark),
          const SizedBox(height: AppSpacing.sm),
          _buildSettingsCard(
            context,
            isDark,
            children: [
              _buildSettingsTile(
                context,
                isDark,
                icon: Icons.language_rounded,
                iconColor: AppColors.primary,
                title: context.l10n.videoPlayerSettingsDefaultTargetLanguage,
                subtitle: translation.targetLangEnum.displayName,
                onTap: () => _showTranslationLangPicker(
                  context,
                  ref,
                  translation.targetLangEnum,
                  isDark,
                ),
              ),
              _buildDivider(isDark),
              _buildSettingsTile(
                context,
                isDark,
                icon: Icons.cloud_queue_rounded,
                iconColor: AppColors.accent,
                title: context.l10n.videoPlayerSettingsTranslationService,
                subtitle: TranslationProviders.byId(translation.providerId).displayName,
                onTap: () => _showTranslationProviderPicker(
                  context,
                  ref,
                  translation.providerId,
                  isDark,
                ),
              ),
              _buildDivider(isDark),
              _buildSwitchTile(
                context,
                isDark,
                icon: Icons.layers_rounded,
                iconColor: AppColors.info,
                title: context.l10n.videoPlayerSettingsBilingualDisplay,
                subtitle: context.l10n.videoPlayerSettingsBilingualDisplayDesc,
                value: translation.bilingual,
                onChanged: (value) {
                  ref
                      .read(subtitleTranslationSettingsProvider.notifier)
                      .setBilingual(value: value);
                },
              ),
              _buildDivider(isDark),
              _buildSwitchTile(
                context,
                isDark,
                icon: Icons.save_alt_rounded,
                iconColor: AppColors.success,
                title: context.l10n.videoPlayerSettingsEnableTranslationCache,
                subtitle: context.l10n.videoPlayerSettingsEnableTranslationCacheDesc,
                value: translation.useCache,
                onChanged: (value) {
                  ref
                      .read(subtitleTranslationSettingsProvider.notifier)
                      .setUseCache(value: value);
                },
              ),
              _buildDivider(isDark),
              _buildSettingsTile(
                context,
                isDark,
                icon: Icons.delete_outline_rounded,
                iconColor: AppColors.warning,
                title: context.l10n.videoPlayerSettingsClearTranslationCache,
                subtitle: context.l10n.videoPlayerSettingsClearTranslationCacheDesc,
                onTap: () async {
                  await SubtitleTranslationService.instance.clearCache();
                  if (!context.mounted) return;
                  context.showSuccessSnackBar(context.l10n.videoPlayerSettingsClearTranslationCacheSuccess);
                },
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xxxl),
        ],
        ),
      ),
    );
  }

  Future<void> _showTranslationLangPicker(
    BuildContext context,
    WidgetRef ref,
    TranslationLang current,
    bool isDark,
  ) async {
    final picked = await showDialog<TranslationLang>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: isDark ? AppColors.darkSurface : null,
        title: Text(context.l10n.videoPlayerSettingsTranslationLangPickerTitle),
        children: [
          RadioGroup<TranslationLang>(
            groupValue: current,
            onChanged: (v) => Navigator.pop(dialogContext, v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final lang in TranslationLang.values)
                  RadioListTile<TranslationLang>(
                    value: lang,
                    title: Text(lang.displayName),
                    subtitle: Text(lang.bcp47),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) {
      ref
          .read(subtitleTranslationSettingsProvider.notifier)
          .setTargetLang(picked.bcp47);
    }
  }

  Future<void> _showTranslationProviderPicker(
    BuildContext context,
    WidgetRef ref,
    String currentId,
    bool isDark,
  ) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: isDark ? AppColors.darkSurface : null,
        title: Text(context.l10n.videoPlayerSettingsTranslationServicePickerTitle),
        children: [
          RadioGroup<String>(
            groupValue: currentId,
            onChanged: (v) => Navigator.pop(dialogContext, v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final p in TranslationProviders.all)
                  RadioListTile<String>(
                    value: p.id,
                    title: Text(p.displayName),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) {
      ref.read(subtitleTranslationSettingsProvider.notifier).setProvider(picked);
    }
  }

  String _getHdrModeLabel(HdrMode mode, BuildContext context) => switch (mode) {
        HdrMode.auto => context.l10n.videoPlayerSettingsHdrModeAuto,
        HdrMode.passthrough => context.l10n.videoPlayerSettingsHdrModePassthrough,
        HdrMode.tonemapping => context.l10n.videoPlayerSettingsHdrModeToneMapping,
        HdrMode.disabled => context.l10n.videoPlayerSettingsHdrModeDisabled,
      };

  String _getToneMappingLabel(ToneMappingMode mode, BuildContext context) => switch (mode) {
        ToneMappingMode.auto => context.l10n.videoPlayerSettingsToneMappingModeAuto,
        ToneMappingMode.mobius => 'Mobius',
        ToneMappingMode.reinhard => 'Reinhard',
        ToneMappingMode.hable => 'Hable',
        ToneMappingMode.bt2390 => 'BT.2390',
        ToneMappingMode.clip => 'Clip',
      };

  String _getAudioPassthroughLabel(AudioPassthroughMode mode, BuildContext context) => switch (mode) {
        AudioPassthroughMode.auto => context.l10n.videoPlayerSettingsAudioPassthroughModeAuto,
        AudioPassthroughMode.enabled => context.l10n.videoPlayerSettingsAudioPassthroughModeEnabled,
        AudioPassthroughMode.disabled => context.l10n.videoPlayerSettingsAudioPassthroughModeDisabled,
      };

  String _getHdrCapabilityText(HdrCapability? capability, BuildContext context) {
    if (capability == null) return context.l10n.videoPlayerSettingsHdrCapabilityDetecting;
    if (!capability.isSupported) return context.l10n.videoPlayerSettingsHdrCapabilityUnsupported;
    final types = capability.supportedTypes.map((t) => switch (t) {
          HdrType.hdr10 => 'HDR10',
          HdrType.hdr10Plus => 'HDR10+',
          HdrType.hlg => 'HLG',
          HdrType.dolbyVision => 'Dolby Vision',
          HdrType.none => '',
        }).where((s) => s.isNotEmpty).join(', ');
    return types.isEmpty ? context.l10n.videoPlayerSettingsHdrCapabilitySupportedAny : context.l10n.videoPlayerSettingsHdrCapabilitySupported(types);
  }

  String _getOutputDeviceText(AudioPassthroughCapability? capability, BuildContext context) {
    if (capability == null) return context.l10n.videoPlayerSettingsOutputDeviceDetecting;
    final device = switch (capability.outputDevice) {
      AudioOutputDevice.hdmi => context.l10n.videoPlayerSettingsOutputDeviceHdmi,
      AudioOutputDevice.spdif => context.l10n.videoPlayerSettingsOutputDeviceSpdif,
      AudioOutputDevice.arc => context.l10n.videoPlayerSettingsOutputDeviceArc,
      AudioOutputDevice.bluetooth => context.l10n.videoPlayerSettingsOutputDeviceBluetooth,
      AudioOutputDevice.speaker => context.l10n.videoPlayerSettingsOutputDeviceSpeaker,
      AudioOutputDevice.headphones => context.l10n.videoPlayerSettingsOutputDeviceHeadphones,
      AudioOutputDevice.unknown => context.l10n.videoPlayerSettingsOutputDeviceUnknown,
    };
    if (capability.deviceName != null && capability.deviceName!.isNotEmpty) {
      return context.l10n.videoPlayerSettingsOutputDeviceWithName(device, capability.deviceName!);
    }
    return device;
  }

  String _getSupportedCodecsText(AudioPassthroughCapability? capability, BuildContext context) {
    if (capability == null) return context.l10n.videoPlayerSettingsOutputDeviceDetecting;
    if (!capability.isSupported || capability.supportedCodecs.isEmpty) {
      return context.l10n.videoPlayerSettingsSupportedCodecsUnsupported;
    }
    return capability.supportedCodecs.map((c) => switch (c) {
          AudioCodec.pcm => 'PCM',
          AudioCodec.ac3 => 'AC3',
          AudioCodec.eac3 => 'DD+ (Atmos)',
          AudioCodec.truehd => 'TrueHD',
          AudioCodec.dts => 'DTS',
          AudioCodec.dtsHd => 'DTS-HD MA',
          AudioCodec.atmos => 'Dolby Atmos',
          AudioCodec.dtsX => 'DTS:X',
        }).join(', ');
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon, bool isDark) => Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: context.textTheme.titleSmall?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      );

  Widget _buildSettingsCard(
    BuildContext context,
    bool isDark, {
    required List<Widget> children,
  }) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
              : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : AppColors.lightOutline.withValues(alpha: 0.3),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: children,
          ),
        ),
      );

  Widget _buildSettingsTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.textTheme.bodyLarge?.copyWith(
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      );

  Widget _buildSwitchTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.textTheme.bodyLarge?.copyWith(
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
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

  Widget _buildInfoTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.textTheme.bodyLarge?.copyWith(
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildDivider(bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Divider(
          height: 1,
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.2)
              : AppColors.lightOutline.withValues(alpha: 0.3),
        ),
      );

  void _showQualityPicker(
    BuildContext context,
    WidgetRef ref,
    VideoQuality currentQuality,
    bool isDark,
  ) {
    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurface.withValues(alpha: 0.95)
                  : AppColors.lightSurface.withValues(alpha: 0.98),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(
                  color: isDark ? AppColors.glassStroke : AppColors.lightOutline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拖动指示器
                  const SheetDragHandle(bottomPadding: 0),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      context.l10n.videoPlayerSettingsQualityPickerTitle,
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                  ),
                  ...VideoQuality.values.map(
                    (quality) => _buildQualityOption(
                      context,
                      ref,
                      quality,
                      currentQuality == quality,
                      isDark,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQualityOption(
    BuildContext context,
    WidgetRef ref,
    VideoQuality quality,
    bool isSelected,
    bool isDark,
  ) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            ref.read(qualitySettingsProvider.notifier).setDefaultQuality(quality);
            Navigator.pop(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : (isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant)
                            .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getQualityIcon(quality),
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quality.label,
                        style: context.textTheme.bodyLarge?.copyWith(
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      Text(
                        _getQualityDescription(quality, context),
                        style: context.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.primaryGradient,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

  IconData _getQualityIcon(VideoQuality quality) => switch (quality) {
        VideoQuality.original => Icons.auto_awesome_rounded,
        VideoQuality.quality4K => Icons.four_k_rounded,
        VideoQuality.quality1080p => Icons.hd_rounded,
        VideoQuality.quality720p => Icons.hd_outlined,
        VideoQuality.quality480p => Icons.sd_rounded,
        VideoQuality.quality360p => Icons.sd_outlined,
      };

  String _getQualityDescription(VideoQuality quality, BuildContext context) => switch (quality) {
        VideoQuality.original => context.l10n.videoPlayerSettingsQualityLabelOriginal,
        VideoQuality.quality4K => context.l10n.videoPlayerSettingsQualityLabel4K,
        VideoQuality.quality1080p => context.l10n.videoPlayerSettingsQualityLabel1080p,
        VideoQuality.quality720p => context.l10n.videoPlayerSettingsQualityLabel720p,
        VideoQuality.quality480p => context.l10n.videoPlayerSettingsQualityLabel480p,
        VideoQuality.quality360p => context.l10n.videoPlayerSettingsQualityLabel360p,
      };

  void _showBufferThresholdPicker(
    BuildContext context,
    WidgetRef ref,
    int currentValue,
    bool isDark,
  ) {
    final thresholds = [1, 2, 3, 5, 8, 10];

    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurface.withValues(alpha: 0.95)
                  : AppColors.lightSurface.withValues(alpha: 0.98),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(
                  color: isDark ? AppColors.glassStroke : AppColors.lightOutline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拖动指示器
                  const SheetDragHandle(bottomPadding: 0),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      context.l10n.videoPlayerSettingsBufferThresholdPickerTitle,
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Text(
                      context.l10n.videoPlayerSettingsBufferThresholdPickerDesc,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...thresholds.map(
                    (threshold) => _buildThresholdOption(
                      context,
                      ref,
                      threshold,
                      currentValue == threshold,
                      isDark,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThresholdOption(
    BuildContext context,
    WidgetRef ref,
    int threshold,
    bool isSelected,
    bool isDark,
  ) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            ref.read(qualitySettingsProvider.notifier).setBufferThreshold(threshold);
            Navigator.pop(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : (isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant)
                            .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      '$threshold',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    '$threshold 秒',
                    style: context.textTheme.bodyLarge?.copyWith(
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.primaryGradient,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

  void _showHdrModePicker(
    BuildContext context,
    WidgetRef ref,
    HdrAudioSettingsState settings,
    bool isDark,
  ) {
    final modes = [
      (HdrMode.auto, context.l10n.videoPlayerSettingsHdrModeAuto, context.l10n.videoPlayerSettingsHdrModeAutoDesc),
      (HdrMode.passthrough, context.l10n.videoPlayerSettingsHdrModePassthrough, context.l10n.videoPlayerSettingsHdrModePassthroughDesc),
      (HdrMode.tonemapping, context.l10n.videoPlayerSettingsHdrModeToneMapping, context.l10n.videoPlayerSettingsHdrModeToneMappingDesc),
      (HdrMode.disabled, context.l10n.videoPlayerSettingsHdrModeDisabled, context.l10n.videoPlayerSettingsHdrModeDisabledDesc),
    ];

    _showOptionPicker(
      context: context,
      ref: ref,
      title: context.l10n.videoPlayerSettingsHdrMode,
      isDark: isDark,
      options: modes.map((m) => (
            value: m.$1,
            label: m.$2,
            description: m.$3,
            isSelected: settings.settings.hdrMode == m.$1,
          )).toList(),
      onSelected: (mode) {
        ref.read(hdrAudioSettingsProvider.notifier).setHdrMode(mode);
      },
    );
  }

  void _showToneMappingPicker(
    BuildContext context,
    WidgetRef ref,
    HdrAudioSettingsState settings,
    bool isDark,
  ) {
    final modes = [
      (ToneMappingMode.auto, context.l10n.videoPlayerSettingsToneMappingModeAuto, context.l10n.videoPlayerSettingsToneMappingModeAutoDesc),
      (ToneMappingMode.mobius, 'Mobius', context.l10n.videoPlayerSettingsToneMappingModeMobiusDesc),
      (ToneMappingMode.reinhard, 'Reinhard', context.l10n.videoPlayerSettingsToneMappingModeReinhardDesc),
      (ToneMappingMode.hable, 'Hable', context.l10n.videoPlayerSettingsToneMappingModeHableDesc),
      (ToneMappingMode.bt2390, 'BT.2390', context.l10n.videoPlayerSettingsToneMappingModeBt2390Desc),
      (ToneMappingMode.clip, 'Clip', context.l10n.videoPlayerSettingsToneMappingModeClipDesc),
    ];

    _showOptionPicker(
      context: context,
      ref: ref,
      title: context.l10n.videoPlayerSettingsToneMapping,
      isDark: isDark,
      options: modes.map((m) => (
            value: m.$1,
            label: m.$2,
            description: m.$3,
            isSelected: settings.settings.toneMappingMode == m.$1,
          )).toList(),
      onSelected: (mode) {
        ref.read(hdrAudioSettingsProvider.notifier).setToneMappingMode(mode);
      },
    );
  }

  void _showAudioPassthroughPicker(
    BuildContext context,
    WidgetRef ref,
    HdrAudioSettingsState settings,
    bool isDark,
  ) {
    final modes = [
      (AudioPassthroughMode.auto, context.l10n.videoPlayerSettingsAudioPassthroughModeAuto, context.l10n.videoPlayerSettingsAudioPassthroughModeAutoDesc),
      (AudioPassthroughMode.enabled, context.l10n.videoPlayerSettingsAudioPassthroughModeEnabled, context.l10n.videoPlayerSettingsAudioPassthroughModeEnabledDesc),
      (AudioPassthroughMode.disabled, context.l10n.videoPlayerSettingsAudioPassthroughModeDisabled, context.l10n.videoPlayerSettingsAudioPassthroughModeDisabledDesc),
    ];

    _showOptionPicker(
      context: context,
      ref: ref,
      title: context.l10n.videoPlayerSettingsAudioPassthroughMode,
      isDark: isDark,
      options: modes.map((m) => (
            value: m.$1,
            label: m.$2,
            description: m.$3,
            isSelected: settings.settings.audioPassthroughMode == m.$1,
          )).toList(),
      onSelected: (mode) {
        ref.read(hdrAudioSettingsProvider.notifier).setAudioPassthroughMode(mode);
      },
    );
  }

  void _showOptionPicker<T>({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    required bool isDark,
    required List<({T value, String label, String description, bool isSelected})> options,
    required void Function(T) onSelected,
  }) {
    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurface.withValues(alpha: 0.95)
                  : AppColors.lightSurface.withValues(alpha: 0.98),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(
                  color: isDark ? AppColors.glassStroke : AppColors.lightOutline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拖动指示器
                  const SheetDragHandle(bottomPadding: 0),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      title,
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                  ),
                  ...options.map(
                    (option) => _buildPickerOption(
                      context,
                      isDark,
                      label: option.label,
                      description: option.description,
                      isSelected: option.isSelected,
                      onTap: () {
                        onSelected(option.value);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPickerOption(
    BuildContext context,
    bool isDark, {
    required String label,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: context.textTheme.bodyLarge?.copyWith(
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.primaryGradient,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}
