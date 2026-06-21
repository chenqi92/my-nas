import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/shared/utils/form_l10n.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

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
          const SheetDragHandle(bottomPadding: 0),

          // 标题
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.aspect_ratio),
                const SizedBox(width: 12),
                Text(
                  context.l10n.videoAspectRatioSelectorTitle,
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

  String _getDescription(BuildContext context) => switch (mode) {
      AspectRatioMode.auto => context.l10n.videoAspectRatioDescAuto,
      AspectRatioMode.fill => context.l10n.videoAspectRatioDescFill,
      AspectRatioMode.contain => context.l10n.videoAspectRatioDescContain,
      AspectRatioMode.cover => context.l10n.videoAspectRatioCover,
      AspectRatioMode.r16x9 => context.l10n.videoAspectRatioDesc16x9,
      AspectRatioMode.r4x3 => context.l10n.videoAspectRatioDesc4x3,
      AspectRatioMode.r21x9 => context.l10n.videoAspectRatioDesc21x9,
      AspectRatioMode.r1x1 => context.l10n.videoAspectRatioDesc1x1,
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
          localizeFormText(context, mode.label),
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        subtitle: Text(
          _getDescription(context),
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
