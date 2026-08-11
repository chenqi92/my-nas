import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_empty_state.dart';

/// 所有「桌面变体」page 共用的页眉外框，统一 24/13.5 字号 + 上方 22px 间距
/// + 居中最大宽度。普通页面默认整体滚动；文件浏览器等自身已有主滚动区的
/// 页面可将 [scrollable] 设为 false，让 body 填满剩余视口，避免嵌套滚动。
class DesktopPageScaffold extends StatelessWidget {
  const DesktopPageScaffold({
    required this.title,
    required this.body,
    this.subtitle,
    this.actions,
    this.maxWidth = 1280,
    this.scrollable = true,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? actions;
  final double maxWidth;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final page = Center(
      child: ConstrainedBox(
        key: const ValueKey('desktop-page-content'),
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: t.text0,
                          ),
                        ),
                        if (subtitle case final s?) ...[
                          const SizedBox(height: 4),
                          Text(
                            s,
                            style: TextStyle(fontSize: 13, color: t.text2),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (actions != null) ...[const SizedBox(width: 18), actions!],
                ],
              ),
              const SizedBox(height: 20),
              if (scrollable)
                SizedBox(
                  key: const ValueKey('desktop-page-body'),
                  width: double.infinity,
                  child: body,
                )
              else
                Expanded(
                  child: SizedBox(
                    key: const ValueKey('desktop-page-body'),
                    width: double.infinity,
                    child: body,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (scrollable) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 112),
        child: page,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: page,
    );
  }
}

/// 一个统一风格的"待铺占位"提示，避免每个桌面变体页都从零造空态。
class DesktopComingSoon extends StatelessWidget {
  const DesktopComingSoon({
    required this.message,
    this.icon = Icons.auto_awesome_rounded,
    super.key,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      DesktopEmptyState(icon: icon, message: message);
}
