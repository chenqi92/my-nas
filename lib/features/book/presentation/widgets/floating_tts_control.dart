import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/book/data/services/tts/tts_service.dart';
import 'package:my_nas/features/book/data/services/tts/tts_settings.dart';
import 'package:my_nas/features/book/presentation/providers/tts_provider.dart';

/// 垂直浮动 TTS 控制组件
///
/// 固定在右上角，纵向展示，不遮挡进度条
/// 音色/设置使用类似视频播放器的悬浮弹框
class FloatingTTSControl extends ConsumerStatefulWidget {
  const FloatingTTSControl({
    required this.onClose,
    this.backgroundColor,
    super.key,
  });

  final VoidCallback onClose;
  final Color? backgroundColor;

  @override
  ConsumerState<FloatingTTSControl> createState() => _FloatingTTSControlState();
}

class _FloatingTTSControlState extends ConsumerState<FloatingTTSControl>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _slideAnimation;

  // 用于弹框定位
  final GlobalKey _voiceButtonKey = GlobalKey();
  final GlobalKey _settingsButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    _slideAnimation = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleClose() async {
    await _animationController.reverse();
    await ref.read(ttsProvider.notifier).stop();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final ttsState = ref.watch(ttsProvider);
    final ttsNotifier = ref.read(ttsProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) => Positioned(
        top: mediaQuery.padding.top + 60,
        right: 16 + _slideAnimation.value,
        child: Opacity(
          opacity: _scaleAnimation.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: _scaleAnimation.value,
            alignment: Alignment.centerRight,
            child: child,
          ),
        ),
      ),
      // 使用 GestureDetector 包裹，阻止点击事件穿透到下层（如翻页）
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // 吸收点击事件，不传递到下层
        child: _buildControlBar(ttsState, ttsNotifier, isDark),
      ),
    );
  }

  Widget _buildControlBar(
    TTSState state,
    TTSNotifier notifier,
    bool isDark,
  ) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: (widget.backgroundColor ??
                (isDark ? const Color(0xFF1E1E1E) : Colors.white))
            .withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(-2, 4),
          ),
        ],
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 关闭按钮
          _buildIconButton(
            icon: Icons.close_rounded,
            onPressed: _handleClose,
            isDark: isDark,
            tooltip: '关闭',
          ),

          const SizedBox(height: 4),
          _buildDivider(isDark),
          const SizedBox(height: 4),

          // 上一段
          _buildIconButton(
            icon: Icons.skip_previous_rounded,
            onPressed: notifier.previousParagraph,
            isDark: isDark,
            tooltip: '上一段',
          ),

          const SizedBox(height: 4),

          // 播放/暂停
          _buildPlayPauseButton(state, notifier, isDark),

          const SizedBox(height: 4),

          // 下一段
          _buildIconButton(
            icon: Icons.skip_next_rounded,
            onPressed: notifier.nextParagraph,
            isDark: isDark,
            tooltip: '下一段',
          ),

          const SizedBox(height: 4),
          _buildDivider(isDark),
          const SizedBox(height: 4),

          // 音色
          _buildIconButton(
            key: _voiceButtonKey,
            icon: Icons.record_voice_over_rounded,
            onPressed: () => _showVoicePopup(context),
            isDark: isDark,
            tooltip: '音色',
          ),

          const SizedBox(height: 4),

          // 设置
          _buildIconButton(
            key: _settingsButtonKey,
            icon: Icons.tune_rounded,
            onPressed: () => _showSettingsPopup(context),
            isDark: isDark,
            tooltip: '设置',
          ),
        ],
      ),
    );

  Widget _buildIconButton({
    Key? key,
    required IconData icon,
    required VoidCallback onPressed,
    required bool isDark,
    String? tooltip,
  }) {
    // 按钮使用半透明黑色背景 + 白色图标，确保在任何阅读器背景下可见

    Widget button = Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            icon,
            size: 20,
            color: Colors.white,
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip, child: button);
    }

    return button;
  }

  Widget _buildPlayPauseButton(TTSState state, TTSNotifier notifier, bool isDark) {
    final isPlaying = state.playState == TTSPlayState.playing;

    return Material(
      color: AppColors.primary,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () {
          if (isPlaying) {
            notifier.pause();
          } else if (state.isPaused) {
            notifier.resume();
          }
        },
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 22,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(bool isDark) => Container(
      width: 24,
      height: 1,
      color: isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.08),
    );

  /// 显示音色选择弹框（视频播放器风格）
  void _showVoicePopup(BuildContext context) {
    final RenderBox? renderBox =
        _voiceButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _showFloatingPopup(
      context: context,
      anchorOffset: offset,
      anchorSize: size,
      maxHeight: 400,
      child: const _VoiceSelectionPopup(),
    );
  }

  /// 显示设置弹框（视频播放器风格）
  void _showSettingsPopup(BuildContext context) {
    final RenderBox? renderBox =
        _settingsButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _showFloatingPopup(
      context: context,
      anchorOffset: offset,
      anchorSize: size,
      child: const _SettingsPopup(),
    );
  }

  /// 显示悬浮弹框
  void _showFloatingPopup({
    required BuildContext context,
    required Offset anchorOffset,
    required Size anchorSize,
    required Widget child,
    double maxHeight = 320,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    // 计算弹框位置（在按钮左边）
    const popupWidth = 260.0;
    final left = anchorOffset.dx - popupWidth - 12;
    final top = anchorOffset.dy - 20;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      barrierDismissible: true,
      builder: (context) => GestureDetector(
        // 阻止点击事件穿透到弹框下层
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(context),
        child: Stack(
          children: [
            // 弹框（包裹在 GestureDetector 中阻止点击传递到外层）
            Positioned(
              left: left.clamp(16.0, screenWidth - popupWidth - 16),
              top: top.clamp(80.0, MediaQuery.of(context).size.height - maxHeight - 50),
              child: GestureDetector(
                onTap: () {}, // 阻止点击穿透
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: popupWidth,
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 音色选择弹框（包含引擎切换）
class _VoiceSelectionPopup extends ConsumerWidget {
  const _VoiceSelectionPopup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(ttsProvider).settings;
    final notifier = ref.read(ttsProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEdge = settings.engine == TTSEngine.edge;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 引擎切换标签
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: _buildEngineTab(
                  context: context,
                  label: '系统语音',
                  icon: Icons.phone_android_rounded,
                  isSelected: !isEdge,
                  isDark: isDark,
                  onTap: () => notifier.setEngine(TTSEngine.system),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildEngineTab(
                  context: context,
                  label: 'Edge TTS',
                  icon: Icons.cloud_rounded,
                  isSelected: isEdge,
                  isDark: isDark,
                  onTap: () => notifier.setEngine(TTSEngine.edge),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 音色列表
        Flexible(
          child: isEdge
              ? _buildEdgeVoiceList(settings, notifier, isDark, context)
              : _buildSystemVoiceList(ref, settings, isDark, context),
        ),
      ],
    );
  }

  Widget _buildEngineTab({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.15)
              : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: AppColors.primary, width: 1.5) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppColors.primary : (isDark ? Colors.white54 : Colors.black54),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? AppColors.primary : (isDark ? Colors.white54 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );

  Widget _buildEdgeVoiceList(
    TTSSettings settings,
    TTSNotifier notifier,
    bool isDark,
    BuildContext context,
  ) {
    // Edge TTS 中文音色列表
    final voices = [
      ('zh-CN-XiaoxiaoNeural', '晓晓（女声·温柔）'),
      ('zh-CN-YunxiNeural', '云希（男声·活泼）'),
      ('zh-CN-XiaoyiNeural', '晓依（女声·亲切）'),
      ('zh-CN-YunjianNeural', '云健（男声·沉稳）'),
      ('zh-CN-XiaochenNeural', '晓辰（女声·新闻）'),
      ('zh-CN-YunyangNeural', '云扬（男声·新闻）'),
      ('zh-CN-XiaoshuangNeural', '晓双（女声·童声）'),
      ('zh-CN-YunxiaNeural', '云夏（男声·童声）'),
      ('zh-TW-HsiaoChenNeural', '曉臻（台湾女声）'),
      ('zh-TW-YunJheNeural', '雲哲（台湾男声）'),
      ('zh-HK-HiuGaaiNeural', '曉佳（粤语女声）'),
      ('zh-HK-WanLungNeural', '雲龍（粤语男声）'),
    ];

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: voices.length,
      itemBuilder: (context, index) {
        final (id, name) = voices[index];
        final isSelected = settings.selectedEdgeVoiceId == id;

        return InkWell(
          onTap: () {
            notifier.setEdgeVoice(id);
            Navigator.pop(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : null,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark ? Colors.white70 : Colors.black87),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_rounded, color: AppColors.primary, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSystemVoiceList(
    WidgetRef ref,
    TTSSettings settings,
    bool isDark,
    BuildContext context,
  ) {
    final ttsState = ref.watch(ttsProvider);
    final notifier = ref.read(ttsProvider.notifier);
    final voices = ttsState.voices;

    if (voices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            '正在加载系统音色...',
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
        ),
      );
    }

    // 过滤中文音色
    final chineseVoices = voices.where((v) =>
      v.language.contains('zh') ||
      v.name.contains('中文') ||
      v.name.contains('Chinese'),
    ).toList();

    final displayVoices = chineseVoices.isNotEmpty ? chineseVoices : voices;

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: displayVoices.length,
      itemBuilder: (context, index) {
        final voice = displayVoices[index];
        final isSelected = ttsState.selectedVoice?.id == voice.id;

        return InkWell(
          onTap: () {
            notifier.setVoice(voice);
            Navigator.pop(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : null,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        voice.name,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.primary
                              : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (voice.language.isNotEmpty)
                        Text(
                          voice.language,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_rounded, color: AppColors.primary, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 设置弹框
class _SettingsPopup extends ConsumerWidget {
  const _SettingsPopup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(ttsProvider).settings;
    final notifier = ref.read(ttsProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'TTS 设置',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        const Divider(height: 1),
        // 语速
        _buildSliderItem(
          context: context,
          label: '语速',
          value: settings.speechRate,
          min: 0.5,
          max: 2.0,
          displayValue: '${settings.speechRate.toStringAsFixed(1)}x',
          onChanged: notifier.setSpeechRate,
          isDark: isDark,
        ),
        // 音调
        _buildSliderItem(
          context: context,
          label: '音调',
          value: settings.pitch,
          min: 0.5,
          max: 2.0,
          displayValue: settings.pitch.toStringAsFixed(1),
          onChanged: notifier.setPitch,
          isDark: isDark,
        ),
        // 音量
        _buildSliderItem(
          context: context,
          label: '音量',
          value: settings.volume,
          min: 0.0,
          max: 1.0,
          displayValue: '${(settings.volume * 100).round()}%',
          onChanged: notifier.setVolume,
          isDark: isDark,
        ),
        const Divider(height: 1),
        // 开关选项
        _buildSwitchItem(
          label: '自动播放下一章',
          value: settings.autoPlayNextChapter,
          onChanged: (v) => notifier.updateSettings(
            settings.copyWith(autoPlayNextChapter: v),
          ),
          isDark: isDark,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSliderItem({
    required BuildContext context,
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              Text(
                displayValue,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              activeColor: AppColors.primary,
              inactiveColor: isDark ? Colors.white24 : Colors.black12,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchItem({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
}

