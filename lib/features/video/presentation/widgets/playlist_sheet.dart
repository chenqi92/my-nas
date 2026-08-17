import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/presentation/providers/playlist_provider.dart';

/// 显示播放列表（Infuse 风格右侧面板）
void showPlaylistSheet(BuildContext context) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.l10n.videoPlaylistSheetBarrierLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondaryAnimation) =>
        const _PlaylistPanel(),
  );
}

class _PlaylistPanel extends ConsumerStatefulWidget {
  const _PlaylistPanel();

  @override
  ConsumerState<_PlaylistPanel> createState() => _PlaylistPanelState();
}

class _PlaylistPanelState extends ConsumerState<_PlaylistPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _controller.reverse();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlist = ref.watch(playlistProvider);
    final playlistNotifier = ref.read(playlistProvider.notifier);

    return GestureDetector(
      onTap: _close,
      behavior: HitTestBehavior.opaque,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ColoredBox(
          color: Colors.black38,
          child: Row(
            children: [
              // 左侧点击区域关闭
              const Expanded(child: SizedBox.expand()),

              // 右侧播放列表面板
              SlideTransition(
                position: _slideAnimation,
                child: GestureDetector(
                  onTap: () {}, // 阻止点击穿透
                  child: Container(
                    width: 360,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(16),
                      ),
                    ),
                    child: SafeArea(
                      left: false,
                      child: Column(
                        children: [
                          // 标题栏
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.playlist_play_rounded,
                                  color: Colors.white70,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        context.l10n.videoPlaylistPanelTitle,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      Text(
                                        context.l10n.videoPlaylistItemCount(playlist.length),
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                          fontWeight: FontWeight.normal,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // 循环模式
                                IconButton(
                                  onPressed: playlistNotifier.toggleRepeatMode,
                                  icon: Icon(
                                    _getRepeatIcon(playlist.repeatMode),
                                    color: playlist.repeatMode != VideoRepeatMode.none
                                        ? Colors.white
                                        : Colors.white54,
                                  ),
                                  tooltip: _getRepeatTooltip(playlist.repeatMode, context),
                                ),
                                // 随机播放
                                IconButton(
                                  onPressed: playlistNotifier.toggleShuffle,
                                  icon: Icon(
                                    Icons.shuffle_rounded,
                                    color: playlist.shuffleEnabled
                                        ? Colors.white
                                        : Colors.white54,
                                  ),
                                  tooltip: playlist.shuffleEnabled
                                      ? context.l10n.videoPlaylistShuffleOn
                                      : context.l10n.videoPlaylistShuffleOff,
                                ),
                                IconButton(
                                  onPressed: _close,
                                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),

                          const Divider(color: Colors.white24, height: 1),

                          // 播放列表内容
                          Expanded(
                            child: playlist.isEmpty
                                ? _buildEmptyState()
                                : ReorderableListView.builder(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    itemCount: playlist.items.length,
                                    onReorderItem: playlistNotifier.moveItem,
                                    itemBuilder: (context, index) {
                                      final item = playlist.items[index];
                                      final isPlaying = index == playlist.currentIndex;

                                      return _PlaylistItem(
                                        key: ValueKey(item.path),
                                        item: item,
                                        index: index,
                                        isPlaying: isPlaying,
                                        onTap: () {
                                          playlistNotifier.playAt(index);
                                          _close();
                                        },
                                        onRemove: () {
                                          playlistNotifier.removeFromPlaylist(index);
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.queue_music_rounded,
              size: 64,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.videoPlaylistEmptyTitle,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.videoPlaylistEmptySubtitle,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 14,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      );

  IconData _getRepeatIcon(VideoRepeatMode mode) => switch (mode) {
        VideoRepeatMode.none => Icons.repeat_rounded,
        VideoRepeatMode.all => Icons.repeat_rounded,
        VideoRepeatMode.one => Icons.repeat_one_rounded,
      };

  String _getRepeatTooltip(VideoRepeatMode mode, BuildContext context) => switch (mode) {
        VideoRepeatMode.none => context.l10n.videoPlaylistRepeatNone,
        VideoRepeatMode.all => context.l10n.videoPlaylistRepeatAll,
        VideoRepeatMode.one => context.l10n.videoPlaylistRepeatOne,
      };
}

class _PlaylistItem extends StatelessWidget {
  const _PlaylistItem({
    required super.key,
    required this.item,
    required this.index,
    required this.isPlaying,
    required this.onTap,
    required this.onRemove,
  });

  final VideoItem item;
  final int index;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Dismissible(
        key: ValueKey('dismiss_${item.path}'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onRemove(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: AppColors.error.withValues(alpha: 0.8),
          child: const Icon(Icons.delete_rounded, color: Colors.white),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // 序号/播放指示
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isPlaying
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: isPlaying
                          ? const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 20,
                            )
                          : Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 视频信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isPlaying ? Colors.white : Colors.white70,
                            fontSize: 14,
                            fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatSize(item.size, context),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 拖拽手柄
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: Colors.white38,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  String _formatSize(int bytes, BuildContext context) {
    if (bytes <= 0) return context.l10n.videoPlaylistItemSizeUnknown;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
