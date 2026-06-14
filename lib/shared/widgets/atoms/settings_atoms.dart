import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';

/// 设计稿 `.set-head`：设置 pane 顶部的图标 + 标题 + 副标题（+ 右侧动作）。
class SetHead extends StatelessWidget {
  const SetHead({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actions,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: t.chipBgActive,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 21, color: t.accentBright),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.46,
                    height: 1.1,
                    color: t.text0,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 580),
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: t.text2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions != null) ...[
            const SizedBox(width: 12),
            ...actions!,
          ],
        ],
      ),
    );
  }
}

/// 设计稿 `.set-card`：分组标题（UPPERCASE）+ 圆角卡片容器（内含若干 [SetRow]）。
class SetSection extends StatelessWidget {
  const SetSection({
    required this.children,
    this.title,
    this.hint,
    this.bottomMargin = true,
    super.key,
  });

  final List<Widget> children;

  /// 分组标题（`.set-card-h`，小号大写灰字）。
  final String? title;

  /// 标题右侧灰色提示（`.h-hint`，常为对应配置键名）。
  final String? hint;
  final bool bottomMargin;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottomMargin ? 22 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 9),
              child: Row(
                children: [
                  Text(
                    title!.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.55,
                      color: t.text3,
                    ),
                  ),
                  if (hint != null) ...[
                    const Spacer(),
                    Text(
                      hint!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: t.text3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: t.cardBg,
              border: Border.all(color: t.cardBorder),
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// 设计稿 `.set-row`：一行设置项（标题 + 描述 + 右侧控件），底部 hairline 分隔。
class SetRow extends StatelessWidget {
  const SetRow({
    required this.title,
    this.desc,
    this.trailing,
    this.leading,
    this.last = false,
    super.key,
  });

  final String title;
  final String? desc;
  final Widget? trailing;
  final Widget? leading;

  /// 是否为分组内最后一行（最后一行无底部分隔线）。
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.text0,
                  ),
                ),
                if (desc != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    desc!,
                    style: TextStyle(fontSize: 12, color: t.text2),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 14),
            trailing!,
          ],
        ],
      ),
    );
  }
}
