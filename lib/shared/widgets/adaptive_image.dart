import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/local_file_uri.dart';

/// 自适应图片组件
///
/// 根据 URL 类型自动选择合适的图片加载方式：
/// - file:// 协议：使用 Image.file 加载本地文件
/// - http/https 协议：使用 CachedNetworkImage 加载网络图片
class AdaptiveImage extends StatefulWidget {
  const AdaptiveImage({
    required this.imageUrl,
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
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

  /// 图片在裁剪区域内的对齐方式。
  final Alignment alignment;

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
  static bool isNetworkUrl(String url) =>
      url.startsWith('http://') || url.startsWith('https://');

  /// 检查 URL 是否可以直接加载（支持的协议）
  static bool isSupportedUrl(String url) =>
      isLocalFile(url) || isNetworkUrl(url) || !url.contains('://');

  /// 将 file:// URL 转换为本地文件路径
  static String? toLocalPath(String url) {
    if (!isLocalFile(url)) return null;
    return localPathFromFileUri(url);
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cacheWidth = _decodeCacheWidth(context, constraints);
      // 检查是否是不支持的协议（如 smb://）
      if (!AdaptiveImage.isSupportedUrl(widget.imageUrl)) {
        return widget.errorWidget?.call(context, 'Unsupported URL scheme') ??
            _buildDefaultError(context);
      }

      if (AdaptiveImage.isLocalFile(widget.imageUrl)) {
        return _buildLocalImage(context, cacheWidth);
      }
      if (AdaptiveImage.isNetworkUrl(widget.imageUrl)) {
        return _buildNetworkImage(context, cacheWidth);
      }
      // 假设是本地路径
      return _buildLocalPathImage(context, widget.imageUrl, cacheWidth);
    },
  );

  Widget _buildLocalImage(BuildContext context, int? cacheWidth) {
    final localPath = AdaptiveImage.toLocalPath(widget.imageUrl);
    if (localPath == null) {
      return widget.errorWidget?.call(context, 'Invalid file URL') ??
          _buildDefaultError(context);
    }
    return _buildLocalPathImage(context, localPath, cacheWidth);
  }

  Widget _buildLocalPathImage(
    BuildContext context,
    String path,
    int? cacheWidth,
  ) {
    // 如果已经缓存了这个路径的检查结果，直接使用
    if (_cachedPath == path && _fileExistsCache != null) {
      return _buildLocalPathImageContent(
        context,
        path,
        _fileExistsCache!,
        cacheWidth,
      );
    }

    final file = File(path);

    return FutureBuilder<bool>(
      future: file.exists(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // 第一次加载时显示占位符
          return widget.placeholder?.call(context) ??
              _buildDefaultPlaceholder();
        }

        final exists = snapshot.data ?? false;
        // 缓存结果，避免后续重建时闪烁
        _fileExistsCache = exists;
        _cachedPath = path;

        return _buildLocalPathImageContent(context, path, exists, cacheWidth);
      },
    );
  }

  Widget _buildLocalPathImageContent(
    BuildContext context,
    String path,
    bool exists,
    int? cacheWidth,
  ) {
    if (!exists) {
      return widget.errorWidget?.call(context, 'File not found') ??
          _buildDefaultError(context);
    }

    return Image.file(
      File(path),
      key: ValueKey(path),
      fit: widget.fit,
      alignment: widget.alignment,
      width: widget.width,
      height: widget.height,
      cacheWidth: cacheWidth,
      // 使用 frameBuilder 实现平滑加载，避免闪烁
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return widget.placeholder?.call(context) ?? _buildDefaultPlaceholder();
      },
      errorBuilder: (context, error, stackTrace) =>
          widget.errorWidget?.call(context, error) ??
          _buildDefaultError(context),
    );
  }

  Widget _buildNetworkImage(BuildContext context, int? cacheWidth) =>
      CachedNetworkImage(
        imageUrl: widget.imageUrl,
        fit: widget.fit,
        alignment: widget.alignment,
        width: widget.width,
        height: widget.height,
        fadeInDuration: widget.fadeInDuration,
        // 海报墙里的原图常为 1000×1500+，一屏几十张即数百 MB 解码峰值。
        // 按控件逻辑宽 × 像素密度限制解码尺寸，避免移动端 OOM。
        memCacheWidth: cacheWidth,
        placeholder: (context, _) =>
            widget.placeholder?.call(context) ?? _buildDefaultPlaceholder(),
        errorWidget: (context, _, error) =>
            widget.errorWidget?.call(context, error) ??
            _buildDefaultError(context),
      );

  /// 按控件宽度 × 设备像素比推导解码宽度上限。
  ///
  /// 未显式指定宽度时使用父布局的有限约束；只有两者都未知时才返回 null。
  int? _decodeCacheWidth(BuildContext context, BoxConstraints constraints) {
    final explicitWidth = widget.width;
    final width = explicitWidth != null && explicitWidth.isFinite
        ? explicitWidth
        : constraints.hasBoundedWidth
        ? constraints.maxWidth
        : null;
    if (width == null || width <= 0) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (width * dpr).round();
  }

  Widget _buildDefaultPlaceholder() => Builder(
    builder: (ctx) => Container(
      width: widget.width,
      height: widget.height,
      color: ctx.placeholderColor,
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
