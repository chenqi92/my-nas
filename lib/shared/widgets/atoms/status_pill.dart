import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';

/// 设计稿 `.state-pill` 原子：传输 / 下载任务状态徽标。
enum PillStatus { downloading, seeding, paused, queued, completed, error, info }

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {this.label, super.key});

  final PillStatus status;

  /// 自定义文案，缺省走 [PillStatus] 默认中文。
  final String? label;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, text) = switch (status) {
      PillStatus.downloading => (
          const Color(0x245B9DFF),
          const Color(0xFF7DB1FF),
          appL10n.pillStatusDownloading,
        ),
      PillStatus.seeding => (
          const Color(0x2434D399),
          const Color(0xFF34D399),
          appL10n.pillStatusSeeding,
        ),
      PillStatus.paused => (
          const Color(0x2494A3B8),
          const Color(0xFF94A3B8),
          appL10n.pillStatusPaused,
        ),
      PillStatus.queued => (
          const Color(0x24F5B754),
          const Color(0xFFF5B754),
          appL10n.pillStatusQueued,
        ),
      PillStatus.completed => (
          const Color(0x246E788C),
          const Color(0xFF8B94A7),
          appL10n.pillStatusCompleted,
        ),
      PillStatus.error => (
          const Color(0x24F87171),
          const Color(0xFFF87171),
          appL10n.pillStatusError,
        ),
      PillStatus.info => (
          DesignTokens.of(context).chipBg,
          DesignTokens.of(context).text2,
          appL10n.pillStatusInfo,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label ?? text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
