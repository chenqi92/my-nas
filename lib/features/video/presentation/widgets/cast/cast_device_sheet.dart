import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/domain/entities/cast_device.dart';
import 'package:my_nas/features/video/presentation/providers/cast_provider.dart';
import 'package:my_nas/features/video/presentation/theme/video_player_colors.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 投屏设备选择面板
class CastDeviceSheet extends ConsumerStatefulWidget {
  const CastDeviceSheet({
    super.key,
    this.onDeviceSelected,
  });

  /// 设备选中回调
  final ValueChanged<CastDevice>? onDeviceSelected;

  @override
  ConsumerState<CastDeviceSheet> createState() => _CastDeviceSheetState();
}

class _CastDeviceSheetState extends ConsumerState<CastDeviceSheet> {
  @override
  void initState() {
    super.initState();
    // 自动开始搜索设备
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(castProvider.notifier).startDiscovery();
    });
  }

  @override
  Widget build(BuildContext context) {
    final castState = ref.watch(castProvider);
    final isDiscovering = castState.isDiscovering;
    final devices = castState.devices;
    final error = castState.error;

    return Container(
      decoration: const BoxDecoration(
        color: VideoPlayerColors.darkBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽指示条
            const SheetDragHandle(bottomPadding: 0),

            // 标题栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.cast,
                    color: VideoPlayerColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '选择投屏设备',
                      style: TextStyle(
                        color: VideoPlayerColors.primary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // 刷新按钮
                  IconButton(
                    onPressed: isDiscovering ? null : () => ref.read(castProvider.notifier).refreshDevices(),
                    icon: isDiscovering
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: VideoPlayerColors.primary,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, color: VideoPlayerColors.primary),
                    tooltip: '刷新',
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: VideoPlayerColors.divider),

            // 错误提示
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: VideoPlayerColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: VideoPlayerColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: VideoPlayerColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error,
                          style: const TextStyle(color: VideoPlayerColors.error, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 设备列表
            Flexible(
              child: _buildDeviceList(devices, isDiscovering),
            ),

            // 提示文字
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '请确保投屏设备与手机在同一网络',
                style: VideoPlayerColors.subtitleTextStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList(List<CastDevice> devices, bool isDiscovering) {
    if (devices.isEmpty && isDiscovering) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: VideoPlayerColors.primary),
            SizedBox(height: 16),
            Text(
              '正在搜索设备...',
              style: TextStyle(color: VideoPlayerColors.secondary),
            ),
          ],
        ),
      );
    }

    if (devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cast,
              size: 48,
              color: VideoPlayerColors.disabled,
            ),
            const SizedBox(height: 16),
            const Text(
              '未发现投屏设备',
              style: TextStyle(
                color: VideoPlayerColors.secondary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请确保设备已开启并连接到同一网络',
              style: VideoPlayerColors.subtitleTextStyle,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => ref.read(castProvider.notifier).refreshDevices(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新搜索'),
              style: OutlinedButton.styleFrom(
                foregroundColor: VideoPlayerColors.primary,
                side: VideoPlayerColors.buttonBorder,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final device = devices[index];
        return _DeviceListTile(
          device: device,
          onTap: () => widget.onDeviceSelected?.call(device),
        );
      },
    );
  }
}

/// 设备列表项
class _DeviceListTile extends StatelessWidget {
  const _DeviceListTile({
    required this.device,
    required this.onTap,
  });

  final CastDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: VideoPlayerColors.castIndicatorBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _getProtocolIcon(device.protocol),
            color: VideoPlayerColors.primary,
            size: 24,
          ),
        ),
        title: Text(
          device.name,
          style: const TextStyle(
            color: VideoPlayerColors.primary,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          device.description,
          style: VideoPlayerColors.subtitleTextStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: VideoPlayerColors.castIndicatorBg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            device.protocol.label,
            style: const TextStyle(
              color: VideoPlayerColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );

  IconData _getProtocolIcon(CastProtocol protocol) => switch (protocol) {
        CastProtocol.dlna => Icons.tv,
        CastProtocol.airplay => Icons.airplay,
      };
}
