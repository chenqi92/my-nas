import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/theme/dynamic_accent_service.dart';
import 'package:my_nas/core/utils/local_file_uri.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';

/// 当前播放歌曲的动态主题色。封面变化时异步重算，无封面时退回 [DynamicAccent.fallback]。
final musicDynamicAccentProvider = FutureProvider<DynamicAccent>((ref) async {
  final music = ref.watch(currentMusicProvider);
  if (music == null) return DynamicAccent.fallback;

  // 优先：内嵌封面字节
  final coverData = music.coverData;
  if (coverData != null && coverData.isNotEmpty) {
    return DynamicAccentService.instance.fromCoverBytes(
      Uint8List.fromList(coverData),
      cacheKey: '${music.sourceId ?? ''}|${music.path}|bytes',
    );
  }

  // 次之：file:// URL（本地缓存命中）
  final coverUrl = music.coverUrl;
  if (coverUrl != null && coverUrl.startsWith('file://')) {
    final path = localPathFromFileUri(coverUrl);
    if (path != null && await File(path).exists()) {
      return DynamicAccentService.instance.fromCoverFile(
        path,
        cacheKey: '${music.sourceId ?? ''}|$path',
      );
    }
  }

  return DynamicAccent.fallback;
});

/// 同步访问 — 给不需要等待的 UI 用（背景渐变首次为 fallback，加载完成后切换）
final musicDynamicAccentValueProvider = Provider<DynamicAccent>((ref) {
  final async = ref.watch(musicDynamicAccentProvider);
  return async.maybeWhen(data: (v) => v, orElse: () => DynamicAccent.fallback);
});
