import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/features/video/data/services/sync/video_progress_sync_module.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';

/// video_progress 同步契约的 golden 测试。
///
/// 这些断言与 docs/sync-contract-video-progress.md 一一对应。Swift 客户端按
/// 该文档解析 `video_progress.json`，Dart 侧改字段名 / 改可选性 / 改时间格式
/// 都会让这里失败，而不是等到跨端跑起来才发现对不上。
///
/// 改这个文件前先改文档，两边一起改。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDirectory;
  late Box<dynamic> progressBox;
  late Box<dynamic> watchedBox;
  late Box<dynamic> historyBox;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'my_nas_video_progress_sync_',
    );
    Hive.init(hiveDirectory.path);
    // 全程保持 box 打开：VideoHistoryService 是单例且用 late Box 缓存句柄，
    // 每个测试 close 一次会让后续测试拿到已关闭的 box。
    progressBox = await Hive.openBox<dynamic>('video_progress');
    watchedBox = await Hive.openBox<dynamic>('video_watched');
    historyBox = await Hive.openBox<dynamic>('video_history');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  setUp(() async {
    await progressBox.clear();
    await watchedBox.clear();
    await historyBox.clear();
  });

  VideoProgressSyncModule module() => VideoProgressSyncModule();

  /// 直接写 box，绕过 service 的 DateTime.now()，让时间戳可预期。
  Future<void> putProgress(
    String path, {
    required int positionMs,
    required int durationMs,
    required String updatedAt,
  }) => progressBox.put(path, {
    'videoPath': path,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'updatedAt': updatedAt,
  });

  Future<void> putHistory(List<VideoHistoryItem> items) =>
      historyBox.put('list', items.map((h) => h.toJson()).toList());

  VideoHistoryItem historyItem({
    required String path,
    required DateTime watchedAt,
    String name = 'Movie',
    String url = 'smb://host/share/Movie.mkv',
    String? sourceId = 'source-1',
    String? thumbnailUrl = 'https://example.invalid/t.jpg',
    int size = 1024,
    Duration? lastPosition = const Duration(seconds: 30),
    Duration? duration = const Duration(minutes: 90),
  }) => VideoHistoryItem(
    videoPath: path,
    videoName: name,
    videoUrl: url,
    sourceId: sourceId,
    thumbnailUrl: thumbnailUrl,
    size: size,
    lastPosition: lastPosition,
    duration: duration,
    watchedAt: watchedAt,
  );

  Map<String, dynamic> itemFor(Map<String, dynamic> data, String path) =>
      (data['items'] as List).cast<Map<String, dynamic>>().firstWhere(
        (e) => e['videoPath'] == path,
      );

  group('module identity', () {
    test('key 决定远端文件名 video_progress.json，不能改', () {
      expect(module().key, 'video_progress');
    });
  });

  group('exportData 顶层结构', () {
    test('空数据也返回 version + items，不返回 null', () async {
      final data = await module().exportData();

      expect(data.keys.toSet(), {'version', 'items'});
      expect(data['version'], 1);
      expect(data['items'], isEmpty);
    });

    test('items 的主键是三个 box 的 videoPath 并集', () async {
      await putProgress(
        '/only-progress',
        positionMs: 1000,
        durationMs: 2000,
        updatedAt: '2026-01-01T00:00:00.000',
      );
      await watchedBox.put('/only-watched', '2026-01-02T00:00:00.000');
      await putHistory([
        historyItem(path: '/only-history', watchedAt: DateTime(2026, 1, 3)),
      ]);

      final data = await module().exportData();
      final paths = (data['items'] as List)
          .cast<Map<String, dynamic>>()
          .map((e) => e['videoPath'])
          .toSet();

      expect(paths, {'/only-progress', '/only-watched', '/only-history'});
    });
  });

  group('exportData 记录字段集（v1）', () {
    test('三个 box 都有数据时导出完整字段集', () async {
      const path = '/media/Movie.mkv';
      await putProgress(
        path,
        positionMs: 61000,
        durationMs: 5400000,
        updatedAt: '2026-03-01T10:00:00.000',
      );
      await watchedBox.put(path, '2026-03-02T11:00:00.000');
      await putHistory([
        historyItem(
          path: path,
          watchedAt: DateTime.utc(2026, 3, 3, 12),
          name: 'Movie',
          url: 'smb://host/share/Movie.mkv',
          sourceId: 'source-1',
          thumbnailUrl: 'https://example.invalid/t.jpg',
          size: 1024,
          lastPosition: const Duration(seconds: 42),
          duration: const Duration(minutes: 91),
        ),
      ]);

      final record = itemFor(await module().exportData(), path);

      // 字段集精确断言：多一个字段 Swift 侧会忽略，少一个字段会解析出空值。
      expect(record.keys.toSet(), {
        'videoPath',
        'positionMs',
        'durationMs',
        'progressUpdatedAt',
        'watchedAt',
        'videoName',
        'videoUrl',
        'sourceId',
        'thumbnailUrl',
        'size',
        'historyAddedAt',
        'historyLastPositionMs',
        'historyDurationMs',
      });

      expect(record['videoPath'], path);
      expect(record['positionMs'], 61000);
      expect(record['durationMs'], 5400000);
      expect(record['progressUpdatedAt'], '2026-03-01T10:00:00.000');
      expect(record['watchedAt'], '2026-03-02T11:00:00.000');
      expect(record['videoName'], 'Movie');
      expect(record['videoUrl'], 'smb://host/share/Movie.mkv');
      expect(record['sourceId'], 'source-1');
      expect(record['thumbnailUrl'], 'https://example.invalid/t.jpg');
      expect(record['size'], 1024);
      expect(record['historyAddedAt'], '2026-03-03T12:00:00.000Z');
      expect(record['historyLastPositionMs'], 42000);
      expect(record['historyDurationMs'], 5460000);
    });

    test('progress 的 durationMs 与 history 的 historyDurationMs 是两个来源', () async {
      const path = '/media/Split.mkv';
      await putProgress(
        path,
        positionMs: 1,
        durationMs: 111,
        updatedAt: '2026-03-01T10:00:00.000',
      );
      await putHistory([
        historyItem(
          path: path,
          watchedAt: DateTime(2026, 3, 1, 10),
          lastPosition: const Duration(milliseconds: 2),
          duration: const Duration(milliseconds: 222),
        ),
      ]);

      final record = itemFor(await module().exportData(), path);

      expect(record['durationMs'], 111, reason: 'video_progress box');
      expect(record['historyDurationMs'], 222, reason: 'video_history box');
      expect(record['positionMs'], 1);
      expect(record['historyLastPositionMs'], 2);
    });

    test('watchedAt 来自 video_watched，不是 history 时间', () async {
      const path = '/media/Marked.mkv';
      await watchedBox.put(path, '2026-04-01T00:00:00.000');
      await putHistory([
        historyItem(path: path, watchedAt: DateTime(2026, 4, 9)),
      ]);

      final record = itemFor(await module().exportData(), path);

      expect(record['watchedAt'], '2026-04-01T00:00:00.000');
      expect(record['historyAddedAt'], '2026-04-09T00:00:00.000');
    });

    test('只有进度时不写 history / watched 字段', () async {
      const path = '/media/ProgressOnly.mkv';
      await putProgress(
        path,
        positionMs: 5,
        durationMs: 10,
        updatedAt: '2026-05-01T00:00:00.000',
      );

      final record = itemFor(await module().exportData(), path);

      expect(record.keys.toSet(), {
        'videoPath',
        'positionMs',
        'durationMs',
        'progressUpdatedAt',
      });
    });

    test('只有观看标记时只写 videoPath + watchedAt', () async {
      const path = '/media/WatchedOnly.mkv';
      await watchedBox.put(path, '2026-05-02T00:00:00.000');

      final record = itemFor(await module().exportData(), path);

      expect(record.keys.toSet(), {'videoPath', 'watchedAt'});
    });

    test('history 的 sourceId / thumbnailUrl / 时长为 null 时整键省略', () async {
      const path = '/media/Sparse.mkv';
      await putHistory([
        historyItem(
          path: path,
          watchedAt: DateTime(2026, 5, 3),
          sourceId: null,
          thumbnailUrl: null,
          lastPosition: null,
          duration: null,
        ),
      ]);

      final record = itemFor(await module().exportData(), path);

      // 省略而不是写 null：Swift 侧 decodeIfPresent 与 null 值行为一致，
      // 但省略能让 JSON 体积小且避免「null 表示清空」的歧义。
      expect(record.keys.toSet(), {
        'videoPath',
        'videoName',
        'videoUrl',
        'size',
        'historyAddedAt',
      });
      expect(record.containsKey('sourceId'), isFalse);
      expect(record.containsKey('thumbnailUrl'), isFalse);
      expect(record.containsKey('historyLastPositionMs'), isFalse);
      expect(record.containsKey('historyDurationMs'), isFalse);
    });

    test('size 缺省为 0 而不是省略', () async {
      const path = '/media/NoSize.mkv';
      await putHistory([
        historyItem(path: path, watchedAt: DateTime(2026, 5, 4), size: 0),
      ]);

      final record = itemFor(await module().exportData(), path);

      expect(record['size'], 0);
    });
  });

  group('exportData 线格式', () {
    test('整个 payload 能 jsonEncode 且往返不变形', () async {
      const path = '/media/Wire.mkv';
      await putProgress(
        path,
        positionMs: 61000,
        durationMs: 5400000,
        updatedAt: '2026-06-01T10:00:00.000',
      );
      await watchedBox.put(path, '2026-06-02T10:00:00.000');
      await putHistory([
        historyItem(path: path, watchedAt: DateTime(2026, 6, 3, 10)),
      ]);

      final data = await module().exportData();
      final roundTripped = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;

      expect(roundTripped, data);
      // 时间戳是字符串（ISO8601），不是 epoch 数字 —— 与 manifest.json 的
      // updatedAt（epoch ms int）不同，两者不要混用。
      expect(itemFor(roundTripped, path)['progressUpdatedAt'], isA<String>());
      expect(itemFor(roundTripped, path)['positionMs'], isA<int>());
    });

    test('时间戳小数位可能是 0 / 3 / 6 位，带或不带 Z', () async {
      // DateTime.now() 常带微秒 => toIso8601String() 输出 6 位小数。
      // 对端严格按 3 位解析（如 Swift ISO8601DateFormatter.withFractionalSeconds）
      // 会解析失败，所以这里把三种精度都固定成契约。
      await putProgress(
        '/micro',
        positionMs: 1,
        durationMs: 2,
        updatedAt: '2026-03-01T10:00:00.123456',
      );
      await putProgress(
        '/milli',
        positionMs: 1,
        durationMs: 2,
        updatedAt: '2026-03-01T10:00:00.000',
      );
      await putProgress(
        '/utc',
        positionMs: 1,
        durationMs: 2,
        updatedAt: '2026-03-01T10:00:00.000Z',
      );

      final data = await module().exportData();

      expect(
        itemFor(data, '/micro')['progressUpdatedAt'],
        '2026-03-01T10:00:00.123456',
      );
      expect(
        itemFor(data, '/milli')['progressUpdatedAt'],
        '2026-03-01T10:00:00.000',
      );
      expect(
        itemFor(data, '/utc')['progressUpdatedAt'],
        '2026-03-01T10:00:00.000Z',
      );
    });

    test('微秒精度时间戳参与 last-wins 且不丢精度', () async {
      const path = '/media/Micro.mkv';
      await putProgress(
        path,
        positionMs: 1000,
        durationMs: 5000,
        updatedAt: '2026-03-01T10:00:00.123456',
      );

      // 同一秒内、仅微秒更大 => 远端应当胜出
      await module().importData({
        'version': 1,
        'items': [
          {
            'videoPath': path,
            'positionMs': 4000,
            'durationMs': 5000,
            'progressUpdatedAt': '2026-03-01T10:00:00.123457',
          },
        ],
      });

      final stored = progressBox.get(path) as Map;
      expect(stored['positionMs'], 4000);
      expect(stored['updatedAt'], '2026-03-01T10:00:00.123457');
    });

    test('时长字段是毫秒整数，不是秒也不是浮点', () async {
      const path = '/media/Units.mkv';
      await putProgress(
        path,
        positionMs: 1500,
        durationMs: 2500,
        updatedAt: '2026-06-04T00:00:00.000',
      );

      final record = itemFor(await module().exportData(), path);

      expect(record['positionMs'], 1500);
      expect(record['durationMs'], 2500);
      expect(record['positionMs'], isA<int>());
    });
  });

  group('getLocalUpdatedAt', () {
    test('取三个 box 中最大时间', () async {
      await putProgress(
        '/a',
        positionMs: 1,
        durationMs: 2,
        updatedAt: '2026-07-01T00:00:00.000',
      );
      await watchedBox.put('/b', '2026-07-05T00:00:00.000');
      await putHistory([
        historyItem(path: '/c', watchedAt: DateTime(2026, 7, 3)),
      ]);

      expect(await module().getLocalUpdatedAt(), DateTime(2026, 7, 5));
    });

    test('三个 box 全空时返回 null（CloudSyncService 据此 skip）', () async {
      expect(await module().getLocalUpdatedAt(), isNull);
    });
  });

  group('importData 合并规则', () {
    test('远端进度更新则覆盖本地', () async {
      const path = '/media/Newer.mkv';
      await putProgress(
        path,
        positionMs: 1000,
        durationMs: 5000,
        updatedAt: '2026-08-01T00:00:00.000',
      );

      await module().importData({
        'version': 1,
        'items': [
          {
            'videoPath': path,
            'positionMs': 4000,
            'durationMs': 5000,
            'progressUpdatedAt': '2026-08-02T00:00:00.000',
          },
        ],
      });

      expect((progressBox.get(path) as Map)['positionMs'], 4000);
    });

    test('远端进度更旧则保留本地', () async {
      const path = '/media/Older.mkv';
      await putProgress(
        path,
        positionMs: 4000,
        durationMs: 5000,
        updatedAt: '2026-08-02T00:00:00.000',
      );

      await module().importData({
        'version': 1,
        'items': [
          {
            'videoPath': path,
            'positionMs': 1000,
            'durationMs': 5000,
            'progressUpdatedAt': '2026-08-01T00:00:00.000',
          },
        ],
      });

      expect((progressBox.get(path) as Map)['positionMs'], 4000);
    });

    test('缺 progressUpdatedAt 的进度整条丢弃，不写入本地', () async {
      const path = '/media/NoStamp.mkv';

      await module().importData({
        'version': 1,
        'items': [
          {'videoPath': path, 'positionMs': 4000, 'durationMs': 5000},
        ],
      });

      expect(progressBox.get(path), isNull);
    });

    test('远端没有 watchedAt 时不清除本地已观看标记', () async {
      const path = '/media/StayWatched.mkv';
      await watchedBox.put(path, '2026-08-01T00:00:00.000');

      await module().importData({
        'version': 1,
        'items': [
          {
            'videoPath': path,
            'positionMs': 10,
            'durationMs': 100,
            'progressUpdatedAt': '2026-08-05T00:00:00.000',
          },
        ],
      });

      expect(watchedBox.get(path), '2026-08-01T00:00:00.000');
    });

    test('watchedAt 取较新的一侧', () async {
      const path = '/media/WatchedNewer.mkv';
      await watchedBox.put(path, '2026-08-01T00:00:00.000');

      await module().importData({
        'version': 1,
        'items': [
          {'videoPath': path, 'watchedAt': '2026-08-09T00:00:00.000'},
        ],
      });

      expect(watchedBox.get(path), '2026-08-09T00:00:00.000');
    });

    test('本地独有的历史条目在导入后保留', () async {
      await putHistory([
        historyItem(path: '/local-only', watchedAt: DateTime(2026, 8, 1)),
      ]);

      await module().importData({
        'version': 1,
        'items': [
          {
            'videoPath': '/remote-only',
            'videoName': 'Remote',
            'videoUrl': 'smb://host/share/Remote.mkv',
            'historyAddedAt': '2026-08-02T00:00:00.000',
          },
        ],
      });

      final paths = (historyBox.get('list') as List)
          .cast<Map<dynamic, dynamic>>()
          .map((e) => e['videoPath'])
          .toSet();

      expect(paths, {'/local-only', '/remote-only'});
    });

    test('历史元数据按 historyAddedAt last-wins', () async {
      const path = '/media/Meta.mkv';
      await putHistory([
        historyItem(
          path: path,
          watchedAt: DateTime(2026, 8, 1),
          name: 'Old name',
        ),
      ]);

      await module().importData({
        'version': 1,
        'items': [
          {
            'videoPath': path,
            'videoName': 'New name',
            'videoUrl': 'smb://host/share/Meta.mkv',
            'historyAddedAt': '2026-08-02T00:00:00.000',
          },
        ],
      });

      final list = (historyBox.get('list') as List)
          .cast<Map<dynamic, dynamic>>();
      expect(list.single['videoName'], 'New name');
    });

    test('缺 videoName / videoUrl 的历史条目被跳过', () async {
      await module().importData({
        'version': 1,
        'items': [
          {
            'videoPath': '/media/NoName.mkv',
            'historyAddedAt': '2026-08-02T00:00:00.000',
          },
        ],
      });

      expect(historyBox.get('list'), isEmpty);
    });

    test('合并后历史按时间倒序且截断到 100 条', () async {
      await module().importData({
        'version': 1,
        'items': [
          for (var i = 0; i < 150; i++)
            {
              'videoPath': '/media/$i.mkv',
              'videoName': 'Item $i',
              'videoUrl': 'smb://host/share/$i.mkv',
              // i 越大时间越新
              'historyAddedAt': DateTime(
                2026,
                1,
                1,
              ).add(Duration(minutes: i)).toIso8601String(),
            },
        ],
      });

      final list = (historyBox.get('list') as List)
          .cast<Map<dynamic, dynamic>>();

      expect(list.length, 100);
      expect(list.first['videoPath'], '/media/149.mkv');
      expect(list.last['videoPath'], '/media/50.mkv');
    });

    test('items 缺失或为空时是 no-op，不清空本地', () async {
      await putProgress(
        '/keep',
        positionMs: 1,
        durationMs: 2,
        updatedAt: '2026-08-01T00:00:00.000',
      );

      await module().importData({'version': 1});
      await module().importData({'version': 1, 'items': const <Object>[]});

      expect(progressBox.get('/keep'), isNotNull);
    });

    test('单条记录格式错误不影响同批其他记录', () async {
      await module().importData({
        'version': 1,
        'items': [
          'not-a-map',
          {'videoPath': 42},
          {
            'videoPath': '/media/Good.mkv',
            'positionMs': 7,
            'durationMs': 70,
            'progressUpdatedAt': '2026-08-03T00:00:00.000',
          },
        ],
      });

      expect((progressBox.get('/media/Good.mkv') as Map)['positionMs'], 7);
    });

    test('记录里的未知字段被忽略（v1 前向兼容，允许对端加可选字段）', () async {
      const path = '/media/Future.mkv';

      await module().importData({
        'version': 1,
        'items': [
          {
            'videoPath': path,
            'positionMs': 9,
            'durationMs': 90,
            'progressUpdatedAt': '2026-08-04T00:00:00.000',
            'somethingSwiftAddedLater': {'nested': true},
          },
        ],
      });

      expect((progressBox.get(path) as Map)['positionMs'], 9);
    });

    test('version 目前不被校验：任何 version 都按 v1 解析', () async {
      const path = '/media/V2.mkv';

      // 记录当前行为，不是背书。加 v2 时必须同时在 importData 里加分支，
      // 否则 v2 数据会被 v1 逻辑误读 —— 这条测试会提醒改这里。
      await module().importData({
        'version': 2,
        'items': [
          {
            'videoPath': path,
            'positionMs': 11,
            'durationMs': 110,
            'progressUpdatedAt': '2026-08-06T00:00:00.000',
          },
        ],
      });

      expect((progressBox.get(path) as Map)['positionMs'], 11);
    });

    test('导出再导入是幂等的（自身往返不丢字段）', () async {
      const path = '/media/RoundTrip.mkv';
      await putProgress(
        path,
        positionMs: 61000,
        durationMs: 5400000,
        updatedAt: '2026-09-01T10:00:00.000',
      );
      await watchedBox.put(path, '2026-09-02T10:00:00.000');
      await putHistory([
        historyItem(path: path, watchedAt: DateTime(2026, 9, 3, 10)),
      ]);

      final exported = await module().exportData();
      await progressBox.clear();
      await watchedBox.clear();
      await historyBox.clear();
      await module().importData(
        jsonDecode(jsonEncode(exported)) as Map<String, dynamic>,
      );

      expect(await module().exportData(), exported);
    });

    test('空 items 不截断本地历史', () async {
      // 先写本地 3 条
      await putHistory([
        historyItem(path: '/local/1', watchedAt: DateTime(2026, 1, 1)),
        historyItem(path: '/local/2', watchedAt: DateTime(2026, 1, 2)),
        historyItem(path: '/local/3', watchedAt: DateTime(2026, 1, 3)),
      ]);

      // 远端传空 items
      await module().importData({'version': 1, 'items': <Object?>[]});

      final history = await module().exportData();
      expect((history['items'] as List).length, 3); // 本地不被截断
    });

    test('一条格式错不杀整批', () async {
      final remoteData = {
        'version': 1,
        'items': [
          {'videoPath': 123}, // videoPath 不是字符串
          {
            'videoPath': '/good',
            'positionMs': 1000,
            'durationMs': 2000,
            'progressUpdatedAt': '2026-01-01T10:00:00.000Z',
          },
          'not a map', // 根本不是 map
        ],
      };

      await module().importData(remoteData);
      final exported = await module().exportData();
      final items = exported['items'] as List<dynamic>;
      expect(items.length, 1); // 只有好的那条
      final item = items.single as Map<String, dynamic>;
      expect(item['videoPath'], '/good');
    });
  });
}
