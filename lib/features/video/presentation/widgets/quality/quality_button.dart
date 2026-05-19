import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';
import 'package:my_nas/features/video/presentation/providers/quality_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/quality/quality_selector_sheet.dart';

/// 清晰度快捷按钮（显示在视频控制栏）- PopupMenu 风格
class QualityButton extends ConsumerWidget {
  const QualityButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qualityState = ref.watch(qualityStateProvider);

    // 如果不支持切换画质，只显示当前画质标签
    if (!qualityState.canSwitchQuality) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.high_quality_rounded, color: Colors.white54, size: 20),
            const SizedBox(width: 4),
            Text(
              qualityState.currentQuality.label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return PopupMenuButton<VideoQuality>(
      onSelected: (quality) {
        if (!qualityState.isLoading) {
          ref.read(qualityStateProvider.notifier).switchQuality(quality);
        }
      },
      offset: const Offset(0, -280),
      color: Colors.black87,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tooltip: '画质',
      enabled: !qualityState.isLoading,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.high_quality_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 4),
            Text(
              qualityState.currentQuality.label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            if (qualityState.isLoading) ...[
              const SizedBox(width: 6),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              ),
            ],
          ],
        ),
      ),
      itemBuilder: (context) => qualityState.availableQualities
          .map(
            (quality) => PopupMenuItem<VideoQuality>(
              value: quality,
              child: Row(
                children: [
                  Icon(
                    _getQualityIcon(quality),
                    size: 18,
                    color: quality == qualityState.currentQuality
                        ? Colors.white
                        : Colors.white70,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          quality.label,
                          style: TextStyle(
                            color: quality == qualityState.currentQuality
                                ? Colors.white
                                : Colors.white70,
                            fontWeight: quality == qualityState.currentQuality
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        if (quality.bitrateLabel != null)
                          Text(
                            quality.bitrateLabel!,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (quality == qualityState.currentQuality)
                    const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  IconData _getQualityIcon(VideoQuality quality) => switch (quality) {
        VideoQuality.original => Icons.auto_awesome_rounded,
        VideoQuality.quality4K => Icons.four_k_rounded,
        VideoQuality.quality1080p => Icons.hd_rounded,
        VideoQuality.quality720p => Icons.hd_outlined,
        VideoQuality.quality480p => Icons.sd_rounded,
        VideoQuality.quality360p => Icons.sd_outlined,
      };
}

/// 清晰度按钮（带边框样式，用于顶部栏）
class QualityButtonOutlined extends ConsumerWidget {
  const QualityButtonOutlined({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qualityState = ref.watch(qualityStateProvider);

    return GestureDetector(
      onTap: () => showQualitySelectorSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white54),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              qualityState.currentQuality.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
            if (qualityState.isLoading) ...[
              const SizedBox(width: 6),
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 清晰度图标按钮（仅图标）
class QualityIconButton extends ConsumerWidget {
  const QualityIconButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qualityState = ref.watch(qualityStateProvider);

    return IconButton(
      onPressed: () => showQualitySelectorSheet(context),
      icon: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.high_quality_rounded,
            color: Colors.white,
          ),
          if (qualityState.isLoading)
            const Positioned(
              right: -2,
              bottom: -2,
              child: SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              ),
            ),
        ],
      ),
      tooltip: '画质: ${qualityState.currentQuality.label}',
    );
  }
}
