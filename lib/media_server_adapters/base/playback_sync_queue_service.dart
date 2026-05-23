import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/media_server_adapters/base/media_server_entities.dart';
import 'package:sqflite/sqflite.dart';

/// 同步事件类型
enum SyncEventType {
  playbackStart,
  playbackProgress,
  playbackStop,
  markWatched,
  markUnwatched,
}

/// 同步状态
enum SyncStatus {
  pending,
  syncing,
  synced,
  failed,
}

/// 播放同步队列条目
class PlaybackSyncEntry {
  const PlaybackSyncEntry({
    this.id,
    required this.sourceId,
    required this.itemId,
    required this.positionTicks,
    required this.isWatched,
    required this.eventType,
    required this.syncStatus,
    this.retryCount = 0,
    required this.createdAt,
    this.syncedAt,
    this.errorMessage,
  });

  factory PlaybackSyncEntry.fromMap(Map<String, dynamic> map) => PlaybackSyncEntry(
      id: map['id'] as int?,
      sourceId: map['source_id'] as String,
      itemId: map['item_id'] as String,
      positionTicks: map['position_ticks'] as int,
      isWatched: (map['is_watched'] as int) == 1,
      eventType: SyncEventType.values.firstWhere(
        (e) => e.name == map['event_type'],
        orElse: () => SyncEventType.playbackProgress,
      ),
      syncStatus: SyncStatus.values.firstWhere(
        (e) => e.name == map['sync_status'],
        orElse: () => SyncStatus.pending,
      ),
      retryCount: map['retry_count'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      syncedAt: map['synced_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['synced_at'] as int)
          : null,
      errorMessage: map['error_message'] as String?,
    );

  final int? id;
  final String sourceId;
  final String itemId;
  final int positionTicks;
  final bool isWatched;
  final SyncEventType eventType;
  final SyncStatus syncStatus;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? syncedAt;
  final String? errorMessage;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'source_id': sourceId,
        'item_id': itemId,
        'position_ticks': positionTicks,
        'is_watched': isWatched ? 1 : 0,
        'event_type': eventType.name,
        'sync_status': syncStatus.name,
        'retry_count': retryCount,
        'created_at': createdAt.millisecondsSinceEpoch,
        'synced_at': syncedAt?.millisecondsSinceEpoch,
        'error_message': errorMessage,
      };

  PlaybackSyncEntry copyWith({
    int? id,
    String? sourceId,
    String? itemId,
    int? positionTicks,
    bool? isWatched,
    SyncEventType? eventType,
    SyncStatus? syncStatus,
    int? retryCount,
    DateTime? createdAt,
    DateTime? syncedAt,
    String? errorMessage,
  }) => PlaybackSyncEntry(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      itemId: itemId ?? this.itemId,
      positionTicks: positionTicks ?? this.positionTicks,
      isWatched: isWatched ?? this.isWatched,
      eventType: eventType ?? this.eventType,
      syncStatus: syncStatus ?? this.syncStatus,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
}

/// 播放同步队列服务
///
/// 用于离线时缓存播放进度，恢复连接后同步到服务器
class PlaybackSyncQueueService {
  PlaybackSyncQueueService(this._ref);

  final Ref _ref;
  static const String _table = 'playback_sync_queue';
  static const int _maxRetries = 3;

  Database? _db;
  Timer? _syncTimer;
  bool _isSyncing = false;

  Future<void> init() async {
    await VideoDatabaseService().init();
    _db = VideoDatabaseService().database;
    // 启动定期同步
    _startSyncTimer();
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    // 每 30 秒尝试同步一次
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      syncPending();
    });
  }

  /// 添加同步条目
  Future<void> enqueue({
    required String sourceId,
    required String itemId,
    required int positionTicks,
    bool isWatched = false,
    required SyncEventType eventType,
  }) async {
    if (_db == null) await init();

    final entry = PlaybackSyncEntry(
      sourceId: sourceId,
      itemId: itemId,
      positionTicks: positionTicks,
      isWatched: isWatched,
      eventType: eventType,
      syncStatus: SyncStatus.pending,
      createdAt: DateTime.now(),
    );

    await _db!.insert(_table, entry.toMap());
    logger.d('PlaybackSyncQueue: 已添加同步条目 $itemId (${eventType.name})');
  }

  /// 获取待同步条目
  Future<List<PlaybackSyncEntry>> getPending({int limit = 50}) async {
    if (_db == null) await init();

    final results = await _db!.query(
      _table,
      where: 'sync_status = ? AND retry_count < ?',
      whereArgs: [SyncStatus.pending.name, _maxRetries],
      orderBy: 'created_at ASC',
      limit: limit,
    );

    return results.map(PlaybackSyncEntry.fromMap).toList();
  }

  /// 同步所有待处理条目
  Future<void> syncPending() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final pending = await getPending();
      if (pending.isEmpty) return;

      logger.i('PlaybackSyncQueue: 开始同步 ${pending.length} 条待处理记录');

      // 按源分组
      final bySource = <String, List<PlaybackSyncEntry>>{};
      for (final entry in pending) {
        bySource.putIfAbsent(entry.sourceId, () => []).add(entry);
      }

      // 逐源同步
      for (final sourceId in bySource.keys) {
        final entries = bySource[sourceId]!;
        await _syncSource(sourceId, entries);
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncSource(String sourceId, List<PlaybackSyncEntry> entries) async {
    final connection = _ref.read(activeMediaServerConnectionsProvider)[sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      logger.d('PlaybackSyncQueue: 源 $sourceId 未连接，跳过同步');
      return;
    }

    for (final entry in entries) {
      try {
        // 标记为同步中
        await _updateStatus(entry.id!, SyncStatus.syncing);

        // 根据事件类型构建报告
        final report = PlaybackReport(
          itemId: entry.itemId,
          reportType: _getReportType(entry.eventType),
          positionTicks: entry.positionTicks,
          isPaused: entry.eventType == SyncEventType.playbackStop,
        );

        // 发送到服务器
        await connection.adapter.reportPlayback(report);

        // 标记为已同步
        await _updateStatus(entry.id!, SyncStatus.synced, syncedAt: DateTime.now());
        logger.d('PlaybackSyncQueue: 已同步 ${entry.itemId}');
      } on Exception catch (e) {
        // 增加重试计数
        await _incrementRetry(entry.id!, e.toString());
        logger.w('PlaybackSyncQueue: 同步失败 ${entry.itemId}', e);
      }
    }
  }

  PlaybackReportType _getReportType(SyncEventType eventType) => switch (eventType) {
      SyncEventType.playbackStart => PlaybackReportType.start,
      SyncEventType.playbackStop => PlaybackReportType.stop,
      _ => PlaybackReportType.progress,
    };

  Future<void> _updateStatus(
    int id,
    SyncStatus status, {
    DateTime? syncedAt,
  }) async {
    await _db!.update(
      _table,
      {
        'sync_status': status.name,
        if (syncedAt != null) 'synced_at': syncedAt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _incrementRetry(int id, String errorMessage) async {
    await _db!.rawUpdate('''
      UPDATE $_table
      SET retry_count = retry_count + 1,
          sync_status = ?,
          error_message = ?
      WHERE id = ?
    ''', [SyncStatus.pending.name, errorMessage, id]);
  }

  /// 删除已同步的旧条目
  Future<int> cleanupSynced({Duration maxAge = const Duration(days: 7)}) async {
    if (_db == null) await init();

    final threshold = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    final count = await _db!.delete(
      _table,
      where: 'sync_status = ? AND synced_at < ?',
      whereArgs: [SyncStatus.synced.name, threshold],
    );

    if (count > 0) {
      logger.i('PlaybackSyncQueue: 已清理 $count 条旧记录');
    }
    return count;
  }

  /// 删除指定源的所有条目
  Future<void> deleteBySource(String sourceId) async {
    if (_db == null) await init();

    await _db!.delete(
      _table,
      where: 'source_id = ?',
      whereArgs: [sourceId],
    );
  }

  /// 获取队列统计
  Future<Map<SyncStatus, int>> getStats() async {
    if (_db == null) await init();

    final results = await _db!.rawQuery('''
      SELECT sync_status, COUNT(*) as count
      FROM $_table
      GROUP BY sync_status
    ''');

    return {
      for (final row in results)
        SyncStatus.values.firstWhere(
          (s) => s.name == row['sync_status'],
          orElse: () => SyncStatus.pending,
        ): row['count']! as int,
    };
  }

  void dispose() {
    _syncTimer?.cancel();
  }
}

/// 播放同步队列服务 Provider
final playbackSyncQueueServiceProvider = Provider<PlaybackSyncQueueService>((ref) {
  final service = PlaybackSyncQueueService(ref);
  ref.onDispose(service.dispose);
  return service;
});
