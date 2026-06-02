import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/book/data/services/book_database_service.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';

/// 各媒体库的轻量计数（仅 `COUNT(*)`，不触发整库加载），用于桌面 sidebar
/// 的数量角标。任何异常都降级为 0，角标 = 0 时由 UI 决定不显示。
final _videoCountProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    return await VideoDatabaseService().getCount();
  } on Object {
    return 0;
  }
});

final _musicCountProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    return await MusicDatabaseService().getCount();
  } on Object {
    return 0;
  }
});

final _photoCountProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    return await PhotoDatabaseService().getCount();
  } on Object {
    return 0;
  }
});

final _bookCountProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    return await BookDatabaseService().getCount();
  } on Object {
    return 0;
  }
});

class MediaCounts {
  const MediaCounts({
    this.video = 0,
    this.music = 0,
    this.photo = 0,
    this.reading = 0,
  });

  final int video;
  final int music;
  final int photo;
  final int reading;
}

/// 聚合各库计数，供 sidebar 一次性 watch。
final mediaCountsProvider = Provider.autoDispose<MediaCounts>(
  (ref) => MediaCounts(
    video: ref.watch(_videoCountProvider).valueOrNull ?? 0,
    music: ref.watch(_musicCountProvider).valueOrNull ?? 0,
    photo: ref.watch(_photoCountProvider).valueOrNull ?? 0,
    reading: ref.watch(_bookCountProvider).valueOrNull ?? 0,
  ),
);

/// 248 → "248"，1234 → "1.2k"，0 → null（不显示角标）。
String? formatCountBadge(int count) {
  if (count <= 0) return null;
  if (count < 1000) return '$count';
  final k = count / 1000;
  return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k';
}
