import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/sync/syncable_module.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';

/// 同步阅读进度（图书/漫画/PDF/EPUB/笔记 共用一份）。
///
/// 策略：
/// - exportData = 全部 ReadingProgress 快照
/// - importData = 按 itemId 主键 last-readAt-wins 合并
/// - localUpdatedAt = max(lastReadAt)
class ReadingProgressSyncModule implements SyncableModule {
  ReadingProgressSyncModule();

  final ReadingProgressService _service = ReadingProgressService();

  @override
  String get key => 'reading_progress';

  @override
  String get displayName => appL10n.syncModuleReadingProgress;

  @override
  SyncMergePolicy get mergePolicy => SyncMergePolicy.recordMerge;

  @override
  Future<DateTime?> getLocalUpdatedAt() async {
    await _service.init();
    final list = _service.getAllProgress().toList()
      ..sort((a, b) => a.itemId.compareTo(b.itemId));
    DateTime? maxAt;
    for (final p in list) {
      final ts = p.lastReadAt;
      if (ts == null) continue;
      if (maxAt == null || ts.isAfter(maxAt)) maxAt = ts;
    }
    return maxAt;
  }

  @override
  Future<Map<String, dynamic>> exportData() async {
    await _service.init();
    final list = _service.getAllProgress();
    return {'version': 1, 'progress': list.map((p) => p.toMap()).toList()};
  }

  @override
  Future<void> importData(
    Map<String, dynamic> data, {
    DateTime? remoteUpdatedAt,
  }) async {
    await _service.init();
    final list = data['progress'];
    if (list is! List) {
      throw const FormatException('reading_progress.progress 必须是数组');
    }
    for (final raw in list) {
      if (raw is! Map) continue;
      try {
        final remote = ReadingProgress.fromMap(raw);
        final local = _service.getProgress(remote.itemId);
        if (local == null) {
          await _service.saveProgress(remote);
          continue;
        }
        // last-readAt-wins
        final remoteAt = remote.lastReadAt;
        final localAt = local.lastReadAt;
        if (remoteAt == null) continue;
        if (localAt == null || remoteAt.isAfter(localAt)) {
          await _service.saveProgress(remote);
        }
      } on Object catch (e, st) {
        AppError.ignore(e, st, '远端 reading_progress 单条记录解析失败，跳过该条');
        continue;
      }
    }
  }
}
