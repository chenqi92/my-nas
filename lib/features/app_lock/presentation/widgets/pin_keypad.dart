import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';

/// 9 宫格 PIN 输入键盘
///
/// 仅负责键位渲染与回调，不处理 PIN 校验 / 显示状态。
class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onDelete,
    this.onBiometric,
    this.disabled = false,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onDelete;

  /// 左下角生物识别按钮回调。null 时不显示
  final VoidCallback? onBiometric;

  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface;

    final bio = onBiometric;
    final buttons = <Widget>[
      for (var i = 1; i <= 9; i++) _digitButton(context, fg, i),
      if (bio == null)
        const SizedBox.shrink()
      else
        _iconButton(context, fg, Icons.fingerprint_rounded, onTap: bio),
      _digitButton(context, fg, 0),
      _iconButton(
        context,
        fg,
        Icons.backspace_outlined,
        onTap: onDelete,
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.2,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      children: buttons,
    );
  }

  Widget _digitButton(BuildContext context, Color fg, int digit) =>
      _KeypadButton(
        disabled: disabled,
        onTap: () => onDigit(digit),
        child: Text(
          '$digit',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: fg,
            fontWeight: FontWeight.w300,
          ),
        ),
      );

  Widget _iconButton(
    BuildContext context,
    Color fg,
    IconData icon, {
    required VoidCallback onTap,
  }) => _KeypadButton(
    disabled: disabled,
    onTap: onTap,
    child: Icon(icon, color: fg, size: 26),
  );
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    required this.child,
    required this.onTap,
    required this.disabled,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? AppColors.darkSurfaceVariant.withValues(alpha: 0.4)
        : AppColors.lightSurfaceVariant.withValues(alpha: 0.6);
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: disabled ? null : onTap,
        child: Center(child: child),
      ),
    );
  }
}

/// PIN 进度点指示器
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.length,
    required this.maxLength,
    this.error = false,
  });

  final int length;
  final int maxLength;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filled = error
        ? AppColors.error
        : (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface);
    final empty = isDark
        ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
        : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(maxLength, (i) {
        final isFilled = i < length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? filled : Colors.transparent,
            border: Border.all(color: isFilled ? filled : empty, width: 1.5),
          ),
        );
      }),
    );
  }
}
