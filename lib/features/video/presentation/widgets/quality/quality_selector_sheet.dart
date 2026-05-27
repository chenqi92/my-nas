import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';
import 'package:my_nas/features/video/presentation/providers/quality_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 显示清晰度选择器
void showQualitySelectorSheet(BuildContext context) {
  showAdaptiveModalSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => const QualitySelectorSheet(),
  );
}

/// 清晰度选择面板（Infuse 暗色风格）
class QualitySelectorSheet extends ConsumerWidget {
  const QualitySelectorSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qualityState = ref.watch(qualityStateProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示器
          const SheetDragHandle(bottomPadding: 0),

          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.high_quality_rounded,
                  color: Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  '画质',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
                const Spacer(),
                // 转码能力标识
                if (qualityState.canSwitchQuality)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      qualityState.isServerSideTranscoding ? '服务端转码' : '本地转码',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white24, height: 1),

          // 清晰度列表
          if (!qualityState.canSwitchQuality)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: const [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 48,
                    color: Colors.white38,
                  ),
                  SizedBox(height: 12),
                  Text(
                    '当前源不支持清晰度切换',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '只能播放原画',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: qualityState.availableQualities.length,
                itemBuilder: (context, index) {
                  final quality = qualityState.availableQualities[index];
                  final isSelected = quality == qualityState.currentQuality;
                  final isLoading = qualityState.isLoading && isSelected;

                  return _QualityTile(
                    quality: quality,
                    isSelected: isSelected,
                    isLoading: isLoading,
                    onTap: () {
                      if (!qualityState.isLoading) {
                        ref.read(qualityStateProvider.notifier).switchQuality(quality);
                        Navigator.pop(context);
                      }
                    },
                  );
                },
              ),
            ),

          // 底部提示
          if (qualityState.canSwitchQuality)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 14,
                    color: Colors.white38,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      qualityState.isServerSideTranscoding
                          ? '由服务端实时转码，切换可能需要几秒'
                          : '使用本地转码，可能增加设备负载',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

/// 清晰度选项（暗色风格）
class _QualityTile extends StatelessWidget {
  const _QualityTile({
    required this.quality,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
  });

  final VideoQuality quality;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                // 清晰度图标
                Icon(
                  _getQualityIcon(quality),
                  color: isSelected ? Colors.white : Colors.white60,
                  size: 22,
                ),
                const SizedBox(width: 14),
                // 清晰度信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quality.label,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 15,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      if (quality.bitrateLabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          quality.bitrateLabel!,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // 选中状态或加载指示器
                if (isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      );

  IconData _getQualityIcon(VideoQuality quality) => switch (quality) {
        VideoQuality.original => Icons.auto_awesome_rounded,
        VideoQuality.quality4K => Icons.four_k_rounded,
        VideoQuality.quality1080p => Icons.hd_rounded,
        VideoQuality.quality720p => Icons.hd_outlined,
        VideoQuality.quality480p => Icons.sd_rounded,
        VideoQuality.quality360p => Icons.sd_outlined,
      };
}
