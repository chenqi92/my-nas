import 'dart:async';

import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/sync/cloud_sync_backend.dart';
import 'package:my_nas/core/sync/syncable_module.dart';

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

  factory CloudSyncSettings.fromMap(Map<dynamic, dynamic> m) =>
      CloudSyncSettings(
        endpoint: m['endpoint'] as String?,
        username: m['username'] as String?,
        password: m['password'] as String?,
        rootPath: (m['rootPath'] as String?) ?? '/my-nas-sync',
        enabledModuleKeys: ((m['enabledModuleKeys'] as List?) ?? const [])
            .cast<String>()
            .toSet(),
        seenModuleKeys: ((m['seenModuleKeys'] as List?) ?? const [])
            .cast<String>()
            .toSet(),
        lastSyncedAt: m['lastSyncedAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(m['lastSyncedAt'] as int)
            : null,
      );

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
    if (password != null) 'password': password,
    'rootPath': rootPath,
    'enabledModuleKeys': enabledModuleKeys.toList(),
    'seenModuleKeys': seenModuleKeys.toList(),
    if (lastSyncedAt != null)
      'lastSyncedAt': lastSyncedAt!.millisecondsSinceEpoch,
  };

  CloudSyncSettings copyWith({
    Object? endpoint = const Object(),
    Object? username = const Object(),
    Object? password = const Object(),
    String? rootPath,
    Set<String>? enabledModuleKeys,
    Set<String>? seenModuleKeys,
    Object? lastSyncedAt = const Object(),
  }) => CloudSyncSettings(
    endpoint: identical(endpoint, const Object())
        ? this.endpoint
        : endpoint as String?,
    username: identical(username, const Object())
        ? this.username
        : username as String?,
    password: identical(password, const Object())
        ? this.password
        : password as String?,
    rootPath: rootPath ?? this.rootPath,
    enabledModuleKeys: enabledModuleKeys ?? this.enabledModuleKeys,
    seenModuleKeys: seenModuleKeys ?? this.seenModuleKeys,
    lastSyncedAt: identical(lastSyncedAt, const Object())
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

/// 中心同步服务。当前实现 WebDAV 后端。
///
/// 同步流程：
/// 1. healthCheck → 失败直接返回
/// 2. 读 manifest.json
/// 3. 对每个 enabled module:
///    - 比较 local.updatedAt 与 manifest[key].updatedAt
///    - local 更新 → exportData 上传 + manifest 更新
///    - remote 更新 → readModule + importData
///    - 一致 → skip
/// 4. 写回 manifest.json
class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  static const String _boxName = 'cloud_sync_settings';
  static const String _key = 'settings';

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

  Box<dynamic>? _box;
  CloudSyncSettings _settings = const CloudSyncSettings();
  bool _initialized = false;
  bool _syncing = false;

  Future<void> init() async {
    if (_initialized) return;
    _box = await Hive.openBox<dynamic>(_boxName);
    final raw = _box!.get(_key);
    final hadSeenField = raw is Map && raw.containsKey('seenModuleKeys');
    if (raw is Map) {
      _settings = CloudSyncSettings.fromMap(raw);
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
    _settings = next;
    await _box?.put(_key, next.toMap());
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
      final manifest = await backend.readManifest();
      final newManifest = Map<String, dynamic>.from(manifest);

      final modules = CloudSyncRegistry.instance.modules
          .where((m) => _settings.enabledModuleKeys.contains(m.key))
          .toList();
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
        final report = await _syncModule(
          module,
          backend,
          manifest,
          newManifest,
        );
        reports.add(report);
        processed++;
      }

      await backend.writeManifest(newManifest);
      await applySettings(_settings.copyWith(lastSyncedAt: DateTime.now()));
      _emitProgress(
        CloudSyncProgress(
          phase: CloudSyncPhase.completed,
          processed: processed,
          total: modules.length,
        ),
      );
    } finally {
      _syncing = false;
    }
    return reports;
  }

  Future<CloudSyncReport> _syncModule(
    SyncableModule module,
    CloudSyncBackend backend,
    Map<String, dynamic> manifest,
    Map<String, dynamic> newManifest,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        return await _syncModuleOnce(module, backend, manifest, newManifest);
      } on Exception catch (e, st) {
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

  Future<CloudSyncReport> _syncModuleOnce(
    SyncableModule module,
    CloudSyncBackend backend,
    Map<String, dynamic> manifest,
    Map<String, dynamic> newManifest,
  ) async {
    final remoteEntry = manifest[module.key];
    DateTime? remoteAt;
    if (remoteEntry is Map && remoteEntry['updatedAt'] is int) {
      remoteAt = DateTime.fromMillisecondsSinceEpoch(
        remoteEntry['updatedAt'] as int,
      );
    }
    final localAt = await module.getLocalUpdatedAt();

    if (localAt == null && remoteAt == null) {
      return CloudSyncReport(
        moduleKey: module.key,
        outcome: CloudSyncOutcome.skipped,
      );
    }

    if (remoteAt != null && (localAt == null || remoteAt.isAfter(localAt))) {
      // 远端更新 → 拉取
      final data = await backend.readModule(module.key);
      if (data != null) {
        await module.importData(data);
        newManifest[module.key] = {
          'updatedAt': remoteAt.millisecondsSinceEpoch,
        };
        return CloudSyncReport(
          moduleKey: module.key,
          outcome: CloudSyncOutcome.pulled,
        );
      }
    }

    if (localAt != null && (remoteAt == null || localAt.isAfter(remoteAt))) {
      // 本地更新 → 推送
      final data = await module.exportData();
      await backend.writeModule(module.key, data);
      newManifest[module.key] = {'updatedAt': localAt.millisecondsSinceEpoch};
      return CloudSyncReport(
        moduleKey: module.key,
        outcome: CloudSyncOutcome.pushed,
      );
    }

    // 一致 → 保留 manifest
    if (remoteAt != null) {
      newManifest[module.key] = {'updatedAt': remoteAt.millisecondsSinceEpoch};
    }
    return CloudSyncReport(
      moduleKey: module.key,
      outcome: CloudSyncOutcome.skipped,
    );
  }

  /// 健康检查：用户在设置页点「测试连接」时调
  Future<bool> testConnection() async {
    final backend = _buildBackend();
    if (backend == null) return false;
    return backend.healthCheck();
  }
}
