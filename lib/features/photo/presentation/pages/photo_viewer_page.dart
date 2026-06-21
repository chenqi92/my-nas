import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/core/utils/platform_capabilities.dart';
import 'package:my_nas/core/widgets/keyboard_shortcuts.dart';
import 'package:my_nas/features/photo/data/services/photo_favorites_service.dart';
import 'package:my_nas/features/photo/data/services/photo_save_service.dart';
import 'package:my_nas/features/photo/domain/entities/photo_item.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/mobile/file_systems/mobile_gallery_file_system.dart';
import 'package:my_nas/shared/providers/bottom_nav_visibility_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// 照片 URL 获取回调
typedef PhotoUrlGetter = Future<String?> Function(String path, String sourceId);

/// 文件系统获取回调
typedef FileSystemGetter = NasFileSystem? Function(String sourceId);

/// 相册文件系统获取回调（用于 Live Photo）
typedef GalleryFileSystemGetter = MobileGalleryFileSystem? Function(String sourceId);

/// 照片删除回调
typedef PhotoDeleteCallback = void Function(PhotoItem photo);

/// 照片查看器页面
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    required this.photos, required this.initialIndex, super.key,
    this.getPhotoUrl,
    this.getFileSystem,
    this.getGalleryFileSystem,
    this.onPhotoDeleted,
  });

  final List<PhotoItem> photos;
  final int initialIndex;
  final PhotoUrlGetter? getPhotoUrl;
  final FileSystemGetter? getFileSystem;
  /// 获取相册文件系统（用于 Live Photo 视频访问）
  final GalleryFileSystemGetter? getGalleryFileSystem;
  /// 照片删除后的回调（用于通知列表页刷新）
  final PhotoDeleteCallback? onPhotoDeleted;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  bool _showOverlay = true;
  late AnimationController _overlayController;
  late Animation<double> _overlayAnimation;
  Timer? _autoHideTimer;

  /// 自动隐藏延迟（秒）
  static const _autoHideDelay = Duration(seconds: 3);

  /// 缓存已加载的原图 URL
  final Map<String, String> _loadedUrls = {};

  /// 收藏服务
  final _favoritesService = PhotoFavoritesService();

  /// 当前照片是否已收藏
  bool _isFavorite = false;

  /// 正在切换收藏状态
  bool _isTogglingFavorite = false;

  // ==================== Live Photo 支持 ====================

  /// Live Photo 视频播放器
  Player? _livePhotoPlayer;
  VideoController? _livePhotoVideoController;

  /// 是否正在播放 Live Photo
  bool _isPlayingLivePhoto = false;

  /// 是否正在准备 Live Photo 视频
  bool _isPreparingLivePhoto = false;

  @override
  void initState() {
    super.initState();
    // 隐藏原生 Tab Bar（iOS 玻璃风格）
    NativeTabBarService.instance.setTabBarVisible(false);
    // 隐藏 Flutter 导航栏（经典风格）
    BottomNavVisibilityNotifier.instance?.hide();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1,
    );
    _overlayAnimation = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeInOut,
    );

    // 设置沉浸模式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // 初始化当前照片的 URL（如果已有）
    final currentPhoto = widget.photos[_currentIndex];
    if (currentPhoto.url.isNotEmpty) {
      _loadedUrls[currentPhoto.path] = currentPhoto.url;
    }

    // 启动自动隐藏定时器
    _startAutoHideTimer();

    // 加载收藏状态
    _loadFavoriteStatus();
  }

  /// 加载当前照片的收藏状态
  Future<void> _loadFavoriteStatus() async {
    final photo = widget.photos[_currentIndex];
    final isFav = await _favoritesService.isFavorite(photo.path, photo.sourceId);
    if (mounted) {
      setState(() {
        _isFavorite = isFav;
      });
    }
  }

  /// 切换收藏状态
  Future<void> _toggleFavorite() async {
    if (_isTogglingFavorite) return;

    final photo = widget.photos[_currentIndex];
    setState(() {
      _isTogglingFavorite = true;
    });

    try {
      final newState = await _favoritesService.toggleFavorite(photo);
      if (mounted) {
        setState(() {
          _isFavorite = newState;
          _isTogglingFavorite = false;
        });
      }
    } on Exception catch (e) {
      logger.e('PhotoViewerPage: 切换收藏失败', e);
      if (mounted) {
        setState(() {
          _isTogglingFavorite = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.photoViewerFavoriteToggleFailed(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _overlayController.dispose();
    _autoHideTimer?.cancel();
    // 释放 Live Photo 播放器
    _disposeLivePhotoPlayer();
    // 恢复系统 UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 恢复导航栏可见性（通过 Provider 引用计数，由 MainScaffold 决定实际状态）
    BottomNavVisibilityNotifier.instance?.show();
    super.dispose();
  }

  /// 释放 Live Photo 播放器资源
  void _disposeLivePhotoPlayer() {
    _livePhotoPlayer?.dispose();
    _livePhotoPlayer = null;
    _livePhotoVideoController = null;
  }

  /// 开始播放 Live Photo
  Future<void> _startLivePhotoPlayback(PhotoItem photo) async {
    // 仅 iOS 支持 Live Photo
    if (!Platform.isIOS) return;

    // 检查是否有视频路径
    if (photo.livePhotoVideoPath == null || photo.livePhotoVideoPath!.isEmpty) {
      // 尝试从文件系统获取
      final galleryFs = widget.getGalleryFileSystem?.call(photo.sourceId);
      if (galleryFs == null) {
        logger.w('PhotoViewerPage: 无法获取相册文件系统');
        return;
      }

      // 从 path 中提取 assetId
      final assetId = photo.path.split('/').last;
      final videoUrl = await galleryFs.getLivePhotoVideoUrl(assetId);
      if (videoUrl == null || videoUrl.isEmpty) {
        logger.w('PhotoViewerPage: 无法获取 Live Photo 视频 URL');
        return;
      }

      await _playLivePhotoVideo(videoUrl);
    } else {
      await _playLivePhotoVideo(photo.livePhotoVideoPath!);
    }
  }

  /// 播放 Live Photo 视频
  Future<void> _playLivePhotoVideo(String videoPath) async {
    if (_isPlayingLivePhoto || _isPreparingLivePhoto) return;

    setState(() {
      _isPreparingLivePhoto = true;
    });

    try {
      // 创建播放器
      _livePhotoPlayer = Player();
      _livePhotoVideoController = VideoController(_livePhotoPlayer!);

      // 监听播放结束
      _livePhotoPlayer!.stream.completed.listen((completed) {
        if (completed && mounted) {
          _stopLivePhotoPlayback();
        }
      });

      // 打开视频并播放
      final media = videoPath.startsWith('file://')
          ? Media(videoPath)
          : Media('file://$videoPath');
      await _livePhotoPlayer!.open(media, play: true);
      // 设置音量（Live Photo 通常需要静音或低音量）
      await _livePhotoPlayer!.setVolume(50);

      if (mounted) {
        setState(() {
          _isPlayingLivePhoto = true;
          _isPreparingLivePhoto = false;
        });
      }

      logger.d('PhotoViewerPage: 开始播放 Live Photo 视频');
    } catch (e) {
      logger.e('PhotoViewerPage: 播放 Live Photo 失败', e);
      _disposeLivePhotoPlayer();
      if (mounted) {
        setState(() {
          _isPlayingLivePhoto = false;
          _isPreparingLivePhoto = false;
        });
      }
    }
  }

  /// 停止 Live Photo 播放
  void _stopLivePhotoPlayback() {
    if (!_isPlayingLivePhoto && !_isPreparingLivePhoto) return;

    _disposeLivePhotoPlayer();
    if (mounted) {
      setState(() {
        _isPlayingLivePhoto = false;
        _isPreparingLivePhoto = false;
      });
    }
    logger.d('PhotoViewerPage: 停止 Live Photo 播放');
  }

  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    if (_showOverlay) {
      _autoHideTimer = Timer(_autoHideDelay, () {
        if (mounted && _showOverlay) {
          _hideOverlay();
        }
      });
    }
  }

  void _showOverlayWithTimer() {
    setState(() {
      _showOverlay = true;
      _overlayController.forward();
    });
    _startAutoHideTimer();
  }

  void _hideOverlay() {
    setState(() {
      _showOverlay = false;
      _overlayController.reverse();
    });
    _autoHideTimer?.cancel();
  }

  void _toggleOverlay() {
    if (_showOverlay) {
      _hideOverlay();
    } else {
      _showOverlayWithTimer();
    }
  }

  void _goToNext() {
    if (_currentIndex < widget.photos.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// 加载照片原图 URL
  Future<String?> _loadPhotoUrl(int index) async {
    final photo = widget.photos[index];

    // 如果已缓存，直接返回
    if (_loadedUrls.containsKey(photo.path)) {
      return _loadedUrls[photo.path];
    }

    // 如果照片已有 URL 且不为空，缓存并返回
    if (photo.url.isNotEmpty) {
      _loadedUrls[photo.path] = photo.url;
      return photo.url;
    }

    // 尝试通过回调获取原图 URL（使用 PhotoItem 中的 sourceId）
    if (widget.getPhotoUrl != null && photo.sourceId.isNotEmpty) {
      final url = await widget.getPhotoUrl!(photo.path, photo.sourceId);
      if (url != null && url.isNotEmpty) {
        _loadedUrls[photo.path] = url;
        if (mounted) setState(() {});
        return url;
      }
    }

    // 如果都失败，使用缩略图
    return photo.thumbnailUrl;
  }

  /// 预加载照片 URL
  void _preloadPhotoUrl(int index) {
    _loadPhotoUrl(index);
    // 预加载前后各一张
    if (index > 0) _loadPhotoUrl(index - 1);
    if (index < widget.photos.length - 1) _loadPhotoUrl(index + 1);
  }

  /// 构建 PhotoViewGallery 的页面选项
  /// 使用 StreamImageProvider 支持 SMB/WebDAV 等流式加载
  PhotoViewGalleryPageOptions _buildPhotoViewGalleryPageOptions(
    PhotoItem photo,
    String? cachedUrl,
    Future<String?> Function() onLoadUrl,
    NasFileSystem? fileSystem,
  ) {
    // 优先使用已缓存的 URL，其次使用 photo.url
    final displayUrl = cachedUrl ?? photo.url;
    final hasDisplayUrl = displayUrl.isNotEmpty;
    final hasOriginalImage = hasDisplayUrl && displayUrl != photo.thumbnailUrl;

    // 如果没有有效的原图 URL，尝试加载
    if (!hasOriginalImage && cachedUrl == null) {
      // 异步加载 URL，加载完成后会触发 setState 更新
      onLoadUrl();
    }

    // 决定使用哪个 URL：
    // 1. 如果有原图 URL，直接使用原图
    // 2. 如果没有原图但有文件系统，让 StreamImage 通过 path 加载原图（不传 url）
    // 3. 如果都没有，才使用缩略图
    final canLoadViaStream = fileSystem != null && photo.path.isNotEmpty;
    final String? imageUrl;

    if (hasOriginalImage) {
      // 有原图 URL，使用原图
      imageUrl = displayUrl;
    } else if (canLoadViaStream) {
      // 没有原图 URL 但可以通过流加载，不传 url 让 StreamImage 通过 path 加载原图
      imageUrl = null;
    } else {
      // 无法通过流加载，降级使用缩略图
      imageUrl = photo.thumbnailUrl ?? displayUrl;
    }

    return PhotoViewGalleryPageOptions.customChild(
      child: StreamImage(
        url: imageUrl,
        path: photo.path,
        fileSystem: fileSystem,
        fit: BoxFit.contain,
        preferFullQuality: true, // 预览模式加载原图，不使用缩略图
        placeholder: Center(
          child: CircularProgressIndicator(
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        errorWidget: _buildErrorWidget(photo, onLoadUrl),
        cacheKey: '${photo.path}_full', // 使用不同的缓存键区分原图和缩略图
      ),
      initialScale: PhotoViewComputedScale.contained,
      minScale: PhotoViewComputedScale.contained * 0.5,
      maxScale: PhotoViewComputedScale.covered * 4,
    );
  }

  /// 构建错误提示组件
  Widget _buildErrorWidget(PhotoItem photo, Future<String?> Function() onLoadUrl) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.broken_image_outlined,
          size: 64,
          color: Colors.white.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.photoViewerLoadFailed,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          photo.name,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () {
            onLoadUrl();
            setState(() {});
          },
          icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          label: Text(context.l10n.photoViewerRetry, style: const TextStyle(color: Colors.white70)),
        ),
      ],
    );

  /// 构建键盘快捷键映射
  Map<ShortcutKey, VoidCallback> _buildKeyboardShortcuts(PhotoItem photo) => {
        // 导航
        CommonShortcuts.previous: _goToPrevious,
        CommonShortcuts.next: _goToNext,
        CommonShortcuts.first: () => _pageController.jumpToPage(0),
        CommonShortcuts.last: () => _pageController.jumpToPage(widget.photos.length - 1),

        // 播放/暂停 用于切换覆盖层
        CommonShortcuts.playPause: _toggleOverlay,

        // 收藏 (L)
        CommonShortcuts.favorite: _toggleFavorite,

        // 信息 (I)
        CommonShortcuts.info: () => _showPhotoInfo(context, photo),

        // 退出 (Esc)
        CommonShortcuts.escape: () => Navigator.of(context).pop(),

        // 返回 (Backspace)
        CommonShortcuts.back: () => Navigator.of(context).pop(),
      };

  /// 显示快捷键帮助
  void _showKeyboardHelp() {
    KeyboardShortcutsHelpDialog.show(
      context,
      title: context.l10n.photoViewerKeyboardHelpTitle,
      shortcuts: [
        (key: '←', description: context.l10n.photoViewerKeyboardPrevious),
        (key: '→', description: context.l10n.photoViewerKeyboardNext),
        (key: 'Home', description: context.l10n.photoViewerKeyboardFirst),
        (key: 'End', description: context.l10n.photoViewerKeyboardLast),
        (key: 'Space', description: context.l10n.photoViewerKeyboardToggleControls),
        (key: 'L', description: context.l10n.photoViewerKeyboardToggleFavorite),
        (key: 'I', description: context.l10n.photoViewerKeyboardInfo),
        (key: 'Esc', description: context.l10n.photoViewerKeyboardExit),
        (key: '?', description: context.l10n.photoViewerKeyboardHelp),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_currentIndex];
    final isDesktop = MediaQuery.of(context).size.width > 600;

    return KeyboardShortcuts(
      shortcuts: {
        ..._buildKeyboardShortcuts(photo),
        // 帮助快捷键
        CommonShortcuts.help: _showKeyboardHelp,
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
        onTap: _toggleOverlay,
        // Live Photo: 长按播放视频
        onLongPressStart: photo.isLivePhoto
            ? (_) => _startLivePhotoPlayback(photo)
            : null,
        onLongPressEnd: photo.isLivePhoto
            ? (_) => _stopLivePhotoPlayback()
            : null,
        onLongPressCancel: photo.isLivePhoto
            ? _stopLivePhotoPlayback
            : null,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // 照片查看器 - 使用 PhotoViewGallery 解决放大后拖动与翻页的手势冲突
            PhotoViewGallery.builder(
              scrollPhysics: const BouncingScrollPhysics(),
              pageController: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: (index) {
                // 切换页面时停止 Live Photo 播放
                _stopLivePhotoPlayback();
                setState(() {
                  _currentIndex = index;
                });
                // 预加载当前页的原图 URL
                _preloadPhotoUrl(index);
                // 翻页时重置自动隐藏定时器
                if (_showOverlay) {
                  _startAutoHideTimer();
                }
                // 加载新页面的收藏状态
                _loadFavoriteStatus();
              },
              builder: (context, index) {
                final item = widget.photos[index];
                final cachedUrl = _loadedUrls[item.path];
                final fileSystem = widget.getFileSystem?.call(item.sourceId);
                return _buildPhotoViewGalleryPageOptions(
                  item,
                  cachedUrl,
                  () => _loadPhotoUrl(index),
                  fileSystem,
                );
              },
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              loadingBuilder: (context, event) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      value: event == null || event.expectedTotalBytes == null
                          ? null
                          : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
                      color: Colors.white,
                    ),
                    if (event != null && event.expectedTotalBytes != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${((event.cumulativeBytesLoaded / event.expectedTotalBytes!) * 100).toInt()}%',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Live Photo 视频播放层
            if (_isPlayingLivePhoto && _livePhotoVideoController != null)
              Positioned.fill(
                child: Video(
                  controller: _livePhotoVideoController!,
                  controls: (state) => const SizedBox.shrink(),
                  fit: BoxFit.contain,
                ),
              ),

            // Live Photo 准备中指示器
            if (_isPreparingLivePhoto)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),

            // Live Photo 徽章
            if (photo.isLivePhoto && !_isPlayingLivePhoto)
              Positioned(
                top: MediaQuery.of(context).padding.top + 60,
                left: 16,
                child: _LivePhotoBadge(
                  isPlaying: _isPlayingLivePhoto,
                  isPreparing: _isPreparingLivePhoto,
                ),
              ),

            // 顶部返回按钮（浮动）
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_showOverlay,
                child: FadeTransition(
                  opacity: _overlayAnimation,
                  child: _buildTopBar(context, photo),
                ),
              ),
            ),

            // 底部操作栏（浮动）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_showOverlay,
                child: FadeTransition(
                  opacity: _overlayAnimation,
                  child: _buildBottomBar(context, photo),
                ),
              ),
            ),

            // 左右导航按钮（桌面端）
            if (isDesktop && _showOverlay) ...[
              // 上一张
              if (_currentIndex > 0)
                Positioned(
                  left: 16,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _NavButton(
                      icon: Icons.arrow_back_ios_rounded,
                      onTap: _goToPrevious,
                    ),
                  ),
                ),
              // 下一张
              if (_currentIndex < widget.photos.length - 1)
                Positioned(
                  right: 16,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _NavButton(
                      icon: Icons.arrow_forward_ios_rounded,
                      onTap: _goToNext,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, PhotoItem photo) => DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black54,
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              // 返回按钮
              IconButton(
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white,
                  size: 32,
                ),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: context.l10n.photoViewerTooltipBack,
              ),
              // 页码指示器（居中显示）
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_currentIndex + 1} / ${widget.photos.length}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      photo.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              // 占位，保持标题居中
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );

  Widget _buildBottomBar(BuildContext context, PhotoItem photo) => DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black87,
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 照片信息
            if (photo.modifiedAt != null || photo.size > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 日期
                    if (photo.modifiedAt != null) ...[
                      Icon(
                        Icons.calendar_today_rounded,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(photo.modifiedAt!),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      if (photo.size > 0) const SizedBox(width: 16),
                    ],
                    // 文件大小（仅当 size > 0 时显示）
                    if (photo.size > 0) ...[
                      Icon(
                        Icons.insert_drive_file_outlined,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        photo.displaySize,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            // 操作按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 详细信息
                  _ActionButton(
                    icon: Icons.info_outline,
                    label: context.l10n.photoViewerActionInfo,
                    onTap: () {
                      _startAutoHideTimer();
                      _showPhotoInfo(context, photo);
                    },
                  ),
                  // 收藏
                  _ActionButton(
                    icon: _isFavorite ? Icons.favorite_rounded : Icons.favorite_border,
                    label: _isFavorite ? context.l10n.photoViewerActionFavorited : context.l10n.photoViewerActionFavorite,
                    onTap: _isTogglingFavorite
                        ? null
                        : () {
                            _startAutoHideTimer();
                            _toggleFavorite();
                          },
                  ),
                  // 下载（所有平台都支持，桌面端用文件选择器，移动端保存到相册）
                  _ActionButton(
                    icon: Icons.download_outlined,
                    label: PlatformCapabilities.isMobile ? context.l10n.photoViewerActionSave : context.l10n.photoViewerActionDownload,
                    onTap: () {
                      _startAutoHideTimer();
                      _downloadPhoto(context, photo);
                    },
                  ),
                  // 分享（仅在支持分享的平台显示）
                  if (PlatformCapabilities.canShare)
                    _ActionButton(
                      icon: Icons.share_outlined,
                      label: context.l10n.photoViewerActionShare,
                      onTap: () {
                        _startAutoHideTimer();
                        _sharePhoto(context, photo);
                      },
                    ),
                  // 删除
                  _ActionButton(
                    icon: Icons.delete_outline,
                    label: context.l10n.photoViewerActionDelete,
                    onTap: () {
                      _startAutoHideTimer();
                      _confirmDelete(context, photo);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

  void _showPhotoInfo(BuildContext context, PhotoItem photo) {
    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  Text(
                    context.l10n.photoViewerInfoTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InfoRow(label: context.l10n.photoViewerInfoFileName, value: photo.name),
              _InfoRow(label: context.l10n.photoViewerInfoPath, value: photo.path),
              if (photo.size > 0)
                _InfoRow(label: context.l10n.photoViewerInfoSize, value: photo.displaySize),
              if (photo.displayResolution != null)
                _InfoRow(label: context.l10n.photoViewerInfoResolution, value: photo.displayResolution!),
              if (photo.isLivePhoto)
                _InfoRow(label: context.l10n.photoViewerInfoType, value: context.l10n.photoViewerInfoTypeLivePhoto),
              if (photo.modifiedAt != null)
                _InfoRow(
                  label: context.l10n.photoViewerInfoModifiedTime,
                  value: DateFormat('yyyy-MM-dd HH:mm:ss').format(photo.modifiedAt!),
                ),
              if (photo.takenAt != null)
                _InfoRow(
                  label: context.l10n.photoViewerInfoTakenTime,
                  value: DateFormat('yyyy-MM-dd HH:mm:ss').format(photo.takenAt!),
                ),
              if (photo.cameraInfo != null)
                _InfoRow(label: context.l10n.photoViewerInfoCamera, value: photo.cameraInfo!),
              if (photo.hasLocation)
                _InfoRow(
                  label: context.l10n.photoViewerInfoLocation,
                  value: '${photo.latitude?.toStringAsFixed(6)}, ${photo.longitude?.toStringAsFixed(6)}',
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 下载照片
  /// 智能下载：根据 URL 类型和文件系统自动选择下载方式
  Future<void> _downloadPhoto(BuildContext context, PhotoItem photo) async {
    // 获取当前照片的 URL
    final url = _loadedUrls[photo.path] ?? photo.url;
    if (url.isEmpty) {
      _showErrorSnackBar(context, context.l10n.photoViewerDownloadNoUrl);
      return;
    }

    // 获取文件系统（用于 SMB/WebDAV 等流式下载）
    final fileSystem = widget.getFileSystem?.call(photo.sourceId);

    // 移动端需要先请求权限
    final saveService = PhotoSaveService();
    if (saveService.canSaveToGallery) {
      final hasPermission = await saveService.requestGalleryPermission();
      if (!hasPermission) {
        if (!context.mounted) return;
        _showErrorSnackBar(context, context.l10n.photoViewerDownloadNoPermission);
        return;
      }
    }

    if (!context.mounted) return;

    // 创建取消令牌和进度通知器
    final cancelToken = CancelToken();
    final progressNotifier = ValueNotifier<double>(0);
    var isDialogOpen = true;

    // 显示下载进度对话框（不阻塞）
    // ignore: unawaited_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 进度指示器
                ValueListenableBuilder<double>(
                  valueListenable: progressNotifier,
                  builder: (context, progress, _) => SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: progress > 0 ? progress : null,
                          strokeWidth: 3,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                        if (progress > 0)
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // 状态文字
                ValueListenableBuilder<double>(
                  valueListenable: progressNotifier,
                  builder: (context, progress, _) => Text(
                    progress > 0
                        ? (saveService.isMobile ? context.l10n.photoViewerDownloadingSaving : context.l10n.photoViewerDownloadingProgress)
                        : context.l10n.photoViewerDownloadConnecting,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // 取消按钮
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      cancelToken.cancel(context.l10n.photoViewerDownloadCancel);
                      if (isDialogOpen) {
                        isDialogOpen = false;
                        Navigator.of(dialogContext).pop();
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(context.l10n.photoViewerDownloadCancel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // 执行下载
    final result = await saveService.smartDownloadPhoto(
      url: url,
      path: photo.path,
      fileName: photo.name,
      fileSystem: fileSystem,
      cancelToken: cancelToken,
      onProgress: (progress) {
        if (!cancelToken.isCancelled) {
          progressNotifier.value = progress;
        }
      },
    );

    // 关闭进度对话框
    if (context.mounted && isDialogOpen) {
      isDialogOpen = false;
      Navigator.of(context).pop();
    }

    // 显示结果（取消时不显示）
    if (!context.mounted || result.isCancelled) return;

    if (result.isSuccess) {
      _showSuccessSnackBar(context, result.message);
    } else if (result.isFailure) {
      _showErrorSnackBar(context, result.message);
    }
  }

  /// 分享照片
  /// 智能分享：根据 URL 类型和文件系统自动选择分享方式
  Future<void> _sharePhoto(BuildContext context, PhotoItem photo) async {
    final url = _loadedUrls[photo.path] ?? photo.url;

    if (url.isEmpty) {
      _showErrorSnackBar(context, context.l10n.photoViewerShareNoUrl);
      return;
    }

    // 获取文件系统（用于 SMB/WebDAV 等流式分享）
    final fileSystem = widget.getFileSystem?.call(photo.sourceId);

    // 检查分享功能是否可用
    final saveService = PhotoSaveService();
    if (!saveService.canShare) {
      _showErrorSnackBar(context, context.l10n.photoViewerShareNotSupported);
      return;
    }

    // 在桌面端，提供选择：分享文件或复制链接/路径
    if (saveService.isDesktop) {
      _showShareOptionsDialog(context, photo, url, fileSystem);
      return;
    }

    // 移动端直接使用系统分享
    await _executeSmartShare(context, photo, url, fileSystem);
  }

  /// 执行智能分享
  Future<void> _executeSmartShare(
    BuildContext context,
    PhotoItem photo,
    String url,
    NasFileSystem? fileSystem,
  ) async {
    final saveService = PhotoSaveService();
    final cancelToken = CancelToken();
    final progressNotifier = ValueNotifier<double>(0);
    var isDialogOpen = false;

    // 本地文件不需要显示进度（直接分享）
    final isLocalFile = url.startsWith('file://');

    if (!isLocalFile) {
      isDialogOpen = true;
      // 显示进度对话框（不阻塞）
      // ignore: unawaited_futures
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 进度指示器
                  ValueListenableBuilder<double>(
                    valueListenable: progressNotifier,
                    builder: (context, progress, _) => SizedBox(
                      width: 56,
                      height: 56,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: progress > 0 ? progress : null,
                            strokeWidth: 3,
                            color: Colors.white,
                            backgroundColor: Colors.white24,
                          ),
                          if (progress > 0)
                            Text(
                              '${(progress * 100).toInt()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 状态文字
                  ValueListenableBuilder<double>(
                    valueListenable: progressNotifier,
                    builder: (context, progress, _) => Text(
                      progress > 0 ? context.l10n.photoViewerSharePreparing : context.l10n.photoViewerShareConnecting,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 取消按钮
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        cancelToken.cancel(context.l10n.photoViewerDownloadCancel);
                        if (isDialogOpen) {
                          isDialogOpen = false;
                          Navigator.of(dialogContext).pop();
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(context.l10n.photoViewerDownloadCancel),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 使用智能分享
    final result = await saveService.smartSharePhoto(
      url: url,
      path: photo.path,
      fileName: photo.name,
      fileSystem: fileSystem,
      cancelToken: cancelToken,
      onProgress: (progress) {
        if (!cancelToken.isCancelled) {
          progressNotifier.value = progress;
        }
      },
    );

    // 关闭进度对话框（如果显示了的话）
    if (isDialogOpen && context.mounted) {
      isDialogOpen = false;
      Navigator.of(context).pop();
    }

    // 显示结果（取消时不显示）
    if (!context.mounted || result.isCancelled) return;

    if (result.isFailure) {
      _showErrorSnackBar(context, result.error ?? context.l10n.photoViewerShareFailed);
    }
  }

  /// 显示桌面端分享选项对话框
  void _showShareOptionsDialog(
    BuildContext context,
    PhotoItem photo,
    String url,
    NasFileSystem? fileSystem,
  ) {
    // 判断 URL 类型
    final isHttpUrl = url.startsWith('http://') || url.startsWith('https://');
    final isLocalFile = url.startsWith('file://');

    // 根据 URL 类型决定复制选项的文案
    String copyTitle;
    String copySubtitle;
    String copyContent;

    if (isHttpUrl) {
      copyTitle = context.l10n.photoViewerShareCopyLink;
      copySubtitle = context.l10n.photoViewerShareCopyLinkSubtitle;
      copyContent = url;
    } else if (isLocalFile) {
      copyTitle = context.l10n.photoViewerShareCopyPath;
      copySubtitle = context.l10n.photoViewerShareCopyPathSubtitle;
      copyContent = Uri.parse(url).toFilePath();
    } else {
      // SMB/WebDAV 等
      copyTitle = context.l10n.photoViewerShareCopyPath;
      copySubtitle = context.l10n.photoViewerShareCopyPathSubtitle;
      copyContent = photo.path;
    }

    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.share_outlined, color: Colors.white),
                  const SizedBox(width: 12),
                  Text(
                    context.l10n.photoViewerShareOptionsTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 复制链接/路径
              _ShareOptionTile(
                icon: isHttpUrl ? Icons.link_rounded : Icons.folder_outlined,
                title: copyTitle,
                subtitle: copySubtitle,
                onTap: () {
                  Navigator.pop(sheetContext);
                  Clipboard.setData(ClipboardData(text: copyContent));
                  _showSuccessSnackBar(context, context.l10n.photoViewerShareCopied(copyTitle));
                },
              ),
              const Divider(color: Colors.white24),
              // 分享文件
              _ShareOptionTile(
                icon: Icons.file_present_outlined,
                title: context.l10n.photoViewerShareFile,
                subtitle: isLocalFile ? context.l10n.photoViewerShareFileSubtitleLocal : context.l10n.photoViewerShareFileSubtitleRemote,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _executeSmartShare(context, photo, url, fileSystem);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 确认删除
  void _confirmDelete(BuildContext context, PhotoItem photo) {
    // 获取文件系统
    final fileSystem = widget.getFileSystem?.call(photo.sourceId);

    // 检查是否可以删除
    if (fileSystem == null) {
      _showErrorSnackBar(context, context.l10n.photoViewerDeleteNoFileSystem);
      return;
    }

    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          context.l10n.photoViewerDeleteConfirmTitle,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          context.l10n.photoViewerDeleteConfirmContent(photo.name),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.photoViewerDeleteCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(context.l10n.photoViewerDeleteConfirm),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed ?? false) {
        if (!context.mounted) return;
        await _deletePhoto(context, photo, fileSystem);
      }
    });
  }

  /// 执行删除照片
  Future<void> _deletePhoto(
    BuildContext context,
    PhotoItem photo,
    NasFileSystem fileSystem,
  ) async {
    // 显示删除进度
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.grey[900],
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                context.l10n.photoViewerDeleting,
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      // 执行删除
      await fileSystem.delete(photo.path);
      logger.i('PhotoViewerPage: 已删除照片 ${photo.path}');

      // 关闭进度对话框
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // 通知外部删除成功
      widget.onPhotoDeleted?.call(photo);

      // 从收藏中移除（如果已收藏）
      if (_isFavorite) {
        await _favoritesService.removeFromFavorites(photo.path, photo.sourceId);
      }

      // 处理删除后的导航
      if (!context.mounted) return;

      // 如果只有一张照片，直接返回
      if (widget.photos.length <= 1) {
        _showSuccessSnackBar(context, context.l10n.photoViewerDeletedSuccess);
        Navigator.of(context).pop();
        return;
      }

      // 显示成功消息
      _showSuccessSnackBar(context, context.l10n.photoViewerDeletedSuccess);

      // 从列表中移除并更新视图
      setState(() {
        widget.photos.removeAt(_currentIndex);
        if (_currentIndex >= widget.photos.length) {
          _currentIndex = widget.photos.length - 1;
        }
      });

      // 重新加载收藏状态
      await _loadFavoriteStatus();
    } on Exception catch (e) {
      logger.e('PhotoViewerPage: 删除照片失败', e);

      // 关闭进度对话框
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (!context.mounted) return;
      _showErrorSnackBar(context, context.l10n.photoViewerDeleteFailed(e));
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isDisabled ? Colors.white38 : Colors.white,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isDisabled ? Colors.white38 : Colors.white,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: 50,
          height: 50,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
}

/// 分享选项瓦片（桌面端分享对话框使用）
class _ShareOptionTile extends StatelessWidget {
  const _ShareOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
}

/// Live Photo 徽章组件
class _LivePhotoBadge extends StatelessWidget {
  const _LivePhotoBadge({
    required this.isPlaying,
    required this.isPreparing,
  });

  final bool isPlaying;
  final bool isPreparing;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 圆形指示器
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isPreparing
                  ? Colors.yellow
                  : (isPlaying ? AppColors.error : Colors.white),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          // LIVE 文字
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
}
