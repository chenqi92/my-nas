import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/data/services/playlist_io_service.dart';
import 'package:my_nas/features/music/data/services/playlist_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/playlist_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/mini_player.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_app_bar.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 歌单详情页面
class PlaylistDetailPage extends ConsumerStatefulWidget {
  const PlaylistDetailPage({
    required this.playlist,
    super.key,
  });

  final PlaylistEntry playlist;

  static void open(BuildContext context, PlaylistEntry playlist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistDetailPage(playlist: playlist),
      ),
    );
  }

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage>
    with ConsumerTabBarVisibilityMixin {
  List<MusicItem> _tracks = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dbService = MusicDatabaseService();
      await dbService.init();

      final tracks = <MusicItem>[];

      // 获取最新的歌单数据
      final playlistService = PlaylistService();
      await playlistService.init();
      final currentPlaylist = await playlistService.getPlaylist(widget.playlist.id);

      if (currentPlaylist == null) {
        setState(() {
          _isLoading = false;
          _error = context.l10n.musicPlaylistNotFound;
        });
        return;
      }

      // 获取已连接的源
      final connections = ref.read(activeConnectionsProvider);

      // 从数据库中查找歌曲
      // trackPath 格式可能是:
      // 1. 新格式: "sourceId_/path/to/file.mp3" (带有 sourceId 前缀)
      // 2. 旧格式: "/path/to/file.mp3" (仅路径)
      for (final trackPath in currentPlaylist.trackPaths) {
        MusicTrackEntity? trackEntity;

        // 尝试解析 sourceId 和 path
        final underscoreIndex = trackPath.indexOf('_');
        if (underscoreIndex > 0 && trackPath.substring(0, underscoreIndex).isNotEmpty) {
          // 新格式: sourceId_path
          final sourceId = trackPath.substring(0, underscoreIndex);
          final path = trackPath.substring(underscoreIndex + 1);
          trackEntity = await dbService.get(sourceId, path);
        }

        // 如果没找到，尝试在所有已连接的源中搜索
        if (trackEntity == null) {
          // 可能是旧格式，尝试在所有源中搜索
          for (final entry in connections.entries) {
            if (entry.value.status == SourceStatus.connected) {
              final entity = await dbService.get(entry.key, trackPath);
              if (entity != null) {
                trackEntity = entity;
                break;
              }
            }
          }
        }

        if (trackEntity != null) {
          // 将 MusicTrackEntity 转换为 MusicItem
          final musicItem = _entityToMusicItem(trackEntity, connections);
          if (musicItem != null) {
            tracks.add(musicItem);
          }
        } else {
          logger.w('PlaylistDetail: 未找到曲目: $trackPath');
        }
      }

      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    } on Exception catch (e, stackTrace) {
      logger.e('PlaylistDetail: 加载歌单失败', e, stackTrace);
      setState(() {
        _isLoading = false;
        _error = '加载失败: $e';
      });
    }
  }

  /// 将数据库实体转换为 MusicItem
  MusicItem? _entityToMusicItem(
    MusicTrackEntity entity,
    Map<String, SourceConnection> connections,
  ) {
    final connection = connections[entity.sourceId];
    if (connection == null) return null;

    // 生成播放 URL
    String url;
    if (connection.status == SourceStatus.connected) {
      // 生成一个临时 URL，实际播放时会重新获取
      url = 'nas://${entity.sourceId}${entity.filePath}';
    } else {
      url = '';
    }

    return MusicItem(
      id: '${entity.sourceId}_${entity.filePath}',
      name: entity.fileName,
      path: entity.filePath,
      url: url,
      sourceId: entity.sourceId,
      title: entity.title,
      artist: entity.artist,
      album: entity.album,
      duration: entity.duration != null
          ? Duration(milliseconds: entity.duration!)
          : null,
      size: entity.size,
      trackNumber: entity.trackNumber,
      year: entity.year,
      genre: entity.genre,
    );
  }

  Future<void> _playAll({bool shuffle = false}) async {
    if (_tracks.isEmpty) return;

    final playerNotifier = ref.read(musicPlayerControllerProvider.notifier);
    final queueNotifier = ref.read(playQueueProvider.notifier);

    // 设置播放队列
    if (shuffle) {
      final shuffledTracks = List<MusicItem>.from(_tracks)..shuffle();
      queueNotifier.setQueue(shuffledTracks);
      await playerNotifier.play(shuffledTracks.first);
    } else {
      queueNotifier.setQueue(_tracks);
      await playerNotifier.play(_tracks.first);
    }
  }

  Future<void> _removeTrack(MusicItem track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.musicRemoveTrackDialogTitle),
        content: Text(context.l10n.musicRemoveTrackDialogContent(track.displayTitle)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.musicRemoveTrackButton),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(playlistProvider.notifier).removeFromPlaylist(
            widget.playlist.id,
            track.path,
          );
      // 刷新列表
      await _loadTracks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentMusic = ref.watch(currentMusicProvider);
    final uiStyle = ref.watch(uiStyleProvider);
    final safeTop = MediaQuery.of(context).padding.top;
    final bgColor = isDark ? AppColors.darkBackground : Colors.grey[50];

    // iOS 26 玻璃模式
    if (uiStyle.isGlass) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Stack(
          children: [
            CustomScrollView(
              slivers: [
                // 顶部留白
                SliverToBoxAdapter(
                  child: SizedBox(height: safeTop + 56),
                ),
                // 歌单信息头部
                SliverToBoxAdapter(
                  child: _buildHeader(isDark),
                ),
                // 歌曲列表
                if (_isLoading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 48,
                            color: AppColors.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _loadTracks,
                            child: Text(context.l10n.commonRetry),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_tracks.isEmpty)
                  SliverFillRemaining(
                    child: _buildEmptyView(isDark),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.only(
                      bottom: currentMusic != null ? 80 : 16,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildTrackTile(
                          _tracks[index],
                          index,
                          isDark,
                        ),
                        childCount: _tracks.length,
                      ),
                    ),
                  ),
              ],
            ),
            // 悬浮顶栏
            Positioned(
              top: safeTop + 8,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 左侧：返回按钮 + 标题
                  GlassFloatingBackButton(title: widget.playlist.name),
                  // 右侧：更多菜单
                  GlassButtonGroup(
                    children: [
                      GlassGroupPopupMenuButton<String>(
                        icon: Icons.more_vert_rounded,
                        tooltip: context.l10n.commonMore,
                        onSelected: _handleMenuAction,
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'rename',
                            child: Row(
                              children: [
                                Icon(Icons.edit_rounded, size: 20),
                                SizedBox(width: 12),
                                Text(context.l10n.musicPlaylistRename),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'clear',
                            child: Row(
                              children: [
                                Icon(Icons.clear_all_rounded, size: 20),
                                SizedBox(width: 12),
                                Text(context.l10n.musicPlaylistClear),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_rounded, size: 20, color: AppColors.error),
                                const SizedBox(width: 12),
                                Text(context.l10n.musicPlaylistDelete, style: TextStyle(color: AppColors.error)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 迷你播放器
            if (currentMusic != null)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MiniPlayer(),
              ),
          ],
        ),
      );
    }

    // 经典模式
    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // 顶部 AppBar
              _buildAppBar(isDark),
              // 歌单信息头部
              SliverToBoxAdapter(
                child: _buildHeader(isDark),
              ),
              // 歌曲列表
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _loadTracks,
                          child: Text(context.l10n.commonRetry),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_tracks.isEmpty)
                SliverFillRemaining(
                  child: _buildEmptyView(isDark),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.only(
                    bottom: currentMusic != null ? 80 : 16,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildTrackTile(
                        _tracks[index],
                        index,
                        isDark,
                      ),
                      childCount: _tracks.length,
                    ),
                  ),
                ),
            ],
          ),
          // 迷你播放器
          if (currentMusic != null)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MiniPlayer(),
            ),
        ],
      ),
    );
  }

  Widget _buildAppBar(bool isDark) => SliverAppBar(
        pinned: true,
        backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.playlist.name,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: isDark ? Colors.white : Colors.black87,
            ),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_rounded, size: 20),
                    SizedBox(width: 12),
                    Text(context.l10n.musicPlaylistRename),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.clear_all_rounded, size: 20),
                    SizedBox(width: 12),
                    Text(context.l10n.musicPlaylistClear),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export_m3u8',
                child: Row(
                  children: [
                    Icon(Icons.file_download_rounded, size: 20),
                    SizedBox(width: 12),
                    Text(context.l10n.musicExportM3u8),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export_json',
                child: Row(
                  children: [
                    Icon(Icons.code_rounded, size: 20),
                    SizedBox(width: 12),
                    Text(context.l10n.musicExportJson),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_rounded, size: 20, color: AppColors.error),
                    SizedBox(width: 12),
                    Text(context.l10n.musicPlaylistDelete, style: TextStyle(color: AppColors.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      );

  Widget _buildHeader(bool isDark) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 歌单封面
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF9C27B0).withValues(alpha: 0.8),
                    const Color(0xFFE91E63).withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.playlist_play_rounded,
                color: Colors.white,
                size: 64,
              ),
            ),
            const SizedBox(height: 16),
            // 歌曲数量
            Text(
              context.l10n.musicTrackCount(_tracks.length),
              style: TextStyle(
                fontSize: 14,
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            // 播放按钮
            Row(
              children: [
                Expanded(
                  child: _PlayButton(
                    onPressed: _playAll,
                    icon: Icons.play_arrow_rounded,
                    label: context.l10n.musicPlayAll,
                    isPrimary: true,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PlayButton(
                    onPressed: () => _playAll(shuffle: true),
                    icon: Icons.shuffle_rounded,
                    label: context.l10n.musicShufflePlay,
                    isPrimary: false,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _buildTrackTile(MusicItem track, int index, bool isDark) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = currentMusic?.path == track.path;

    // 检查源是否已连接
    final connections = ref.watch(activeConnectionsProvider);
    final connection = track.sourceId != null ? connections[track.sourceId] : null;
    final isConnected =
        connection != null && connection.status == SourceStatus.connected;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isPlaying
            ? AppColors.primary.withValues(alpha: 0.1)
            : (isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: isPlaying
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.3))
            : Border.all(
                color: isDark
                    ? AppColors.darkOutline.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.2),
              ),
      ),
      child: ListTile(
        onTap: isConnected
            ? () => _playTrack(track, index)
            : null,
        leading: _buildCover(track, isPlaying, isDark),
        title: Text(
          track.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
            color: isPlaying
                ? AppColors.primary
                : (isDark ? Colors.white : Colors.black87),
          ),
        ),
        subtitle: Text(
          track.displayArtist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: isConnected
                ? (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)
                : AppColors.error,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isConnected)
              Icon(
                Icons.cloud_off_rounded,
                size: 16,
                color: AppColors.error,
              ),
            IconButton(
              icon: Icon(
                Icons.more_vert_rounded,
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
              onPressed: () => _showTrackOptions(track),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(MusicItem track, bool isPlaying, bool isDark) {
    Widget coverImage;
    final coverData = track.coverData;
    if (coverData != null && coverData.isNotEmpty) {
      coverImage = Image.memory(
        Uint8List.fromList(coverData),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildDefaultCover(isPlaying),
      );
    } else {
      coverImage = _buildDefaultCover(isPlaying);
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: isPlaying
            ? Border.all(color: AppColors.primary, width: 2)
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: coverImage,
      ),
    );
  }

  Widget _buildDefaultCover(bool isPlaying) => Container(
        color: isPlaying
            ? AppColors.primary.withValues(alpha: 0.3)
            : Colors.grey[300],
        child: Icon(
          Icons.music_note_rounded,
          color: isPlaying ? AppColors.primary : Colors.grey[500],
          size: 24,
        ),
      );

  Widget _buildEmptyView(bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.playlist_add_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.musicPlaylistEmpty,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.musicPlaylistEmptyHint,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  Future<void> _playTrack(MusicItem track, int index) async {
    final playerNotifier = ref.read(musicPlayerControllerProvider.notifier);

    // 设置播放队列为歌单中的所有歌曲
    ref.read(playQueueProvider.notifier).setQueue(_tracks);
    // 播放选中的歌曲
    await playerNotifier.play(track);
  }

  void _showTrackOptions(MusicItem track) {
    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkSurface
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动指示器
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 歌曲信息
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _buildCover(
                      track,
                      false,
                      Theme.of(context).brightness == Brightness.dark,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            track.displayArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 操作选项
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: Text(context.l10n.musicPlay),
                onTap: () {
                  Navigator.pop(context);
                  _playTrack(track, _tracks.indexOf(track));
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(context.l10n.musicAddToQueue),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(playQueueProvider.notifier).addToQueue(track);
                  context.showSuccessToast(context.l10n.musicAddedToQueueToast);
                },
              ),
              ListTile(
                leading: Icon(Icons.remove_circle_outline_rounded,
                    color: AppColors.error),
                title: Text(context.l10n.musicRemoveFromPlaylist,
                    style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(context);
                  _removeTrack(track);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'rename':
        _showRenameDialog();
      case 'clear':
        _showClearConfirm();
      case 'delete':
        _showDeleteConfirm();
      case 'export_m3u8':
        AppError.fireAndForget(_exportPlaylist(asJson: false), action: 'playlist.exportM3u8');
      case 'export_json':
        AppError.fireAndForget(_exportPlaylist(asJson: true), action: 'playlist.exportJson');
    }
  }

  Future<void> _exportPlaylist({required bool asJson}) async {
    final fresh =
        await PlaylistService().getPlaylist(widget.playlist.id) ??
            widget.playlist;
    final content = asJson
        ? await PlaylistIoService.instance.exportJson(fresh)
        : await PlaylistIoService.instance.exportM3u8(fresh);
    final dir = await getTemporaryDirectory();
    final ext = asJson ? 'json' : 'm3u8';
    final safeName = fresh.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filePath = p.join(dir.path, '$safeName.$ext');
    await File(filePath).writeAsString(content);
    await Share.shareXFiles(
      [XFile(filePath)],
      subject: fresh.name,
    );
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: widget.playlist.name);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.musicRenamePlaylistDialogTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.l10n.musicPlaylistNameHint,
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty && name != widget.playlist.name) {
                await ref
                    .read(playlistProvider.notifier)
                    .renamePlaylist(widget.playlist.id, name);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: Text(context.l10n.commonConfirm),
          ),
        ],
      ),
    );
  }

  void _showClearConfirm() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.musicClearPlaylistDialogTitle),
        content: Text(context.l10n.musicClearPlaylistDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              await ref
                  .read(playlistProvider.notifier)
                  .clearPlaylist(widget.playlist.id);
              if (context.mounted) {
                Navigator.pop(context);
                await _loadTracks();
              }
            },
            child: Text(context.l10n.musicClearButton),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.musicDeletePlaylistDialogTitle),
        content: Text(context.l10n.musicDeletePlaylistDialogContent(widget.playlist.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              await ref
                  .read(playlistProvider.notifier)
                  .deletePlaylist(widget.playlist.id);
              if (context.mounted) {
                Navigator.pop(context); // 关闭对话框
                Navigator.pop(context); // 返回上一页
              }
            },
            child: Text(context.l10n.musicDeleteButton),
          ),
        ],
      ),
    );
  }
}

/// 播放按钮
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.isPrimary,
    required this.isDark,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool isPrimary;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            decoration: BoxDecoration(
              gradient: isPrimary
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.secondary],
                    )
                  : null,
              color: isPrimary
                  ? null
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey[200]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: isPrimary
                        ? Colors.white
                        : (isDark ? Colors.white : Colors.black87),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: isPrimary
                          ? Colors.white
                          : (isDark ? Colors.white : Colors.black87),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
