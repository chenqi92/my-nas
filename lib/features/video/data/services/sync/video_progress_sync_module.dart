import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/sync/syncable_module.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';

/// 同步视频播放进度 + 已观看标记 + 播放历史。
///
/// 数据来自三个 Hive box：
/// - `video_progress`：每个 video 的播放位置 / 时长 / updatedAt
/// - `video_watched`：每个已观看 video 的 ISO8601 时间戳
/// - `video_history`：在 'list' key 下的有序历史列表（最多 100）
///
/// 每条同步记录按 videoPath 主键聚合所有相关字段，导入时按字段时间戳分别 last-wins。
///
/// 合并策略：
/// - progress：按 progressUpdatedAt 取新
/// - watchedAt：取新；远端为空时不会清除本地已完成标记（满足"completed=true 不被未完成覆盖"）
/// - history 元数据：按 historyAddedAt 取新
class VideoProgressSyncModule implements SyncableModule {
  VideoProgressSyncModule();

  final VideoHistoryService _service = VideoHistoryService();

  static const int _historyCap = 100;

  @override
  String get key => 'video_progress';

  @override
  String get displayName => '视频 - 播放进度与历史';

  @override
  Future<DateTime?> getLocalUpdatedAt() async {
    await _service.init();

    DateTime? maxAt;
    void bump(DateTime? at) {
      if (at == null) return;
      if (maxAt == null || at.isAfter(maxAt!)) maxAt = at;
    }

    final progressMap = await _service.getAllProgress();
    for (final p in progressMap.values) {
      bump(p.updatedAt);
    }

    final watchedBox = await _openWatchedBox();
    for (final key in watchedBox.keys) {
      final raw = watchedBox.get(key);
      bump(_tryParseDate(raw));
    }

    final history = await _service.getHistory(limit: 1000);
    for (final h in history) {
      bump(h.watchedAt);
    }

    return maxAt;
  }

  @override
  Future<Map<String, dynamic>> exportData() async {
    await _service.init();

    final progressMap = await _service.getAllProgress();
    final history = await _service.getHistory(limit: 1000);
    final historyByPath = {for (final h in history) h.videoPath: h};

    final watchedBox = await _openWatchedBox();
    final watchedMap = <String, DateTime>{};
    for (final key in watchedBox.keys) {
      if (key is! String) continue;
      final at = _tryParseDate(watchedBox.get(key));
      if (at != null) watchedMap[key] = at;
    }

    final paths = <String>{
      ...progressMap.keys,
      ...historyByPath.keys,
      ...watchedMap.keys,
    };

    final items = <Map<String, dynamic>>[];
    for (final path in paths) {
      final p = progressMap[path];
      final h = historyByPath[path];
      final w = watchedMap[path];

      final record = <String, dynamic>{'videoPath': path};

      if (p != null) {
        record['positionMs'] = p.position.inMilliseconds;
        record['durationMs'] = p.duration.inMilliseconds;
        record['progressUpdatedAt'] = p.updatedAt.toIso8601String();
      }
      if (w != null) {
        record['watchedAt'] = w.toIso8601String();
      }
      if (h != null) {
        record['videoName'] = h.videoName;
        record['videoUrl'] = h.videoUrl;
        if (h.sourceId != null) record['sourceId'] = h.sourceId;
        if (h.thumbnailUrl != null) record['thumbnailUrl'] = h.thumbnailUrl;
        record['size'] = h.size;
        record['historyAddedAt'] = h.watchedAt.toIso8601String();
        if (h.lastPosition != null) {
          record['historyLastPositionMs'] = h.lastPosition!.inMilliseconds;
        }
        if (h.duration != null) {
          record['historyDurationMs'] = h.duration!.inMilliseconds;
        }
      }

      items.add(record);
    }

    return {
      'version': 1,
      'items': items,
    };
  }

  @override
  Future<void> importData(Map<String, dynamic> data) async {
    await _service.init();

    final items = (data['items'] as List?) ?? const [];
    if (items.isEmpty) return;

    final progressBox = await _openProgressBox();
    final watchedBox = await _openWatchedBox();
    final historyBox = await _openHistoryBox();

    final localHistory = <String, VideoHistoryItem>{};
    final historyListRaw = historyBox.get('list');
    if (historyListRaw is List) {
      for (final raw in historyListRaw) {
        if (raw is Map) {
          try {
            final item = VideoHistoryItem.fromJson(raw);
            localHistory[item.videoPath] = item;
          } on Exception catch (_) {
            continue;
          }
        }
      }
    }

    for (final raw in items) {
      if (raw is! Map) continue;
      try {
        final path = raw['videoPath'] as String?;
        if (path == null || path.isEmpty) continue;

        // 1. 进度合并
        final remoteProgressAt = _tryParseDate(raw['progressUpdatedAt']);
        final positionMs = raw['positionMs'];
        final durationMs = raw['durationMs'];
        if (remoteProgressAt != null &&
            positionMs is int &&
            durationMs is int) {
          final existing = progressBox.get(path);
          DateTime? localAt;
          if (existing is Map) {
            localAt = _tryParseDate(existing['updatedAt']);
          }
          if (localAt == null || remoteProgressAt.isAfter(localAt)) {
            await progressBox.put(path, {
              'videoPath': path,
              'positionMs': positionMs,
              'durationMs': durationMs,
              'updatedAt': remoteProgressAt.toIso8601String(),
            });
          }
        }

        // 2. 观看标记合并 —— 远端为 null 时不清空本地（已完成不被未完成覆盖）
        final remoteWatchedAt = _tryParseDate(raw['watchedAt']);
        if (remoteWatchedAt != null) {
          final localWatchedAt = _tryParseDate(watchedBox.get(path));
          if (localWatchedAt == null || remoteWatchedAt.isAfter(localWatchedAt)) {
            await watchedBox.put(path, remoteWatchedAt.toIso8601String());
          }
        }

        // 3. 历史元数据合并
        final remoteHistoryAt = _tryParseDate(raw['historyAddedAt']);
        final videoName = raw['videoName'];
        final videoUrl = raw['videoUrl'];
        if (remoteHistoryAt != null &&
            videoName is String &&
            videoUrl is String) {
          final existing = localHistory[path];
          if (existing == null || remoteHistoryAt.isAfter(existing.watchedAt)) {
            final lastPositionMs = raw['historyLastPositionMs'];
            final historyDurationMs = raw['historyDurationMs'];
            localHistory[path] = VideoHistoryItem(
              videoPath: path,
              videoName: videoName,
              videoUrl: videoUrl,
              sourceId: raw['sourceId'] as String?,
              thumbnailUrl: raw['thumbnailUrl'] as String?,
              size: raw['size'] is int ? raw['size'] as int : 0,
              lastPosition: lastPositionMs is int
                  ? Duration(milliseconds: lastPositionMs)
                  : null,
              duration: historyDurationMs is int
                  ? Duration(milliseconds: historyDurationMs)
                  : null,
              watchedAt: remoteHistoryAt,
            );
          }
        }
      } on Exception catch (_) {
        continue;
      }
    }

    final merged = localHistory.values.toList()
      ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    if (merged.length > _historyCap) {
      merged.removeRange(_historyCap, merged.length);
    }
    await historyBox.put('list', merged.map((h) => h.toJson()).toList());
  }

  Future<Box<dynamic>> _openProgressBox() => _open('video_progress');
  Future<Box<dynamic>> _openWatchedBox() => _open('video_watched');
  Future<Box<dynamic>> _openHistoryBox() => _open('video_history');

  Future<Box<dynamic>> _open(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box<dynamic>(name);
    return Hive.openBox<dynamic>(name);
  }

  DateTime? _tryParseDate(Object? raw) {
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }
}
