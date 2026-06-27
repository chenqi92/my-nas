import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';

/// Shared desktop empty state for media and ops pages.
class DesktopEmptyState extends StatelessWidget {
  const DesktopEmptyState({
    required this.icon,
    required this.message,
    this.title,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    this.embedded = false,
    super.key,
  });

  final IconData icon;
  final String? title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final minHeight = compact ? 116.0 : 164.0;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 22 : 28,
        vertical: compact ? 22 : 30,
      ),
      decoration: embedded
          ? null
          : BoxDecoration(
              color: t.panelBg,
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              border: Border.all(color: t.panelBorder),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  t.accent.withValues(alpha: 0.045),
                  t.panelBg,
                  t.panelBg,
                ],
                stops: const [0, 0.32, 1],
              ),
            ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 42 : 50,
                height: compact ? 42 : 50,
                decoration: BoxDecoration(
                  color: t.chipBgActive,
                  borderRadius: BorderRadius.circular(DesignTokens.radius),
                  border: Border.all(color: t.accent.withValues(alpha: 0.12)),
                ),
                child: Icon(
                  icon,
                  size: compact ? 21 : 25,
                  color: t.accentBright,
                ),
              ),
              if (title != null) ...[
                const SizedBox(height: 14),
                Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: t.text0,
                  ),
                ),
              ],
              SizedBox(height: title == null ? 14 : 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.55, color: t.text2),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                AppButton(
                  label: actionLabel!,
                  icon: Icons.arrow_forward_rounded,
                  dense: true,
                  onPressed: onAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
