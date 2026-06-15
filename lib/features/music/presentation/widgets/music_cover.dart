import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';

/// 把 [MusicItem] 的封面解析为 [ImageProvider]，按「内嵌字节 → file:// 本地 →
/// 网络」三路兼容；无封面返回 null。网络封面走 cached_network_image 磁盘缓存。
///
/// NAS 曲目的 coverUrl 通常是 `file://...` 本地缓存路径，旧实现一律用
/// NetworkImage 会全部加载失败留白，故统一收口到此。
ImageProvider? musicCoverProvider(MusicItem? music) {
  if (music == null) return null;
  final data = music.coverData;
  if (data != null && data.isNotEmpty) {
    return MemoryImage(Uint8List.fromList(data));
  }
  final url = music.coverUrl;
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('file://')) {
    return FileImage(File(url.substring(7)));
  }
  if (url.startsWith('/')) {
    return FileImage(File(url));
  }
  return CachedNetworkImageProvider(url);
}

/// 统一的方形封面：三路兼容 + 失败/缺图回退到音符占位。
class MusicCoverImage extends StatelessWidget {
  const MusicCoverImage({
    required this.music,
    required this.size,
    this.radius = 0,
    this.iconSize,
    super.key,
  });

  final MusicItem? music;
  final double size;
  final double radius;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final provider = musicCoverProvider(music);
    final fallback = Container(
      width: size,
      height: size,
      color: t.insetBg,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        size: iconSize ?? size * 0.4,
        color: t.text3,
      ),
    );
    final child = provider == null
        ? fallback
        : Image(
            image: provider,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => fallback,
          );
    return radius > 0
        ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: child)
        : child;
  }
}
