import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/audio_capability.dart';
import 'package:my_nas/features/video/domain/entities/hdr_capability.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';
import 'package:my_nas/features/video/presentation/providers/hdr_audio_settings_provider.dart';
import 'package:my_nas/features/video/presentation/providers/quality_provider.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';

/// 视频播放器设置页面
class VideoPlayerSettingsPage extends ConsumerWidget {
  const VideoPlayerSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(qualitySettingsProvider);
    final hdrAudioSettings = ref.watch(hdrAudioSettingsProvider);

    return HideBottomNavWrapper(
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : null,
        appBar: AppBar(
          backgroundColor: isDark ? AppColors.darkSurface : null,
          title: Text(
            '播放器设置',
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
          _buildSectionHeader(context, '清晰度', Icons.high_quality_rounded, isDark),
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
                title: '默认清晰度',
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
                title: '自适应清晰度建议',
                subtitle: '根据网络状况智能推荐清晰度',
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
                title: '记住清晰度选择',
                subtitle: '下次播放同一视频时自动应用',
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
                title: '缓冲检测阈值',
                subtitle: '${settings.bufferThresholdSeconds} 秒',
                onTap: () => _showBufferThresholdPicker(context, ref, settings.bufferThresholdSeconds, isDark),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // 投屏设置
          _buildSectionHeader(context, '投屏', Icons.cast_rounded, isDark),
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
                title: '支持的投屏协议',
                subtitle: 'DLNA / AirPlay',
              ),
              _buildDivider(isDark),
              _buildInfoTile(
                context,
                isDark,
                icon: Icons.info_outline_rounded,
                iconColor: AppColors.tertiary,
                title: '使用说明',
                subtitle: '播放视频时点击投屏按钮选择设备',
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // 转码设置
          _buildSectionHeader(context, '转码', Icons.settings_applications_rounded, isDark),
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
                title: '服务端转码',
                subtitle: 'Synology Video Station / Jellyfin',
              ),
              _buildDivider(isDark),
              _buildInfoTile(
                context,
                isDark,
                icon: Icons.phone_android_rounded,
                iconColor: AppColors.accent,
                title: '客户端转码',
                subtitle: '需要设备安装 FFmpeg',
              ),
              _buildDivider(isDark),
              _buildSwitchTile(
                context,
                isDark,
                icon: Icons.notifications_rounded,
                iconColor: AppColors.warning,
                title: '不支持转码提示',
                subtitle: '当数据源不支持转码时显示提示',
                value: settings.showUnsupportedHint,
                onChanged: (value) {
                  ref.read(qualitySettingsProvider.notifier).setShowUnsupportedHint(enabled: value);
                },
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // HDR 设置
          _buildSectionHeader(context, 'HDR', Icons.hdr_on_rounded, isDark),
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
                title: 'HDR 模式',
                subtitle: _getHdrModeLabel(hdrAudioSettings.settings.hdrMode),
                onTap: () => _showHdrModePicker(context, ref, hdrAudioSettings, isDark),
              ),
              _buildDivider(isDark),
              // 色调映射
              _buildSettingsTile(
                context,
                isDark,
                icon: Icons.tune_rounded,
                iconColor: AppColors.accent,
                title: '色调映射算法',
                subtitle: _getToneMappingLabel(hdrAudioSettings.settings.toneMappingMode),
                onTap: () => _showToneMappingPicker(context, ref, hdrAudioSettings, isDark),
              ),
              _buildDivider(isDark),
              // 设备能力
              _buildInfoTile(
                context,
                isDark,
                icon: Icons.monitor_rounded,
                iconColor: AppColors.info,
                title: '设备 HDR 能力',
                subtitle: _getHdrCapabilityText(hdrAudioSettings.hdrCapability),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // 音频直通设置
          _buildSectionHeader(context, '音频直通', Icons.surround_sound_rounded, isDark),
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
                title: '音频直通模式',
                subtitle: _getAudioPassthroughLabel(hdrAudioSettings.settings.audioPassthroughMode),
                onTap: () => _showAudioPassthroughPicker(context, ref, hdrAudioSettings, isDark),
              ),
              _buildDivider(isDark),
              // 当前输出设备
              _buildInfoTile(
                context,
                isDark,
                icon: Icons.output_rounded,
                iconColor: AppColors.tertiary,
                title: '当前输出设备',
                subtitle: _getOutputDeviceText(hdrAudioSettings.audioCapability),
              ),
              _buildDivider(isDark),
              // 支持的编码
              _buildInfoTile(
                context,
                isDark,
                icon: Icons.audiotrack_rounded,
                iconColor: AppColors.warning,
                title: '支持的编码',
                subtitle: _getSupportedCodecsText(hdrAudioSettings.audioCapability),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xxxl),
        ],
        ),
      ),
    );
  }

  String _getHdrModeLabel(HdrMode mode) => switch (mode) {
        HdrMode.auto => '自动',
        HdrMode.passthrough => 'HDR 直通',
        HdrMode.tonemapping => '色调映射',
        HdrMode.disabled => '禁用',
      };

  String _getToneMappingLabel(ToneMappingMode mode) => switch (mode) {
        ToneMappingMode.auto => '自动',
        ToneMappingMode.mobius => 'Mobius',
        ToneMappingMode.reinhard => 'Reinhard',
        ToneMappingMode.hable => 'Hable',
        ToneMappingMode.bt2390 => 'BT.2390',
        ToneMappingMode.clip => 'Clip',
      };

  String _getAudioPassthroughLabel(AudioPassthroughMode mode) => switch (mode) {
        AudioPassthroughMode.auto => '自动',
        AudioPassthroughMode.enabled => '启用',
        AudioPassthroughMode.disabled => '禁用',
      };

  String _getHdrCapabilityText(HdrCapability? capability) {
    if (capability == null) return '检测中...';
    if (!capability.isSupported) return '不支持';
    final types = capability.supportedTypes.map((t) => switch (t) {
          HdrType.hdr10 => 'HDR10',
          HdrType.hdr10Plus => 'HDR10+',
          HdrType.hlg => 'HLG',
          HdrType.dolbyVision => 'Dolby Vision',
          HdrType.none => '',
        }).where((s) => s.isNotEmpty).join(', ');
    return types.isEmpty ? '支持 HDR' : '支持 $types';
  }

  String _getOutputDeviceText(AudioPassthroughCapability? capability) {
    if (capability == null) return '检测中...';
    final device = switch (capability.outputDevice) {
      AudioOutputDevice.hdmi => 'HDMI',
      AudioOutputDevice.spdif => 'S/PDIF 光纤',
      AudioOutputDevice.arc => 'HDMI ARC/eARC',
      AudioOutputDevice.bluetooth => '蓝牙',
      AudioOutputDevice.speaker => '内置扬声器',
      AudioOutputDevice.headphones => '耳机',
      AudioOutputDevice.unknown => '未知',
    };
    if (capability.deviceName != null && capability.deviceName!.isNotEmpty) {
      return '$device (${capability.deviceName})';
    }
    return device;
  }

  String _getSupportedCodecsText(AudioPassthroughCapability? capability) {
    if (capability == null) return '检测中...';
    if (!capability.isSupported || capability.supportedCodecs.isEmpty) {
      return '不支持直通';
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
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                          : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      '选择默认清晰度',
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
                        _getQualityDescription(quality),
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

  String _getQualityDescription(VideoQuality quality) => switch (quality) {
        VideoQuality.original => '保持原始画质，不进行转码',
        VideoQuality.quality4K => '3840×2160 • 超高清',
        VideoQuality.quality1080p => '1920×1080 • 全高清',
        VideoQuality.quality720p => '1280×720 • 高清',
        VideoQuality.quality480p => '854×480 • 标清',
        VideoQuality.quality360p => '640×360 • 流畅',
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
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                          : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      '缓冲检测阈值',
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Text(
                      '当视频缓冲超过此时间时，将建议降低清晰度',
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
      (HdrMode.auto, '自动', '根据设备和视频自动选择最佳模式'),
      (HdrMode.passthrough, 'HDR 直通', '直接输出 HDR 信号到支持的显示器'),
      (HdrMode.tonemapping, '色调映射', '将 HDR 转换为 SDR 显示'),
      (HdrMode.disabled, '禁用', '不进行任何 HDR 处理'),
    ];

    _showOptionPicker(
      context: context,
      ref: ref,
      title: 'HDR 模式',
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
      (ToneMappingMode.auto, '自动', '由 MPV 自动选择算法'),
      (ToneMappingMode.mobius, 'Mobius', '平滑过渡，适合大多数内容'),
      (ToneMappingMode.reinhard, 'Reinhard', '经典算法，保留更多细节'),
      (ToneMappingMode.hable, 'Hable', '电影感更强，对比度更高'),
      (ToneMappingMode.bt2390, 'BT.2390', 'ITU 标准算法'),
      (ToneMappingMode.clip, 'Clip', '简单裁剪，高性能'),
    ];

    _showOptionPicker(
      context: context,
      ref: ref,
      title: '色调映射算法',
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
      (AudioPassthroughMode.auto, '自动', '根据输出设备和音频格式自动选择'),
      (AudioPassthroughMode.enabled, '启用', '尝试直通所有支持的音频格式'),
      (AudioPassthroughMode.disabled, '禁用', '始终解码音频后输出'),
    ];

    _showOptionPicker(
      context: context,
      ref: ref,
      title: '音频直通模式',
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
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                          : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
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
