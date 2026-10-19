import 'package:flutter/material.dart';
import 'package:my_nas/core/services/nas_file_system_registry.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

/// 视频海报组件
///
/// 智能检测 URL 类型并选择合适的加载方式：
/// - `http://` 或 `https://` → CachedNetworkImage
/// - NAS 路径（以 `/` 开头）→ StreamImage（自动从 Registry 获取 fileSystem）
/// - `file://` 或本机绝对路径 → AdaptiveImage
class VideoPoster extends StatelessWidget {
  const VideoPoster({
    required this.posterUrl,
    super.key,
    this.sourceId,
    this.fallbackUrls = const [],
    this.fileSystem,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
  });

  /// 海报 URL 或路径
  final String? posterUrl;
  final List<String> fallbackUrls;

  /// 源 ID（用于从 Registry 获取 fileSystem）
  final String? sourceId;

  /// NAS 文件系统（可选，如不提供则从 Registry 获取）
  final NasFileSystem? fileSystem;

  /// 填充方式
  final BoxFit fit;

  /// 图片在裁剪区域内的对齐方式。
  final Alignment alignment;

  /// 宽度
  final double? width;

  /// 高度
  final double? height;

  /// 加载占位组件
  final Widget? placeholder;

  /// 错误占位组件
  final Widget? errorWidget;

  /// 圆角
  final BorderRadius? borderRadius;

  /// 检查是否是网络 URL
  static bool isNetworkUrl(String? url) =>
      url != null && (url.startsWith('http://') || url.startsWith('https://'));

  /// 检查是否是 NAS 路径（需要流式加载）
  static bool isNasPath(String? url) =>
      url != null &&
      url.startsWith('/') &&
      !url.startsWith('//') && // 排除网络路径
      !url.contains('://'); // 排除任何协议

  /// 获取可用的 fileSystem（优先使用传入的，否则从 Registry 获取）
  NasFileSystem? get _effectiveFileSystem {
    if (fileSystem != null) return fileSystem;
    return NasFileSystemRegistry.instance.get(sourceId);
  }

  @override
  Widget build(BuildContext context) {
    if (posterUrl == null || posterUrl!.isEmpty) {
      return _buildPlaceholder(context);
    }

    final urls = {
      posterUrl!,
      ...fallbackUrls,
    }.where((url) => url.isNotEmpty).toList();
    final fs = _effectiveFileSystem;
    Widget imageAt(int index) {
      if (index >= urls.length) return _buildError(context);
      final url = urls[index];
      final fallback = Builder(builder: (_) => imageAt(index + 1));
      if (isNasPath(url) && fs != null) {
        return StreamImage(
          key: ValueKey('${sourceId ?? ''}:$url'),
          cacheKey: '${sourceId ?? identityHashCode(fs)}:$url',
          path: url,
          fileSystem: fs,
          fit: fit,
          alignment: alignment,
          width: width,
          height: height,
          placeholder: _buildPlaceholder(context),
          errorWidget: fallback,
        );
      }
      return AdaptiveImage(
        imageUrl: url,
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        placeholder: (_) => _buildPlaceholder(context),
        errorWidget: (_, _) => fallback,
      );
    }

    final imageWidget = imageAt(0);

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: imageWidget);
    }

    return imageWidget;
  }

  Widget _buildPlaceholder(BuildContext context) =>
      placeholder ??
      Container(
        width: width,
        height: height,
        color: Colors.grey[800],
        child: const Center(
          child: Icon(Icons.movie_outlined, color: Colors.grey, size: 40),
        ),
      );

  Widget _buildError(BuildContext context) =>
      errorWidget ??
      Container(
        width: width,
        height: height,
        color: Colors.grey[900],
        child: const Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.grey,
            size: 40,
          ),
        ),
      );
}
