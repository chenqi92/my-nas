import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';

/// 设计稿 `.tag` 原子：极小尺寸语义标签（10.5px / 语义色）。
///
/// [variant] 决定背景/文字色：
/// - [TagVariant.neutral]（默认）：text2 on insetBg
/// - [TagVariant.plan]：「即将推出」黄
/// - [TagVariant.limit]：「受限」灰
/// - [TagVariant.free]：「Free」绿
/// - [TagVariant.accent]：强调色
/// - [TagVariant.hot]：直播红
enum TagVariant { neutral, plan, limit, free, accent, hot }

class AppTag extends StatelessWidget {
  const AppTag(
    this.label, {
    this.variant = TagVariant.neutral,
    this.icon,
    super.key,
  });

  final String label;
  final TagVariant variant;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    // plan/limit/free 在浅色下需更深的文字色 + 更浅的底色，对齐 styles.css
    // `html[data-theme="light"] .tag-*` 分支。
    final (bg, fg) = switch (variant) {
      TagVariant.neutral => (t.insetBg, t.text2),
      TagVariant.plan =>
        isLight
            ? (const Color(0x29D39429), const Color(0xFF90600F))
            : (const Color(0x24F5B754), const Color(0xFFF5B754)),
      TagVariant.limit =>
        isLight
            ? (const Color(0x1F5A6474), const Color(0xFF5A6470))
            : (const Color(0x1F94A3B8), const Color(0xFF94A3B8)),
      TagVariant.free =>
        isLight
            ? (const Color(0x211F9D6B), const Color(0xFF107A52))
            : (const Color(0x2434D399), const Color(0xFF34D399)),
      TagVariant.accent => (t.chipBgActive, t.accentBright),
      TagVariant.hot => (const Color(0x24E0322E), const Color(0xFFE0322E)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: variant == TagVariant.plan
            ? Border.all(
                color: isLight
                    ? const Color(0x52D39429)
                    : const Color(0x4DF5B754),
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
