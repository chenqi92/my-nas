import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';

/// 设计稿 `.switch` 原子：macOS 风格开关（36×21，开态 #28c840）。
///
/// 对应 `app.css`：
/// ```
/// .switch { width:36px; height:21px; border-radius:999px;
///           background:var(--inset-bg); border:.5px solid var(--hairline); }
/// .switch.on { background:#28c840; border-color:transparent; }
/// .switch::after { width:17px; height:17px; left:1.5px → 17.5px; }
/// ```
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  /// macOS 开关开态绿（与设计稿一致，独立于 accent）。
  static const Color onColor = Color(0xFF28C840);

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final disabled = !enabled || onChanged == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: DesignTokens.ease,
          width: 36,
          height: 21,
          decoration: BoxDecoration(
            color: value ? onColor : t.insetBg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: value ? Colors.transparent : t.hairline,
              width: 0.5,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: DesignTokens.ease,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.all(1.5),
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
