import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/presentation/providers/subtitle_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';

/// 显示字幕样式设置（Infuse 暗色风格）
void showSubtitleStyleSheet(BuildContext context) {
  showAdaptiveModalSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const SubtitleStyleSheet(),
  );
}

class SubtitleStyleSheet extends ConsumerWidget {
  const SubtitleStyleSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(subtitleStyleProvider);
    final notifier = ref.read(subtitleStyleProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.92),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: CustomScrollView(
          controller: scrollController,
          slivers: [
            // 拖拽指示器
            SliverToBoxAdapter(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // 标题栏
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.text_fields_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '字幕样式',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: notifier.reset,
                      child: const Text(
                        '重置',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: Divider(color: Colors.white24, height: 1),
            ),

            // 预览区域
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    // 视频占位
                    Container(
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.grey[800]!, Colors.grey[900]!],
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.movie_rounded,
                          size: 32,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    // 字幕预览
                    Positioned(
                      left: 0,
                      right: 0,
                      top: style.position == SubtitlePosition.top ? 4 : null,
                      bottom: style.position == SubtitlePosition.bottom
                          ? 4
                          : null,
                      child: style.position == SubtitlePosition.center
                          ? Positioned.fill(
                              child: Center(
                                child: _buildSubtitlePreview(style),
                              ),
                            )
                          : _buildSubtitlePreview(style),
                    ),
                  ],
                ),
              ),
            ),

            // 设置选项
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // 字体大小
                  _buildSection(
                    title: '字体大小',
                    child: Row(
                      children: [
                        _DarkIconButton(
                          icon: Icons.remove_rounded,
                          onPressed: () =>
                              notifier.setFontSize(style.fontSize - 2),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: _darkSliderTheme,
                            child: Slider(
                              value: style.fontSize,
                              min: 12,
                              max: 48,
                              divisions: 18,
                              onChanged: notifier.setFontSize,
                            ),
                          ),
                        ),
                        _DarkIconButton(
                          icon: Icons.add_rounded,
                          onPressed: () =>
                              notifier.setFontSize(style.fontSize + 2),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${style.fontSize.round()}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 字体颜色
                  _buildSection(
                    title: '字体颜色',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: subtitleColors.map((color) {
                        final isSelected =
                            color.toARGB32() == style.fontColor.toARGB32();
                        return _ColorButton(
                          color: color,
                          isSelected: isSelected,
                          onTap: () => notifier.setFontColor(color),
                        );
                      }).toList(),
                    ),
                  ),

                  // 字幕背景开关
                  _buildSection(
                    title: '字幕背景',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text(
                              '显示背景',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            Switch(
                              value: style.showBackground,
                              onChanged: (value) {
                                notifier.setShowBackground(show: value);
                              },
                              activeThumbColor: Colors.white,
                              activeTrackColor: Colors.white38,
                            ),
                          ],
                        ),
                        // 只有开启背景时才显示背景颜色选择
                        if (style.showBackground) ...[
                          const SizedBox(height: 8),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '背景颜色',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: subtitleBackgrounds.map((color) {
                              final isSelected =
                                  color.toARGB32() ==
                                  style.backgroundColor.toARGB32();
                              return _ColorButton(
                                color: color,
                                isSelected: isSelected,
                                onTap: () => notifier.setBackgroundColor(color),
                                showTransparent: color == Colors.transparent,
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // 字幕位置
                  _buildSection(
                    title: '字幕位置',
                    child: Row(
                      children: [
                        _PositionChip(
                          label: '顶部',
                          icon: Icons.vertical_align_top_rounded,
                          isSelected: style.position == SubtitlePosition.top,
                          onTap: () =>
                              notifier.setPosition(SubtitlePosition.top),
                        ),
                        const SizedBox(width: 8),
                        _PositionChip(
                          label: '居中',
                          icon: Icons.vertical_align_center_rounded,
                          isSelected: style.position == SubtitlePosition.center,
                          onTap: () =>
                              notifier.setPosition(SubtitlePosition.center),
                        ),
                        const SizedBox(width: 8),
                        _PositionChip(
                          label: '底部',
                          icon: Icons.vertical_align_bottom_rounded,
                          isSelected: style.position == SubtitlePosition.bottom,
                          onTap: () =>
                              notifier.setPosition(SubtitlePosition.bottom),
                        ),
                      ],
                    ),
                  ),

                  // 字体粗细
                  _buildSection(
                    title: '字体粗细',
                    child: Row(
                      children: [
                        _PositionChip(
                          label: '正常',
                          isSelected: style.fontWeight == FontWeight.normal,
                          onTap: () =>
                              notifier.setFontWeight(FontWeight.normal),
                        ),
                        const SizedBox(width: 8),
                        _PositionChip(
                          label: '中等',
                          isSelected: style.fontWeight == FontWeight.w500,
                          onTap: () => notifier.setFontWeight(FontWeight.w500),
                        ),
                        const SizedBox(width: 8),
                        _PositionChip(
                          label: '粗体',
                          isSelected: style.fontWeight == FontWeight.bold,
                          onTap: () => notifier.setFontWeight(FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                  // 描边设置
                  _buildSection(
                    title: '描边效果',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text(
                              '启用描边',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            Switch(
                              value: style.hasOutline,
                              onChanged: (value) {
                                notifier.setHasOutline(hasOutline: value);
                              },
                              activeThumbColor: Colors.white,
                              activeTrackColor: Colors.white38,
                            ),
                          ],
                        ),
                        if (style.hasOutline)
                          Row(
                            children: [
                              const Text(
                                '描边宽度',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: _darkSliderTheme,
                                  child: Slider(
                                    value: style.outlineWidth,
                                    min: 0.5,
                                    max: 5,
                                    divisions: 9,
                                    onChanged: notifier.setOutlineWidth,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                child: Text(
                                  style.outlineWidth.toStringAsFixed(1),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  // 字幕延时
                  _buildSection(
                    title: '字幕延时',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '正值延后字幕，负值提前字幕',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _DarkIconButton(
                              icon: Icons.remove_rounded,
                              onPressed: () =>
                                  notifier.setDelay(style.delay - 0.5),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: _darkSliderTheme,
                                child: Slider(
                                  value: style.delay,
                                  min: -10,
                                  max: 10,
                                  divisions: 40,
                                  onChanged: notifier.setDelay,
                                ),
                              ),
                            ),
                            _DarkIconButton(
                              icon: Icons.add_rounded,
                              onPressed: () =>
                                  notifier.setDelay(style.delay + 0.5),
                            ),
                            SizedBox(
                              width: 56,
                              child: Text(
                                style.delayText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: style.delay != 0
                                      ? Colors.white
                                      : Colors.white54,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // 快捷按钮
                        Wrap(
                          spacing: 6,
                          children: [
                            _QuickChip(
                              label: '-1s',
                              onTap: () => notifier.setDelay(style.delay - 1),
                            ),
                            _QuickChip(
                              label: '-0.5s',
                              onTap: () => notifier.setDelay(style.delay - 0.5),
                            ),
                            _QuickChip(
                              label: '重置',
                              onTap: () => notifier.setDelay(0),
                            ),
                            _QuickChip(
                              label: '+0.5s',
                              onTap: () => notifier.setDelay(style.delay + 0.5),
                            ),
                            _QuickChip(
                              label: '+1s',
                              onTap: () => notifier.setDelay(style.delay + 1),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 字幕底部距离
                  _buildSection(
                    title: '字幕边距',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '调整字幕距离视频边缘的距离',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _DarkIconButton(
                              icon: Icons.remove_rounded,
                              onPressed: () => notifier.setBottomPadding(
                                style.bottomPadding - 8,
                              ),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: _darkSliderTheme,
                                child: Slider(
                                  value: style.bottomPadding,
                                  min: 0,
                                  max: 200,
                                  divisions: 25,
                                  onChanged: notifier.setBottomPadding,
                                ),
                              ),
                            ),
                            _DarkIconButton(
                              icon: Icons.add_rounded,
                              onPressed: () => notifier.setBottomPadding(
                                style.bottomPadding + 8,
                              ),
                            ),
                            SizedBox(
                              width: 56,
                              child: Text(
                                '${style.bottomPadding.round()}px',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static SliderThemeData get _darkSliderTheme => SliderThemeData(
    activeTrackColor: Colors.white,
    inactiveTrackColor: Colors.white24,
    thumbColor: Colors.white,
    overlayColor: Colors.white24,
    trackHeight: 2,
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
  );

  Widget _buildSubtitlePreview(SubtitleStyle style) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        // 只有开启背景时才显示背景颜色
        color: style.showBackground
            ? style.backgroundColor
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '这是字幕预览效果',
        style: TextStyle(
          fontSize: style.fontSize * 0.5,
          color: style.fontColor,
          fontWeight: style.fontWeight,
          shadows: style.hasOutline
              ? [
                  Shadow(
                    color: style.outlineColor,
                    blurRadius: style.outlineWidth,
                    offset: const Offset(1, 1),
                  ),
                  Shadow(
                    color: style.outlineColor,
                    blurRadius: style.outlineWidth,
                    offset: const Offset(-1, -1),
                  ),
                ]
              : null,
        ),
      ),
    ),
  );

  Widget _buildSection({required String title, required Widget child}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}

/// 暗色图标按钮
class _DarkIconButton extends StatelessWidget {
  const _DarkIconButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    icon: Icon(icon, color: Colors.white60, size: 20),
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
  );
}

/// 位置/选项芯片（暗色风格）
class _PositionChip extends StatelessWidget {
  const _PositionChip({
    required this.label,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white12 : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.white38 : Colors.white24,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : Colors.white60,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 快捷芯片（暗色风格）
class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    ),
  );
}

/// 颜色选择按钮
class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.showTransparent = false,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final bool showTransparent;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? Colors.white : Colors.white24,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: showTransparent
          ? CustomPaint(painter: _TransparentPainter())
          : isSelected
          ? Icon(
              Icons.check_rounded,
              color: color.computeLuminance() > 0.5
                  ? Colors.black
                  : Colors.white,
              size: 18,
            )
          : null,
    ),
  );
}

class _TransparentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    paint.color = Colors.grey[300]!;
    canvas.drawArc(rect, 0, 3.14159, true, paint);

    paint.color = Colors.grey[600]!;
    canvas.drawArc(rect, 3.14159, 3.14159, true, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
