import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/services/performance_mode_service.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/smb/smb_pool_config.dart';
import 'package:photo_view/photo_view.dart';

/// 支持流式加载的图片组件
///
/// 优先使用 HTTP URL，如果 URL 无效则通过流加载图片数据
///
/// 注意：在 iOS 平台上，对于 HTTPS URL（可能使用自签名证书），
/// 会自动降级到流式加载以避免证书验证问题。
class StreamImage extends StatefulWidget {
  const StreamImage({
    super.key,
    this.url,
    this.path,
    this.fileSystem,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
    this.cacheKey,
    this.forceStream = false,
    this.enableZoom = false,
    this.minScale,
    this.maxScale,
    this.initialScale,
    this.backgroundColor,
    this.preferFullQuality = false,
  });

  /// HTTP URL（如果可用）
  final String? url;

  /// 文件路径（用于流式加载）
  final String? path;

  /// 文件系统（用于流式加载）
  final NasFileSystem? fileSystem;

  /// 图片填充模式
  final BoxFit fit;

  /// 图片对齐方式
  final Alignment alignment;

  /// 加载中占位符
  final Widget? placeholder;

  /// 错误时显示的组件
  final Widget? errorWidget;

  /// 宽度
  final double? width;

  /// 高度
  final double? height;

  /// 缓存键
  final String? cacheKey;

  /// 强制使用流式加载（即使有有效的 HTTP URL）
  /// 用于解决自签名证书等问题
  final bool forceStream;

  /// 是否启用缩放功能（使用 PhotoView）
  final bool enableZoom;

  /// 最小缩放比例（仅在 enableZoom 为 true 时有效）
  final PhotoViewComputedScale? minScale;

  /// 最大缩放比例（仅在 enableZoom 为 true 时有效）
  final PhotoViewComputedScale? maxScale;

  /// 初始缩放比例（仅在 enableZoom 为 true 时有效）
  final PhotoViewComputedScale? initialScale;

  /// 背景颜色（仅在 enableZoom 为 true 时有效）
  final Color? backgroundColor;

  /// 是否优先加载原图（跳过缩略图）
  ///
  /// 用于照片预览等需要高质量显示的场景
  /// 当为 true 时，加载策略变为：
  /// 1. 如果有 URL → 通过 URL 流加载
  /// 2. 否则 → 通过 getFileStream 加载原文件
  /// 跳过 getThumbnailData 缩略图
  final bool preferFullQuality;

  // 内存缓存（LRU 策略）
  static final Map<String, Uint8List> _memoryCache = {};
  // 最多缓存 200 张图片（海报通常 50-100KB，总共约 10-20MB）
  static const int _maxCacheSize = 200;

  // 并发加载控制
  static int _activeLoads = 0;

  /// 最大并发加载数（动态计算，支持性能模式）
  ///
  /// 普通模式：6
  /// 性能模式：桌面 16，移动 10
  static int get _maxConcurrentLoads {
    if (PerformanceModeService.isPerformanceMode) {
      return SmbPoolConfig.isDesktop ? 16 : 10;
    }
    return 6;
  }

  static final List<Future<void> Function()> _loadQueue = [];

  /// 清除所有内存缓存
  static void clearCache() {
    _memoryCache.clear();
  }

  /// 处理加载队列
  static void _processQueue() {
    while (_activeLoads < _maxConcurrentLoads && _loadQueue.isNotEmpty) {
      final loader = _loadQueue.removeAt(0);
      _activeLoads++;
      loader().whenComplete(() {
        _activeLoads--;
        _processQueue();
      });
    }
  }

  @override
  State<StreamImage> createState() => _StreamImageState();
}

class _StreamImageState extends State<StreamImage> {
  Uint8List? _imageBytes;
  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(StreamImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.path != widget.path) {
      _loadImage();
    }
  }

  String get _cacheKey => widget.cacheKey ?? widget.path ?? widget.url ?? '';

  bool get _hasValidHttpUrl {
    final url = widget.url;
    if (url == null || url.isEmpty) return false;
    // 检查是否是有效的 HTTP/HTTPS URL
    return url.startsWith('http://') || url.startsWith('https://');
  }

  bool get _hasValidFileUrl {
    final url = widget.url;
    if (url == null || url.isEmpty) return false;
    // 检查是否是有效的 file:// URL
    return url.startsWith('file://');
  }

  /// 检查是否应该使用流式加载
  ///
  /// 在以下情况下使用流式加载：
  /// 1. forceStream = true（强制流式加载）
  /// 2. iOS 平台有 HTTP/HTTPS URL（避免自签名证书和其他兼容性问题）
  /// 3. iOS/macOS 平台 + file:// URL（沙盒限制）
  ///
  /// 注意：iOS 上的 CachedNetworkImage 可能存在以下问题：
  /// - 自签名证书不被接受
  /// - 某些 NAS 的 HTTP 响应格式可能不兼容
  /// - 网络超时处理不一致
  /// 因此，对于 NAS 图片，统一使用流式加载以确保兼容性
  bool get _shouldUseStream {
    // 如果没有提供 fileSystem 和 path，无法使用流式加载
    if (widget.fileSystem == null || widget.path == null) return false;

    // 强制流式加载
    if (widget.forceStream) return true;

    // iOS 平台特殊处理：对于 NAS 的 HTTP/HTTPS URL，优先使用流式加载
    // 这样可以利用 Dio 的自签名证书支持和更好的错误处理
    if (Platform.isIOS) {
      if (_hasValidHttpUrl || _hasValidFileUrl) {
        return true;
      }
    }

    // macOS 平台对 HTTPS 自签名证书也有问题
    if (Platform.isMacOS) {
      if (_hasValidHttpUrl && widget.url!.startsWith('https://')) {
        return true;
      }
      if (_hasValidFileUrl) {
        return true;
      }
    }

    return false;
  }

  /// 在iOS/macOS平台上，file:// URL应该使用流式加载
  /// 因为沙盒限制可能导致直接文件访问失败
  bool get _shouldUseStreamForFileUrl {
    if (!_hasValidFileUrl) return false;
    // 如果没有提供 fileSystem 和 path，无法使用流式加载
    if (widget.fileSystem == null || widget.path == null) return false;
    // iOS/macOS 平台优先使用流式加载
    return Platform.isIOS || Platform.isMacOS;
  }

  /// 从 file:// URL 获取本地文件路径
  String? get _localFilePath {
    final url = widget.url;
    if (url == null || !url.startsWith('file://')) return null;
    try {
      final uri = Uri.parse(url);
      return uri.toFilePath();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '无效的 file:// URL: $url');
      return null;
    }
  }

  Future<void> _loadImage() async {
    // 检查是否应该使用流式加载（iOS/macOS 自签名证书、file:// URL、forceStream）
    if (_shouldUseStream) {
      await _loadImageViaStream();
      return;
    }

    // 如果有有效的 HTTP URL，使用 CachedNetworkImage
    if (_hasValidHttpUrl) {
      setState(() {
        _imageBytes = null;
        _hasError = false;
      });
      return;
    }

    // 如果有有效的 file:// URL，在非iOS/macOS平台使用 Image.file
    // 在iOS/macOS平台，由于沙盒限制，优先使用流式加载
    if (_hasValidFileUrl && !_shouldUseStreamForFileUrl) {
      setState(() {
        _imageBytes = null;
        _hasError = false;
      });
      return;
    }

    // 需要通过流加载
    await _loadImageViaStream();
  }

  /// 通过流式加载图片
  ///
  /// 加载策略：
  /// 1. 优先使用 getThumbnailData（本地相册缩略图，最快）
  /// 2. 如果有 URL，通过 getUrlStream 加载
  /// 3. 最后通过 getFileStream 加载原文件（最慢）
  Future<void> _loadImageViaStream() async {
    // 检查内存缓存
    if (_cacheKey.isNotEmpty && StreamImage._memoryCache.containsKey(_cacheKey)) {
      setState(() {
        _imageBytes = StreamImage._memoryCache[_cacheKey];
        _isLoading = false;
        _hasError = false;
      });
      return;
    }

    // 需要通过流加载
    if (widget.fileSystem == null) {
      setState(() {
        _hasError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    // 使用队列控制并发加载
    Future<void> doLoad() async {
      try {
        Uint8List? imageData;

        // 如果 preferFullQuality = true，跳过缩略图，直接加载原图
        if (!widget.preferFullQuality) {
          // 1. 优先使用 getThumbnailData（本地相册缩略图，最快）
          if (widget.path != null) {
            try {
              imageData = await widget.fileSystem!.getThumbnailData(widget.path!);
            } on Exception {
              // ignore - 继续尝试其他方式
            }
          }
        }

        // 2. 尝试 URL 流（优先，因为可能有更好的缓存和压缩）
        if (imageData == null && _hasValidHttpUrl) {
          try {
            final stream = await widget.fileSystem!.getUrlStream(widget.url!);
            final bytes = <int>[];
            await for (final chunk in stream) {
              bytes.addAll(chunk);
              if (bytes.length > 50 * 1024 * 1024) {
                throw Exception(appL10n.streamImageFileTooLarge);
              }
            }
            imageData = Uint8List.fromList(bytes);
          } on Exception catch (e, st) {
            AppError.ignore(e, st, 'URL stream 失败，降级到 file stream');
          }
        }

        // 3. 最后使用文件流（加载完整原文件）
        if (imageData == null) {
          if (widget.path == null) {
            throw Exception(appL10n.streamImageNoValidSource);
          }
          final stream = await widget.fileSystem!.getFileStream(widget.path!);
          final bytes = <int>[];
          await for (final chunk in stream) {
            bytes.addAll(chunk);
            if (bytes.length > 50 * 1024 * 1024) {
              throw Exception(appL10n.streamImageFileTooLarge);
            }
          }
          imageData = Uint8List.fromList(bytes);
        }

        // 添加到缓存
        if (_cacheKey.isNotEmpty) {
          // 如果缓存满了，清除一半
          if (StreamImage._memoryCache.length >= StreamImage._maxCacheSize) {
            final keysToRemove = StreamImage._memoryCache.keys
                .take(StreamImage._maxCacheSize ~/ 2)
                .toList();
            for (final key in keysToRemove) {
              StreamImage._memoryCache.remove(key);
            }
          }
          StreamImage._memoryCache[_cacheKey] = imageData;
        }

        if (mounted) {
          setState(() {
            _imageBytes = imageData;
            _isLoading = false;
          });
        }
      } on Exception catch (e, st) {
        AppError.ignore(e, st, 'loadImageViaStream');
        if (mounted) {
          setState(() {
            _hasError = true;
            _isLoading = false;
          });
        }
      }
    }

    // 添加到加载队列
    StreamImage._loadQueue.add(doLoad);
    StreamImage._processQueue();
  }

  @override
  Widget build(BuildContext context) {
    // 如果使用流式加载（iOS/macOS HTTPS、file:// URL、forceStream）
    if (_shouldUseStream) {
      return _buildStreamImage();
    }

    // 优先使用 HTTP URL（非 iOS/macOS HTTPS 或无 fileSystem）
    if (_hasValidHttpUrl) {
      return CachedNetworkImage(
        imageUrl: widget.url!,
        fit: widget.fit,
        alignment: widget.alignment,
        width: widget.width,
        height: widget.height,
        placeholder: (_, _) => widget.placeholder ?? _buildPlaceholder(),
        errorWidget: (_, _, _) => widget.errorWidget ?? _buildError(),
      );
    }

    // 使用本地文件 (file:// URL)
    // 在iOS/macOS上，如果有fileSystem和path，会fallback到流式加载
    if (_hasValidFileUrl && !_shouldUseStreamForFileUrl) {
      final filePath = _localFilePath;
      if (filePath != null) {
        return Image.file(
          File(filePath),
          fit: widget.fit,
          alignment: widget.alignment,
          width: widget.width,
          height: widget.height,
          errorBuilder: (_, _, _) => widget.errorWidget ?? _buildError(),
        );
      }
    }

    // 默认使用流式加载
    return _buildStreamImage();
  }

  /// 构建流式加载的图片组件
  Widget _buildStreamImage() {
    // 显示加载中
    if (_isLoading) {
      return widget.placeholder ?? _buildPlaceholder();
    }

    // 显示错误
    if (_hasError || _imageBytes == null) {
      return widget.errorWidget ?? _buildError();
    }

    // 如果启用缩放，使用 PhotoView
    if (widget.enableZoom) {
      return PhotoView(
        imageProvider: MemoryImage(_imageBytes!),
        minScale: widget.minScale ?? PhotoViewComputedScale.contained,
        maxScale: widget.maxScale ?? PhotoViewComputedScale.covered * 3,
        initialScale: widget.initialScale ?? PhotoViewComputedScale.contained,
        backgroundDecoration: BoxDecoration(
          color: widget.backgroundColor ?? Colors.black,
        ),
        loadingBuilder: (context, event) => widget.placeholder ?? _buildPlaceholder(),
        errorBuilder: (context, error, stackTrace) => widget.errorWidget ?? _buildError(),
      );
    }

    // 显示流式加载的图片
    return Image.memory(
      _imageBytes!,
      fit: widget.fit,
      alignment: widget.alignment,
      width: widget.width,
      height: widget.height,
      errorBuilder: (_, _, _) => widget.errorWidget ?? _buildError(),
    );
  }

  Widget _buildPlaceholder() => Builder(
    builder: (context) => Container(
      width: widget.width,
      height: widget.height,
      color: context.placeholderColor,
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ),
  );

  Widget _buildError() => Builder(
    builder: (context) => Container(
      width: widget.width,
      height: widget.height,
      color: context.placeholderHighlightColor,
      child: Icon(
        Icons.broken_image_rounded,
        color: context.colorScheme.onSurfaceVariant,
        size: 32,
      ),
    ),
  );
}

/// 带缩略图的流式图片组件
///
/// 先显示缩略图，然后加载原图
class StreamImageWithThumbnail extends StatelessWidget {
  const StreamImageWithThumbnail({
    super.key,
    this.thumbnailUrl,
    this.fullUrl,
    this.path,
    this.fileSystem,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
  });

  final String? thumbnailUrl;
  final String? fullUrl;
  final String? path;
  final NasFileSystem? fileSystem;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) => StreamImage(
      url: thumbnailUrl ?? fullUrl,
      path: path,
      fileSystem: fileSystem,
      fit: fit,
      placeholder: placeholder,
      errorWidget: errorWidget,
      width: width,
      height: height,
      cacheKey: path,
    );
}
