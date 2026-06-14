import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

/// 桌面端照片查看器：全屏遮罩 + 大图缩放 + 左右切换 + 缩略图条。
///
/// 用 [showDesktopPhotoViewer] 打开，键盘 ← → 切换、Esc 关闭。
Future<void> showDesktopPhotoViewer(
  BuildContext context, {
  required List<PhotoEntity> photos,
  required int initialIndex,
}) {
  final l = AppLocalizations.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    barrierDismissible: true,
    barrierLabel: l.photoViewerBarrierLabel,
    pageBuilder: (_, _, _) =>
        _DesktopPhotoViewer(photos: photos, initialIndex: initialIndex),
  );
}

class _DesktopPhotoViewer extends ConsumerStatefulWidget {
  const _DesktopPhotoViewer({required this.photos, required this.initialIndex});
  final List<PhotoEntity> photos;
  final int initialIndex;

  @override
  ConsumerState<_DesktopPhotoViewer> createState() =>
      _DesktopPhotoViewerState();
}

class _DesktopPhotoViewerState extends ConsumerState<_DesktopPhotoViewer> {
  late int _index = widget.initialIndex;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next >= 0 && next < widget.photos.length) {
      setState(() => _index = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];
    final connections = ref.watch(activeConnectionsProvider);
    final fs = connections[photo.sourceId]?.adapter.fileSystem;

    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) _go(1);
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) _go(-1);
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
        }
      },
      child: Stack(
        children: [
          // 大图。
          Positioned.fill(
            child: StreamImage(
              key: ValueKey(photo.uniqueKey),
              // 有文件流时不传缩略图 URL，强制走 getFileStream 加载原图；
              // 没有可流式加载的源时才回退缩略图。
              url: fs != null ? null : photo.thumbnailUrl,
              path: photo.filePath,
              fileSystem: fs,
              fit: BoxFit.contain,
              enableZoom: true,
              preferFullQuality: true,
              placeholder: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: const Center(
                child: Icon(Icons.broken_image_outlined,
                    color: Colors.white54, size: 48),
              ),
            ),
          ),
          // 顶部信息条。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          photo.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${_index + 1} / ${widget.photos.length} · '
                          '${photo.displaySize}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          // 左右切换按钮。
          if (_index > 0)
            Positioned(
              left: 12,
              top: 0,
              bottom: 0,
              child: Center(child: _NavButton(Icons.chevron_left_rounded, () => _go(-1))),
            ),
          if (_index < widget.photos.length - 1)
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: Center(child: _NavButton(Icons.chevron_right_rounded, () => _go(1))),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton(this.icon, this.onTap);
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
