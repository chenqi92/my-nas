import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/sync/cloud_sync_backend.dart';
import 'package:my_nas/core/sync/cloud_sync_service.dart';
import 'package:my_nas/core/sync/syncable_module.dart';

void main() {
  group('CloudSyncSettings', () {
    test('持久化映射不包含密码且容忍错误列表元素', () {
      final settings = CloudSyncSettings.fromMap({
        'endpoint': 'https://dav.example.com',
        'username': 'user',
        'password': 'legacy-secret',
        'enabledModuleKeys': ['video_progress', 42, null],
      });

      expect(settings.password, 'legacy-secret');
      expect(settings.enabledModuleKeys, {'video_progress'});
      expect(settings.toMap(), isNot(contains('password')));
    });
  });

  group('CloudSyncModuleReconciler', () {
    test('本地时间较新时仍合并远端独有记录后再上传', () async {
      final module = _RecordModule({'local': 200});
      final backend = _FakeBackend(
        modules: {
          module.key: _payload({'remote': 100}),
        },
      );
      final updates = <String, dynamic>{};

      final report = await const CloudSyncModuleReconciler().reconcile(
        module: module,
        backend: backend,
        manifest: {
          module.key: {'updatedAt': 100},
        },
        manifestUpdates: updates,
      );

      expect(report.outcome, CloudSyncOutcome.pushed);
      expect(module.records, {'local': 200, 'remote': 100});
      expect(_recordsFrom(backend.modules[module.key]!), module.records);
      expect(backend.moduleWriteCount, 1);
      expect(updates[module.key], isNotNull);
    });

    test('写入前远端发生变化时重新合并，不覆盖并发记录', () async {
      final module = _RecordModule({'local': 300});
      final backend = _FakeBackend(
        modules: {
          module.key: _payload({'remote': 100}),
        },
      );
      backend.onWriteModule = (writeCount, key) {
        if (writeCount == 1) {
          backend.putModule(key, _payload({'remote': 100, 'concurrent': 200}));
        }
      };

      final report = await const CloudSyncModuleReconciler().reconcile(
        module: module,
        backend: backend,
        manifest: {
          module.key: {'updatedAt': 100},
        },
        manifestUpdates: <String, dynamic>{},
      );

      expect(report.outcome, CloudSyncOutcome.pushed);
      expect(_recordsFrom(backend.modules[module.key]!), {
        'local': 300,
        'remote': 100,
        'concurrent': 200,
      });
    });

    test('远端读取异常会失败且绝不写入', () async {
      final module = _RecordModule({'local': 200});
      final backend = _FakeBackend()..moduleReadError = StateError('offline');

      await expectLater(
        const CloudSyncModuleReconciler().reconcile(
          module: module,
          backend: backend,
          manifest: <String, dynamic>{},
          manifestUpdates: <String, dynamic>{},
        ),
        throwsStateError,
      );
      expect(backend.moduleWriteCount, 0);
    });

    test('manifest 有条目但模块文件缺失时失败，不以本地覆盖', () async {
      final module = _RecordModule({'local': 200});
      final backend = _FakeBackend();

      await expectLater(
        const CloudSyncModuleReconciler().reconcile(
          module: module,
          backend: backend,
          manifest: {
            module.key: {'updatedAt': 100},
          },
          manifestUpdates: <String, dynamic>{},
        ),
        throwsStateError,
      );
      expect(backend.moduleWriteCount, 0);
    });

    test('设置快照条件写冲突后按内嵌时间拉取并发的新版本', () async {
      final module = _SnapshotModule(value: 'local', updatedAt: 200);
      final backend = _FakeBackend(
        modules: {
          module.key: {
            'version': 1,
            'settings': {'value': 'remote-old'},
            '_syncUpdatedAt': 100,
          },
        },
      );
      backend.onWriteModule = (writeCount, key) {
        if (writeCount == 1) {
          backend.putModule(key, {
            'version': 1,
            'settings': {'value': 'remote-new'},
            '_syncUpdatedAt': 300,
          });
        }
      };

      final report = await const CloudSyncModuleReconciler().reconcile(
        module: module,
        backend: backend,
        manifest: {
          module.key: {'updatedAt': 100},
        },
        manifestUpdates: <String, dynamic>{},
      );

      expect(report.outcome, CloudSyncOutcome.pulled);
      expect(module.value, 'remote-new');
      expect(module.importedAt, DateTime.fromMillisecondsSinceEpoch(300));
      expect(backend.moduleWriteCount, 1);
      expect(
        (backend.modules[module.key]!['settings']! as Map)['value'],
        'remote-new',
      );
    });

    test('旧版设置快照并发变化且无内嵌时间时停止，不覆盖未知新版本', () async {
      final module = _SnapshotModule(value: 'local', updatedAt: 200);
      final backend = _FakeBackend(
        modules: {
          module.key: {
            'version': 1,
            'settings': {'value': 'remote-old'},
          },
        },
      );
      backend.onWriteModule = (writeCount, key) {
        if (writeCount == 1) {
          backend.putModule(key, {
            'version': 1,
            'settings': {'value': 'remote-concurrent'},
          });
        }
      };

      await expectLater(
        const CloudSyncModuleReconciler().reconcile(
          module: module,
          backend: backend,
          manifest: {
            module.key: {'updatedAt': 100},
          },
          manifestUpdates: <String, dynamic>{},
        ),
        throwsStateError,
      );

      expect(backend.moduleWriteCount, 1);
      expect(
        (backend.modules[module.key]!['settings']! as Map)['value'],
        'remote-concurrent',
      );
    });

    test('模块文件已一致但 manifest 落后时修复索引时间', () async {
      final module = _SnapshotModule(value: 'same', updatedAt: 300);
      final backend = _FakeBackend(
        modules: {
          module.key: {
            'version': 1,
            'settings': {'value': 'same'},
            '_syncUpdatedAt': 300,
          },
        },
      );
      final updates = <String, dynamic>{};

      final report = await const CloudSyncModuleReconciler().reconcile(
        module: module,
        backend: backend,
        manifest: {
          module.key: {'updatedAt': 100},
        },
        manifestUpdates: updates,
      );

      expect(report.outcome, CloudSyncOutcome.skipped);
      expect(backend.moduleWriteCount, 0);
      expect(updates[module.key], {'updatedAt': 300});
    });
  });
}

Map<String, dynamic> _payload(Map<String, int> records) => {
  'version': 1,
  'items':
      records.entries
          .map((entry) => {'id': entry.key, 'updatedAt': entry.value})
          .toList()
        ..sort((a, b) => (a['id']! as String).compareTo(b['id']! as String)),
};

Map<String, int> _recordsFrom(Map<String, dynamic> payload) {
  final items = payload['items']! as List<dynamic>;
  return {
    for (final item in items.cast<Map<String, dynamic>>())
      item['id']! as String: item['updatedAt']! as int,
  };
}

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value))! as Map<String, dynamic>;

class _RecordModule implements SyncableModule {
  _RecordModule(Map<String, int> records) : records = Map.of(records);

  final Map<String, int> records;

  @override
  String get key => 'records';

  @override
  String get displayName => 'Records';

  @override
  SyncMergePolicy get mergePolicy => SyncMergePolicy.recordMerge;

  @override
  Future<Map<String, dynamic>> exportData() async => _payload(records);

  @override
  Future<DateTime?> getLocalUpdatedAt() async {
    if (records.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      records.values.reduce((a, b) => a > b ? a : b),
    );
  }

  @override
  Future<void> importData(
    Map<String, dynamic> data, {
    DateTime? remoteUpdatedAt,
  }) async {
    final remote = _recordsFrom(data);
    for (final entry in remote.entries) {
      final localAt = records[entry.key];
      if (localAt == null || entry.value > localAt) {
        records[entry.key] = entry.value;
      }
    }
  }
}

class _SnapshotModule implements SyncableModule {
  _SnapshotModule({required this.value, required int updatedAt})
    : updatedAt = DateTime.fromMillisecondsSinceEpoch(updatedAt);

  String value;
  DateTime updatedAt;
  DateTime? importedAt;

  @override
  String get key => 'settings';

  @override
  String get displayName => 'Settings';

  @override
  SyncMergePolicy get mergePolicy => SyncMergePolicy.lastWriteWins;

  @override
  Future<Map<String, dynamic>> exportData() async => {
    'version': 1,
    'settings': {'value': value},
  };

  @override
  Future<DateTime?> getLocalUpdatedAt() async => updatedAt;

  @override
  Future<void> importData(
    Map<String, dynamic> data, {
    DateTime? remoteUpdatedAt,
  }) async {
    value = (data['settings']! as Map)['value']! as String;
    importedAt = remoteUpdatedAt;
    if (remoteUpdatedAt != null) updatedAt = remoteUpdatedAt;
  }
}

class _FakeBackend extends CloudSyncBackend {
  _FakeBackend({Map<String, Map<String, dynamic>>? modules})
    : modules = modules ?? <String, Map<String, dynamic>>{} {
    for (final key in this.modules.keys) {
      _moduleRevisions[key] = 1;
    }
  }

  final Map<String, Map<String, dynamic>> modules;
  Map<String, dynamic> manifest = <String, dynamic>{};
  final Map<String, int> _moduleRevisions = {};
  int _manifestRevision = 0;
  Object? moduleReadError;
  int moduleReadCount = 0;
  int moduleWriteCount = 0;
  void Function(int readCount, String key)? onReadModule;
  void Function(int writeCount, String key)? onWriteModule;

  void putModule(String key, Map<String, dynamic> data) {
    modules[key] = _copy(data);
    _moduleRevisions[key] = (_moduleRevisions[key] ?? 0) + 1;
  }

  @override
  Future<void> deleteModule(String key) async {
    modules.remove(key);
  }

  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<CloudSyncDocument?> readManifestDocument() async => manifest.isEmpty
      ? null
      : CloudSyncDocument(
          data: _copy(manifest),
          revision: 'manifest-$_manifestRevision',
        );

  @override
  Future<CloudSyncDocument?> readModuleDocument(String key) async {
    moduleReadCount++;
    onReadModule?.call(moduleReadCount, key);
    final error = moduleReadError;
    if (error != null) throw error;
    final value = modules[key];
    return value == null
        ? null
        : CloudSyncDocument(
            data: _copy(value),
            revision: '$key-${_moduleRevisions[key] ?? 0}',
          );
  }

  @override
  Future<bool> writeManifestIfUnchanged(
    Map<String, dynamic> next, {
    required CloudSyncDocument? expected,
  }) async {
    final currentRevision = manifest.isEmpty
        ? null
        : 'manifest-$_manifestRevision';
    if (expected?.revision != currentRevision) return false;
    manifest = _copy(next);
    _manifestRevision++;
    return true;
  }

  @override
  Future<bool> writeModuleIfUnchanged(
    String key,
    Map<String, dynamic> data, {
    required CloudSyncDocument? expected,
  }) async {
    moduleWriteCount++;
    onWriteModule?.call(moduleWriteCount, key);
    final currentRevision = modules.containsKey(key)
        ? '$key-${_moduleRevisions[key] ?? 0}'
        : null;
    if (expected?.revision != currentRevision) return false;
    putModule(key, data);
    return true;
  }
}
