import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/cast_device.dart';
import 'package:my_nas/features/video/presentation/providers/cast_provider.dart';
import 'package:my_nas/features/video/presentation/theme/video_player_colors.dart';
import 'package:my_nas/features/video/presentation/widgets/cast/cast_device_sheet.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 投屏按钮 - PopupMenu 风格
class CastButton extends ConsumerStatefulWidget {
  const CastButton({
    super.key,
    this.size = 24,
    this.color,
    this.onCastStarted,
    this.onCastStopped,
  });

  /// 图标大小
  final double size;

  /// 图标颜色
  final Color? color;

  /// 投屏开始回调
  final VoidCallback? onCastStarted;

  /// 投屏结束回调
  final VoidCallback? onCastStopped;

  @override
  ConsumerState<CastButton> createState() => _CastButtonState();
}

class _CastButtonState extends ConsumerState<CastButton> {
  @override
  Widget build(BuildContext context) {
    final castState = ref.watch(castProvider);
    final isCasting = castState.isCasting;
    final isDiscovering = castState.isDiscovering;
    final devices = castState.devices;

    return PopupMenuButton<_CastAction>(
      onSelected: (action) => _handleAction(action, ref),
      onOpened: () {
        // 打开菜单时自动开始搜索设备
        if (!isCasting && !isDiscovering) {
          ref.read(castProvider.notifier).startDiscovery();
        }
      },
      offset: const Offset(0, -280),
      color: Colors.black87,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tooltip: isCasting ? context.l10n.videoCastCasting : context.l10n.videoCastIdle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDiscovering)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.color ?? Colors.white,
                ),
              )
            else
              Icon(
                isCasting ? Icons.cast_connected : Icons.cast,
                size: 20,
                color: isCasting
                    ? Colors.greenAccent
                    : (widget.color ?? Colors.white),
              ),
            if (isCasting) ...[
              const SizedBox(width: 4),
              Text(
                castState.session?.device.name ?? context.l10n.videoCastCasting,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
      itemBuilder: (context) {
        if (isCasting) {
          // 正在投屏时，显示控制选项
          return [
            PopupMenuItem<_CastAction>(
              enabled: false,
              child: Row(
                children: [
                  const Icon(Icons.cast_connected, size: 18, color: Colors.greenAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(context.l10n.videoCastCastingTo, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        Text(
                          castState.session?.device.name ?? context.l10n.videoCastUnknownDevice,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<_CastAction>(
              value: _CastAction.stop,
              child: Row(
                children: [
                  Icon(Icons.stop_rounded, size: 18, color: Colors.redAccent),
                  SizedBox(width: 12),
                  Text(context.l10n.videoCastStopCasting, style: TextStyle(color: Colors.redAccent)),
                ],
              ),
            ),
          ];
        }

        // 未投屏时，显示设备列表
        final items = <PopupMenuEntry<_CastAction>>[]
          // 标题
          ..add(
            PopupMenuItem<_CastAction>(
              enabled: false,
              child: Row(
                children: [
                  const Icon(Icons.cast, size: 18, color: Colors.white70),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(context.l10n.videoCastSelectDevice, style: TextStyle(color: Colors.white70)),
                  ),
                  if (isDiscovering)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white54),
                    )
                  else
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        ref.read(castProvider.notifier).refreshDevices();
                      },
                      child: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white54),
                    ),
                ],
              ),
            ),
          )
          ..add(const PopupMenuDivider());

        if (devices.isEmpty) {
          // 无设备
          items.add(
            PopupMenuItem<_CastAction>(
              enabled: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDiscovering ? Icons.search_rounded : Icons.cast,
                      size: 32,
                      color: Colors.white38,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isDiscovering ? context.l10n.videoCastSearching : context.l10n.videoCastNotFound,
                      style: const TextStyle(color: Colors.white54),
                    ),
                    if (!isDiscovering)
                      Text(
                        context.l10n.videoCastNetworkHint,
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),
          );
        } else {
          // 设备列表
          for (final device in devices) {
            items.add(
              PopupMenuItem<_CastAction>(
                value: _CastAction.selectDevice(device),
                child: Row(
                  children: [
                    Icon(
                      _getProtocolIcon(device.protocol),
                      size: 18,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            device.name,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            device.description,
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        device.protocol.label,
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }

        return items;
      },
    );
  }

  void _handleAction(_CastAction action, WidgetRef ref) {
    switch (action) {
      case _CastActionStop():
        ref.read(castProvider.notifier).stop();
        widget.onCastStopped?.call();
      case _CastActionSelectDevice():
        // 实际投屏逻辑需要在外部处理（需要视频路径等信息）
        widget.onCastStarted?.call();
    }
  }

  IconData _getProtocolIcon(CastProtocol protocol) => switch (protocol) {
        CastProtocol.dlna => Icons.tv,
        CastProtocol.airplay => Icons.airplay,
      };
}

/// 投屏按钮 - 带轮廓样式
class CastButtonOutlined extends ConsumerWidget {
  const CastButtonOutlined({
    super.key,
    this.onCastStarted,
    this.onCastStopped,
  });

  final VoidCallback? onCastStarted;
  final VoidCallback? onCastStopped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCasting = ref.watch(isCastingProvider);
    final isDiscovering = ref.watch(isDiscoveringDevicesProvider);

    return OutlinedButton.icon(
      onPressed: () => _handleTap(context, ref, isCasting),
      icon: _buildIcon(isCasting, isDiscovering),
      label: Text(isCasting ? context.l10n.videoCastCasting : context.l10n.videoCastIdle),
      style: OutlinedButton.styleFrom(
        foregroundColor: VideoPlayerColors.primary,
        side: VideoPlayerColors.buttonBorder,
      ),
    );
  }

  Widget _buildIcon(bool isCasting, bool isDiscovering) {
    if (isDiscovering) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: VideoPlayerColors.primary,
        ),
      );
    }

    return Icon(
      isCasting ? Icons.cast_connected : Icons.cast,
      size: 18,
    );
  }

  void _handleTap(BuildContext context, WidgetRef ref, bool isCasting) {
    if (isCasting) {
      _showCastControlSheet(context, ref);
    } else {
      _showDeviceSheet(context, ref);
    }
  }

  void _showDeviceSheet(BuildContext context, WidgetRef ref) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VideoPlayerColors.transparent,
      builder: (context) => CastDeviceSheet(
        onDeviceSelected: (device) {
          Navigator.pop(context);
          onCastStarted?.call();
        },
      ),
    );
  }

  void _showCastControlSheet(BuildContext context, WidgetRef ref) {
    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: VideoPlayerColors.transparent,
      builder: (context) => _CastControlSheet(
        onStop: () {
          Navigator.pop(context);
          ref.read(castProvider.notifier).stop();
          onCastStopped?.call();
        },
      ),
    );
  }
}

/// 简单的投屏控制面板
class _CastControlSheet extends ConsumerWidget {
  const _CastControlSheet({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final castState = ref.watch(castProvider);
    final session = castState.session;

    return Container(
      decoration: const BoxDecoration(
        color: VideoPlayerColors.darkBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽指示条
            const SheetDragHandle(topPadding: 0, bottomPadding: 0),
            const SizedBox(height: 20),

            // 设备信息
            Row(
              children: [
                const Icon(
                  Icons.cast_connected,
                  color: VideoPlayerColors.primary,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.videoCastCastingTo,
                        style: VideoPlayerColors.subtitleTextStyle,
                      ),
                      Text(
                        session?.device.name ?? context.l10n.videoCastUnknownDevice,
                        style: const TextStyle(
                          color: VideoPlayerColors.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 视频标题
            if (session != null)
              Text(
                session.videoTitle,
                style: VideoPlayerColors.titleTextStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 20),

            // 播放控制
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => ref.read(castProvider.notifier).togglePlayPause(),
                  iconSize: 64,
                  icon: Icon(
                    (session?.isPlaying ?? false) ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                    color: VideoPlayerColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 进度条
            if (session != null && session.duration > Duration.zero) ...[
              Row(
                children: [
                  Text(
                    _formatDuration(session.position),
                    style: VideoPlayerColors.timeTextStyle,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: VideoPlayerColors.getSliderTheme(context),
                      child: Slider(
                        value: session.progress.clamp(0.0, 1.0),
                        onChanged: (value) {
                          final position = Duration(
                            milliseconds: (value * session.duration.inMilliseconds).round(),
                          );
                          ref.read(castProvider.notifier).seek(position);
                        },
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(session.duration),
                    style: VideoPlayerColors.timeTextStyle,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // 停止投屏按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop_rounded),
                label: Text(context.l10n.videoCastStopCasting),
                style: OutlinedButton.styleFrom(
                  foregroundColor: VideoPlayerColors.primary,
                  side: VideoPlayerColors.buttonBorder,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 投屏操作类型
sealed class _CastAction {
  const _CastAction();

  /// 停止投屏
  static const stop = _CastActionStop();

  /// 选择设备
  static _CastActionSelectDevice selectDevice(CastDevice device) =>
      _CastActionSelectDevice(device);
}

/// 停止投屏操作
class _CastActionStop extends _CastAction {
  const _CastActionStop();
}

/// 选择设备操作
class _CastActionSelectDevice extends _CastAction {
  const _CastActionSelectDevice(this.device);
  final CastDevice device;
}
