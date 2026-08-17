import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/local_file_uri.dart';
import 'package:my_nas/features/music/data/services/music_cover_cache_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 显示播放队列
void showMusicQueueSheet(BuildContext context) {
  showAdaptiveModalSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const MusicQueueSheet(),
  );
}

class MusicQueueSheet extends ConsumerWidget {
  const MusicQueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final queue = ref.watch(playQueueProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);
    final currentMusic = ref.watch(currentMusicProvider);
    final uiStyle = ref.watch(uiStyleProvider);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => GestureDetector(
          onTap: () {}, // 阻止点击穿透到外层关闭弹框
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey[900]!.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    // 拖拽指示器
                    const SheetDragHandle(bottomPadding: 0),
                    // 标题栏
                    _buildHeader(context, ref, queue, isDark),
                    // 当前播放提示
                    if (currentMusic != null)
                      _buildNowPlaying(context, currentMusic, isDark),
                    // 分隔线
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Divider(
                        height: 1,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    // 队列列表
                    Expanded(
                      child: queue.isEmpty
                          ? _buildEmptyState(context, isDark)
                          : _buildQueueList(
                              context,
                              ref,
                              queue,
                              playerState,
                              currentMusic,
                              scrollController,
                              isDark,
                              uiStyle,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    List<MusicItem> queue,
    bool isDark,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
    child: Row(
      children: [
        // 图标
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.secondary],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.queue_music_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        // 标题和数量
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.musicQueueSheetTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                context.l10n.musicQueueSheetSubtitle(queue.length),
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ],
          ),
        ),
        // 清空按钮
        if (queue.isNotEmpty)
          TextButton.icon(
            onPressed: () {
              ref.read(playQueueProvider.notifier).clear();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: const Icon(Icons.clear_all_rounded, size: 18),
            label: Text(context.l10n.musicQueueSheetClearButton),
          ),
      ],
    ),
  );

  Widget _buildNowPlaying(
    BuildContext context,
    MusicItem currentMusic,
    bool isDark,
  ) => Container(
    margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
    ),
    child: Row(
      children: [
        // 动态图标
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.equalizer_rounded,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        // 当前播放信息
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.musicQueueSheetNowPlayingLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                currentMusic.displayTitle,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildEmptyState(BuildContext context, bool isDark) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.03),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.queue_music_outlined,
            size: 40,
            color: isDark ? Colors.white30 : Colors.black26,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          context.l10n.musicQueueSheetEmptyTitle,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.musicQueueSheetEmptyDescription,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    ),
  );

  Widget _buildQueueList(
    BuildContext context,
    WidgetRef ref,
    List<MusicItem> queue,
    MusicPlayerState playerState,
    MusicItem? currentMusic,
    ScrollController scrollController,
    bool isDark,
    UIStyle uiStyle,
  ) {
    // 计算经典模式下的底部 padding
    final classicBottomPadding = _getClassicBottomPadding(context, uiStyle);

    return ReorderableListView.builder(
      scrollController: scrollController,
      padding: EdgeInsets.only(
        top: 8,
        bottom: 8 + classicBottomPadding,
        left: 12,
        right: 12,
      ),
      itemCount: queue.length,
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, child) => Material(
          color: Colors.transparent,
          elevation: 8,
          shadowColor: AppColors.primary.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          child: child,
        ),
        child: child,
      ),
      onReorder: (oldIndex, newIndex) {
        ref.read(playQueueProvider.notifier).reorder(oldIndex, newIndex);
        // 更新当前索引
        if (oldIndex == playerState.currentIndex) {
          ref
              .read(musicPlayerControllerProvider.notifier)
              .updateCurrentIndex(newIndex);
        } else if (oldIndex < playerState.currentIndex &&
            newIndex >= playerState.currentIndex) {
          ref
              .read(musicPlayerControllerProvider.notifier)
              .updateCurrentIndex(playerState.currentIndex - 1);
        } else if (oldIndex > playerState.currentIndex &&
            newIndex <= playerState.currentIndex) {
          ref
              .read(musicPlayerControllerProvider.notifier)
              .updateCurrentIndex(playerState.currentIndex + 1);
        }
      },
      itemBuilder: (context, index) {
        final track = queue[index];
        final isPlaying = currentMusic?.path == track.path;
        return _QueueItem(
          key: ValueKey(track.path),
          track: track,
          index: index,
          isPlaying: isPlaying,
          isDark: isDark,
          onTap: () =>
              ref.read(musicPlayerControllerProvider.notifier).playAt(index),
          onRemove: () {
            ref.read(playQueueProvider.notifier).removeFromQueue(index);
            if (index < playerState.currentIndex) {
              ref
                  .read(musicPlayerControllerProvider.notifier)
                  .updateCurrentIndex(playerState.currentIndex - 1);
            }
          },
        );
      },
    );
  }
}

/// 计算经典模式下的底部 padding
///
/// 经典模式下 Flutter 渲染导航栏，需要为底部弹框预留导航栏高度
/// 玻璃模式下原生导航栏悬浮在内容之上，不需要额外 padding
double _getClassicBottomPadding(BuildContext context, UIStyle uiStyle) {
  // 玻璃模式不需要额外 padding
  if (uiStyle.isGlass) return 0;

  // 经典模式：添加导航栏高度 + 安全区域
  final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
  const navBarHeight = kBottomNavigationBarHeight;

  return navBarHeight + bottomPadding;
}

class _QueueItem extends StatelessWidget {
  const _QueueItem({
    required this.track,
    required this.index,
    required this.isPlaying,
    required this.isDark,
    required this.onTap,
    required this.onRemove,
    super.key,
  });

  final MusicItem track;
  final int index;
  final bool isPlaying;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Dismissible(
    key: ValueKey('dismiss_${track.path}'),
    direction: DismissDirection.endToStart,
    onDismissed: (_) => onRemove(),
    background: Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.delete_rounded, color: Colors.white, size: 24),
    ),
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: isPlaying
            ? AppColors.primary.withValues(alpha: 0.15)
            : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.03)),
        borderRadius: BorderRadius.circular(16),
        border: isPlaying
            ? Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
                width: 1.5,
              )
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // 封面
                _buildCover(),
                const SizedBox(width: 12),
                // 信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isPlaying
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isPlaying
                              ? AppColors.primary
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.displayArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
                // 时长
                Text(
                  track.durationText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(width: 8),
                // 拖动手柄
                ReorderableDragStartListener(
                  index: index,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: isDark ? Colors.white30 : Colors.black26,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildCover() {
    final coverData = track.coverData;
    final coverUrl = track.coverUrl;
    Widget coverImage;

    // 1. 优先使用内存中的封面数据
    if (coverData != null && coverData.isNotEmpty) {
      coverImage = Image.memory(
        Uint8List.fromList(coverData),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildDefaultCover(),
      );
    } else {
      // 2. 尝试从缓存服务动态获取封面路径（解决 iOS 沙盒 UUID 变化问题）
      final effectiveCoverPath = _getEffectiveCoverPath();
      if (effectiveCoverPath != null && effectiveCoverPath.isNotEmpty) {
        coverImage = Image.file(
          File(effectiveCoverPath),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildDefaultCover(),
        );
      } else if (coverUrl != null && coverUrl.isNotEmpty) {
        // 3. 回退到 coverUrl
        if (coverUrl.startsWith('file://')) {
          final filePath = localPathFromFileUri(coverUrl);
          // 检查文件是否存在
          if (filePath != null && File(filePath).existsSync()) {
            coverImage = Image.file(
              File(filePath),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _buildDefaultCover(),
            );
          } else {
            coverImage = _buildDefaultCover();
          }
        } else {
          coverImage = Image.network(
            coverUrl,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _buildDefaultCover(),
          );
        }
      } else {
        coverImage = _buildDefaultCover();
      }
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: isPlaying
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            coverImage,
            if (isPlaying)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.4),
                child: const Center(
                  child: Icon(
                    Icons.equalizer_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultCover() => ColoredBox(
    color: isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.05),
    child: Icon(
      Icons.music_note_rounded,
      color: isDark ? Colors.white30 : Colors.black26,
      size: 24,
    ),
  );

  /// 动态获取有效的封面路径
  /// 参考 recent_tracks_section.dart 中的实现
  String? _getEffectiveCoverPath() {
    // 从 MusicItem 获取 sourceId 和 path
    final sourceId = track.sourceId;
    final path = track.path;
    if (sourceId == null || path.isEmpty) return null;

    // 从缓存服务动态获取
    final uniqueKey = '${sourceId}_$path';
    return MusicCoverCacheService().getCachedCoverPathSync(uniqueKey);
  }
}
