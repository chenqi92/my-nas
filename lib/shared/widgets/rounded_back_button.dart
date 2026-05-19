import 'package:flutter/material.dart';

/// 圆润风格的返回按钮。
///
/// Flutter 默认的 [BackButton] 在 Windows / Linux / Android 上使用
/// [Icons.arrow_back]（方角箭头），与 Material rounded 图标族风格不
/// 一致。本组件强制使用 [Icons.arrow_back_rounded]，行为与 [BackButton]
/// 完全一致（按下时 `Navigator.maybePop`）。
///
/// 用在 `AppBar(leading: const RoundedBackButton())` 上即可。
class RoundedBackButton extends StatelessWidget {
  const RoundedBackButton({
    super.key,
    this.color,
    this.onPressed,
  });

  final Color? color;

  /// 自定义点击行为。默认 `Navigator.maybePop(context)`。
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: color),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      );
}
