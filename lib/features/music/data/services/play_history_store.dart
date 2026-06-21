import 'dart:async';
import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';

/// 单条播放事件。仅当用户实听时长 ≥ [PlayHistoryStore.recordedThresholdSec]
/// 时才会被记录，避免被 skip 的歌污染 Top 排行。
class PlayHistoryEntry {
  PlayHistoryEntry({
    required this.songId,
    required this.songTitle,
    required this.artistName,
    required this.albumTitle,
    required this.playedAt,
    required this.listenedSec,
    required this.sourceId,
  });

  factory PlayHistoryEntry.fromMap(Map<dynamic, dynamic> m) =>
      PlayHistoryEntry(
        songId: (m['songId'] as String?) ?? '',
        songTitle: (m['songTitle'] as String?) ?? '',
        artistName: (m['artistName'] as String?) ?? '',
        albumTitle: (m['albumTitle'] as String?) ?? '',
        playedAt: DateTime.fromMillisecondsSinceEpoch(
          (m['playedAt'] as num?)?.toInt() ?? 0,
        ),
        listenedSec: (m['listenedSec'] as num?)?.toDouble() ?? 0,
        sourceId: (m['sourceId'] as String?) ?? '',
      );

  final String songId;
  final String songTitle;
  final String artistName;
  final String albumTitle;
  final DateTime playedAt;
  final double listenedSec;
  final String sourceId;

  Map<String, dynamic> toMap() => {
        'songId': songId,
        'songTitle': songTitle,
        'artistName': artistName,
        'albumTitle': albumTitle,
        'playedAt': playedAt.millisecondsSinceEpoch,
        'listenedSec': listenedSec,
        'sourceId': sourceId,
      };
}

/// 时间范围（与 primuse 对齐）
enum PlayHistoryRange {
  week(7),
  month(30),
  year(365);

  const PlayHistoryRange(this.days);
  final int days;

  DateTime startDate([DateTime? now]) {
    final base = now ?? DateTime.now();
    return base.subtract(Duration(days: days));
  }
}

/// 排行项（top songs / artists / albums 共用）
class RankedItem {
  const RankedItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.playCount,
    required this.totalSec,
  });

  final String id;
  final String title;
  final String subtitle;
  final int playCount;
  final double totalSec;
}

/// 听歌统计摘要
class PlayHistorySummary {
  const PlayHistorySummary({
    required this.totalPlays,
    required this.totalSec,
    required this.activeDays,
    required this.uniqueSongs,
  });

  final int totalPlays;
  final double totalSec;
  final int activeDays;
  final int uniqueSongs;

  static const empty = PlayHistorySummary(
    totalPlays: 0,
    totalSec: 0,
    activeDays: 0,
    uniqueSongs: 0,
  );
}

/// 本地播放历史 — 给「听歌统计」页用。
///
/// 跟现有的两条数据通路是互补关系：
/// - `recent_tracks_section.dart`：100 条滑动窗口，无时间戳，给 Home 页「最近播放」用
/// - 本类：append-only JSON 日志，5000 条滚动，按周/月/年聚合 + Top 排行
///
/// **隐私**：纯本地存储，云同步功能开启后会作为可选项进入同步范围。
class PlayHistoryStore {
  PlayHistoryStore._();

  static final PlayHistoryStore instance = PlayHistoryStore._();

  /// 触发记录的最低实听秒数（与 Scrobble 保持一致：50% 或 240s 较小者，30s 保底）
  static const double recordedThresholdSec = 30;

  /// 最大保留条目数 — 滚动 evict 最老的。5000 条按平均 3 分钟一首
  /// 大约 250h，能覆盖 1-2 年的零散听歌。
  static const int maxEntries = 5000;

  static const String _boxName = 'music_play_history';
  static const String _entriesKey = 'entries';

  Box<dynamic>? _box;
  List<PlayHistoryEntry> _entries = [];

  // 当前会话状态
  MusicItem? _currentSong;
  DateTime? _currentStartedAt;
  double _currentMaxElapsedSec = 0;

  Timer? _saveDebounce;

  Future<void> _ensureLoaded() async {
    if (_box != null) return;
    try {
      _box = await Hive.openBox<dynamic>(_boxName);
      final raw = _box!.get(_entriesKey);
      if (raw is String && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List<dynamic>)
            .cast<Map<dynamic, dynamic>>();
        _entries = list.map(PlayHistoryEntry.fromMap).toList()
          ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'PlayHistoryStore.load');
    }
  }

  /// 公开的初始化入口，启动时调一次以便后续查询零延迟。
  Future<void> init() => _ensureLoaded();

  // ------------------------------ Session ------------------------------

  /// 开始播放新歌；若上一首未结算则先 flush
  Future<void> beginSession(MusicItem song) async {
    await _ensureLoaded();
    await endSession();
    _currentSong = song;
    _currentStartedAt = DateTime.now();
    _currentMaxElapsedSec = 0;
  }

  /// 进度刻度（与 Scrobble 同步触发）。high-water mark：seek 回去不会让累计变小
  void tick(Duration elapsed) {
    if (_currentSong == null) return;
    final sec = elapsed.inMilliseconds / 1000.0;
    if (sec > _currentMaxElapsedSec) _currentMaxElapsedSec = sec;
  }

  /// 结束会话（停 / 切歌 / 播完）。低于阈值不写入。
  Future<void> endSession() async {
    final song = _currentSong;
    final startedAt = _currentStartedAt;
    _currentSong = null;
    _currentStartedAt = null;
    final elapsed = _currentMaxElapsedSec;
    _currentMaxElapsedSec = 0;
    if (song == null || startedAt == null) return;
    if (elapsed < recordedThresholdSec) return;
    await _record(
      PlayHistoryEntry(
        songId: song.id,
        songTitle: song.title ?? song.name,
        artistName: song.artist ?? '',
        albumTitle: song.album ?? '',
        playedAt: startedAt,
        listenedSec: elapsed,
        sourceId: song.sourceId ?? '',
      ),
    );
  }

  Future<void> _record(PlayHistoryEntry entry) async {
    await _ensureLoaded();
    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries = _entries.sublist(0, maxEntries);
    }
    _scheduleSave();
  }

  Future<void> clearAll() async {
    await _ensureLoaded();
    _entries.clear();
    await _box?.delete(_entriesKey);
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), () {
      AppError.fireAndForget(
        _saveNow(),
        action: 'PlayHistoryStore.save',
      );
    });
  }

  Future<void> _saveNow() async {
    final box = _box;
    if (box == null) return;
    try {
      final json =
          jsonEncode(_entries.map((e) => e.toMap()).toList());
      await box.put(_entriesKey, json);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'PlayHistoryStore.saveNow');
    }
  }

  // ------------------------------ 查询 / 聚合 ------------------------------

  List<PlayHistoryEntry> entriesIn(PlayHistoryRange range, {DateTime? now}) {
    final cutoff = range.startDate(now);
    return _entries.where((e) => e.playedAt.isAfter(cutoff)).toList();
  }

  PlayHistorySummary summary(PlayHistoryRange range, {DateTime? now}) {
    final scoped = entriesIn(range, now: now);
    if (scoped.isEmpty) return PlayHistorySummary.empty;
    final dayBuckets = <DateTime>{
      for (final e in scoped) DateTime(e.playedAt.year, e.playedAt.month, e.playedAt.day),
    };
    final uniqueSongs = <String>{for (final e in scoped) e.songId};
    final total = scoped.fold<double>(0, (acc, e) => acc + e.listenedSec);
    return PlayHistorySummary(
      totalPlays: scoped.length,
      totalSec: total,
      activeDays: dayBuckets.length,
      uniqueSongs: uniqueSongs.length,
    );
  }

  List<RankedItem> topSongs(PlayHistoryRange range, {int limit = 20}) {
    final scoped = entriesIn(range);
    final groups = <String, List<PlayHistoryEntry>>{};
    for (final e in scoped) {
      groups.putIfAbsent(e.songId, () => []).add(e);
    }
    final items = groups.entries.map((kv) {
      final first = kv.value.first;
      final total =
          kv.value.fold<double>(0, (acc, e) => acc + e.listenedSec);
      return RankedItem(
        id: kv.key,
        title: first.songTitle,
        subtitle: first.artistName,
        playCount: kv.value.length,
        totalSec: total,
      );
    }).toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    return items.take(limit).toList();
  }

  List<RankedItem> topArtists(PlayHistoryRange range, {int limit = 20}) {
    final scoped =
        entriesIn(range).where((e) => e.artistName.isNotEmpty).toList();
    final groups = <String, List<PlayHistoryEntry>>{};
    for (final e in scoped) {
      groups.putIfAbsent(e.artistName, () => []).add(e);
    }
    final items = groups.entries.map((kv) {
      final uniqueSongs = <String>{for (final e in kv.value) e.songId};
      final total =
          kv.value.fold<double>(0, (acc, e) => acc + e.listenedSec);
      return RankedItem(
        id: 'artist:${kv.key}',
        title: kv.key,
        subtitle: appL10n.musicSongCountUnit(uniqueSongs.length),
        playCount: kv.value.length,
        totalSec: total,
      );
    }).toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    return items.take(limit).toList();
  }

  List<RankedItem> topAlbums(PlayHistoryRange range, {int limit = 20}) {
    final scoped =
        entriesIn(range).where((e) => e.albumTitle.isNotEmpty).toList();
    final groups = <String, List<PlayHistoryEntry>>{};
    for (final e in scoped) {
      final key = '${e.albumTitle}|${e.artistName}';
      groups.putIfAbsent(key, () => []).add(e);
    }
    final items = groups.entries.map((kv) {
      final first = kv.value.first;
      final total =
          kv.value.fold<double>(0, (acc, e) => acc + e.listenedSec);
      return RankedItem(
        id: 'album:${kv.key}',
        title: first.albumTitle,
        subtitle: first.artistName,
        playCount: kv.value.length,
        totalSec: total,
      );
    }).toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    return items.take(limit).toList();
  }

  /// 按天聚合的播放数 — 热力图用
  List<({DateTime date, int count})> dailyPlayCounts(
    PlayHistoryRange range, {
    DateTime? now,
  }) {
    final base = now ?? DateTime.now();
    final start = DateTime(base.year, base.month, base.day)
        .subtract(Duration(days: range.days - 1));
    final end = DateTime(base.year, base.month, base.day);
    final scoped = entriesIn(range, now: base);
    final bucket = <DateTime, int>{};
    for (final e in scoped) {
      final day = DateTime(e.playedAt.year, e.playedAt.month, e.playedAt.day);
      bucket[day] = (bucket[day] ?? 0) + 1;
    }
    final result = <({DateTime date, int count})>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      result.add((date: cursor, count: bucket[cursor] ?? 0));
      cursor = cursor.add(const Duration(days: 1));
    }
    return result;
  }

  /// 调试用
  int get totalEntries {
    logger.d('PlayHistoryStore: ${_entries.length} entries');
    return _entries.length;
  }
}
