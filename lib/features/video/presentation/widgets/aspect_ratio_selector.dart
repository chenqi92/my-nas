import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';

/// 画面比例类型
enum AspectRatioMode {
  auto('自动', null),
  fill('填充', null),
  contain('包含', null),
  cover('覆盖', null),
  r16x9('16:9', 16 / 9),
  r4x3('4:3', 4 / 3),
  r21x9('21:9', 21 / 9),
  r1x1('1:1', 1);

  const AspectRatioMode(this.label, this.ratio);

  final String label;
  final double? ratio;
}

/// 当前画面比例
final aspectRatioModeProvider = StateProvider<AspectRatioMode>((ref) => AspectRatioMode.auto);

/// 画面比例选择器
class AspectRatioSelector extends ConsumerWidget {
  const AspectRatioSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(aspectRatioModeProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动条
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 标题
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.aspect_ratio),
                const SizedBox(width: 12),
                Text(
                  '画面比例',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 选项列表
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final mode in AspectRatioMode.values)
                  _AspectRatioTile(
                    mode: mode,
                    isSelected: currentMode == mode,
                    onTap: () {
                      ref.read(aspectRatioModeProvider.notifier).state = mode;
                      Navigator.pop(context);
                    },
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 画面比例选项
class _AspectRatioTile extends StatelessWidget {
  const _AspectRatioTile({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  final AspectRatioMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  IconData get _icon => switch (mode) {
      AspectRatioMode.auto => Icons.auto_fix_high,
      AspectRatioMode.fill => Icons.fullscreen_rounded,
      AspectRatioMode.contain => Icons.fit_screen,
      AspectRatioMode.cover => Icons.crop_free,
      AspectRatioMode.r16x9 => Icons.rectangle_outlined,
      AspectRatioMode.r4x3 => Icons.crop_3_2,
      AspectRatioMode.r21x9 => Icons.panorama_wide_angle_outlined,
      AspectRatioMode.r1x1 => Icons.crop_square,
    };

  String get _description => switch (mode) {
      AspectRatioMode.auto => '根据视频自动调整',
      AspectRatioMode.fill => '拉伸填满屏幕',
      AspectRatioMode.contain => '完整显示，可能有黑边',
      AspectRatioMode.cover => '裁剪填满，可能裁掉部分画面',
      AspectRatioMode.r16x9 => '宽屏比例',
      AspectRatioMode.r4x3 => '传统电视比例',
      AspectRatioMode.r21x9 => '超宽屏/电影比例',
      AspectRatioMode.r1x1 => '正方形',
    };

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(
          _icon,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(
          mode.label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        subtitle: Text(
          _description,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: isSelected
            ? Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              )
            : null,
        onTap: onTap,
      );
}

/// 显示画面比例选择器
void showAspectRatioSelector(BuildContext context) {
  showAdaptiveModalSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const AspectRatioSelector(),
  );
}
