import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';

/// 设计稿 `.kbd` 原子：键盘提示 chip（如 `⌘K`）。
class AppKbd extends StatelessWidget {
  const AppKbd(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.insetBg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: t.hairline, width: 1),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'SF Mono',
          fontFamilyFallback: const ['Menlo', 'monospace'],
          fontFeatures: const [FontFeature.tabularFigures()],
          fontSize: 11,
          color: t.text2,
        ),
      ),
    );
  }
}
