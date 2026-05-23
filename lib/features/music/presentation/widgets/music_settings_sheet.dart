import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/music/data/services/music_audio_handler_interface.dart';
import 'package:my_nas/features/music/presentation/providers/desktop_lyric_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_settings_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';

/// 显示音乐设置
void showMusicSettingsSheet(BuildContext context) {
  showAdaptiveModalSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const MusicSettingsSheet(),
  );
}

class MusicSettingsSheet extends ConsumerWidget {
  const MusicSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(musicSettingsProvider);
    final notifier = ref.read(musicSettingsProvider.notifier);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: DraggableScrollableSheet(
        expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => GestureDetector(
        onTap: () {}, // 阻止点击穿透到外层关闭弹框
        child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.grey[900]!.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
            ),
            child: Column(
              children: [
                // 拖拽指示器
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 标题栏
                _buildHeader(context, notifier, isDark),
                // 分隔线
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(
                    height: 1,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                // 设置列表
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: [
                      // 播放模式
                      _buildPlayModeSection(settings, notifier, isDark),
                      const SizedBox(height: 24),
                      // 音量控制
                      _buildVolumeSection(settings, notifier, isDark),
                      const SizedBox(height: 24),
                      // 淡入淡出
                      _buildCrossfadeSection(settings, notifier, isDark),
                      const SizedBox(height: 24),
                      // 开关选项
                      _buildSwitchOptions(settings, notifier, isDark),
                      const SizedBox(height: 24),
                      // 桌面歌词设置（仅桌面端）
                      if (Platform.isWindows || Platform.isMacOS)
                        _buildDesktopLyricSection(context, ref, isDark),
                      if (Platform.isWindows || Platform.isMacOS)
                        const SizedBox(height: 24),
                      // 播放引擎选择
                      _buildEngineSection(context, settings, notifier, isDark),
                      SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    MusicSettingsNotifier notifier,
    bool isDark,
  ) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          // 图标
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary,
                  AppColors.secondary,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          // 标题
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '播放设置',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '自定义您的音乐体验',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          // 重置按钮
          TextButton.icon(
            onPressed: notifier.reset,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('重置'),
          ),
        ],
      ),
    );

  Widget _buildPlayModeSection(
    MusicSettings settings,
    MusicSettingsNotifier notifier,
    bool isDark,
  ) => _SettingsSection(
      title: '播放模式',
      icon: Icons.repeat_rounded,
      isDark: isDark,
      child: Row(
        children: [
          _PlayModeButton(
            icon: Icons.repeat_rounded,
            label: '列表循环',
            isSelected: settings.playMode == PlayMode.loop,
            isDark: isDark,
            onTap: () => notifier.setPlayMode(PlayMode.loop),
          ),
          const SizedBox(width: 12),
          _PlayModeButton(
            icon: Icons.repeat_one_rounded,
            label: '单曲循环',
            isSelected: settings.playMode == PlayMode.repeatOne,
            isDark: isDark,
            onTap: () => notifier.setPlayMode(PlayMode.repeatOne),
          ),
          const SizedBox(width: 12),
          _PlayModeButton(
            icon: Icons.shuffle_rounded,
            label: '随机播放',
            isSelected: settings.playMode == PlayMode.shuffle,
            isDark: isDark,
            onTap: () => notifier.setPlayMode(PlayMode.shuffle),
          ),
        ],
      ),
    );

  Widget _buildVolumeSection(
    MusicSettings settings,
    MusicSettingsNotifier notifier,
    bool isDark,
  ) => _SettingsSection(
      title: '默认音量',
      icon: Icons.volume_up_rounded,
      isDark: isDark,
      child: Column(
        children: [
          // 音量滑块
          Row(
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
        ],
      ),
    );

  Widget _buildCrossfadeSection(
    MusicSettings settings,
    MusicSettingsNotifier notifier,
    bool isDark,
  ) => _SettingsSection(
      title: '歌曲切换淡入淡出',
      subtitle: '歌曲切换时平滑过渡',
      icon: Icons.compare_arrows_rounded,
      isDark: isDark,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: availableCrossfadeDurations.map((duration) {
          final isSelected = duration == settings.crossfadeDuration;
          return _DurationChip(
            label: duration == 0 ? '关闭' : '$duration秒',
            isSelected: isSelected,
            isDark: isDark,
            onTap: () => notifier.setCrossfadeDuration(duration),
          );
        }).toList(),
      ),
    );

  Widget _buildSwitchOptions(
    MusicSettings settings,
    MusicSettingsNotifier notifier,
    bool isDark,
  ) => Column(
      children: [
        _SettingsSwitch(
          icon: Icons.graphic_eq_rounded,
          title: '无缝播放',
          subtitle: '播放列表歌曲之间无间隙',
          value: settings.gaplessPlayback,
          isDark: isDark,
          onChanged: (value) => notifier.setGaplessPlayback(enabled: value),
        ),
        const SizedBox(height: 12),
        _SettingsSwitch(
          icon: Icons.lyrics_rounded,
          title: '显示歌词',
          subtitle: '在播放页面显示歌词（如果可用）',
          value: settings.showLyrics,
          isDark: isDark,
          onChanged: (value) => notifier.setShowLyrics(enabled: value),
        ),
        const SizedBox(height: 12),
        _SettingsSwitch(
          icon: Icons.play_circle_outline_rounded,
          title: '连接后自动播放',
          subtitle: '连接到数据源后自动继续上次播放',
          value: settings.autoPlayOnConnect,
          isDark: isDark,
          onChanged: (value) => notifier.setAutoPlayOnConnect(enabled: value),
        ),
      ],
    );

  Widget _buildDesktopLyricSection(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
  ) {
    final desktopLyricState = ref.watch(desktopLyricProvider);
    final desktopLyricNotifier = ref.read(desktopLyricProvider.notifier);
    final menuBarState = ref.watch(menuBarProvider);
    final menuBarNotifier = ref.read(menuBarProvider.notifier);

    return _SettingsSection(
      title: '桌面增强',
      subtitle: Platform.isMacOS ? '桌面歌词和状态栏播放器' : '桌面歌词',
      icon: Icons.desktop_windows_rounded,
      isDark: isDark,
      child: Column(
        children: [
          // 桌面歌词开关
          _DesktopSettingsTile(
            icon: Icons.subtitles_rounded,
            title: '桌面歌词',
            subtitle: '在桌面显示悬浮歌词窗口',
            trailing: Platform.isWindows
                ? 'Ctrl+Shift+L'
                : Platform.isMacOS
                    ? '⌘+⇧+L'
                    : null,
            value: desktopLyricState.isVisible,
            isDark: isDark,
            onChanged: (value) {
              if (value) {
                desktopLyricNotifier.show();
              } else {
                desktopLyricNotifier.hide();
              }
            },
          ),
          // macOS 状态栏开关
          if (Platform.isMacOS) ...[
            const SizedBox(height: 12),
            _DesktopSettingsTile(
              icon: Icons.menu_rounded,
              title: '状态栏播放器',
              subtitle: '在菜单栏显示迷你播放器',
              value: menuBarState.isVisible,
              isDark: isDark,
              onChanged: menuBarNotifier.setVisible,
            ),
          ],
          // 最小化时显示桌面歌词
          const SizedBox(height: 12),
          _DesktopSettingsTile(
            icon: Icons.minimize_rounded,
            title: '最小化时显示歌词',
            subtitle: '主窗口最小化时自动显示桌面歌词',
            value: desktopLyricState.settings.showOnMinimize,
            isDark: isDark,
            onChanged: (value) {
              desktopLyricNotifier.updateSettings(
                desktopLyricState.settings.copyWith(showOnMinimize: value),
              );
            },
          ),
          // 恢复时隐藏桌面歌词
          if (desktopLyricState.settings.showOnMinimize) ...[
            const SizedBox(height: 12),
            _DesktopSettingsTile(
              icon: Icons.open_in_full_rounded,
              title: '恢复时隐藏歌词',
              subtitle: '主窗口恢复时自动隐藏桌面歌词',
              value: desktopLyricState.settings.hideOnRestore,
              isDark: isDark,
              onChanged: (value) {
                desktopLyricNotifier.updateSettings(
                  desktopLyricState.settings.copyWith(hideOnRestore: value),
                );
              },
            ),
          ],
          // 桌面歌词设置提示
          if (desktopLyricState.isVisible) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '拖动歌词窗口可调整位置，将鼠标悬停在窗口上显示控制按钮',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.primary.withValues(alpha: 0.9)
                            : AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEngineSection(
    BuildContext context,
    MusicSettings settings,
    MusicSettingsNotifier notifier,
    bool isDark,
  ) => _SettingsSection(
      title: '播放引擎',
      subtitle: '切换需要重启应用生效',
      icon: Icons.memory_rounded,
      isDark: isDark,
      child: Column(
        children: [
          Row(
            children: [
              _EngineButton(
                icon: Icons.phone_android_rounded,
                title: '平台原生',
                subtitle: '稳定 / 低功耗',
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
                title: 'FFmpeg',
                subtitle: 'AC3 / DTS / Dolby',
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
                        ? '当前使用 FFmpeg 引擎，支持 AC3、DTS、Dolby 等高级音频格式'
                        : '当前使用平台原生引擎，更省电但不支持 AC3/DTS 等格式',
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
      builder: (context) => AlertDialog(
        title: const Text('切换播放引擎'),
        content: Text(
          newEngine == MusicPlayerEngine.mediaKit
              ? '切换到 FFmpeg 引擎后，将支持 AC3、DTS、Dolby TrueHD 等高级音频格式。\n\n需要重启应用才能生效。'
              : '切换到平台原生引擎后，将更加省电但不再支持 AC3/DTS 等高级格式。\n\n需要重启应用才能生效。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              notifier.setPlayerEngine(newEngine);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('播放引擎已更改，请重启应用生效'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('确认切换'),
          ),
        ],
      ),
    );
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
            activeThumbColor: Colors.white,
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black54),
                size: 28,
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
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

/// 桌面设置项组件
class _DesktopSettingsTile extends StatelessWidget {
  const _DesktopSettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.isDark,
    required this.onChanged,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailing;
  final bool value;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
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
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          trailing!,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white54 : Colors.black45,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ],
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
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.primary,
            activeThumbColor: Colors.white,
          ),
        ],
      ),
    );
}
