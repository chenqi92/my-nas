import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

/// 自适应图片组件
///
/// 根据 URL 类型自动选择合适的图片加载方式：
/// - file:// 协议：使用 Image.file 加载本地文件
/// - http/https 协议：使用 CachedNetworkImage 加载网络图片
class AdaptiveImage extends StatefulWidget {
  const AdaptiveImage({
    required this.imageUrl, super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.fadeInDuration = const Duration(milliseconds: 300),
  });

  /// 图片 URL（支持 file://、http://、https://）
  final String imageUrl;

  /// 图片填充方式
  final BoxFit fit;

  /// 宽度
  final double? width;

  /// 高度
  final double? height;

  /// 加载中占位组件
  final Widget Function(BuildContext context)? placeholder;

  /// 错误时显示的组件
  final Widget Function(BuildContext context, Object error)? errorWidget;

  /// 淡入动画时长
  final Duration fadeInDuration;

  /// 检查是否是本地文件 URL
  static bool isLocalFile(String url) => url.startsWith('file://');

  /// 检查是否是网络 URL
  static bool isNetworkUrl(String url) => url.startsWith('http://') || url.startsWith('https://');

  /// 检查 URL 是否可以直接加载（支持的协议）
  static bool isSupportedUrl(String url) => isLocalFile(url) || isNetworkUrl(url) || !url.contains('://');

  /// 将 file:// URL 转换为本地文件路径
  static String? toLocalPath(String url) {
    if (!isLocalFile(url)) return null;
    try {
      final uri = Uri.parse(url);
      return uri.toFilePath(windows: Platform.isWindows);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'toLocalPath');
      return null;
    }
  }

  @override
  State<AdaptiveImage> createState() => _AdaptiveImageState();
}

class _AdaptiveImageState extends State<AdaptiveImage> {
  // 缓存文件存在检查结果，避免每次 rebuild 时重新检查导致闪烁
  bool? _fileExistsCache;
  String? _cachedPath;

  @override
  void didUpdateWidget(AdaptiveImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果 URL 变了，清除缓存
    if (oldWidget.imageUrl != widget.imageUrl) {
      _fileExistsCache = null;
      _cachedPath = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 检查是否是不支持的协议（如 smb://）
    if (!AdaptiveImage.isSupportedUrl(widget.imageUrl)) {
      return widget.errorWidget?.call(context, 'Unsupported URL scheme') ??
          _buildDefaultError(context);
    }

    if (AdaptiveImage.isLocalFile(widget.imageUrl)) {
      return _buildLocalImage(context);
    } else if (AdaptiveImage.isNetworkUrl(widget.imageUrl)) {
      return _buildNetworkImage(context);
    } else {
      // 假设是本地路径
      return _buildLocalPathImage(context, widget.imageUrl);
    }
  }

  Widget _buildLocalImage(BuildContext context) {
    final localPath = AdaptiveImage.toLocalPath(widget.imageUrl);
    if (localPath == null) {
      return widget.errorWidget?.call(context, 'Invalid file URL') ??
          _buildDefaultError(context);
    }
    return _buildLocalPathImage(context, localPath);
  }

  Widget _buildLocalPathImage(BuildContext context, String path) {
    // 如果已经缓存了这个路径的检查结果，直接使用
    if (_cachedPath == path && _fileExistsCache != null) {
      return _buildLocalPathImageContent(context, path, _fileExistsCache!);
    }

    final file = File(path);

    return FutureBuilder<bool>(
      future: file.exists(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // 第一次加载时显示占位符
          return widget.placeholder?.call(context) ?? _buildDefaultPlaceholder();
        }

        final exists = snapshot.data ?? false;
        // 缓存结果，避免后续重建时闪烁
        _fileExistsCache = exists;
        _cachedPath = path;

        return _buildLocalPathImageContent(context, path, exists);
      },
    );
  }

  Widget _buildLocalPathImageContent(BuildContext context, String path, bool exists) {
    if (!exists) {
      return widget.errorWidget?.call(context, 'File not found') ??
          _buildDefaultError(context);
    }

    return Image.file(
      File(path),
      key: ValueKey(path),
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      cacheWidth: _decodeCacheWidth(context),
      // 使用 frameBuilder 实现平滑加载，避免闪烁
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return widget.placeholder?.call(context) ?? _buildDefaultPlaceholder();
      },
      errorBuilder: (context, error, stackTrace) =>
          widget.errorWidget?.call(context, error) ?? _buildDefaultError(context),
    );
  }

  Widget _buildNetworkImage(BuildContext context) => CachedNetworkImage(
      imageUrl: widget.imageUrl,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      fadeInDuration: widget.fadeInDuration,
      // 海报墙里的原图常为 1000×1500+，一屏几十张即数百 MB 解码峰值。
      // 按控件逻辑宽 × 像素密度限制解码尺寸，避免移动端 OOM。
      memCacheWidth: _decodeCacheWidth(context),
      placeholder: (context, _) =>
          widget.placeholder?.call(context) ?? _buildDefaultPlaceholder(),
      errorWidget: (context, _, error) =>
          widget.errorWidget?.call(context, error) ?? _buildDefaultError(context),
    );

  /// 按控件宽度 × 设备像素比推导解码宽度上限。
  ///
  /// 未显式指定宽度（`width == null`，如铺满父容器）时返回 null，
  /// 交给原始尺寸解码 —— 此时无法预知实际布局宽，强行截断会糊。
  int? _decodeCacheWidth(BuildContext context) {
    final width = widget.width;
    if (width == null || !width.isFinite || width <= 0) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (width * dpr).round();
  }

  Widget _buildDefaultPlaceholder() => Builder(
      builder: (ctx) => Container(
        width: widget.width,
        height: widget.height,
        color: ctx.placeholderColor,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );

  Widget _buildDefaultError(BuildContext context) => Container(
      width: widget.width,
      height: widget.height,
      color: context.placeholderHighlightColor,
      child: Icon(
        Icons.broken_image_outlined,
        color: context.colorScheme.onSurfaceVariant,
        size: 48,
      ),
    );
}
