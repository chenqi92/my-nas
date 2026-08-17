import 'dart:async';

import 'package:collection/collection.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/storage/secure_storage_options.dart';
import 'package:my_nas/core/sync/cloud_sync_backend.dart';
import 'package:my_nas/core/sync/syncable_module.dart';

const Object _notProvided = Object();

/// 同步设置：WebDAV 凭证 + 启用的模块 key 列表。
class CloudSyncSettings {
  const CloudSyncSettings({
    this.endpoint,
    this.username,
    this.password,
    this.rootPath = '/my-nas-sync',
    this.enabledModuleKeys = const {},
    this.seenModuleKeys = const {},
    this.lastSyncedAt,
  });

  factory CloudSyncSettings.fromMap(Map<dynamic, dynamic> m) {
    String? stringValue(Object? value) => value is String ? value : null;
    Set<String> stringSet(Object? value) {
      if (value is! List) return <String>{};
      return value.whereType<String>().toSet();
    }

    return CloudSyncSettings(
      endpoint: stringValue(m['endpoint']),
      username: stringValue(m['username']),
      // 仅用于迁移 1.1.1 及更早版本留下的明文密码；新写入不会包含该字段。
      password: stringValue(m['password']),
      rootPath: stringValue(m['rootPath']) ?? '/my-nas-sync',
      enabledModuleKeys: stringSet(m['enabledModuleKeys']),
      seenModuleKeys: stringSet(m['seenModuleKeys']),
      lastSyncedAt: m['lastSyncedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(m['lastSyncedAt'] as int)
          : null,
    );
  }

  final String? endpoint;
  final String? username;
  final String? password;
  final String rootPath;
  final Set<String> enabledModuleKeys;

  /// 历史上已注册过的模块 key 集合。用于在新版本注册新模块时，将其
  /// 默认加入 enabledModuleKeys 一次（已被用户取消的不会被复活）。
  final Set<String> seenModuleKeys;
  final DateTime? lastSyncedAt;

  bool get isConfigured =>
      (endpoint?.isNotEmpty ?? false) &&
      (username?.isNotEmpty ?? false) &&
      (password?.isNotEmpty ?? false);

  Map<String, dynamic> toMap() => {
    if (endpoint != null) 'endpoint': endpoint,
    if (username != null) 'username': username,
    'rootPath': rootPath,
    'enabledModuleKeys': enabledModuleKeys.toList(),
    'seenModuleKeys': seenModuleKeys.toList(),
    if (lastSyncedAt != null)
      'lastSyncedAt': lastSyncedAt!.millisecondsSinceEpoch,
  };

  CloudSyncSettings copyWith({
    Object? endpoint = _notProvided,
    Object? username = _notProvided,
    Object? password = _notProvided,
    String? rootPath,
    Set<String>? enabledModuleKeys,
    Set<String>? seenModuleKeys,
    Object? lastSyncedAt = _notProvided,
  }) => CloudSyncSettings(
    endpoint: identical(endpoint, _notProvided)
        ? this.endpoint
        : endpoint as String?,
    username: identical(username, _notProvided)
        ? this.username
        : username as String?,
    password: identical(password, _notProvided)
        ? this.password
        : password as String?,
    rootPath: rootPath ?? this.rootPath,
    enabledModuleKeys: enabledModuleKeys ?? this.enabledModuleKeys,
    seenModuleKeys: seenModuleKeys ?? this.seenModuleKeys,
    lastSyncedAt: identical(lastSyncedAt, _notProvided)
        ? this.lastSyncedAt
        : lastSyncedAt as DateTime?,
  );
}

/// 同步结果（每模块）
class CloudSyncReport {
  CloudSyncReport({required this.moduleKey, required this.outcome, this.error});
  final String moduleKey;
  final CloudSyncOutcome outcome;
  final String? error;
}

enum CloudSyncOutcome {
  pulled, // 远端更新，已应用到本地
  pushed, // 本地更新，已上传
  skipped, // 双方一致或本地无变更
  failed,
}

/// 云同步阶段。供活动中心订阅进度用。
enum CloudSyncPhase { idle, preparing, syncing, completed, error }

/// 云同步进度事件（订阅 [CloudSyncService.progressStream]）。
class CloudSyncProgress {
  const CloudSyncProgress({
    required this.phase,
    this.processed = 0,
    this.total = 0,
    this.currentModule,
  });

  final CloudSyncPhase phase;

  /// 已处理模块数。
  final int processed;

  /// 启用的模块总数。
  final int total;

  /// 当前正在同步的模块 key。
  final String? currentModule;

  /// 0..1。准备阶段或总数未知时为 0。
  double get progress => total > 0 ? processed / total : 0;
}

/// 对单个模块执行一次可测试的冲突协调。
///
/// 记录型模块不依赖“整个快照的最大时间戳”决定方向，而是先让模块合并远端
/// 记录，再把合并后的快照写回。这样两台设备各自新增记录时不会互相覆盖。
class CloudSyncModuleReconciler {
  const CloudSyncModuleReconciler({this.maxWriteAttempts = 3})
    : assert(maxWriteAttempts > 0);

  static const _equality = DeepCollectionEquality();
  static const _snapshotUpdatedAtKey = '_syncUpdatedAt';

  final int maxWriteAttempts;

  Future<CloudSyncReport> reconcile({
    required SyncableModule module,
    required CloudSyncBackend backend,
    required Map<String, dynamic> manifest,
    required Map<String, dynamic> manifestUpdates,
  }) async {
    final manifestAt = _manifestUpdatedAt(manifest, module.key);
    final localAt = await module.getLocalUpdatedAt();

    if (module.mergePolicy == SyncMergePolicy.recordMerge) {
      return _reconcileRecords(
        module: module,
        backend: backend,
        manifestUpdates: manifestUpdates,
        localAt: localAt,
        remoteAt: manifestAt,
      );
    }

    return _reconcileSnapshot(
      module: module,
      backend: backend,
      manifestUpdates: manifestUpdates,
      localAt: localAt,
      manifestAt: manifestAt,
    );
  }

  Future<CloudSyncReport> _reconcileSnapshot({
    required SyncableModule module,
    required CloudSyncBackend backend,
    required Map<String, dynamic> manifestUpdates,
    required DateTime? localAt,
    required DateTime? manifestAt,
  }) async {
    var sawWriteConflict = false;
    for (var attempt = 1; attempt <= maxWriteAttempts; attempt++) {
      final remote = await backend.readModuleDocument(module.key);
      if (remote == null && manifestAt != null) {
        throw StateError('manifest 声明 ${module.key} 存在，但远端模块文件缺失');
      }

      final embeddedAt = _documentUpdatedAt(remote?.data);
      final remoteAt = embeddedAt ?? manifestAt;
      if (sawWriteConflict && remote != null && embeddedAt == null) {
        // 旧客户端写出的快照没有自带更新时间。ETag 已证明它在本轮发生了
        // 变化，仅凭旧 manifest 无法判断新内容与本地谁更新，必须停止。
        throw StateError('${module.key} 并发更新缺少内嵌时间，拒绝猜测覆盖方向');
      }
      if (remote != null && remoteAt == null && localAt != null) {
        throw StateError('${module.key} 远端快照缺少更新时间，拒绝以本地数据覆盖');
      }

      if (localAt == null && remote == null) {
        return CloudSyncReport(
          moduleKey: module.key,
          outcome: CloudSyncOutcome.skipped,
        );
      }

      if (remote != null &&
          (localAt == null ||
              (remoteAt != null && remoteAt.isAfter(localAt)))) {
        await module.importData(remote.data, remoteUpdatedAt: remoteAt);
        _repairManifestTimestamp(
          module.key,
          manifestAt: manifestAt,
          documentAt: embeddedAt,
          manifestUpdates: manifestUpdates,
        );
        return CloudSyncReport(
          moduleKey: module.key,
          outcome: CloudSyncOutcome.pulled,
        );
      }

      if (localAt != null &&
          (remote == null || (remoteAt != null && localAt.isAfter(remoteAt)))) {
        final data = Map<String, dynamic>.from(await module.exportData())
          ..[_snapshotUpdatedAtKey] = localAt.millisecondsSinceEpoch;
        if (!await backend.writeModuleIfUnchanged(
          module.key,
          data,
          expected: remote,
        )) {
          sawWriteConflict = true;
          continue;
        }
        manifestUpdates[module.key] = {
          'updatedAt': localAt.millisecondsSinceEpoch,
        };
        return CloudSyncReport(
          moduleKey: module.key,
          outcome: CloudSyncOutcome.pushed,
        );
      }

      if (remote != null && localAt != null && remoteAt == localAt) {
        final local = await module.exportData();
        final remotePayload = Map<String, dynamic>.from(remote.data)
          ..remove(_snapshotUpdatedAtKey);
        if (!_equality.equals(local, remotePayload)) {
          throw StateError('${module.key} 双方时间相同但内容不同，拒绝猜测覆盖方向');
        }
      }
      _repairManifestTimestamp(
        module.key,
        manifestAt: manifestAt,
        documentAt: embeddedAt,
        manifestUpdates: manifestUpdates,
      );
      return CloudSyncReport(
        moduleKey: module.key,
        outcome: CloudSyncOutcome.skipped,
      );
    }

    throw StateError('${module.key} 远端内容持续变化，同步失败');
  }

  DateTime? _documentUpdatedAt(Map<String, dynamic>? data) {
    final value = data?[_snapshotUpdatedAtKey];
    return value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;
  }

  void _repairManifestTimestamp(
    String key, {
    required DateTime? manifestAt,
    required DateTime? documentAt,
    required Map<String, dynamic> manifestUpdates,
  }) {
    if (documentAt != null &&
        (manifestAt == null || manifestAt.isBefore(documentAt))) {
      manifestUpdates[key] = {'updatedAt': documentAt.millisecondsSinceEpoch};
    }
  }

  Future<CloudSyncReport> _reconcileRecords({
    required SyncableModule module,
    required CloudSyncBackend backend,
    required Map<String, dynamic> manifestUpdates,
    required DateTime? localAt,
    required DateTime? remoteAt,
  }) async {
    final localBefore = await module.exportData();
    final remoteDocument = await backend.readModuleDocument(module.key);
    final remoteData = remoteDocument?.data;
    if (remoteDocument == null && remoteAt != null) {
      throw StateError('manifest 声明 ${module.key} 存在，但远端模块文件缺失');
    }

    if (remoteData != null) {
      await module.importData(remoteData, remoteUpdatedAt: remoteAt);
    }
    final merged = await module.exportData();
    final localChanged = !_equality.equals(localBefore, merged);
    final shouldUpload = remoteData == null
        ? localAt != null
        : !_equality.equals(remoteData, merged);

    if (shouldUpload) {
      await _writeMergedSnapshot(
        module: module,
        backend: backend,
        expectedRemote: remoteDocument,
        merged: merged,
      );
      final mergedAt = await module.getLocalUpdatedAt();
      final updatedAt = _nextUpdatedAt(
        localAt: localAt,
        remoteAt: remoteAt,
        mergedAt: mergedAt,
      );
      manifestUpdates[module.key] = {
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };
      return CloudSyncReport(
        moduleKey: module.key,
        outcome: CloudSyncOutcome.pushed,
      );
    }

    // 模块文件写成功但 manifest 写失败后，下次即使快照已经一致，也要修复
    // 过期索引；否则其它设备会继续按旧时间判断方向。
    if (remoteData != null) {
      final mergedAt = await module.getLocalUpdatedAt();
      if (mergedAt != null &&
          (remoteAt == null || remoteAt.isBefore(mergedAt))) {
        manifestUpdates[module.key] = {
          'updatedAt': mergedAt.millisecondsSinceEpoch,
        };
      }
    }
    return CloudSyncReport(
      moduleKey: module.key,
      outcome: localChanged
          ? CloudSyncOutcome.pulled
          : CloudSyncOutcome.skipped,
    );
  }

  Future<Map<String, dynamic>> _writeMergedSnapshot({
    required SyncableModule module,
    required CloudSyncBackend backend,
    required CloudSyncDocument? expectedRemote,
    required Map<String, dynamic> merged,
  }) async {
    var baseline = expectedRemote;
    var next = merged;

    for (var attempt = 1; attempt <= maxWriteAttempts; attempt++) {
      final latest = await backend.readModuleDocument(module.key);
      if (!_sameDocument(latest, baseline)) {
        if (latest != null) await module.importData(latest.data);
        baseline = latest;
        next = await module.exportData();
      }

      final written = await backend.writeModuleIfUnchanged(
        module.key,
        next,
        expected: baseline,
      );
      if (written) return next;

      // ETag 条件写冲突：重新读取并合并另一台设备刚写入的记录。
      final concurrent = await backend.readModuleDocument(module.key);
      if (concurrent != null) await module.importData(concurrent.data);
      baseline = concurrent;
      next = await module.exportData();
    }

    throw StateError('${module.key} 远端内容持续变化，合并写入失败');
  }

  bool _sameDocument(CloudSyncDocument? a, CloudSyncDocument? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.revision != null || b.revision != null) {
      return a.revision == b.revision;
    }
    return _equality.equals(a.data, b.data);
  }

  DateTime? _manifestUpdatedAt(Map<String, dynamic> manifest, String key) {
    final entry = manifest[key];
    if (entry is Map) {
      final updatedAt = entry['updatedAt'];
      if (updatedAt is int) {
        return DateTime.fromMillisecondsSinceEpoch(updatedAt);
      }
    }
    return null;
  }

  DateTime _nextUpdatedAt({
    required DateTime? localAt,
    required DateTime? remoteAt,
    required DateTime? mergedAt,
  }) {
    var next = DateTime.now();
    for (final candidate in [localAt, remoteAt, mergedAt]) {
      if (candidate != null && candidate.isAfter(next)) next = candidate;
    }
    if (remoteAt != null && !next.isAfter(remoteAt)) {
      next = remoteAt.add(const Duration(milliseconds: 1));
    }
    return next;
  }
}

/// 中心同步服务。当前实现 WebDAV 后端。
///
/// 设置型模块按更新时间 last-write-wins；记录型模块始终读取双方快照，调用模块
/// 自身的逐记录合并逻辑后写回并集。远端读取失败会中断对应操作，不会被当成
/// “首次同步”而用本地空/旧数据覆盖。
class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  static const String _boxName = 'cloud_sync_settings';
  static const String _key = 'settings';
  static const String _passwordKey = 'cloud_sync_webdav_password_v1';

  /// 1.1.1 之前已发布的模块 key。用于在升级时把 [CloudSyncSettings.seenModuleKeys]
  /// 一次性补齐到这一基线，避免把用户之前明确不勾选的旧模块"复活"。
  /// 新增模块的 key 不应该出现在这里。
  static const Set<String> _legacyModuleKeys = {
    'music_favorites',
    'music_playlists',
    'music_settings',
    'video_favorites',
    'reading_progress',
    'book_sources',
    'app_settings',
  };

  /// 单模块出错时的最大重试次数。
  static const int _maxRetries = 3;

  static const _reconciler = CloudSyncModuleReconciler(
    maxWriteAttempts: _maxRetries,
  );

  Box<dynamic>? _box;
  CloudSyncSettings _settings = const CloudSyncSettings();
  bool _initialized = false;
  bool _syncing = false;
  bool _passwordPersistedSecurely = true;
  bool _securePasswordReadFailed = false;
  String? _legacyPasswordPendingMigration;

  Future<void> init() async {
    if (_initialized) return;
    _box = await Hive.openBox<dynamic>(_boxName);
    final raw = _box!.get(_key);
    final hadSeenField = raw is Map && raw.containsKey('seenModuleKeys');
    if (raw is Map) {
      _settings = CloudSyncSettings.fromMap(raw);
    }

    final legacyPassword = _settings.password;
    _legacyPasswordPendingMigration = legacyPassword;
    String? securePassword;
    try {
      securePassword = await defaultSecureStorage.read(key: _passwordKey);
      _securePasswordReadFailed = false;
    } on Object catch (e, st) {
      _securePasswordReadFailed = true;
      _passwordPersistedSecurely = false;
      AppError.handle(e, st, 'cloudSync.readSecurePassword');
    }
    if (securePassword?.isNotEmpty ?? false) {
      _passwordPersistedSecurely = true;
      _legacyPasswordPendingMigration = null;
      _settings = _settings.copyWith(password: securePassword);
      if (raw is Map && raw.containsKey('password')) {
        try {
          await _box!.put(_key, _settings.toMap());
        } on Object catch (e, st) {
          AppError.handle(e, st, 'cloudSync.removeLegacyPlaintextPassword');
        }
      }
    } else if (!_securePasswordReadFailed &&
        (legacyPassword?.isNotEmpty ?? false)) {
      // 先验证安全存储确实持久化成功，再删除 Hive 中的旧明文字段。
      // 迁移失败时保留旧值，避免升级后凭证不可恢复。
      try {
        await writeSecureValueVerified(
          defaultSecureStorage,
          key: _passwordKey,
          value: legacyPassword!,
        );
        _passwordPersistedSecurely = true;
        await _box!.put(_key, _settings.toMap());
        _legacyPasswordPendingMigration = null;
      } on Object catch (e, st) {
        _passwordPersistedSecurely = false;
        AppError.handle(e, st, 'cloudSync.migrateLegacyPassword');
      }
    }
    // 旧版本没有 seenModuleKeys 字段：升级时把基线 seed 进去，
    // 这样只有真正新增的模块会被默认启用。
    if (raw is Map && !hadSeenField) {
      _settings = _settings.copyWith(seenModuleKeys: _legacyModuleKeys);
    }
    _initialized = true;
    await _autoEnableNewModules();
  }

  /// 把任何首次出现的已注册模块加入 enabledModuleKeys（默认开启），
  /// 并刷新 seenModuleKeys。已被用户主动取消的不会被恢复。
  Future<void> _autoEnableNewModules() async {
    final registered = CloudSyncRegistry.instance.modules
        .map((m) => m.key)
        .toSet();
    if (registered.isEmpty) return;
    final unseen = registered.difference(_settings.seenModuleKeys);
    if (unseen.isEmpty) return;
    final next = _settings.copyWith(
      enabledModuleKeys: {..._settings.enabledModuleKeys, ...unseen},
      seenModuleKeys: {..._settings.seenModuleKeys, ...registered},
    );
    await applySettings(next);
  }

  CloudSyncSettings get settings => _settings;

  bool get isSyncing => _syncing;

  /// 同步进度流（活动中心订阅）。单例，应用生命周期内常驻，不主动 close。
  final _progressController = StreamController<CloudSyncProgress>.broadcast();
  Stream<CloudSyncProgress> get progressStream => _progressController.stream;

  void _emitProgress(CloudSyncProgress p) {
    if (!_progressController.isClosed) _progressController.add(p);
  }

  Future<void> applySettings(CloudSyncSettings next) async {
    await init();
    final previousPassword = _settings.password;
    final passwordChanged = next.password != previousPassword;
    final shouldPersistPassword =
        passwordChanged ||
        ((next.password?.isNotEmpty ?? false) &&
            !_passwordPersistedSecurely &&
            !_securePasswordReadFailed);
    if (shouldPersistPassword) {
      try {
        final password = next.password;
        if (password == null || password.isEmpty) {
          await defaultSecureStorage.delete(key: _passwordKey);
        } else {
          await writeSecureValueVerified(
            defaultSecureStorage,
            key: _passwordKey,
            value: password,
          );
        }
        _passwordPersistedSecurely = true;
        _securePasswordReadFailed = false;
        _legacyPasswordPendingMigration = null;
      } on Object catch (e, st) {
        _passwordPersistedSecurely = false;
        AppError.handle(e, st, 'cloudSync.persistSecurePassword');
        rethrow;
      }
    }

    try {
      final persisted = next.toMap();
      if (_securePasswordReadFailed &&
          !passwordChanged &&
          (_legacyPasswordPendingMigration?.isNotEmpty ?? false)) {
        // 安全存储读取状态未知时，不能因自动启用新模块等无关设置写入而
        // 删除唯一可恢复的旧凭证；下次启动读取成功后会继续迁移并清除。
        persisted['password'] = _legacyPasswordPendingMigration;
      }
      await _box?.put(_key, persisted);
      _settings = next;
    } on Object catch (e, st) {
      AppError.handle(e, st, 'cloudSync.persistSettings');
      if (shouldPersistPassword) {
        try {
          if (previousPassword == null || previousPassword.isEmpty) {
            await defaultSecureStorage.delete(key: _passwordKey);
          } else {
            await writeSecureValueVerified(
              defaultSecureStorage,
              key: _passwordKey,
              value: previousPassword,
            );
          }
          _passwordPersistedSecurely = true;
        } on Object catch (rollbackError, rollbackStack) {
          _passwordPersistedSecurely = false;
          AppError.handle(
            rollbackError,
            rollbackStack,
            'cloudSync.rollbackSecurePassword',
          );
        }
      }
      rethrow;
    }
  }

  CloudSyncBackend? _buildBackend() {
    if (!_settings.isConfigured) return null;
    return WebDavCloudSyncBackend(
      endpoint: _settings.endpoint!,
      username: _settings.username!,
      password: _settings.password!,
      rootPath: _settings.rootPath,
    );
  }

  /// 触发一次同步。返回每模块结果。
  Future<List<CloudSyncReport>> syncNow() async {
    await init();
    if (_syncing) return const [];
    _syncing = true;
    _emitProgress(const CloudSyncProgress(phase: CloudSyncPhase.preparing));
    final reports = <CloudSyncReport>[];
    try {
      final backend = _buildBackend();
      if (backend == null) {
        _emitProgress(const CloudSyncProgress(phase: CloudSyncPhase.error));
        return [
          CloudSyncReport(
            moduleKey: '*',
            outcome: CloudSyncOutcome.failed,
            error: appL10n.cloudSyncNotConfigured,
          ),
        ];
      }
      final ok = await backend.healthCheck();
      if (!ok) {
        _emitProgress(const CloudSyncProgress(phase: CloudSyncPhase.error));
        return [
          CloudSyncReport(
            moduleKey: '*',
            outcome: CloudSyncOutcome.failed,
            error: appL10n.cloudSyncCannotConnectWebdav,
          ),
        ];
      }
      final modules = CloudSyncRegistry.instance.modules
          .where((m) => _settings.enabledModuleKeys.contains(m.key))
          .toList();
      final manifestUpdates = <String, dynamic>{};
      var processed = 0;
      for (final module in modules) {
        _emitProgress(
          CloudSyncProgress(
            phase: CloudSyncPhase.syncing,
            processed: processed,
            total: modules.length,
            currentModule: module.key,
          ),
        );
        final report = await _syncModule(module, backend, manifestUpdates);
        reports.add(report);
        processed++;
      }

      await _writeManifestUpdates(backend, manifestUpdates);
      final hasFailures = reports.any(
        (report) => report.outcome == CloudSyncOutcome.failed,
      );
      if (!hasFailures) {
        await applySettings(_settings.copyWith(lastSyncedAt: DateTime.now()));
      }
      _emitProgress(
        CloudSyncProgress(
          phase: hasFailures ? CloudSyncPhase.error : CloudSyncPhase.completed,
          processed: processed,
          total: modules.length,
        ),
      );
    } on Object catch (e, st) {
      AppError.handle(e, st, 'cloudSync.syncNow');
      reports.add(
        CloudSyncReport(
          moduleKey: '*',
          outcome: CloudSyncOutcome.failed,
          error: e.toString(),
        ),
      );
      _emitProgress(const CloudSyncProgress(phase: CloudSyncPhase.error));
    } finally {
      _syncing = false;
    }
    return reports;
  }

  Future<CloudSyncReport> _syncModule(
    SyncableModule module,
    CloudSyncBackend backend,
    Map<String, dynamic> manifestUpdates,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        // 每次尝试都重读 manifest，避免整轮同步开始后另一台设备已更新，
        // 本机仍按过期时间戳决定方向。
        final manifest = await backend.readManifest();
        return await _reconciler.reconcile(
          module: module,
          backend: backend,
          manifest: manifest,
          manifestUpdates: manifestUpdates,
        );
      }
      // catch Object 而非 Exception：模块解析远端数据时的类型错误是 TypeError
      // （Error 不是 Exception），只 catch Exception 会让单个模块的坏数据
      // 逃出这里、跳过后续模块和 writeManifest，整轮同步中断。
      on Object catch (e, st) {
        lastError = e;
        AppError.handle(e, st, 'cloudSync.${module.key}.attempt$attempt');
        if (attempt < _maxRetries) {
          await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
        }
      }
    }
    return CloudSyncReport(
      moduleKey: module.key,
      outcome: CloudSyncOutcome.failed,
      error: lastError?.toString(),
    );
  }

  Future<void> _writeManifestUpdates(
    CloudSyncBackend backend,
    Map<String, dynamic> updates,
  ) async {
    if (updates.isEmpty) return;
    const equality = DeepCollectionEquality();

    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      final baseline = await backend.readManifestDocument();
      final merged = Map<String, dynamic>.from(
        baseline?.data ?? const <String, dynamic>{},
      );
      for (final entry in updates.entries) {
        final existingAt = _manifestTimestamp(merged[entry.key]);
        final updateAt = _manifestTimestamp(entry.value);
        if (existingAt == null ||
            updateAt == null ||
            !existingAt.isAfter(updateAt)) {
          merged[entry.key] = entry.value;
        }
      }

      if (!await backend.writeManifestIfUnchanged(merged, expected: baseline)) {
        continue;
      }
      final verified = await backend.readManifest();
      final preserved = merged.entries.every((entry) {
        final expectedAt = _manifestTimestamp(entry.value);
        final actualAt = _manifestTimestamp(verified[entry.key]);
        if (expectedAt != null && actualAt != null) {
          return !actualAt.isBefore(expectedAt);
        }
        return equality.equals(verified[entry.key], entry.value);
      });
      if (preserved) return;
    }

    throw StateError('云同步 manifest 持续变化，写入失败');
  }

  DateTime? _manifestTimestamp(Object? entry) {
    if (entry is! Map) return null;
    final value = entry['updatedAt'];
    return value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;
  }

  /// 健康检查：用户在设置页点「测试连接」时调
  Future<bool> testConnection() async {
    final backend = _buildBackend();
    if (backend == null) return false;
    return backend.healthCheck();
  }
}
