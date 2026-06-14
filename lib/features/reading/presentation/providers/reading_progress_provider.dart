import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';

/// 阅读进度映射：`itemId`（`${sourceId}_$path`）→ 进度 0..1。
///
/// 供阅读列表/聚合页给封面填充进度条。仅保留有实际进度（>0）的项。
/// 从阅读器返回后由页面 `ref.invalidate` 刷新。
final readingProgressMapProvider =
    FutureProvider<Map<String, double>>((ref) async {
  final service = ReadingProgressService();
  await service.init();
  return {
    for (final p in service.getAllProgress())
      if (p.progressPercent > 0) p.itemId: p.progressPercent,
  };
});
