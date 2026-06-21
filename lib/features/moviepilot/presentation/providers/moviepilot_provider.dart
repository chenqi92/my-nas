import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:my_nas/service_adapters/moviepilot/api/moviepilot_api.dart';
import 'package:my_nas/service_adapters/moviepilot/moviepilot_adapter.dart';

/// MoviePilot 连接状态
enum MoviePilotConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// MoviePilot 连接信息
class MoviePilotConnection {
  const MoviePilotConnection({
    required this.source,
    required this.adapter,
    this.status = MoviePilotConnectionStatus.disconnected,
    this.errorMessage,
  });

  final SourceEntity source;
  final MoviePilotAdapter adapter;
  final MoviePilotConnectionStatus status;
  final String? errorMessage;
}

/// MoviePilot 连接管理 Provider
final moviepilotConnectionProvider = StateNotifierProvider.family<
    MoviePilotConnectionNotifier, MoviePilotConnection?, String>(
  (ref, sourceId) => MoviePilotConnectionNotifier(sourceId),
);

class MoviePilotConnectionNotifier
    extends StateNotifier<MoviePilotConnection?> {
  MoviePilotConnectionNotifier(this.sourceId) : super(null);

  final String sourceId;

  /// 连接到 MoviePilot
  Future<MoviePilotConnection> connect(SourceEntity source) async {
    logger.i('MoviePilotProvider: 连接到 ${source.name}');

    final adapter = MoviePilotAdapter();

    state = MoviePilotConnection(
      source: source,
      adapter: adapter,
      status: MoviePilotConnectionStatus.connecting,
    );

    final config = ServiceConnectionConfig.fromSource(source);

    try {
      final result = await adapter.connect(config);

      final connection = result.when(
        success: (_) => MoviePilotConnection(
          source: source,
          adapter: adapter,
          status: MoviePilotConnectionStatus.connected,
        ),
        failure: (error) => MoviePilotConnection(
          source: source,
          adapter: adapter,
          status: MoviePilotConnectionStatus.error,
          errorMessage: error,
        ),
      );

      state = connection;
      return connection;
    } on Exception catch (e) {
      final connection = MoviePilotConnection(
        source: source,
        adapter: adapter,
        status: MoviePilotConnectionStatus.error,
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
      logger.i('MoviePilotProvider: 断开连接 $sourceId');
    }
  }

  /// 获取适配器
  MoviePilotAdapter? get adapter => state?.adapter;
}

/// MoviePilot 概况统计 Provider
final moviepilotStatsProvider = FutureProvider.family
    .autoDispose<MoviePilotOverviewStats?, String>((ref, sourceId) async {
  final connection = ref.watch(moviepilotConnectionProvider(sourceId));
  if (connection == null ||
      connection.status != MoviePilotConnectionStatus.connected) {
    return null;
  }

  try {
    return await connection.adapter.getOverviewStats();
  } on Exception catch (e) {
    logger.e('MoviePilotProvider: 获取统计失败', e);
    return null;
  }
});

/// MoviePilot 订阅列表 Provider
final moviepilotSubscribesProvider = FutureProvider.family
    .autoDispose<List<MoviePilotSubscribe>, String>((ref, sourceId) async {
  final connection = ref.watch(moviepilotConnectionProvider(sourceId));
  if (connection == null ||
      connection.status != MoviePilotConnectionStatus.connected) {
    return [];
  }

  try {
    return await connection.adapter.getSubscribes();
  } on Exception catch (e) {
    logger.e('MoviePilotProvider: 获取订阅列表失败', e);
    return [];
  }
});

/// MoviePilot 下载任务 Provider
final moviepilotDownloadsProvider = FutureProvider.family
    .autoDispose<List<MoviePilotDownloadTask>, String>((ref, sourceId) async {
  final connection = ref.watch(moviepilotConnectionProvider(sourceId));
  if (connection == null ||
      connection.status != MoviePilotConnectionStatus.connected) {
    return [];
  }

  try {
    return await connection.adapter.getDownloadTasks();
  } on Exception catch (e) {
    logger.e('MoviePilotProvider: 获取下载任务失败', e);
    return [];
  }
});

/// MoviePilot 转移历史 Provider
final moviepilotTransferHistoryProvider = FutureProvider.family
    .autoDispose<List<MoviePilotTransferHistory>, String>((ref, sourceId) async {
  final connection = ref.watch(moviepilotConnectionProvider(sourceId));
  if (connection == null ||
      connection.status != MoviePilotConnectionStatus.connected) {
    return [];
  }

  try {
    return await connection.adapter.getTransferHistory();
  } on Exception catch (e) {
    logger.e('MoviePilotProvider: 获取转移历史失败', e);
    return [];
  }
});
