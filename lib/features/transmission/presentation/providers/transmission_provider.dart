import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:my_nas/service_adapters/transmission/api/transmission_api.dart';
import 'package:my_nas/service_adapters/transmission/transmission_adapter.dart';

/// Transmission 服务连接状态
class TransmissionConnection {
  const TransmissionConnection({
    required this.source,
    required this.adapter,
    this.status = TransmissionConnectionStatus.disconnected,
    this.errorMessage,
  });

  final SourceEntity source;
  final TransmissionAdapter adapter;
  final TransmissionConnectionStatus status;
  final String? errorMessage;

  TransmissionConnection copyWith({
    SourceEntity? source,
    TransmissionAdapter? adapter,
    TransmissionConnectionStatus? status,
    String? errorMessage,
  }) =>
      TransmissionConnection(
        source: source ?? this.source,
        adapter: adapter ?? this.adapter,
        status: status ?? this.status,
        errorMessage: errorMessage,
      );
}

/// 连接状态枚举
enum TransmissionConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Transmission 连接管理 Provider
final transmissionConnectionProvider = StateNotifierProvider.family<
    TransmissionConnectionNotifier, TransmissionConnection?, String>(
  (ref, sourceId) => TransmissionConnectionNotifier(sourceId),
);

class TransmissionConnectionNotifier
    extends StateNotifier<TransmissionConnection?> {
  TransmissionConnectionNotifier(this.sourceId) : super(null);

  final String sourceId;

  /// 连接到 Transmission
  Future<TransmissionConnection> connect(
    SourceEntity source, {
    String? password,
  }) async {
    logger.i('TransmissionProvider: 连接到 ${source.name}');

    final adapter = TransmissionAdapter();

    // 更新状态为连接中
    state = TransmissionConnection(
      source: source,
      adapter: adapter,
      status: TransmissionConnectionStatus.connecting,
    );

    final config = ServiceConnectionConfig.fromSource(source, password: password);

    try {
      final result = await adapter.connect(config);

      final connection = result.when(
        success: (_) => TransmissionConnection(
          source: source,
          adapter: adapter,
          status: TransmissionConnectionStatus.connected,
        ),
        failure: (error) => TransmissionConnection(
          source: source,
          adapter: adapter,
          status: TransmissionConnectionStatus.error,
          errorMessage: error,
        ),
      );

      state = connection;
      return connection;
    } on Exception catch (e) {
      final connection = TransmissionConnection(
        source: source,
        adapter: adapter,
        status: TransmissionConnectionStatus.error,
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
      logger.i('TransmissionProvider: 断开连接 $sourceId');
    }
  }

  /// 获取适配器
  TransmissionAdapter? get adapter => state?.adapter;
}

/// Transmission 会话统计 Provider
final transmissionSessionStatsProvider = FutureProvider.family
    .autoDispose<TransmissionSessionStats?, String>((ref, sourceId) async {
  final connection = ref.watch(transmissionConnectionProvider(sourceId));
  if (connection == null ||
      connection.status != TransmissionConnectionStatus.connected) {
    return null;
  }

  try {
    return await connection.adapter.getSessionStats();
  } on Exception catch (e) {
    logger.e('TransmissionProvider: 获取会话统计失败', e);
    return null;
  }
});

/// Transmission Torrent 列表 Provider
final transmissionTorrentsProvider = FutureProvider.family
    .autoDispose<List<TransmissionTorrent>, String>((ref, sourceId) async {
  final connection = ref.watch(transmissionConnectionProvider(sourceId));
  if (connection == null ||
      connection.status != TransmissionConnectionStatus.connected) {
    return [];
  }

  try {
    return await connection.adapter.getTorrents();
  } on Exception catch (e) {
    logger.e('TransmissionProvider: 获取 Torrent 列表失败', e);
    return [];
  }
});

/// 自动刷新的 Torrent 列表 Provider
class TransmissionAutoRefreshNotifier extends StateNotifier<List<TransmissionTorrent>> {
  TransmissionAutoRefreshNotifier(this._ref, this._sourceId) : super([]) {
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
    final connection = _ref.read(transmissionConnectionProvider(_sourceId));
    if (connection == null ||
        connection.status != TransmissionConnectionStatus.connected) {
      return;
    }

    try {
      final torrents = await connection.adapter.getTorrents();
      if (mounted) {
        state = torrents;
      }
    } on Exception catch (e) {
      logger.e('TransmissionAutoRefresh: 刷新失败', e);
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

final transmissionAutoRefreshProvider = StateNotifierProvider.family
    .autoDispose<TransmissionAutoRefreshNotifier, List<TransmissionTorrent>, String>(
  TransmissionAutoRefreshNotifier.new,
);

/// 自动刷新的会话统计 Provider
class TransmissionStatsAutoRefreshNotifier extends StateNotifier<TransmissionSessionStats?> {
  TransmissionStatsAutoRefreshNotifier(this._ref, this._sourceId) : super(null) {
    _startAutoRefresh();
  }

  final Ref _ref;
  final String _sourceId;
  Timer? _timer;

  void _startAutoRefresh() {
    // 立即获取一次
    _refresh();
    // 每 2 秒刷新一次
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final connection = _ref.read(transmissionConnectionProvider(_sourceId));
    if (connection == null ||
        connection.status != TransmissionConnectionStatus.connected) {
      return;
    }

    try {
      final stats = await connection.adapter.getSessionStats();
      if (mounted) {
        state = stats;
      }
    } on Exception catch (e) {
      logger.e('TransmissionStatsAutoRefresh: 刷新失败', e);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final transmissionStatsAutoRefreshProvider = StateNotifierProvider.family
    .autoDispose<TransmissionStatsAutoRefreshNotifier, TransmissionSessionStats?, String>(
  TransmissionStatsAutoRefreshNotifier.new,
);

/// Torrent 操作 Provider
final transmissionActionsProvider =
    Provider.family<TransmissionActions, String>(TransmissionActions.new);

class TransmissionActions {
  TransmissionActions(this._ref, this._sourceId);

  final Ref _ref;
  final String _sourceId;

  TransmissionAdapter? get _adapter =>
      _ref.read(transmissionConnectionProvider(_sourceId))?.adapter;

  void _invalidate() {
    _ref.invalidate(transmissionAutoRefreshProvider(_sourceId));
  }

  /// 开始 Torrent
  Future<void> start(List<int> ids) async {
    final adapter = _adapter;
    if (adapter == null) return;

    await adapter.startTorrents(ids);
    _invalidate();
  }

  /// 开始所有 Torrent
  Future<void> startAll() async {
    final adapter = _adapter;
    if (adapter == null) return;

    await adapter.startAllTorrents();
    _invalidate();
  }

  /// 停止 Torrent
  Future<void> stop(List<int> ids) async {
    final adapter = _adapter;
    if (adapter == null) return;

    await adapter.stopTorrents(ids);
    _invalidate();
  }

  /// 停止所有 Torrent
  Future<void> stopAll() async {
    final adapter = _adapter;
    if (adapter == null) return;

    await adapter.stopAllTorrents();
    _invalidate();
  }

  /// 删除 Torrent
  Future<void> remove(List<int> ids, {bool deleteFiles = false}) async {
    final adapter = _adapter;
    if (adapter == null) return;

    await adapter.removeTorrents(ids, deleteFiles: deleteFiles);
    _invalidate();
  }

  /// 验证 Torrent 数据
  Future<void> verify(List<int> ids) async {
    final adapter = _adapter;
    if (adapter == null) return;

    await adapter.verifyTorrents(ids);
    _invalidate();
  }

  /// 添加 Torrent（通过 URL 或 Magnet 链接）
  Future<TransmissionTorrentAdded> addTorrent(
    String url, {
    String? downloadDir,
    bool paused = false,
  }) async {
    final adapter = _adapter;
    if (adapter == null) {
      throw Exception(appL10n.transmissionProviderNotConnectedError);
    }

    final result = await adapter.addTorrent(
      url,
      downloadDir: downloadDir,
      paused: paused,
    );
    _invalidate();
    return result;
  }
}

/// Torrent 排序方式
enum TransmissionSortMode {
  name('name', '名称'),
  size('totalSize', '大小'),
  progress('percentDone', '进度'),
  status('status', '状态'),
  dlSpeed('rateDownload', '下载速度'),
  upSpeed('rateUpload', '上传速度'),
  addedOn('addedDate', '添加时间'),
  ratio('uploadRatio', '分享率'),
  uploaded('uploadedEver', '总上传量');

  const TransmissionSortMode(this.value, this.label);

  final String value;
  final String label;
}

/// 排序设置 Provider
class TransmissionSortSettingsNotifier extends StateNotifier<TransmissionSortSettings> {
  TransmissionSortSettingsNotifier() : super(const TransmissionSortSettings());

  void setSortMode(TransmissionSortMode mode) {
    state = state.copyWith(sortMode: mode);
  }

  void toggleReverse() {
    state = state.copyWith(reverse: !state.reverse);
  }

  void setFilterStatus(TransmissionTorrentStatus? status) {
    state = state.copyWith(filterStatus: status, clearStatus: status == null);
  }
}

class TransmissionSortSettings {
  const TransmissionSortSettings({
    this.sortMode = TransmissionSortMode.addedOn,
    this.reverse = true,
    this.filterStatus,
  });

  final TransmissionSortMode sortMode;
  final bool reverse;
  final TransmissionTorrentStatus? filterStatus;

  TransmissionSortSettings copyWith({
    TransmissionSortMode? sortMode,
    bool? reverse,
    TransmissionTorrentStatus? filterStatus,
    bool clearStatus = false,
  }) =>
      TransmissionSortSettings(
        sortMode: sortMode ?? this.sortMode,
        reverse: reverse ?? this.reverse,
        filterStatus: clearStatus ? null : (filterStatus ?? this.filterStatus),
      );
}

final transmissionSortSettingsProvider = StateNotifierProvider.family<
    TransmissionSortSettingsNotifier, TransmissionSortSettings, String>(
  (ref, sourceId) => TransmissionSortSettingsNotifier(),
);
