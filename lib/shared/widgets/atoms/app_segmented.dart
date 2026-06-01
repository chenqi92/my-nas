import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';

class AppSegmentedOption<T> {
  const AppSegmentedOption({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

/// 设计稿 `.segmented` 原子：macOS 风灰底分段控件。
///
/// 与现有 `ElegantSegmentControl`（发光风格）并存，专供桌面新外壳与桌面变体
/// page 使用，避免风格混杂。
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    required this.options,
    required this.value,
    required this.onChanged,
    this.dense = false,
    super.key,
  });

  final List<AppSegmentedOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.insetBg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(color: t.hairline, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final opt in options)
            _Seg<T>(
              option: opt,
              selected: opt.value == value,
              dense: dense,
              onTap: () => onChanged(opt.value),
            ),
        ],
      ),
    );
  }
}

class _Seg<T> extends StatelessWidget {
  const _Seg({
    required this.option,
    required this.selected,
    required this.dense,
    required this.onTap,
  });

  final AppSegmentedOption<T> option;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final fg = selected ? t.text0 : t.text2;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: DesignTokens.ease,
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 8 : 12,
            vertical: dense ? 3 : 5,
          ),
          decoration: BoxDecoration(
            color: selected ? t.segOnBg : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (option.icon != null) ...[
                Icon(option.icon, size: 13, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                option.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
