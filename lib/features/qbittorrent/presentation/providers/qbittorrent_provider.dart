import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:my_nas/service_adapters/qbittorrent/api/qbittorrent_api.dart';
import 'package:my_nas/service_adapters/qbittorrent/qbittorrent_adapter.dart';

/// qBittorrent 服务连接状态
class QBittorrentConnection {
  const QBittorrentConnection({
    required this.source,
    required this.adapter,
    this.status = QBConnectionStatus.disconnected,
    this.errorMessage,
  });

  final SourceEntity source;
  final QBittorrentAdapter adapter;
  final QBConnectionStatus status;
  final String? errorMessage;

  QBittorrentConnection copyWith({
    SourceEntity? source,
    QBittorrentAdapter? adapter,
    QBConnectionStatus? status,
    String? errorMessage,
  }) => QBittorrentConnection(
    source: source ?? this.source,
    adapter: adapter ?? this.adapter,
    status: status ?? this.status,
    errorMessage: errorMessage,
  );
}

/// 连接状态枚举
enum QBConnectionStatus { disconnected, connecting, connected, error }

/// qBittorrent 连接管理 Provider
final qbittorrentConnectionProvider =
    StateNotifierProvider.family<
      QBittorrentConnectionNotifier,
      QBittorrentConnection?,
      String
    >(QBittorrentConnectionNotifier.new);

class QBittorrentConnectionNotifier
    extends StateNotifier<QBittorrentConnection?> {
  QBittorrentConnectionNotifier(this._ref, this.sourceId) : super(null);

  final Ref _ref;
  final String sourceId;

  /// 连接到 qBittorrent
  Future<QBittorrentConnection> connect(
    SourceEntity source, {
    String? password,
  }) async {
    logger.i('QBittorrentProvider: 连接到 ${source.name}');

    final adapter = QBittorrentAdapter();

    // 更新状态为连接中
    state = QBittorrentConnection(
      source: source,
      adapter: adapter,
      status: QBConnectionStatus.connecting,
    );

    final storedPassword =
        password ??
        (await _ref.read(sourceManagerProvider).getCredential(source.id))
            ?.password;
    final config = ServiceConnectionConfig.fromSource(
      source,
      password: storedPassword,
    );

    try {
      final result = await adapter.connect(config);

      final connection = result.when(
        success: (_) => QBittorrentConnection(
          source: source,
          adapter: adapter,
          status: QBConnectionStatus.connected,
        ),
        failure: (error) => QBittorrentConnection(
          source: source,
          adapter: adapter,
          status: QBConnectionStatus.error,
          errorMessage: error,
        ),
      );

      state = connection;
      return connection;
    } on Exception catch (e) {
      final connection = QBittorrentConnection(
        source: source,
        adapter: adapter,
        status: QBConnectionStatus.error,
        errorMessage: e.toString(),
      );
      state = connection;
      return connection;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    final connection = state;
    if (connection != null) {
      await connection.adapter.disconnect();
      state = null;
      logger.i('QBittorrentProvider: 断开连接 $sourceId');
    }
  }

  /// 获取适配器
  QBittorrentAdapter? get adapter => state?.adapter;
}

/// qBittorrent 下载统计 Provider
final qbittorrentStatsProvider = FutureProvider.family
    .autoDispose<QBDownloadStats?, String>((ref, sourceId) async {
      final connection = ref.watch(qbittorrentConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != QBConnectionStatus.connected) {
        return null;
      }

      try {
        return await connection.adapter.getDownloadStats();
      } on Exception catch (e) {
        logger.e('QBittorrentProvider: 获取下载统计失败', e);
        return null;
      }
    });

/// qBittorrent Torrent 列表 Provider
final qbittorrentTorrentsProvider = FutureProvider.family
    .autoDispose<List<QBTorrent>, String>((ref, sourceId) async {
      final connection = ref.watch(qbittorrentConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != QBConnectionStatus.connected) {
        return [];
      }

      try {
        return await connection.adapter.getTorrents();
      } on Exception catch (e) {
        logger.e('QBittorrentProvider: 获取 Torrent 列表失败', e);
        return [];
      }
    });

/// qBittorrent 传输信息 Provider（实时速度等）
final qbittorrentTransferInfoProvider = FutureProvider.family
    .autoDispose<QBTransferInfo?, String>((ref, sourceId) async {
      final connection = ref.watch(qbittorrentConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != QBConnectionStatus.connected) {
        return null;
      }

      try {
        return await connection.adapter.getTransferInfo();
      } on Exception catch (e) {
        logger.e('QBittorrentProvider: 获取传输信息失败', e);
        return null;
      }
    });

/// 自动刷新的 Torrent 列表 Provider
class QBittorrentAutoRefreshNotifier extends StateNotifier<List<QBTorrent>> {
  QBittorrentAutoRefreshNotifier(this._ref, this._sourceId) : super([]) {
    _startAutoRefresh();
  }

  final Ref _ref;
  final String _sourceId;
  Timer? _timer;

  void _startAutoRefresh() {
    // 立即获取一次
    _refresh();
    // 每 3 秒刷新一次
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final connection = _ref.read(qbittorrentConnectionProvider(_sourceId));
    if (connection == null ||
        connection.status != QBConnectionStatus.connected) {
      return;
    }

    try {
      final torrents = await connection.adapter.getTorrents();
      if (mounted) {
        state = torrents;
      }
    } on Exception catch (e) {
      logger.e('QBittorrentAutoRefresh: 刷新失败', e);
    }
  }

  /// 手动刷新
  Future<void> refresh() => _refresh();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final qbittorrentAutoRefreshProvider = StateNotifierProvider.family
    .autoDispose<QBittorrentAutoRefreshNotifier, List<QBTorrent>, String>(
      QBittorrentAutoRefreshNotifier.new,
    );

/// 自动刷新的传输信息 Provider
class QBTransferInfoAutoRefreshNotifier extends StateNotifier<QBTransferInfo?> {
  QBTransferInfoAutoRefreshNotifier(this._ref, this._sourceId) : super(null) {
    _startAutoRefresh();
  }

  final Ref _ref;
  final String _sourceId;
  Timer? _timer;

  void _startAutoRefresh() {
    // 立即获取一次
    _refresh();
    // 每 2 秒刷新一次（速度信息需要更频繁更新）
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final connection = _ref.read(qbittorrentConnectionProvider(_sourceId));
    if (connection == null ||
        connection.status != QBConnectionStatus.connected) {
      return;
    }

    try {
      final info = await connection.adapter.getTransferInfo();
      if (mounted) {
        state = info;
      }
    } on Exception catch (e) {
      logger.e('QBTransferInfoAutoRefresh: 刷新失败', e);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final qbTransferInfoAutoRefreshProvider = StateNotifierProvider.family
    .autoDispose<QBTransferInfoAutoRefreshNotifier, QBTransferInfo?, String>(
      QBTransferInfoAutoRefreshNotifier.new,
    );

/// Torrent 操作 Provider
final qbittorrentActionsProvider = Provider.family<QBittorrentActions, String>(
  QBittorrentActions.new,
);

class QBittorrentActions {
  QBittorrentActions(this._ref, this._sourceId);

  final Ref _ref;
  final String _sourceId;

  QBittorrentAdapter? get _adapter =>
      _ref.read(qbittorrentConnectionProvider(_sourceId))?.adapter;

  QBittorrentAdapter _requireAdapter() {
    final adapter = _adapter;
    if (adapter == null) {
      throw Exception(appL10n.qbittorrentAdapterNotConnected);
    }
    return adapter;
  }

  void _invalidate() {
    _ref.invalidate(qbittorrentAutoRefreshProvider(_sourceId));
  }

  /// 暂停 Torrent
  Future<void> pause(List<String> hashes) async {
    final adapter = _requireAdapter();

    await adapter.pauseTorrents(hashes);
    _invalidate();
  }

  /// 暂停所有 Torrent
  Future<void> pauseAll() async {
    final adapter = _requireAdapter();

    await adapter.pauseAllTorrents();
    _invalidate();
  }

  /// 恢复 Torrent
  Future<void> resume(List<String> hashes) async {
    final adapter = _requireAdapter();

    await adapter.resumeTorrents(hashes);
    _invalidate();
  }

  /// 恢复所有 Torrent
  Future<void> resumeAll() async {
    final adapter = _requireAdapter();

    await adapter.resumeAllTorrents();
    _invalidate();
  }

  /// 删除 Torrent
  Future<void> delete(List<String> hashes, {bool deleteFiles = false}) async {
    final adapter = _requireAdapter();

    await adapter.deleteTorrents(hashes, deleteFiles: deleteFiles);
    _invalidate();
  }

  /// 添加 Torrent（通过 URL 或 Magnet 链接）
  Future<void> addTorrent(
    String url, {
    String? savePath,
    String? category,
    bool paused = false,
  }) async {
    final adapter = _requireAdapter();

    await adapter.addTorrent(
      url,
      savePath: savePath,
      category: category,
      paused: paused,
    );
    _invalidate();
  }

  /// 重命名 Torrent
  Future<void> rename(String hash, String name) async {
    final adapter = _requireAdapter();

    await adapter.renameTorrent(hash, name);
    _invalidate();
  }

  /// 设置 Torrent 保存位置
  Future<void> setLocation(List<String> hashes, String location) async {
    final adapter = _requireAdapter();

    await adapter.setTorrentLocation(hashes, location);
    _invalidate();
  }

  /// 设置 Torrent 分类
  Future<void> setCategory(List<String> hashes, String category) async {
    final adapter = _requireAdapter();

    await adapter.setTorrentCategory(hashes, category);
    _invalidate();
  }

  /// 添加标签到 Torrent
  Future<void> addTags(List<String> hashes, List<String> tags) async {
    final adapter = _requireAdapter();

    await adapter.addTorrentTags(hashes, tags);
    _invalidate();
  }

  /// 从 Torrent 移除标签
  Future<void> removeTags(List<String> hashes, List<String> tags) async {
    final adapter = _requireAdapter();

    await adapter.removeTorrentTags(hashes, tags);
    _invalidate();
  }

  /// 切换备用速度限制
  Future<void> toggleAlternativeSpeedLimits() async {
    final adapter = _requireAdapter();

    await adapter.toggleAlternativeSpeedLimits();
    _ref
      ..invalidate(qbPreferencesProvider(_sourceId))
      ..invalidate(qbTransferInfoAutoRefreshProvider(_sourceId));
  }

  /// 设置全局限速
  Future<void> setGlobalSpeedLimits({int? dlLimit, int? upLimit}) async {
    final adapter = _requireAdapter();

    await adapter.setGlobalSpeedLimits(dlLimit: dlLimit, upLimit: upLimit);
    _ref.invalidate(qbPreferencesProvider(_sourceId));
  }

  /// 设置备用速度限速
  Future<void> setAlternativeSpeedLimits({int? dlLimit, int? upLimit}) async {
    final adapter = _requireAdapter();

    await adapter.setAlternativeSpeedLimits(dlLimit: dlLimit, upLimit: upLimit);
    _ref.invalidate(qbPreferencesProvider(_sourceId));
  }

  /// 创建分类
  Future<void> createCategory(String category, {String? savePath}) async {
    final adapter = _requireAdapter();

    await adapter.createCategory(category, savePath: savePath);
    _ref.invalidate(qbCategoriesProvider(_sourceId));
  }

  /// 创建标签
  Future<void> createTags(List<String> tags) async {
    final adapter = _requireAdapter();

    await adapter.createTags(tags);
    _ref.invalidate(qbTagsProvider(_sourceId));
  }
}

/// qBittorrent 分类 Provider
final qbCategoriesProvider = FutureProvider.family
    .autoDispose<Map<String, QBCategory>, String>((ref, sourceId) async {
      final connection = ref.watch(qbittorrentConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != QBConnectionStatus.connected) {
        return {};
      }

      try {
        return await connection.adapter.getCategories();
      } on Exception catch (e) {
        logger.e('QBittorrentProvider: 获取分类失败', e);
        return {};
      }
    });

/// qBittorrent 标签 Provider
final qbTagsProvider = FutureProvider.family.autoDispose<List<String>, String>((
  ref,
  sourceId,
) async {
  final connection = ref.watch(qbittorrentConnectionProvider(sourceId));
  if (connection == null || connection.status != QBConnectionStatus.connected) {
    return [];
  }

  try {
    return await connection.adapter.getTags();
  } on Exception catch (e) {
    logger.e('QBittorrentProvider: 获取标签失败', e);
    return [];
  }
});

/// qBittorrent 偏好设置 Provider
final qbPreferencesProvider = FutureProvider.family
    .autoDispose<QBPreferences?, String>((ref, sourceId) async {
      final connection = ref.watch(qbittorrentConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != QBConnectionStatus.connected) {
        return null;
      }

      try {
        return await connection.adapter.getPreferences();
      } on Exception catch (e) {
        logger.e('QBittorrentProvider: 获取偏好设置失败', e);
        return null;
      }
    });

/// qBittorrent 单个 Torrent 的文件列表 Provider（key = (sourceId, hash)）。
final qbTorrentFilesProvider = FutureProvider.autoDispose
    .family<List<QBTorrentFile>, (String, String)>((ref, key) async {
      final (sourceId, hash) = key;
      final connection = ref.watch(qbittorrentConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != QBConnectionStatus.connected) {
        return const [];
      }
      try {
        return await connection.adapter.getTorrentFiles(hash);
      } on Exception catch (e) {
        logger.e('QBittorrentProvider: 获取文件列表失败', e);
        return const [];
      }
    });

/// Torrent 排序方式
enum QBSortMode {
  name('name', '名称'),
  size('size', '大小'),
  progress('progress', '进度'),
  state('state', '状态'),
  dlSpeed('dlspeed', '下载速度'),
  upSpeed('upspeed', '上传速度'),
  addedOn('added_on', '添加时间'),
  ratio('ratio', '分享率'),
  eta('eta', '剩余时间'),
  uploaded('uploaded', '总上传量');

  const QBSortMode(this.value, this.label);

  final String value;
  final String label;
}

/// 排序设置 Provider
class QBSortSettingsNotifier extends StateNotifier<QBSortSettings> {
  QBSortSettingsNotifier() : super(const QBSortSettings());

  void setSortMode(QBSortMode mode) {
    state = state.copyWith(sortMode: mode);
  }

  void toggleReverse() {
    state = state.copyWith(reverse: !state.reverse);
  }

  void setFilterCategory(String? category) {
    state = state.copyWith(
      filterCategory: category,
      clearCategory: category == null,
    );
  }

  void setFilterTag(String? tag) {
    state = state.copyWith(filterTag: tag, clearTag: tag == null);
  }
}

class QBSortSettings {
  const QBSortSettings({
    this.sortMode = QBSortMode.addedOn,
    this.reverse = true,
    this.filterCategory,
    this.filterTag,
  });

  final QBSortMode sortMode;
  final bool reverse;
  final String? filterCategory;
  final String? filterTag;

  QBSortSettings copyWith({
    QBSortMode? sortMode,
    bool? reverse,
    String? filterCategory,
    String? filterTag,
    bool clearCategory = false,
    bool clearTag = false,
  }) => QBSortSettings(
    sortMode: sortMode ?? this.sortMode,
    reverse: reverse ?? this.reverse,
    filterCategory: clearCategory
        ? null
        : (filterCategory ?? this.filterCategory),
    filterTag: clearTag ? null : (filterTag ?? this.filterTag),
  );
}

final qbSortSettingsProvider =
    StateNotifierProvider.family<
      QBSortSettingsNotifier,
      QBSortSettings,
      String
    >((ref, sourceId) => QBSortSettingsNotifier());
