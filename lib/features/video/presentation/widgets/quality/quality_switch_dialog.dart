import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';
import 'package:my_nas/features/video/presentation/providers/quality_provider.dart';
import 'package:my_nas/shared/utils/form_l10n.dart';

/// 清晰度切换建议弹窗
/// 当检测到播放卡顿时显示，建议用户切换到较低清晰度
class QualitySwitchDialog extends ConsumerStatefulWidget {
  const QualitySwitchDialog({
    required this.currentQuality,
    required this.suggestedQuality,
    super.key,
  });

  final VideoQuality currentQuality;
  final VideoQuality suggestedQuality;

  @override
  ConsumerState<QualitySwitchDialog> createState() => _QualitySwitchDialogState();
}

class _QualitySwitchDialogState extends ConsumerState<QualitySwitchDialog> {
  bool _dontAskAgain = false;

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题区域
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      context.l10n.videoQualitySwitchDialogTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),

              // 描述
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  context.l10n.videoQualitySwitchDialogDescription,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 清晰度对比
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      _QualityCompareRow(
                        label: context.l10n.videoQualitySwitchCurrentLabel,
                        quality: widget.currentQuality,
                        isHighlighted: false,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Icon(
                          Icons.arrow_downward_rounded,
                          color: Colors.white38,
                          size: 20,
                        ),
                      ),
                      _QualityCompareRow(
                        label: context.l10n.videoQualitySwitchSuggestedLabel,
                        quality: widget.suggestedQuality,
                        isHighlighted: true,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 不再询问选项
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: InkWell(
                  onTap: () => setState(() => _dontAskAgain = !_dontAskAgain),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: _dontAskAgain,
                            onChanged: (value) => setState(() => _dontAskAgain = value ?? false),
                            activeColor: Colors.white,
                            checkColor: Colors.black,
                            side: const BorderSide(color: Colors.white54),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.l10n.videoQualitySwitchDontAskAgain,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 按钮区域
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    // 保持原画按钮
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          ref.read(qualityStateProvider.notifier).rejectSuggestion(
                                dontAskAgain: _dontAskAgain,
                              );
                          Navigator.pop(context);
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Colors.white24),
                          ),
                        ),
                        child: Text(
                          context.l10n.videoQualitySwitchKeepQuality(localizeFormText(context, widget.currentQuality.label)),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 切换按钮
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          ref.read(qualityStateProvider.notifier).acceptSuggestion();
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          context.l10n.videoQualitySwitchSwitchQuality(localizeFormText(context, widget.suggestedQuality.label)),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// 清晰度对比行
class _QualityCompareRow extends StatelessWidget {
  const _QualityCompareRow({
    required this.label,
    required this.quality,
    required this.isHighlighted,
  });

  final String label;
  final VideoQuality quality;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isHighlighted ? Colors.green.withValues(alpha: 0.2) : Colors.white12,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isHighlighted ? Colors.green : Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              localizeFormText(context, quality.label),
              style: TextStyle(
                color: isHighlighted ? Colors.white : Colors.white70,
                fontSize: 15,
                fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          if (quality.bitrateLabel != null)
            Text(
              quality.bitrateLabel!,
              style: TextStyle(
                color: isHighlighted ? Colors.white54 : Colors.white38,
                fontSize: 12,
                decoration: TextDecoration.none,
              ),
            ),
        ],
      );
}

/// 显示清晰度切换建议弹窗
Future<void> showQualitySwitchDialog(
  BuildContext context, {
  required VideoQuality currentQuality,
  required VideoQuality suggestedQuality,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => QualitySwitchDialog(
      currentQuality: currentQuality,
      suggestedQuality: suggestedQuality,
    ),
  );
}
