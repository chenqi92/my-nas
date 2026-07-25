import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/service_adapters/aria2/api/aria2_api.dart';
import 'package:my_nas/service_adapters/aria2/aria2_adapter.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';

/// Aria2 服务连接状态
class Aria2Connection {
  const Aria2Connection({
    required this.source,
    required this.adapter,
    this.status = Aria2ConnectionStatus.disconnected,
    this.errorMessage,
  });

  final SourceEntity source;
  final Aria2Adapter adapter;
  final Aria2ConnectionStatus status;
  final String? errorMessage;

  Aria2Connection copyWith({
    SourceEntity? source,
    Aria2Adapter? adapter,
    Aria2ConnectionStatus? status,
    String? errorMessage,
  }) => Aria2Connection(
    source: source ?? this.source,
    adapter: adapter ?? this.adapter,
    status: status ?? this.status,
    errorMessage: errorMessage,
  );
}

/// 连接状态枚举
enum Aria2ConnectionStatus { disconnected, connecting, connected, error }

/// Aria2 连接管理 Provider
final aria2ConnectionProvider =
    StateNotifierProvider.family<
      Aria2ConnectionNotifier,
      Aria2Connection?,
      String
    >(Aria2ConnectionNotifier.new);

class Aria2ConnectionNotifier extends StateNotifier<Aria2Connection?> {
  Aria2ConnectionNotifier(this._ref, this.sourceId) : super(null);

  final Ref _ref;
  final String sourceId;

  /// 连接到 Aria2
  Future<Aria2Connection> connect(
    SourceEntity source, {
    String? rpcSecret,
  }) async {
    logger.i('Aria2Provider: 连接到 ${source.name}');

    final adapter = Aria2Adapter();

    // 更新状态为连接中
    state = Aria2Connection(
      source: source,
      adapter: adapter,
      status: Aria2ConnectionStatus.connecting,
    );

    final credential = rpcSecret == null
        ? await _ref.read(sourceManagerProvider).getCredential(source.id)
        : null;
    final secureRpcSecret = credential?.extraSecrets['rpcSecret'];
    final storedRpcSecret =
        rpcSecret ??
        (secureRpcSecret is String ? secureRpcSecret : null) ??
        source.extraConfig?['rpcSecret'] as String?;

    // 构建配置，传入 rpcSecret
    final config = ServiceConnectionConfig(
      baseUrl: 'http://${source.host}:${source.port}',
      extraConfig: storedRpcSecret != null
          ? {'rpcSecret': storedRpcSecret}
          : source.extraConfig,
    );

    try {
      final result = await adapter.connect(config);

      final connection = result.when(
        success: (_) => Aria2Connection(
          source: source,
          adapter: adapter,
          status: Aria2ConnectionStatus.connected,
        ),
        failure: (error) => Aria2Connection(
          source: source,
          adapter: adapter,
          status: Aria2ConnectionStatus.error,
          errorMessage: error,
        ),
      );

      state = connection;
      return connection;
    } on Exception catch (e) {
      final connection = Aria2Connection(
        source: source,
        adapter: adapter,
        status: Aria2ConnectionStatus.error,
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
      logger.i('Aria2Provider: 断开连接 $sourceId');
    }
  }

  /// 获取适配器
  Aria2Adapter? get adapter => state?.adapter;
}

/// Aria2 全局统计 Provider
final aria2GlobalStatProvider = FutureProvider.family
    .autoDispose<Aria2GlobalStat?, String>((ref, sourceId) async {
      final connection = ref.watch(aria2ConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != Aria2ConnectionStatus.connected) {
        return null;
      }

      try {
        return await connection.adapter.getGlobalStat();
      } on Exception catch (e) {
        logger.e('Aria2Provider: 获取全局统计失败', e);
        return null;
      }
    });

/// Aria2 下载列表 Provider
final aria2DownloadsProvider = FutureProvider.family
    .autoDispose<List<Aria2Download>, String>((ref, sourceId) async {
      final connection = ref.watch(aria2ConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != Aria2ConnectionStatus.connected) {
        return [];
      }

      try {
        return await connection.adapter.getDownloads();
      } on Exception catch (e) {
        logger.e('Aria2Provider: 获取下载列表失败', e);
        return [];
      }
    });

/// 自动刷新的下载列表 Provider
class Aria2AutoRefreshNotifier extends StateNotifier<List<Aria2Download>> {
  Aria2AutoRefreshNotifier(this._ref, this._sourceId) : super([]) {
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
    final connection = _ref.read(aria2ConnectionProvider(_sourceId));
    if (connection == null ||
        connection.status != Aria2ConnectionStatus.connected) {
      return;
    }

    try {
      final downloads = await connection.adapter.getDownloads();
      if (mounted) {
        state = downloads;
      }
    } on Exception catch (e) {
      logger.e('Aria2AutoRefresh: 刷新失败', e);
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

final aria2AutoRefreshProvider = StateNotifierProvider.family
    .autoDispose<Aria2AutoRefreshNotifier, List<Aria2Download>, String>(
      Aria2AutoRefreshNotifier.new,
    );

/// 自动刷新的全局统计 Provider
class Aria2StatsAutoRefreshNotifier extends StateNotifier<Aria2GlobalStat?> {
  Aria2StatsAutoRefreshNotifier(this._ref, this._sourceId) : super(null) {
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
    final connection = _ref.read(aria2ConnectionProvider(_sourceId));
    if (connection == null ||
        connection.status != Aria2ConnectionStatus.connected) {
      return;
    }

    try {
      final stats = await connection.adapter.getGlobalStat();
      if (mounted) {
        state = stats;
      }
    } on Exception catch (e) {
      logger.e('Aria2StatsAutoRefresh: 刷新失败', e);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final aria2StatsAutoRefreshProvider = StateNotifierProvider.family
    .autoDispose<Aria2StatsAutoRefreshNotifier, Aria2GlobalStat?, String>(
      Aria2StatsAutoRefreshNotifier.new,
    );

/// 下载操作 Provider
final aria2ActionsProvider = Provider.family<Aria2Actions, String>(
  Aria2Actions.new,
);

class Aria2Actions {
  Aria2Actions(this._ref, this._sourceId);

  final Ref _ref;
  final String _sourceId;

  Aria2Adapter? get _adapter =>
      _ref.read(aria2ConnectionProvider(_sourceId))?.adapter;

  Aria2Adapter _requireAdapter() {
    final adapter = _adapter;
    if (adapter == null) {
      throw Exception(appL10n.aria2AdapterNotConnected);
    }
    return adapter;
  }

  void _invalidate() {
    _ref.invalidate(aria2AutoRefreshProvider(_sourceId));
  }

  /// 暂停下载
  Future<void> pause(String gid) async {
    final adapter = _requireAdapter();

    await adapter.pauseDownload(gid);
    _invalidate();
  }

  /// 暂停所有下载
  Future<void> pauseAll() async {
    final adapter = _requireAdapter();

    await adapter.pauseAllDownloads();
    _invalidate();
  }

  /// 恢复下载
  Future<void> resume(String gid) async {
    final adapter = _requireAdapter();

    await adapter.resumeDownload(gid);
    _invalidate();
  }

  /// 恢复所有下载
  Future<void> resumeAll() async {
    final adapter = _requireAdapter();

    await adapter.resumeAllDownloads();
    _invalidate();
  }

  /// 删除下载
  Future<void> remove(String gid) async {
    final adapter = _requireAdapter();

    await adapter.removeDownload(gid);
    _invalidate();
  }

  /// 清除已完成/错误的下载
  Future<void> purgeResults() async {
    final adapter = _requireAdapter();

    await adapter.purgeDownloadResults();
    _invalidate();
  }

  /// 添加 URI 下载
  Future<String> addUri(
    List<String> uris, {
    String? dir,
    String? filename,
  }) async {
    final adapter = _requireAdapter();

    final gid = await adapter.addUri(uris, dir: dir, filename: filename);
    _invalidate();
    return gid;
  }
}

/// 下载排序方式
enum Aria2SortMode {
  name('name', '名称'),
  size('totalLength', '大小'),
  progress('progress', '进度'),
  status('status', '状态'),
  dlSpeed('downloadSpeed', '下载速度'),
  upSpeed('uploadSpeed', '上传速度');

  const Aria2SortMode(this.value, this.label);

  final String value;
  final String label;
}

/// 下载状态筛选
enum Aria2StatusFilter {
  all('all', '全部'),
  active('active', '下载中'),
  waiting('waiting', '等待中'),
  paused('paused', '已暂停'),
  complete('complete', '已完成'),
  error('error', '错误');

  const Aria2StatusFilter(this.value, this.label);

  final String value;
  final String label;
}

/// 排序设置 Provider
class Aria2SortSettingsNotifier extends StateNotifier<Aria2SortSettings> {
  Aria2SortSettingsNotifier() : super(const Aria2SortSettings());

  void setSortMode(Aria2SortMode mode) {
    state = state.copyWith(sortMode: mode);
  }

  void toggleReverse() {
    state = state.copyWith(reverse: !state.reverse);
  }

  void setFilterStatus(Aria2StatusFilter? status) {
    state = state.copyWith(
      filterStatus: status,
      clearStatus: status == null || status == Aria2StatusFilter.all,
    );
  }
}

class Aria2SortSettings {
  const Aria2SortSettings({
    this.sortMode = Aria2SortMode.name,
    this.reverse = false,
    this.filterStatus,
  });

  final Aria2SortMode sortMode;
  final bool reverse;
  final Aria2StatusFilter? filterStatus;

  Aria2SortSettings copyWith({
    Aria2SortMode? sortMode,
    bool? reverse,
    Aria2StatusFilter? filterStatus,
    bool clearStatus = false,
  }) => Aria2SortSettings(
    sortMode: sortMode ?? this.sortMode,
    reverse: reverse ?? this.reverse,
    filterStatus: clearStatus ? null : (filterStatus ?? this.filterStatus),
  );
}

final aria2SortSettingsProvider =
    StateNotifierProvider.family<
      Aria2SortSettingsNotifier,
      Aria2SortSettings,
      String
    >((ref, sourceId) => Aria2SortSettingsNotifier());
